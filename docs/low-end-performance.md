# Low-end performance: findings, benchmarks, evaluated tools

Target hardware: older Intel i3/i5, older Ryzen, integrated GPUs. Everything here was
measured; nothing was assumed. Numbers are a **relative** proxy for an iGPU, not a
prediction of absolute FPS on a specific machine.

**Read section 0 first.** It supersedes the frame-time numbers in sections 1-2: the harness
they came from hid a layer that the real app never hides (see 0.1), so they understated the
real per-frame cost and missed the largest single item.

## Graphics options (Settings)

Settings (the `/profile` dialog) has a **Graphics** section. Every option applies immediately,
is remembered, and can be switched back and forth while the app runs
(`scripts/graphics_quality.gd`, `GraphicsQualityConfig.apply_settings()`).

| Option | Values | What it does |
|---|---|---|
| Quality | High / Medium / Low / Custom | Named combinations of the three options below. Pressing cycles the presets. |
| Anti-aliasing | 4x / Off / 2x | 2D MSAA. Only curved edges change (plot curves, splines, the faintest plot guide lines); panel outlines and text are analytic shader edges. |
| Panel blur | Full / Fast / Off | **Full**: menus, dialogs and the top bar blur the live screen (a framebuffer copy per draw); node panels sample the background. **Fast**: every panel samples a baked 1/4-resolution copy of the background, nothing copies the framebuffer. **Off**: flat translucent glass. |
| Soft backdrop | On / Off | The 9-tap gaussian on panels that read the background texture (node panels, the top bar on the Dataset tab). Only available with Full blur. |

| Preset | Anti-aliasing | Panel blur | Soft backdrop |
|---|---|---|---|
| High | 4x | Full | On |
| Medium | Off | Fast | - |
| Low | Off | Off | - |

Precedence at startup: a `--graphics=low\|medium\|high` launch argument wins for that session and
is never saved; otherwise the options saved from Settings; otherwise the GPU decides (integrated,
software and virtual adapters get Medium, everything else High).

**Soft backdrop and the original look.** The background texture (`bg`) has no mip levels, so
`blur_level` does nothing for a panel that samples it: the 9-tap gaussian is the only blur it gets.
Commit `0a065f5` set `gaussian_mix` to 0 on 25 materials assuming the mip lookup blurred, which left
node panels (and the top bar on the Dataset tab) showing the raw pixel-art background. With Soft
backdrop on, High renders within 3/255 of the pre-`0a065f5` tree (`4185b0d`) on the Graphs tab, for
about 1% of frame time (below), because the gaussian only runs for panels that read `bg`. Restoring
it on all 25 materials, including the live-screen ones whose mips already blur, cost 5.7 ms
(Graphs) / 10.5 ms (Simulation) for no visible gain.

Measured cost, low-end proxy, Car Track, Graphs tab, ms per drawn frame (redraw forced every frame,
two repetitions; raw output in `scratch/perfbench/attrib*.jsonl` and `smooth_cost.jsonl`; sessions
differ by about 1 ms):

| Anti-aliasing | Panel blur | ms |
|---|---|---|
| 4x | Full | 44.7 (soft backdrop off) / 46.5 (on) |
| 2x | Full | 21.3 |
| Off | Full | 20.1 |
| 4x | Fast | 40.1 |
| 2x | Fast | 15.8 |
| Off | Fast (Medium) | 14.6 |
| 2x | Off | 15.3 |
| Off | Off (Low) | 14.2 |

Most of High-to-Medium is the MSAA level (24.6 of 30.1 ms); the baked blur path is 4.6 ms; Low is only
0.4 ms under Medium. 2x MSAA costs about 1.1 ms over Off but about 23 ms less than 4x. The proxy is
software rendering, which probably overstates MSAA cost on a real GPU.

Switching at runtime: Full to Fast or Off swaps the `block_screen` shader source once (one recompile),
and Fast publishes its baked background after about four frames so panels never flash black.

## 0. Second pass: per-tab isolation, and what was actually in the frame

