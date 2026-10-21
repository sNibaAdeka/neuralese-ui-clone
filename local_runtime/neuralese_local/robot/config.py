"""The input/output mapping config: schema, defaults, validation, and the math.

This module is deliberately free of numpy, onnx and every other heavy import, so
the UI can validate a config and preview the mapping without the runtime being
installed, and so the fast test tier needs no dependencies at all.

The config is a plain dict, JSON round-trippable, versioned::

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

``inputs`` is ordered: entry *i* becomes element *i* of the model input vector,
and element *i* of the sensor frame on the wire. ``outputs`` is ordered the same
way against the actuator frame.

Why scaling lives here and not on the robot
-------------------------------------------
The device sends raw native integers and receives final native integers. All
float work happens on the host. That means the device script is identical for
every model, a micro:bit never parses a float, and -- most importantly -- the
scaling that has to match how the model was *trained* is derived once, here,
from the dataset's own column ranges, instead of being retyped by a child.
"""

from __future__ import annotations

import hashlib
import json
from typing import Any, Dict, List, Optional, Sequence, Tuple

from .codec import MAX_LINE_BYTES, SEQ_MOD
from .errors import (
    ERR_ARITY_MISMATCH,
    ERR_BAD_CONFIG,
    ERR_UNKNOWN_CHANNEL,
    ERR_UNSUPPORTED_TRANSPORT,
    ValidationReport,
)
from .platforms import TRANSPORT_BLE, TRANSPORT_SERIAL, TRANSPORT_TCP, get_platform

SCHEMA_VERSION = 1

MODE_DIRECT = "direct"
MODE_ARGMAX = "argmax"
MODE_THRESHOLD = "threshold"
OUTPUT_MODES = (MODE_DIRECT, MODE_ARGMAX, MODE_THRESHOLD)

SCALE_LINEAR = "linear"
SCALE_IDENTITY = "identity"
SCALE_KINDS = (SCALE_LINEAR, SCALE_IDENTITY)

MIN_RATE_HZ = 1
MIN_WATCHDOG_MS = 50
MAX_WATCHDOG_MS = 5000


def clamp(value: float, low: float, high: float) -> float:
    if low > high:
        low, high = high, low
    if value < low:
        return low
    if value > high:
        return high
    return value


# ---------------------------------------------------------------------------
# Scaling
# ---------------------------------------------------------------------------

def linear_scale(in_min: float, in_max: float, out_min: float, out_max: float) -> Dict[str, Any]:
    return {
        "kind": SCALE_LINEAR,
        "in_min": float(in_min),
        "in_max": float(in_max),
        "out_min": float(out_min),
        "out_max": float(out_max),
    }


def identity_scale() -> Dict[str, Any]:
    return {"kind": SCALE_IDENTITY}


def apply_scale(scale: Dict[str, Any], value: float) -> float:
    kind = str(scale.get("kind", SCALE_IDENTITY))
    if kind == SCALE_IDENTITY:
        return float(value)
    in_min = float(scale.get("in_min", 0.0))
    in_max = float(scale.get("in_max", 1.0))
    out_min = float(scale.get("out_min", 0.0))
    out_max = float(scale.get("out_max", 1.0))
    span = in_max - in_min
    if span == 0.0:
        # A degenerate range would divide by zero. Collapsing to the low end of
        # the output range is the inert choice: for a motor that is "stopped".
        return out_min
    ratio = (float(value) - in_min) / span
    return out_min + ratio * (out_max - out_min)


def invert_scale(scale: Dict[str, Any]) -> Dict[str, Any]:
    """The same linear map read backwards, for the model -> actuator direction."""
    if str(scale.get("kind", SCALE_IDENTITY)) == SCALE_IDENTITY:
        return identity_scale()
    return linear_scale(
        float(scale.get("out_min", 0.0)),
        float(scale.get("out_max", 1.0)),
        float(scale.get("in_min", 0.0)),
        float(scale.get("in_max", 1.0)),
    )


# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------

