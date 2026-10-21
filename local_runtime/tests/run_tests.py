#!/usr/bin/env python3
"""Test runner for the robot export feature.

    python3 local_runtime/tests/run_tests.py              # everything offline
    python3 local_runtime/tests/run_tests.py --emulators  # + the EV3 emulator
    python3 local_runtime/tests/run_tests.py --fast       # protocol/logic only

Three tiers, and the difference between them matters when reading the results:

fast
    Pure logic: the wire protocol, config validation and scaling, script
    generation snapshots, and the host control loop driven against a fake clock.
    No dependencies, no network, no threads, milliseconds to run.

stub-device
    The *generated* micro:bit and SPIKE scripts really execute, against stubbed
    ``microbit`` / ``pybricks`` modules, talking the real protocol to the real
    host bridge over a byte pipe. Not an emulator -- the micro:bit simulator
    ships no binary artefact and no SPIKE simulator exists at all -- so this
    cannot catch MicroPython dialect gaps, RAM limits or real timing.

emulator
    The genuine article, for the EV3 only: the generated script runs against the
    real ``ev3dev2`` library driving a real fake-sysfs device tree, over a real
    socket. Motor assertions read the same files a motor driver would. Needs a
    one-off clone from GitHub, so it is opt-in.
"""

from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

TESTS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(TESTS_DIR))
sys.path.insert(0, str(TESTS_DIR.parent))

TIERS = {
    "fast": [
        "test_robot_codec",
        "test_robot_config",
        "test_robot_generate",
        "test_robot_bridge",
        "test_robot_export",
    ],
    "stub-device": [
        "test_stub_device_microbit",
        "test_stub_device_spike",
    ],
    "emulator": [
        "test_emulator_ev3",
    ],
}


def main(argv: list) -> int:
    fast_only = "--fast" in argv
    with_emulators = "--emulators" in argv
    if with_emulators:
        os.environ.setdefault("NEURALESE_EMULATORS", "1")

    names = list(TIERS["fast"])
    if not fast_only:
        names += TIERS["stub-device"]
        names += TIERS["emulator"]

    loader = unittest.TestLoader()
    suite = unittest.TestSuite(loader.loadTestsFromName(name) for name in names)
    result = unittest.TextTestRunner(verbosity=2 if "-v" in argv else 1).run(suite)

    if result.skipped:
        print("\nSkipped %d test(s):" % len(result.skipped))
        for test, reason in result.skipped:
            print("  %s\n    %s" % (test, reason))
        if not with_emulators:
            print("\nRun with --emulators to include the EV3 emulator tier.")

    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