Harness: `scratch/perfbench/bench_tab.gd` (one process = one config; `--tab=graph|env|ds|net`,
`--mode=cost|idle|cpu`, `--hide=` / `--noproc=` isolation tokens, `--shot=`). Same Car Track
project, same window, same warm-up for every tree; serial runs pinned to 4 cores (llvmpipe
proxy, 1280x720); two repetitions per cell, spread <=0.4 ms. Trees: `4185b0d` (original),
`7b19379` (previous pass), working tree (this pass). Absolute ms are proxy ms.

### 0.1 Harness correction: an invisible full-screen blur was drawn all session

`bench_suite.gd` / `bench_interact.gd` dismissed the onboarding dialog by hiding
`dialog.get_parent()`, which is `ui.cl` (CanvasLayer 128). `ui.cl` also holds `ui.blur`, the
full-screen splash backdrop. `ui.blur` is created at `self_modulate.a = 0` and only raised while
a splash is open, but it stayed `visible` and it is a `block_screen` (live-screen) material, so
in the real app every drawn frame paid for a full framebuffer copy, mip chain and full-screen
shader pass to draw nothing. Verified in the app's own dismissal path
(`dismiss_with_splash_animation()`), still present 12 s later with no toast on screen. The old
harness removed it from every number. Cost of it, isolated (`--hide=@clbg`, serial):

| Tab / preset | with `ui.blur` | hidden | cost |
|---|---|---|---|
| Graphs, High | 71.2 ms | 45.1 ms | 26.1 ms (37%) |
| Graphs, Medium | 19.8 ms | 14.9 ms | 5.0 ms (25%) |
| Simulation, High | 79.3 ms | 53.6 ms | 25.7 ms (32%) |
| Simulation, Medium | 16.4 ms | 11.5 ms | 4.9 ms (30%) |

