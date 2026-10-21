# Robot export: micro:bit, LEGO EV3, LEGO SPIKE Prime

Exports a trained Neuralese model so it drives a physical robot, alongside the
existing ONNX / Windows / Linux export targets.

This document covers the programmatic layer only. There is no UI yet; everything
here is built to be wired into one (see [API surface](#api-surface-for-the-ui)).

---

## How it works

The robot does **not** run the neural network.

```
   robot                              host (this computer)
   ─────                              ────────────────────
   read sensors
        │   S,seq,v0,v1,…,crc
        ├──────────────────────────►  scale readings into model space
        │                             run the ONNX model
        │                             map outputs to motor values
        │   A,seq,v0,v1,…,crc
        ◄──────────────────────────┤
   drive motors
```

None of these three devices can run onnxruntime, so the model has to live on the
host regardless. Two things follow from that, and both are the point:

* **The device program never changes when a child retrains.** It only changes
  when they pick different sensors or motors. One small script, flashed rarely.
* **Godot is not in the control loop.** A single Python process owns the link
  *and* the onnxruntime session, so the 20–50 Hz sensor-to-motor path never
  crosses a process boundary. Godot starts that process, tails its telemetry, and
  stops it. (The existing `infer_loop.py` polls a request file every 10 ms, which
  is fine for a child pressing a button and not fine for something with motors.)

---

## Why USB, and not WiFi or a browser WebSocket

Chosen from what the hardware can actually do, not from preference:

| Robot | WiFi | Bluetooth | USB | Chosen link |
|---|---|---|---|---|
| micro:bit v2 | none | BLE | CDC serial | **serial** |
| SPIKE Prime | none | BLE | CDC serial | **serial** |
| EV3 (ev3dev) | dongle only | RFCOMM | CDC **network** | **TCP** |

* **WiFi is not an option.** The micro:bit and the SPIKE hub have no WiFi radio
  at all; on the EV3 it needs a specific USB dongle most classrooms do not have.
* **BLE is opt-in, never default.** It works on two of the three, but it needs
  pairing plus an OS Bluetooth permission dialog — a real wall for a child — and
  its latency is worse and far less predictable than a wire. Implemented as
  `BleTransport` behind the same interface, so switching costs nothing.
* **A WebSocket from the site was considered and rejected.** Reaching these
  devices from a page requires Web Serial or Web Bluetooth, which would restrict
  the whole feature to Chrome and put a browser tab inside a robot's control
  loop. Godot 4 also has no Bluetooth stack, so any BLE path has to be in Python
  anyway.
* **The EV3 is TCP, not serial**, because plugging an EV3 in does not give you a
  serial port — it gives you a network interface, and the brick answers at
  `ev3dev.local`.

---

## Safety

A child-facing robot has exactly one rule that cannot bend: **losing the link
stops the robot.** Everything else is negotiable.

1. **Watchdogs on both ends.** The host answers every reading, so silence means
   the link is gone. The device stops its motors if no command arrives within
   `watchdog_ms`; the host drives every actuator to its safe value if the robot
   goes quiet. A robot that holds its last motor command after losing the link is
   a robot that drives into something.
2. **Every exit path stops the motors.** Errors, shutdown, a closed socket, a
   dead parent process. On the EV3 the guarantee lives in `serve_one_session`'s
   own `finally`, not only in its caller — a closed socket exits the loop before
   the watchdog can fire. *(This was a real bug, caught by the emulator tests.)*
3. **Checksums are enforced, not advisory.** A truncated line can decode as a
   perfectly plausible motor command. Every frame carries a checksum and a
   damaged frame is dropped, never acted on.
4. **Newest wins, nothing queues.** Stale and out-of-order frames are dropped by
   sequence number. Acting on a stale reading is acting on a world that moved.
5. **Nothing moves before the handshake.** The device sits saying hello, showing
   a "waiting" indicator, until the host accepts it — and the host refuses to act
   on readings from a robot it has not handshaken with, so an old flashed script
   with the same channel *count* but different channels cannot be driven with the
   wrong mapping. That is only safe because a device whose host went quiet starts
   announcing itself again, so "Disconnect, then Connect" always completes a
   fresh handshake instead of hanging.
6. **Readings are clamped before scaling**, so a glitching sensor cannot push the
   model into a region it never saw in training, where its output is meaningless.
7. **A motor command is remembered only after the write succeeds.** The device
   scripts skip re-issuing an unchanged command, because each one is a real sysfs
   write. Caching it *before* the write would let a failed `stop()` leave the
   script believing the motor had stopped, so the retry would return early and
   the motor would keep running.

---

## Wire protocol (NLR/1)

Line-oriented ASCII, `\n` terminated, **integers only**, max 240 bytes per line.

Designed for the weakest device in the set: micro:bit MicroPython has a few tens
of KB of free RAM, slow float parsing, and a real risk of serial RX overrun. So
the format is fixed-field-order CSV with a checksum cheap enough to compute as a
byte sum — one add per byte, rather than a CRC-16 table the hub would spend its
frame budget on.

```
H,<proto>,<platform>,<cfg_hash>,<n_in>,<n_out>,<rate_hz>,<watchdog_ms>,<crc>   robot → host
K,<proto>,<crc>                                                                host → robot  (accepted)
E,<code>,<crc>                                                                 host → robot  (refused)
S,<seq>,<v0>,…,<vn>,<crc>                                                      robot → host  (sensors)
A,<seq>,<v0>,…,<vm>,<crc>                                                      host → robot  (actuators)
X,<crc>                                                                        host → robot  (stop)
```

* `<crc>` is four lowercase hex digits: the sum of the payload bytes, masked to
  16 bits.
* `<seq>` wraps at 10000. Comparison is modular, so newest-wins keeps working
  across the wrap instead of ignoring every command for 10000 frames.
* `<cfg_hash>` fingerprints the mapping the device script was generated from. A
  child who changes the mapping but forgets to copy the new program across is
  turned away at the handshake with a message saying exactly that, rather than
  discovering it as a robot driving the wrong motor.
* All values on the wire are **native device units** (millimetres, percent,
  0–1023). Every float conversion happens on the host, which is why the device
  script is identical for every model.

Frame width is checked at **export** time against the configured channels' native
ranges. Leaving it to the codec would mean the failure surfacing on the robot,
mid-run, the first time a sensor happened to report a wide enough value.

---

## Mapping config

Ordered lists: input *i* is element *i* of both the sensor frame and the model's
input vector.

```jsonc
{
  "schema_version": 1,
  "platform": "ev3",
  "transport": {"kind": "tcp", "host": "ev3dev.local", "port": 9999},
  "rate_hz": 20,
  "watchdog_ms": 400,
  "inputs": [
    {"channel": "ultrasonic_4",
     "scale": {"kind": "linear", "in_min": 0, "in_max": 2550,
               "out_min": 0.0, "out_max": 1.0}}
  ],
  "outputs": [
    {"channel": "motor_a_speed", "mode": "argmax",
     "classes": {"0": 60, "1": -60, "2": 0}}
  ]
}
```

Output modes:

| mode | meaning |
|---|---|
| `argmax` | the winning class picks a value — the default for classifiers, which is most of what children train |
| `direct` | one model output, scaled onto the actuator's range |
| `threshold` | one model output, above/below a cut-off |

An unmapped class stops the actuator rather than guessing a speed for it.

### The scaling that has to be right

`default_input_scale()` maps a sensor's native range onto the range the model was
**trained** on. This is the highest-risk part of the feature: the Neuralese
trainer feeds dataset cells through essentially unchanged, so "model space" *is*
"dataset column space". If a sensor reports 0–2550 mm but the model only ever saw
0–100, the robot behaves randomly and **nothing anywhere reports an error**.

So the scaling is derived from the dataset's own column ranges rather than being
retyped by a child. Pass those ranges as `train_signature`:

```gdscript
{"input_columns": [{"name": "distance", "min": 0, "max": 100}, …]}
```

Without it the mapping falls back to identity and the response carries an
`unscaled_input` warning per channel. **The UI should surface that warning** —
it is the difference between a working robot and a baffling one.

---

## API surface for the UI

All of it goes through one process-launch pattern (`request.json` →
`response.json`), matching `export_yolk.py`. GDScript wrappers are in
`scripts/run_manager.gd`.

| GDScript | Action | Purpose |
|---|---|---|
| `robot_platforms()` | `list_platforms` | Every robot, sensor, motor, transport, deploy method. Drives all the dropdowns. |
| `robot_model_meta(input)` | `model_meta` | Model arity, for sizing the mapping form. |
| `robot_default_config(input, platform, train_signature)` | `default_config` | A ready-to-run mapping, so the child sees something working instead of an empty form. |
| `robot_validate_config(config, input)` | `validate` | **Every** problem at once, each with a `field` like `inputs[2].channel` to highlight. |
| `robot_preview_script(config)` | `preview_script` | The device program as text, for a preview pane. |
| `robot_list_devices(platform)` | `list_devices` | What is plugged in right now. Never crashes on a missing optional dependency. |
| `export_robot_bundle(input, platform, output_path, …)` | `export` | Writes the folder. |
| `start_robot_link(input, config)` | — | Starts the live host process; returns a `RobotLink`. |
| `robot_link_status(link)` | — | State, frame counters, latency, last readings and commands. Safe to call every frame. |
| `stop_robot_link(link)` | — | Stops the robot and exits. |

Errors always come back as `{"status": "error", "code", "message", "field"?}` so
the UI has one shape to render. Codes are stable — see `robot/errors.py`.

**Two things to know when wiring the UI:**

* Every call spawns a Python process. That is fine for the export and connect
  actions, but **`robot_validate_config` should be debounced** rather than run on
  every dropdown change, or the mapping screen will feel sluggish.
* `validate` returns `warnings` as well as `errors`, and the warnings are the
  ones that prevent baffling behaviour: `unscaled_input` (the sensor's range was
  not matched to the training data), `hardware_conflict` (two channels share one
  piece of hardware), `watchdog_too_tight`. **Surface them.** They do not block
  export, so nothing else will.

### The exported folder

```
MyRobot/
  main.py  (or neuralese_robot.py)   the device program
  model.onnx                         the trained model (the host runs this)
  robot_config.json                  the mapping, reloadable via load_bundle_config()
  HOW_TO_USE.txt                     per-platform instructions, English or Russian
```

---

## Testing

```bash
python3 local_runtime/tests/run_tests.py              # everything offline
python3 local_runtime/tests/run_tests.py --emulators  # + the EV3 emulator
```

Three tiers. **The difference matters when reading the results:**

### `fast` — 122 tests, no dependencies, no network

Protocol round-trips and corruption handling, config validation and scaling
arithmetic, generated-script snapshots, and the whole host control loop driven
against a fake clock. Every safety rule — watchdog, stale frames, inference
failure, shutdown — is checked as arithmetic rather than by sleeping and hoping.

### `emulator` — EV3 only, genuinely emulated

Two GitHub projects give real EV3 emulation on a desktop with no brick and no VM:

* [`ev3dev/ev3dev-lang-python`](https://github.com/ev3dev/ev3dev-lang-python) —
  the real `ev3dev2` library, unmodified.
* [`ddemidov/ev3dev-lang-fake-sys`](https://github.com/ddemidov/ev3dev-lang-fake-sys)
  — a fake `/sys` device tree.

`ev3dev2` drives motors by writing sysfs attribute files, so pointing it at a
directory of ordinary files makes every device call real. The **generated** script
runs, importing the **real** library, over a **real** socket, answered by the real
host bridge. When a test asserts a motor was told to run, it reads the same file
the motor driver would.

Opt-in (`--emulators`) because it clones once from GitHub; skipped loudly
otherwise. This tier found the fail-safe bug described in [Safety](#safety).

### `stub-device` — micro:bit and SPIKE: **not** emulated

Stated plainly because it bounds what the green ticks mean:

* **micro:bit**: the Foundation's simulator is a WebAssembly build with no
  published binary artefact, so using it would mean an Emscripten toolchain and a
  Node runtime in the test path.
* **SPIKE Prime**: no simulator exists at all, open source or otherwise.

So `emulators/device_stubs.py` reimplements enough of the `microbit` and
`pybricks` APIs for the generated scripts to run under CPython. What that does
buy is real: the actual generated script executes, its protocol handling, framing
and watchdog are exercised against the real host bridge over a real byte pipe,
and every sensor read and motor write is recorded and asserted. What it **cannot**
catch: MicroPython dialect gaps, RAM limits, real timing, and USB behaviour.
Those need hardware.

---

## Known limitations

* **micro:bit and SPIKE are not hardware-verified.** See above. The EV3 path is
  the one with genuine emulator coverage.
* **Deployment is manual on all three.** The registry carries a `deploy`
  descriptor per platform (method, whether it can be automated, and why not) and
  the bundle ships written instructions, but nothing flashes the device for you.
  micro:bit needs a `.hex` build; SPIKE and EV3 need their own tooling. Automating
  micro:bit via `uflash` is the most tractable follow-up.
* **SPIKE Prime requires the Pybricks firmware.** LEGO's own firmware is not
  supported. Pybricks is open source, has a stable documented API and a plain USB
  serial REPL; LEGO's has none of those.
* **`BleTransport` is untested on hardware.** It is written and wired in, and
  `bleak` is deliberately not in `requirements.txt`, so it reports a clean "not
  installed" error rather than being silently half-available.
* **Quantised models are not handled differently** — the robot path exports the
  trained f32 ONNX, matching the current behaviour of `export_fully_local_model`.
