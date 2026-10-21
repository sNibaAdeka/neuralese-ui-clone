"""Shared helpers for the robot tests."""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

RUNTIME_ROOT = Path(__file__).resolve().parents[1]
if str(RUNTIME_ROOT) not in sys.path:
    sys.path.insert(0, str(RUNTIME_ROOT))

from neuralese_local.robot import codec  # noqa: E402
from neuralese_local.robot.config import config_hash  # noqa: E402
from neuralese_local.robot.model_meta import InferenceEngine  # noqa: E402
from neuralese_local.robot.transport import LoopbackTransport  # noqa: E402


class FakeClock:
    """Manually advanced clock, so watchdog behaviour is tested by arithmetic
    rather than by sleeping and hoping."""

    def __init__(self, start: float = 1000.0) -> None:
        self.now = float(start)

    def __call__(self) -> float:
        return self.now

    def advance(self, seconds: float) -> None:
        self.now += float(seconds)


class ScriptedEngine(InferenceEngine):
    """Inference stub. Records what it was asked, returns what it was told to."""

    def __init__(self, outputs: Any = None, raises: Optional[BaseException] = None) -> None:
        self.outputs = outputs if outputs is not None else [1.0]
        self.raises = raises
        self.calls: List[List[float]] = []

    def infer(self, values: Any) -> List[float]:
        self.calls.append([float(v) for v in values])
        if self.raises is not None:
            raise self.raises
        if callable(self.outputs):
            return [float(v) for v in self.outputs(list(values))]
        return [float(v) for v in self.outputs]


class FakeRobot:
    """A robot that speaks the protocol, wired to a loopback transport.

    Used to drive the bridge through handshakes, sensor frames, corruption and
    silence without any hardware. The device-script harnesses in ``emulators/``
    do the same job with the *real* generated scripts; this one is for pinning
    the host's behaviour precisely.
    """

    def __init__(self, config: Dict[str, Any], n_in: int, n_out: int) -> None:
        self.transport = LoopbackTransport()
        self.config = config
        self.n_in = n_in
        self.n_out = n_out
        self.seq = 0
        self.applied: List[List[int]] = []
        self.acked = False
        self.errors: List[str] = []
        self.stopped = False
        self._reader = codec.LineReader()

    def send_hello(self, *, protocol: Optional[int] = None, cfg_hash: Optional[str] = None,
                   platform: Optional[str] = None, n_in: Optional[int] = None,
                   n_out: Optional[int] = None) -> None:
        payload = codec.encode_frame(codec.FRAME_HELLO, [
            codec.PROTOCOL_VERSION if protocol is None else protocol,
            self.config["platform"] if platform is None else platform,
            config_hash(self.config) if cfg_hash is None else cfg_hash,
            self.n_in if n_in is None else n_in,
            self.n_out if n_out is None else n_out,
            self.config.get("rate_hz", 20),
            self.config.get("watchdog_ms", 300),
        ])
        self.transport.robot_send(payload)

    def send_sensors(self, values: List[int], seq: Optional[int] = None) -> int:
        if seq is None:
            self.seq = codec.seq_next(self.seq)
            seq = self.seq
        self.transport.robot_send(codec.encode_sensors(seq, values))
        return seq

    def send_raw(self, data: bytes) -> None:
        self.transport.robot_send(data)

    def drain(self) -> None:
        """Consume everything the host sent, recording commands and errors."""
        for line in self._reader.feed(self.transport.robot_receive()):
            try:
                frame = codec.decode_frame(line)
            except Exception:
                continue
            kind = frame["kind"]
            if kind == codec.FRAME_ACK:
                self.acked = True
            elif kind == codec.FRAME_ACTUATORS:
                self.applied.append(codec.parse_values(frame["fields"])["values"])
            elif kind == codec.FRAME_ERROR:
                self.errors.append(frame["fields"][0])
            elif kind == codec.FRAME_STOP:
                self.stopped = True

    @property
    def last_command(self) -> Optional[List[int]]:
        return self.applied[-1] if self.applied else None