Fix: `blur.gd` now sets `visible = self_modulate.a > 0.001` from `frame_pre_draw` (zero lag with
whatever the frame's scripts set). Splash dialog screenshot is pixel-identical to before
(0 px differ); `tests/godot/test_ui_blur_visibility.tscn`.

### 0.2 Simulation tab: it redrew the whole screen every frame while idle

Hypothesis "all sprites are redrawn every frame" - **partly right, wrong mechanism.**
- The world sprites are retained: static chunks re-record only on change, and while the sim is
  *running* only `VirtualWorldRenderer` redraws (60/s, ~0.65 ms script per redraw; `bench_sim_running.gd`).
  Hiding `WorldRoot` saves only 0.6 ms (Medium) / 4.6 ms (High) per drawn frame.
- What did redraw everything, at 144 drawn frames/s with the mouse still (drawn/process = 1.00,
  vs 0.03 on the Graphs tab), was two unconditional per-frame writes, found by bisecting with
  `--noproc=` and then replaying each line alone (`bench_sim_lines.gd`):
  1. `SimulationEditor._apply_responsive_runtime_layout` called `add_theme_constant_override`
     every frame from `SimulationTab._process`; that always sends `NOTIFICATION_THEME_CHANGED`
     (drawn/process 1.000 alone). Also guarded the `offset_top` write (0.10 alone).
  2. `Camera2D.make_current()` re-enables the camera's internal polling, and `SimulationTab.window_show`
     applied `IdleCamera` *before* it. Re-applied after.
- The Dataset tab (`ds`) had the same disease, not covered before: an instance shader parameter set
  every frame, and `tick()` / `_process()` resizing the console backdrop to two different widths
  every frame (`CodeEdit.size.x - 1` then `size.x`). Fixed in `dataset_tab.gd`.

Idle drawn frames/s (native RTX 3050, mouse still, `low_processor_usage_mode` on):

| Tab | 4185b0d | 7b19379 | now |
|---|---|---|---|
| Graphs | 144.9 | 3.6 | 4.0 |
| Simulation | 144.9 | **144.9** | **4.8** |
| Dataset | 144.9 | **144.9** | **3.8** |
| Net | 144.9 | 4.0 | 7.6 |

On the llvmpipe proxy the Simulation tab at High was 12.3 drawn/s at 284% CPU with the process loop
starved to 12 iterations/s (input handled at 12 Hz); now 0 drawn/s, 145 iterations/s, 46% CPU.
Regression test: `tests/godot/test_tabs_idle.tscn` (fails on `7b19379` with all three defects).

### 0.3 Cost of one *drawn* frame, before / after (proxy, ms, lower is better)

| | 4185b0d | 7b19379 | now | now vs 4185b0d | now vs 7b19379 |
|---|---|---|---|---|---|
| Graphs, High (4x MSAA, live blur) | 126.8 | 73.3 | **45.8** | **2.77x** | 1.60x |
| Graphs, Medium (auto on iGPU) | 126.8 | 22.6 | **15.1** | **8.4x** | 1.50x |
| Simulation, High | 128.4 | 81.5 | **53.7** | **2.39x** | 1.52x |
| Simulation, Medium (auto on iGPU) | 128.4 | 19.1 | **11.6** | **11.1x** | 1.65x |

Medium has a ~7 ms floor on this proxy (an empty scene runs at the 144 Hz present cadence), so its
ratios are capped by the floor rather than by the app. "Now" = `blur.gd` visibility (0.1) plus opaque
background blit (0.5); the idle fixes (0.2) do not change the cost of a drawn frame. The
`4185b0d` numbers here (127 ms) are higher than section 1 (68 ms) for the same commit purely because
of 0.1; compare within a table, not across harnesses.

Interactive scenarios, Graphs tab, Car Track, proxy (`bench_interact.gd`, `ui.cl` no longer hidden):

| Scenario | 4185b0d | 7b19379 High | now High | 7b19379 Med | now Med |
|---|---|---|---|---|---|
| Mouse still (drawn/s) | 7.9 | 0.2 | 0.2 | 3.5 | 5.0 |
| Hover a button (drawn/s) | 8.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| Mouse sweeping (process fps) | 7.9 | 99.5 | 114.9 | 121.7 | 127.5 |
| Camera pan (ms/frame) | 110.0 | 78.0 | 49.5 | 27.2 | 19.3 |

### 0.4 Where a drawn frame goes now (proxy, serial, Medium unless noted)

| Removing... | Simulation | Graphs |
|---|---|---|
| everything below (floor; still includes the then-present `ui.blur`) | 9.3 | 11.8 |
| background blit (`bg.gdshader`) | -4.1 | -4.0 |
| top bar (`fg`) | -1.9 | -1.9 |
| Simulation UI panels / graph nodes | -2.8 (UI) | -4.4 (`GraphStorage`, 330 draws) |
| world sprites | -0.6 | n/a |

(Measured before 0.1 and 0.5 were fixed, full frame 18.9 / 22.4 ms.) At High, 4x MSAA is ~33 ms of an
81 ms Simulation frame (`--msaa=0`: 47.9 ms) and 31 ms of it remains with a single draw call left, which
is the llvmpipe MSAA resolve cost; a real GPU will pay less of that fixed part, so treat High
ratios as an upper bound on MSAA's share.

### 0.5 Opaque background blit

`bg.gdshader` (a plain full-screen texture copy, the bottom-most item, only used by `bg.tscn`) now
uses `render_mode blend_disabled`: -2.6 ms (env 18.94 -> 16.35) and -2.7 ms (graph 22.42 -> 19.68)
at Medium. The background SubViewport texture was checked to be fully opaque (min alpha 1.000 on
all four tabs at five pan/zoom states), and screenshots are pixel-identical.

### 0.6 Experiments measured and rejected (kept here so they are not retried)

| Idea | Result | Why it failed |
|---|---|---|
| Rect `BackBufferCopy` strips for Palette / RuntimeBar / node palette (the TopBar trick) | Simulation High 81.2 -> 84.0 ms (**worse**, +2.8) | Godot sets `material_screen_texture_cached` after *any* copy, so items after an explicit copy reuse it (good), but every additional `BackBufferCopy` is another render-pass break plus a copy of its rect (with mips) that runs even if nothing samples it. The TopBar wins (86.8 -> 81.0) only because its strip replaces the one full copy of its layer; two panels in one layer cost two copies vs one. Source: `renderer_canvas_render_rd.cpp` (canvas_render_items). |
| Idle governor: raise `low_processor_usage_mode_sleep_usec` to 16 ms after 1 s without input | Iterations 145 -> 65/s but process CPU **46% -> 55%** (interleaved A/B, 3 reps, `powersave` cpufreq) | Sleeping longer lets cores clock down, so the same work takes longer; also adds up to 16 ms input latency and risks missing sub-iteration taps in the mouse-polling code. Idle CPU% on this box is dominated by DVFS; do not use it as a metric. |
| Drop anisotropic filtering on the global `bg` sampler | 16.35 -> 16.46 / 19.68 -> 19.80 ms (noise) | Panels use `textureLod`; anisotropy never applies. |
| Blur kernel changes | not attempted | Live blur is one `textureLod` tap per panel; the cost is the copy + mip chain, not the kernel. |

### 0.7 Still open (measured, not fixed)

- Per-frame script cost of the legacy polling UI on the Graphs tab: ~2 ms per process iteration on
  a 12th-gen i5 (`bench_tab.gd --mode=cpu`; several times that on an old i3). Ranked by disabling one
  script at a time (`bench_proc_scripts.gd`): `block_component.gd` (107 nodes) 0.51 ms,
  `graph_manager.gd` 0.43, `connection.gd` (32 nodes) 0.38. Each polls the mouse every iteration;
  turning that event-driven is a UI rewrite, not a guard.
- High is still 4x MSAA (33 ms of the Simulation frame on the proxy). Needs a visual sign-off to drop
  to 2x, or to replace it with shader/line antialiasing.
- Sim/Graphs live-blur panels at High still each pay a screen copy; the only way to remove it is
  baking the blur (Medium), which changes the look.

## How it was measured

- **Low-end proxy:** llvmpipe (software Vulkan) pinned to 4 logical cores, 1280x720,
  `--rendering-method mobile`. The app is fill-rate bound, so shader/fill work is paid
  for on the CPU and relative gains transfer.
- **Native:** RTX 3050 (NVK). Vsync/`low_processor_usage_mode` capped, so it can show
  idle behaviour and CPU cost but not render cost.
- **Scenes:** built-in Car Track / Digits projects loaded into `project.tscn`.
- **Harness:** `scratch/perfbench/` (not committed). `bench_suite.gd` = per-frame cost with a
  redraw forced every frame; `bench_interact.gd` = still / hover / sweep / pan scenarios;
  `bench_redraw*.gd` = idle-redraw isolation. Baseline = `4185b0d`.

## 1. Per-frame render cost (Car Track, low-end proxy, redraw forced every frame)

| Config | ms/frame | vs baseline |
|---|---|---|
| Baseline `4185b0d` | 68.4 | 1.0x |
| High (4x 2D MSAA, live blur) | 41.6 | 1.6x |
| High, MSAA 2x (`--msaa=1`, experiment) | 19.1 | 3.6x |
| High, MSAA off (experiment) | 17.9 | 3.8x |
| Medium (MSAA off, baked blur) | 13.1 | 5.2x |
| Low (no blur) | 12.8 | 5.3x |

Digits: 67.4 -> 40.8 (High) -> 13.7 (Medium) -> 13.3 (Low).

Decomposition of the High frame: **4x MSAA is 23.7 ms (57%)**; live blur is 4.8 ms (baking
it recovers ~4.5 ms; removing it entirely only 0.3 ms more). The blur is already one
`textureLod` tap per panel (the 9-tap gaussian runs only for the one material with
`gaussian_mix > 0`, `scenes/fg.tscn`), so there is little left to optimise in the kernel.
The remaining lever in High is MSAA. High is left at 4x to keep the shipped look.

Auto preset: integrated/software/virtual GPUs get Medium (`scripts/graphics_quality.gd`).

## 2. The app never went idle (fixed)

`glob.gd` sets `OS.low_processor_usage_mode = true`, but the editor redrew **every frame
even with nothing changing** (drawn/process frames = 1.00, 145 fps on the native box).
Bisected to four sources:

1. **`Camera2D` itself.** A Camera2D in the tree re-applies the canvas transform from its
   internal process every frame, which requests a redraw. Reproduced in an empty project:
   plain Camera2D -> 1.00, none -> 0.00. `IdleCamera` (`scripts/idle_camera.gd`) turns that
   polling off; the camera still updates immediately on position/zoom assignment. Engine
   re-enables the polling on tree re-entry and on `enabled = true`, so it is re-applied on
   `tree_entered` and from `TabWindow._set_camera_enabled`. Covers the main camera and the
   background SubViewport camera.
2. `camera_2d.gd` set the `_view_scale` global shader parameter, `zoom` and `position`
   every frame; now only on change.
3. `gview.gd` wrote `position` every frame; now stops at the target.
4. `bg_loop.gd` rewrote three sprites' position/flip every frame; now only when the tile
   under the camera changes. `color_rect.gd`/`sub_viewport.gd` guarded likewise.

Pitfall for future code: **any unconditional per-frame write to a Camera2D, a Node2D
transform, or a global shader parameter defeats idle**, even to the same value. (Control
`modulate` etc. early-out on equal values and are fine.) Guarded by
`tests/godot/test_idle_camera.gd`.

### Scenario results (Car Track)

Drawn frames per second, and cost per frame where it applies. The baseline draws *every* frame
(on the proxy each takes ~125 ms, hence ~8/s), so compare it against 0 rather than as a rate:

| Scenario | Baseline (proxy) | New High (proxy) | New Medium (proxy) | Baseline (native) | New (native) |
|---|---|---|---|---|---|
| Mouse still | 7.9 drawn/s, 283% CPU | **0.2** drawn/s, 48% CPU | 3.7 drawn/s | 144.9 drawn/s | **9.7** |
| Hover a button | 8.0 | 0.0 | 0.0 | 144.9 | 0.0 |
| Mouse sweeping canvas | 8.0 | 4.7 | 11.0 | 144.9 | 37.0 |
| Camera panning (ms/frame) | 109.9 | 75.4 | 25.8 | 6.9 (all drawn) | 6.9 (all drawn) |

Real app, idle 45 s, per-thread `top`: 47.4% -> 31.6% of one core (native GPU hides most of
the saving; the proxy shows it as 283% -> 48%).

Interpretation: the idle fix removes GPU/CPU work when nothing changes (battery, heat,
competing with local training) but **does not reduce the cost of a frame that is drawn**;
that is what section 1 addresses.

## 3. Evaluated GitHub projects (none adopted)

| Repo | License | Last push | Verdict |
|---|---|---|---|
| dueddel/godot-idle-energy-saver | MIT | 2024-11 | Throttles FPS when unfocused (~100 lines). Measured: idle CPU 43.7% -> 18.7% at a 15 fps cap. Not added: visible behaviour change (a second-monitor window would refresh at 15 fps); needs a product decision. |
| lucasbecker-dev/godot-smart-graphics-settings | MIT | 2025-11 | Adaptive 3D settings for 4.5.1; no 2D/canvas handling. Presets already exist. |
| puchik/godot-extras (importance LOD) | none found | 2025-07 | 3D mesh LOD in C++; not applicable to a 2D UI editor; no license. |
| godot-addons/godot-object-pool | MIT | 2024-01 | No allocation churn in profiles (node count constant at 1867 across runs). |
| Pineapple/GodotTracy, nodlag/profily, godot-debug-menu | MIT | 2024-26 | Tracy needs an engine rebuild; overlays add nothing over the harness above. |
| motion-blur addons (JFA etc.) | MIT | 2026 | Screen-space motion blur, unrelated to UI backdrop blur. |
| godotengine/godot#56873, godot-proposals#14344, godot-docs `screen-reading_shaders` | MIT | - | Confirm the `BackBufferCopy` behaviour measured in 0.6 and that mipmapped `hint_screen_texture` reads cost ms on iGPUs; no addon exists for it, the fix is fewer/smaller copies or baking. |

MCP: `.mcp.json` uses `@satelliteoflove/godot-mcp` (MIT, 4.1.11); the repo also bundles
`addons/godot_mcp`.

## Not measured / open

- Real i3/Ryzen + iGPU hardware. All low-end numbers are the llvmpipe proxy.
- Idle behaviour on the Simulation/Dataset/Net tabs: measured in section 0.2 (Simulation and Dataset
  were still redrawing every frame and are fixed).
- Medium/Low differ visually from High (no MSAA, baked 1/4-res blur).
- High at MSAA 2x looks like a cheap ~2x win on the proxy; needs a visual sign-off.