def _column_range(column: Dict[str, Any]) -> Optional[Tuple[float, float]]:
    """The value range a training column actually occupied, if it is known."""
    if not isinstance(column, dict):
        return None
    low = column.get("min")
    high = column.get("max")
    if low is None or high is None:
        return None
    try:
        low_f, high_f = float(low), float(high)
    except (TypeError, ValueError):
        return None
    if low_f == high_f:
        return None
    return (low_f, high_f)


def default_input_scale(channel, train_column: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    """Map a sensor's native range onto the range the model was trained on.

    This is the single most important function in the feature. The Neuralese
    trainer feeds dataset cells through essentially unchanged (numbers as-is,
    image bytes divided by 255), so "model space" *is* "dataset column space".
    If a sensor reports 0..2550 mm but the model only ever saw 0..100, the robot
    behaves randomly and nothing anywhere reports an error -- so when the column
    range is known we build the map from it, and when it is not we fall back to
    identity and make the caller warn about it.
    """
    column_range = _column_range(train_column or {})
    if column_range is None:
        return identity_scale()
    out_min, out_max = column_range
    return linear_scale(channel.native_min, channel.native_max, out_min, out_max)


def default_transport(platform_id: str) -> Dict[str, Any]:
    platform = get_platform(platform_id)
    kind = platform.default_transport
    if kind == TRANSPORT_SERIAL:
        # `port` empty means "autodetect": the UI can offer a picker, and the
        # bridge falls back to scanning for a plausible device.
        return {"kind": TRANSPORT_SERIAL, "port": "", "baud": 115200}
    if kind == TRANSPORT_TCP:
        return {"kind": TRANSPORT_TCP, "host": "ev3dev.local", "port": 9999}
    return {"kind": TRANSPORT_BLE, "address": ""}


def default_config(
    platform_id: str,
    model_meta: Optional[Dict[str, Any]] = None,
    train_signature: Optional[Dict[str, Any]] = None,
    report: Optional[ValidationReport] = None,
) -> Dict[str, Any]:
    """Build a ready-to-run config, guessing sensibly so the child sees a
    working default rather than an empty form.

    ``model_meta`` comes from :mod:`.model_meta` (``input_size``/``output_size``).
    ``train_signature`` is optional dataset metadata::

        {"input_columns":  [{"name": "distance", "min": 0, "max": 100}, ...],
         "output_columns": [{"name": "action", "classes": ["go", "left"]}]}

    Everything it produces is overridable; nothing here is load-bearing for
    correctness beyond giving good starting ranges.
    """
    platform = get_platform(platform_id)
    meta = model_meta or {}
    signature = train_signature or {}

    input_size = int(meta.get("input_size", 0) or 0)
    output_size = int(meta.get("output_size", 0) or 0)
    train_columns: List[Dict[str, Any]] = list(signature.get("input_columns", []) or [])

    inputs: List[Dict[str, Any]] = []
    for index in range(input_size):
        if index >= len(platform.sensors):
            # More model inputs than the robot has sensors. Validation reports
            # this properly; here we just stop rather than invent channels.
            break
        channel = platform.sensors[index]
        column = train_columns[index] if index < len(train_columns) else None
        scale = default_input_scale(channel, column)
        if report is not None and scale["kind"] == SCALE_IDENTITY:
            report.warn(
                "unscaled_input",
                "No training range is known for '%s', so its readings are sent to the "
                "model unchanged. Check that the sensor's range matches the data the "
                "model was trained on." % channel.label,
                field="inputs[%d]" % index,
                channel=channel.id,
            )
        inputs.append({"channel": channel.id, "scale": scale})

    outputs: List[Dict[str, Any]] = []
    if platform.actuators and output_size > 0:
        if output_size > 1:
            # More than one model output is overwhelmingly a classifier in this
            # product, and "pick the winning class, then do the thing" is the
            # mental model a child already has.
            channel = platform.actuators[0]
            outputs.append({
                "channel": channel.id,
                "mode": MODE_ARGMAX,
                "classes": {str(i): _default_class_value(channel, i, output_size) for i in range(output_size)},
            })
        else:
            channel = platform.actuators[0]
            outputs.append({
                "channel": channel.id,
                "mode": MODE_DIRECT,
                "index": 0,
                "scale": linear_scale(0.0, 1.0, channel.native_min, channel.native_max),
            })

    return {
        "schema_version": SCHEMA_VERSION,
        "platform": platform.id,
        "transport": default_transport(platform.id),
        "rate_hz": platform.default_rate_hz,
        "watchdog_ms": platform.default_watchdog_ms,
        "inputs": inputs,
        "outputs": outputs,
    }


def _default_class_value(channel, class_index: int, class_count: int) -> int:
    """Spread class indices across the actuator's range.

    For a 3-class model on a motor this gives full reverse / stop / full
    forward, which is a demonstrably sensible first behaviour to watch.
    """
    if class_count <= 1:
        return int(channel.safe_value)
    ratio = class_index / float(class_count - 1)
    return int(round(channel.native_min + ratio * (channel.native_max - channel.native_min)))


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

def validate_config(config: Dict[str, Any], model_meta: Optional[Dict[str, Any]] = None) -> ValidationReport:
    """Check a config top to bottom, collecting every problem.

    Passing ``model_meta`` additionally checks the config against the real
    model's input/output arity, which is the check that catches "the child
    retrained with an extra column and the old mapping is now wrong".
    """
    report = ValidationReport()

    if not isinstance(config, dict):
        report.error(ERR_BAD_CONFIG, "The robot config must be a dictionary.")
        return report

    version = config.get("schema_version", SCHEMA_VERSION)
    if int(version or 0) > SCHEMA_VERSION:
        report.error(
            ERR_BAD_CONFIG,
            "This robot config was written by a newer version of Neuralese "
            "(schema %s, this build understands %s)." % (version, SCHEMA_VERSION),
            field="schema_version",
        )
        return report

    try:
        platform = get_platform(config.get("platform", ""))
    except Exception as exc:  # RobotError, but keep validation total
        report.error(getattr(exc, "code", ERR_BAD_CONFIG), str(exc), field="platform")
        return report

    _validate_transport(config.get("transport"), platform, report)
    _validate_timing(config, platform, report)
    _validate_inputs(config.get("inputs"), platform, report)
    _validate_outputs(config.get("outputs"), platform, report)
    _validate_frame_size(config, platform, report)
    _validate_hardware_conflicts(config, platform, report)

    if model_meta:
        _validate_against_model(config, model_meta, report)

    return report


def _validate_transport(transport: Any, platform, report: ValidationReport) -> None:
    if not isinstance(transport, dict):
        report.error(ERR_BAD_CONFIG, "The transport section is missing.", field="transport")
        return
    kind = str(transport.get("kind", ""))
    if kind not in platform.transports:
        report.error(
            ERR_UNSUPPORTED_TRANSPORT,
            "%s cannot connect over '%s'. Supported: %s."
            % (platform.label, kind or "(none)", ", ".join(platform.transports)),
            field="transport.kind",
            supported=list(platform.transports),
        )
        return
    if kind == TRANSPORT_TCP and not str(transport.get("host", "")).strip():
        report.error(ERR_BAD_CONFIG, "A TCP link needs the robot's address.", field="transport.host")
    if kind == TRANSPORT_SERIAL:
        baud = transport.get("baud", 115200)
        if not isinstance(baud, int) or baud <= 0:
            report.error(ERR_BAD_CONFIG, "Serial baud rate must be a positive whole number.", field="transport.baud")


def _validate_timing(config: Dict[str, Any], platform, report: ValidationReport) -> None:
    rate = config.get("rate_hz", platform.default_rate_hz)
    if not isinstance(rate, int) or rate < MIN_RATE_HZ:
        report.error(ERR_BAD_CONFIG, "Update rate must be a whole number of hertz, at least %d." % MIN_RATE_HZ, field="rate_hz")
    elif rate > platform.max_rate_hz:
        report.error(
            ERR_BAD_CONFIG,
            "%s cannot keep up with %d Hz; the maximum is %d Hz." % (platform.label, rate, platform.max_rate_hz),
            field="rate_hz",
            max_rate_hz=platform.max_rate_hz,
        )

    watchdog = config.get("watchdog_ms", platform.default_watchdog_ms)
    if not isinstance(watchdog, int) or not MIN_WATCHDOG_MS <= watchdog <= MAX_WATCHDOG_MS:
        report.error(
            ERR_BAD_CONFIG,
            "The safety timeout must be between %d and %d milliseconds." % (MIN_WATCHDOG_MS, MAX_WATCHDOG_MS),
            field="watchdog_ms",
        )
    elif isinstance(rate, int) and rate >= MIN_RATE_HZ and watchdog < (2000 // rate):
        # Shorter than two update periods and ordinary jitter trips the
        # watchdog, so the robot stutters to a halt on a perfectly healthy link.
        report.warn(
            "watchdog_too_tight",
            "A %d ms safety timeout at %d Hz will trip on normal delays. "
            "At least %d ms is recommended." % (watchdog, rate, 2000 // rate),
            field="watchdog_ms",
            recommended_ms=2000 // rate,
        )


def _validate_scale(scale: Any, field: str, report: ValidationReport) -> None:
    if scale is None:
        return
    if not isinstance(scale, dict):
        report.error(ERR_BAD_CONFIG, "Scaling must be a dictionary.", field=field)
        return
    kind = str(scale.get("kind", SCALE_IDENTITY))
    if kind not in SCALE_KINDS:
        report.error(ERR_BAD_CONFIG, "Unknown scaling type '%s'." % kind, field=field + ".kind")
        return
    if kind == SCALE_LINEAR:
        for key in ("in_min", "in_max", "out_min", "out_max"):
            value = scale.get(key)
            if not isinstance(value, (int, float)) or isinstance(value, bool):
                report.error(ERR_BAD_CONFIG, "Scaling value '%s' must be a number." % key, field="%s.%s" % (field, key))
                return
        if float(scale["in_min"]) == float(scale["in_max"]):
            report.error(
                ERR_BAD_CONFIG,
                "Scaling input range is empty (min and max are both %s)." % scale["in_min"],
                field=field,
            )


def _validate_inputs(inputs: Any, platform, report: ValidationReport) -> None:
    if not isinstance(inputs, list):
        report.error(ERR_BAD_CONFIG, "The inputs section must be a list.", field="inputs")
        return
    if not inputs:
        report.error(ERR_BAD_CONFIG, "At least one sensor has to be connected to the model.", field="inputs")
        return
    for index, entry in enumerate(inputs):
        field = "inputs[%d]" % index
        if not isinstance(entry, dict):
            report.error(ERR_BAD_CONFIG, "Each input must be a dictionary.", field=field)
            continue
        channel_id = str(entry.get("channel", ""))
        if platform.sensor(channel_id) is None:
            report.error(
                ERR_UNKNOWN_CHANNEL,
                "%s has no sensor called '%s'." % (platform.label, channel_id),
                field=field + ".channel",
                channel=channel_id,
                available=[c.id for c in platform.sensors],
            )
            continue
        _validate_scale(entry.get("scale"), field + ".scale", report)


def _validate_outputs(outputs: Any, platform, report: ValidationReport) -> None:
    if not isinstance(outputs, list):
        report.error(ERR_BAD_CONFIG, "The outputs section must be a list.", field="outputs")
        return
    if not outputs:
        report.error(ERR_BAD_CONFIG, "The model has to drive at least one motor or light.", field="outputs")
        return
    for index, entry in enumerate(outputs):
        field = "outputs[%d]" % index
        if not isinstance(entry, dict):
            report.error(ERR_BAD_CONFIG, "Each output must be a dictionary.", field=field)
            continue
        channel_id = str(entry.get("channel", ""))
        channel = platform.actuator(channel_id)
        if channel is None:
            report.error(
                ERR_UNKNOWN_CHANNEL,
                "%s has no motor or light called '%s'." % (platform.label, channel_id),
                field=field + ".channel",
                channel=channel_id,
                available=[c.id for c in platform.actuators],
            )
            continue

        mode = str(entry.get("mode", MODE_DIRECT))
        if mode not in OUTPUT_MODES:
            report.error(
                ERR_BAD_CONFIG,
                "Unknown output mode '%s'. Use one of: %s." % (mode, ", ".join(OUTPUT_MODES)),
                field=field + ".mode",
            )
            continue

        if mode == MODE_DIRECT:
            model_index = entry.get("index", 0)
            if not isinstance(model_index, int) or isinstance(model_index, bool) or model_index < 0:
                report.error(ERR_BAD_CONFIG, "Output index must be a whole number of 0 or more.", field=field + ".index")
            _validate_scale(entry.get("scale"), field + ".scale", report)
        elif mode == MODE_ARGMAX:
            classes = entry.get("classes", {})
            if not isinstance(classes, dict) or not classes:
                report.error(
                    ERR_BAD_CONFIG,
                    "An 'argmax' output needs a value for each class the model can predict.",
                    field=field + ".classes",
                )
                continue
            for key, value in classes.items():
                if not str(key).lstrip("-").isdigit():
                    report.error(ERR_BAD_CONFIG, "Class key '%s' is not a class number." % key, field=field + ".classes")
                elif not isinstance(value, (int, float)) or isinstance(value, bool):
                    report.error(ERR_BAD_CONFIG, "Class '%s' must map to a number." % key, field=field + ".classes")
                elif not (channel.native_min <= float(value) <= channel.native_max):
                    report.error(
                        ERR_BAD_CONFIG,
                        "Class '%s' is set to %s, outside what %s accepts (%g to %g)."
                        % (key, value, channel.label, channel.native_min, channel.native_max),
                        field=field + ".classes",
                    )
        elif mode == MODE_THRESHOLD:
            if not isinstance(entry.get("threshold", 0.5), (int, float)) or isinstance(entry.get("threshold"), bool):
                report.error(ERR_BAD_CONFIG, "Threshold must be a number.", field=field + ".threshold")
            model_index = entry.get("index", 0)
            if not isinstance(model_index, int) or isinstance(model_index, bool) or model_index < 0:
                report.error(ERR_BAD_CONFIG, "Output index must be a whole number of 0 or more.", field=field + ".index")


def _channel_ids(entries: Any) -> List[str]:
    if not isinstance(entries, list):
        return []
    return [str(entry.get("channel", "")) for entry in entries if isinstance(entry, dict)]


def _validate_hardware_conflicts(config: Dict[str, Any], platform, report: ValidationReport) -> None:
    """Warn when two mapped channels share one piece of hardware.

    A warning rather than an error: the combination works, it just works badly,
    and a child who genuinely wants it should not be blocked. But nobody should
    have to discover it by watching a screen flicker and wondering why the robot
    got worse.
    """
    inputs = set(_channel_ids(config.get("inputs")))
    outputs = set(_channel_ids(config.get("outputs")))
    for conflict in platform.conflicts:
        sensor = str(conflict.get("sensor", ""))
        if sensor not in inputs:
            continue
        clashing = [name for name in conflict.get("actuators", []) if name in outputs]
        if clashing:
            report.warn(
                "hardware_conflict",
                str(conflict.get("message", "")),
                field="outputs",
                sensor=sensor,
                actuators=clashing,
            )


def _worst_case_frame_bytes(channels: List[Any]) -> int:
    """Longest line these channels could ever produce.

    ``"S"`` + seq + one field per channel + checksum + newline, with each field
    sized by the widest number the channel's native range can print.
    """
    total = 1 + 1 + len(str(SEQ_MOD - 1)) + 1 + 4 + 1
    for channel in channels:
        widest = max(len(str(int(channel.native_min))), len(str(int(channel.native_max))))
        total += 1 + widest
    return total


def _validate_frame_size(config: Dict[str, Any], platform, report: ValidationReport) -> None:
    """Refuse a mapping whose frames would not fit on the wire.

    Caught here, at export, rather than by the codec at encode time -- which
    would mean the failure surfaces on the robot, mid-run, once a sensor happens
    to report a wide enough value.
    """
    for section, lookup in (("inputs", platform.sensor), ("outputs", platform.actuator)):
        entries = config.get(section)
        if not isinstance(entries, list):
            continue
        channels = []
        for entry in entries:
            if isinstance(entry, dict):
                channel = lookup(str(entry.get("channel", "")))
                if channel is not None:
                    channels.append(channel)
        if not channels:
            continue
        size = _worst_case_frame_bytes(channels)
        if size > MAX_LINE_BYTES:
            report.error(
                ERR_BAD_CONFIG,
                "Too many things are connected at once: they would need %d bytes per "
                "message and the robot link allows %d. Connect fewer than %d."
                % (size, MAX_LINE_BYTES, len(channels)),
                field=section,
                bytes_needed=size,
                bytes_available=MAX_LINE_BYTES,
            )


def _validate_against_model(config: Dict[str, Any], model_meta: Dict[str, Any], report: ValidationReport) -> None:
    inputs = config.get("inputs") or []
    outputs = config.get("outputs") or []

    input_size = int(model_meta.get("input_size", 0) or 0)
    if input_size and isinstance(inputs, list) and len(inputs) != input_size:
        report.error(
            ERR_ARITY_MISMATCH,
            "The model expects %d input value(s) but %d sensor(s) are connected."
            % (input_size, len(inputs)),
            field="inputs",
            expected=input_size,
            actual=len(inputs),
        )

    output_size = int(model_meta.get("output_size", 0) or 0)
    if not output_size or not isinstance(outputs, list):
        return
    for index, entry in enumerate(outputs):
        if not isinstance(entry, dict):
            continue
        mode = str(entry.get("mode", MODE_DIRECT))
        field = "outputs[%d]" % index
        if mode in (MODE_DIRECT, MODE_THRESHOLD):
            model_index = entry.get("index", 0)
            if isinstance(model_index, int) and not isinstance(model_index, bool) and model_index >= output_size:
                report.error(
                    ERR_ARITY_MISMATCH,
                    "This output reads model value %d, but the model only produces %d."
                    % (model_index, output_size),
                    field=field + ".index",
                    expected_below=output_size,
                )
        elif mode == MODE_ARGMAX:
            classes = entry.get("classes", {})
            if isinstance(classes, dict):
                missing = [str(i) for i in range(output_size) if str(i) not in classes]
                if missing:
                    report.error(
                        ERR_ARITY_MISMATCH,
                        "The model can predict %d classes, but classes %s have no value set."
                        % (output_size, ", ".join(missing)),
                        field=field + ".classes",
                        missing=missing,
                    )


# ---------------------------------------------------------------------------
# Compiled plan
# ---------------------------------------------------------------------------

class MappingPlan:
    """A validated config turned into the two functions the bridge needs.

    Compiling up front keeps per-frame work to arithmetic on a short list, which
    matters when this runs 20-50 times a second.
    """

    def __init__(self, config: Dict[str, Any]) -> None:
        self.config = config
        self.platform = get_platform(config["platform"])
        self.rate_hz = int(config.get("rate_hz", self.platform.default_rate_hz))
        self.watchdog_ms = int(config.get("watchdog_ms", self.platform.default_watchdog_ms))

        self.input_channels = []
        self._input_scales: List[Dict[str, Any]] = []
        for entry in config.get("inputs", []):
            channel = self.platform.sensor(str(entry["channel"]))
            self.input_channels.append(channel)
            self._input_scales.append(entry.get("scale") or identity_scale())

        self.output_channels = []
        self._output_specs: List[Dict[str, Any]] = []
        for entry in config.get("outputs", []):
            channel = self.platform.actuator(str(entry["channel"]))
            self.output_channels.append(channel)
            self._output_specs.append(entry)

    @property
    def input_count(self) -> int:
        return len(self.input_channels)

    @property
    def output_count(self) -> int:
        return len(self.output_channels)

    def safe_values(self) -> List[int]:
        """What every actuator is driven to when the link is not healthy."""
        return [int(channel.safe_value) for channel in self.output_channels]

    def sensors_to_model(self, native_values: Sequence[int]) -> List[float]:
        """Native sensor integers from the wire -> the model's input vector."""
        if len(native_values) != self.input_count:
            raise ValueError(
                "Robot sent %d sensor value(s), the mapping expects %d."
                % (len(native_values), self.input_count)
            )
        out: List[float] = []
        for index, raw in enumerate(native_values):
            channel = self.input_channels[index]
            # Clamp before scaling: a sensor briefly reporting outside its
            # documented range must not push the model far outside the space it
            # was trained on, where its output is meaningless.
            bounded = clamp(float(raw), channel.native_min, channel.native_max)
            out.append(apply_scale(self._input_scales[index], bounded))
        return out

    def model_to_actuators(self, model_output: Sequence[float]) -> List[int]:
        """The model's output vector -> native actuator integers for the wire."""
        values = [float(v) for v in model_output]
        results: List[int] = []
        for index, spec in enumerate(self._output_specs):
            channel = self.output_channels[index]
            mode = str(spec.get("mode", MODE_DIRECT))
            if mode == MODE_ARGMAX:
                native = self._argmax_value(spec, channel, values)
            elif mode == MODE_THRESHOLD:
                native = self._threshold_value(spec, channel, values)
            else:
                native = self._direct_value(spec, channel, values)
            results.append(int(round(clamp(native, channel.native_min, channel.native_max))))
        return results

    def _direct_value(self, spec: Dict[str, Any], channel, values: List[float]) -> float:
        model_index = int(spec.get("index", 0))
        raw = values[model_index] if 0 <= model_index < len(values) else 0.0
        scale = spec.get("scale")
        if scale:
            return apply_scale(scale, raw)
        return raw

    def _argmax_value(self, spec: Dict[str, Any], channel, values: List[float]) -> float:
        if not values:
            return float(channel.safe_value)
        best_index = 0
        best_value = values[0]
        for index in range(1, len(values)):
            if values[index] > best_value:
                best_value = values[index]
                best_index = index
        classes = spec.get("classes", {}) or {}
        if str(best_index) in classes:
            return float(classes[str(best_index)])
        # An unmapped class is not an error worth stopping the robot for, but
        # guessing a motor speed for it would be. Do the inert thing.
        return float(channel.safe_value)

    def _threshold_value(self, spec: Dict[str, Any], channel, values: List[float]) -> float:
        model_index = int(spec.get("index", 0))
        raw = values[model_index] if 0 <= model_index < len(values) else 0.0
        threshold = float(spec.get("threshold", 0.5))
        if raw >= threshold:
            return float(spec.get("on_value", channel.native_max))
        return float(spec.get("off_value", channel.safe_value))


def compile_config(config: Dict[str, Any], model_meta: Optional[Dict[str, Any]] = None) -> MappingPlan:
    """Validate then compile. Raises :class:`.errors.ConfigError` on failure."""
    validate_config(config, model_meta).raise_if_failed()
    return MappingPlan(config)


def config_hash(config: Dict[str, Any]) -> str:
    """Short stable fingerprint of the parts the device script depends on.

    The device reports this in its hello frame, so a host running a config the
    child has since changed is caught at connect time rather than showing up as
    a robot that drives the wrong motor. Only fields the *script* embeds are
    hashed: retuning a scale on the host must not invalidate a flashed script.
    """
    material = {
        "schema_version": config.get("schema_version", SCHEMA_VERSION),
        "platform": config.get("platform", ""),
        "rate_hz": config.get("rate_hz", 0),
        "watchdog_ms": config.get("watchdog_ms", 0),
        "inputs": [str(entry.get("channel", "")) for entry in config.get("inputs", []) or []],
        "outputs": [str(entry.get("channel", "")) for entry in config.get("outputs", []) or []],
    }
    blob = json.dumps(material, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(blob).hexdigest()[:8]
