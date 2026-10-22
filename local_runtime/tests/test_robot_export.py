"""The ``request.json`` -> ``response.json`` entry point and the export bundle.

This is the contract the Godot client codes against, so its shape is pinned here.
Actions that need a trained model are skipped when ``onnx`` is not installed; the
rest run everywhere, which keeps the UI-facing surface covered even in a bare
checkout.
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path

from support import RUNTIME_ROOT  # noqa: F401  (puts the runtime on sys.path)

from neuralese_local.robot import export_robot
from neuralese_local.robot.bundle import CONFIG_FILENAME, MODEL_FILENAME, README_FILENAME, load_bundle_config, write_bundle
from neuralese_local.robot.config import compile_config, config_hash, linear_scale

ENTRY = RUNTIME_ROOT / "neuralese_local" / "robot" / "export_robot.py"


def ev3_config(**overrides):
    base = {
        "schema_version": 1,
        "platform": "ev3",
        "transport": {"kind": "tcp", "host": "ev3dev.local", "port": 9999},
        "rate_hz": 20,
        "watchdog_ms": 400,
        "inputs": [{"channel": "ultrasonic_4", "scale": linear_scale(0, 2550, 0.0, 1.0)}],
        "outputs": [{"channel": "motor_a_speed", "mode": "argmax", "classes": {"0": 60, "1": -60}}],
    }
    base.update(overrides)
    return base


class RegistryActionTests(unittest.TestCase):
    """Everything the UI needs to draw its screens, without a trained model."""

    def test_list_platforms_describes_all_three_robots(self) -> None:
        result = export_robot.handle_request({"action": "list_platforms"})
        self.assertEqual(result["status"], "ok")
        ids = [platform["id"] for platform in result["platforms"]]
        self.assertEqual(ids, ["microbit", "ev3", "spike"])

    def test_each_platform_carries_what_a_dropdown_needs(self) -> None:
        result = export_robot.handle_request({"action": "list_platforms"})
        for platform in result["platforms"]:
            with self.subTest(platform=platform["id"]):
                self.assertTrue(platform["sensors"])
                self.assertTrue(platform["actuators"])
                self.assertTrue(platform["transports"])
                self.assertIn(platform["default_transport"], platform["transports"])
                self.assertIn("deploy", platform)
                for channel in platform["sensors"] + platform["actuators"]:
                    self.assertTrue(channel["label"])
                    self.assertLess(channel["native_min"], channel["native_max"])

    def test_device_code_is_not_leaked_into_the_ui_payload(self) -> None:
        result = export_robot.handle_request({"action": "list_platforms"})
        blob = json.dumps(result)
        self.assertNotIn("run_forever", blob)
        self.assertNotIn("accelerometer.get_x", blob)

    def test_default_config_without_a_model_still_answers(self) -> None:
        result = export_robot.handle_request({"action": "default_config", "platform": "ev3"})
        self.assertEqual(result["status"], "ok")
        self.assertEqual(result["config"]["platform"], "ev3")

    def test_validate_reports_problems_with_fields_for_the_ui(self) -> None:
        result = export_robot.handle_request({
            "action": "validate",
            "config": ev3_config(inputs=[{"channel": "not_a_sensor"}]),
        })
        self.assertEqual(result["status"], "ok")
        self.assertFalse(result["validation"]["ok"])
        self.assertEqual(result["validation"]["errors"][0]["field"], "inputs[0].channel")

    def test_validate_passes_a_good_config(self) -> None:
        result = export_robot.handle_request({"action": "validate", "config": ev3_config()})
        self.assertTrue(result["validation"]["ok"])
        self.assertEqual(result["config_hash"], config_hash(ev3_config()))

    def test_preview_script_returns_the_program_and_its_filename(self) -> None:
        result = export_robot.handle_request({"action": "preview_script", "config": ev3_config()})
        self.assertEqual(result["filename"], "neuralese_robot.py")
        self.assertIn("def safe_stop():", result["script"])

    def test_list_devices_never_crashes_on_a_missing_optional_dependency(self) -> None:
        # This runs on the "connect your robot" screen; an uninstalled pyserial
        # has to read as an unavailable transport, not as a crash.
        from neuralese_local.robot.errors import MissingDependencyError
        with patch("neuralese_local.robot.transport.SerialTransport._pyserial", side_effect=MissingDependencyError("not installed")):
            result = export_robot.handle_request({"action": "list_devices", "platform": "microbit"})
        self.assertEqual(result["status"], "ok")
        self.assertIn("serial", result["devices"]["transports"])

    def test_an_unknown_action_is_a_clean_error(self) -> None:
        from neuralese_local.robot.errors import RobotError

        with self.assertRaises(RobotError):
            export_robot.handle_request({"action": "teleport"})


class BundleTests(unittest.TestCase):
    """The folder handed to the child. ``write_bundle`` copies the model
    verbatim, so these run without onnx."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.model = self.root / "trained.onnx"
        self.model.write_bytes(b"pretend-onnx-bytes")
        self.plan = compile_config(ev3_config())

    def test_the_bundle_has_everything_needed_to_run(self) -> None:
        result = write_bundle(self.plan, self.model, self.root / "MyRobot")
        self.assertEqual(result["status"], "ok")
        self.assertEqual(
            sorted(result["files"]),
            sorted([README_FILENAME, CONFIG_FILENAME, MODEL_FILENAME, "neuralese_robot.py"]),
        )

    def test_the_model_is_copied_byte_for_byte(self) -> None:
        result = write_bundle(self.plan, self.model, self.root / "MyRobot")
        self.assertEqual(Path(result["model_path"]).read_bytes(), b"pretend-onnx-bytes")

    def test_the_saved_config_can_be_loaded_back(self) -> None:
        # So a child can reconnect to a saved export without exporting again.
        result = write_bundle(self.plan, self.model, self.root / "MyRobot")
        loaded = load_bundle_config(result["output_path"])
        self.assertEqual(loaded["platform"], "ev3")
        self.assertEqual(loaded["config_hash"], config_hash(ev3_config()))

    def test_the_script_and_the_saved_config_agree(self) -> None:
        result = write_bundle(self.plan, self.model, self.root / "MyRobot")
        script = Path(result["script_path"]).read_text(encoding="utf-8")
        self.assertIn('CFG_HASH = "%s"' % result["config_hash"], script)

    def test_existing_folder_is_refused_and_preserved(self) -> None:
        from neuralese_local.robot.errors import RobotError
        target = self.root / "MyRobot"
        target.mkdir()
        (target / "notes.txt").write_text("keep")
        with self.assertRaises(RobotError):
            write_bundle(self.plan, self.model, target)
        self.assertEqual((target / "notes.txt").read_text(), "keep")

    def test_failed_copy_leaves_no_partial_export(self) -> None:
        target = self.root / "MyRobot"
        with patch("neuralese_local.robot.bundle.shutil.copy2", side_effect=OSError("disk failure")):
            with self.assertRaises(OSError):
                write_bundle(self.plan, self.model, target)
        self.assertFalse(target.exists())
        self.assertFalse(list(self.root.glob(".neuralese-export-*")))

    def test_zip_does_not_touch_existing_same_stem_folder(self) -> None:
        target = self.root / "MyRobot"
        target.mkdir()
        (target / "notes.txt").write_text("keep")
        write_bundle(self.plan, self.model, target.with_suffix(".zip"), as_zip=True)
        self.assertEqual((target / "notes.txt").read_text(), "keep")

    def test_existing_zip_is_preserved(self) -> None:
        from neuralese_local.robot.errors import RobotError
        target = self.root / "MyRobot.zip"
        target.write_bytes(b"keep")
        with self.assertRaises(RobotError):
            write_bundle(self.plan, self.model, target, as_zip=True)
        self.assertEqual(target.read_bytes(), b"keep")

    def test_changed_model_is_refused_before_publication(self) -> None:
        from neuralese_local.robot.errors import RobotError
        with self.assertRaises(RobotError):
            write_bundle(self.plan, self.model, self.root / "MyRobot", expected_model_sha256="outdated")
        self.assertFalse((self.root / "MyRobot").exists())

    def test_failed_archive_leaves_no_partial_zip(self) -> None:
        target = self.root / "MyRobot.zip"
        with patch("neuralese_local.robot.bundle.zipfile.ZipFile.write", side_effect=OSError("disk failure")):
            with self.assertRaises(OSError):
                write_bundle(self.plan, self.model, target, as_zip=True)
        self.assertFalse(target.exists())
        self.assertFalse(list(self.root.glob(".neuralese-export-*")))

    def test_failed_publication_preserves_concurrently_added_file(self) -> None:
        import os
        target = self.root / "MyRobot"
        real_link = os.link
        calls = []
        def interrupted_link(source, destination):
            calls.append(destination)
            if len(calls) == 2:
                (target / "notes.txt").write_text("keep")
                raise OSError("disk failure")
            return real_link(source, destination)
        with patch("neuralese_local.robot.bundle.os.link", side_effect=interrupted_link):
            with self.assertRaises(OSError):
                write_bundle(self.plan, self.model, target)
        self.assertEqual([item.name for item in target.iterdir()], ["notes.txt"])
        self.assertEqual((target / "notes.txt").read_text(), "keep")

    def test_symlink_destination_does_not_change_its_target(self) -> None:
        from neuralese_local.robot.errors import RobotError
        existing = self.root / "existing"
        existing.mkdir()
        (existing / "notes.txt").write_text("keep")
        target = self.root / "MyRobot"
        target.symlink_to(existing, target_is_directory=True)
        with self.assertRaises(RobotError):
            write_bundle(self.plan, self.model, target)
        self.assertEqual((existing / "notes.txt").read_text(), "keep")

    def test_the_readme_tells_the_child_what_to_do(self) -> None:
        result = write_bundle(self.plan, self.model, self.root / "MyRobot")
        readme = (Path(result["output_path"]) / README_FILENAME).read_text(encoding="utf-8")
        self.assertIn("ev3dev", readme)
        self.assertIn("neuralese_robot.py", readme)
        # The safety behaviour is stated in the instructions, not only in code.
        self.assertIn("400 ms", readme)

    def test_the_readme_is_available_in_russian(self) -> None:
        result = write_bundle(self.plan, self.model, self.root / "MyRobot", lang="ru")
        readme = (Path(result["output_path"]) / README_FILENAME).read_text(encoding="utf-8")
        self.assertIn("подключение робота ещё недоступно", readme)

    def test_a_zipped_bundle_contains_the_same_files(self) -> None:
        import zipfile

        result = write_bundle(self.plan, self.model, self.root / "MyRobot.zip", as_zip=True)
        self.assertTrue(result.get("zipped"))
        with zipfile.ZipFile(result["output_path"]) as archive:
            self.assertEqual(
                sorted(archive.namelist()),
                sorted([README_FILENAME, CONFIG_FILENAME, MODEL_FILENAME, "neuralese_robot.py"]),
            )


class ModelFingerprintTests(unittest.TestCase):
    def setUp(self):
        try:
            import onnx
        except ImportError:
            self.skipTest("onnx is not installed")
        self.onnx = onnx
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / "trained.onnx"
        self.write_model(1.0)

    def write_model(self, weight):
        onnx = self.onnx
        helper = onnx.helper
        model = helper.make_model(helper.make_graph(
            [helper.make_node("Mul", ["x", "w"], ["y"])], "fingerprint",
            [helper.make_tensor_value_info("x", onnx.TensorProto.FLOAT, [1, 1])],
            [helper.make_tensor_value_info("y", onnx.TensorProto.FLOAT, [1, 1])],
            [helper.make_tensor("w", onnx.TensorProto.FLOAT, [1], [weight])],
        ))
        onnx.save(model, self.path)

    def test_equal_shape_retraining_changes_fingerprint_and_refuses_export(self):
        from neuralese_local.robot.model_meta import read_model_meta
        from neuralese_local.robot.errors import RobotError
        original = read_model_meta(self.path)
        self.write_model(2.0)
        retrained = read_model_meta(self.path)
        self.assertEqual(original["input_size"], retrained["input_size"])
        self.assertNotEqual(original["model_sha256"], retrained["model_sha256"])
        target = self.path.parent / "export"
        with self.assertRaises(RobotError):
            export_robot.handle_request({"action": "export", "model_path": str(self.path), "output_path": str(target), "expected_model_sha256": original["model_sha256"], "config": ev3_config()})
        self.assertFalse(target.exists())

    def test_external_tensor_data_is_rejected_without_reading_external_files(self):
        from neuralese_local.robot.model_meta import read_model_meta
        from neuralese_local.robot.errors import RobotError
        model = self.onnx.load(self.path)
        tensor = model.graph.initializer[0]
        tensor.data_location = self.onnx.TensorProto.EXTERNAL
        field = tensor.external_data.add()
        field.key = "location"
        field.value = "missing-secret-file"
        self.path.write_bytes(model.SerializeToString())
        with self.assertRaisesRegex(RobotError, "self-contained"):
            read_model_meta(self.path)


class ProcessContractTests(unittest.TestCase):
    """The entry point as Godot actually invokes it: a file in, a file out."""

    def _run(self, request: dict):
        with tempfile.TemporaryDirectory() as tmp:
            request_path = Path(tmp) / "request.json"
            request_path.write_text(json.dumps(request), encoding="utf-8")
            process = subprocess.run(
                [sys.executable, str(ENTRY), str(request_path)],
                capture_output=True, text=True, timeout=60,
            )
            response_path = Path(tmp) / "response.json"
            self.assertTrue(response_path.exists(), "No response.json was written. stderr: %s" % process.stderr)
            return process.returncode, json.loads(response_path.read_text(encoding="utf-8"))

    def test_a_good_request_exits_zero_and_writes_a_response(self) -> None:
        code, response = self._run({"action": "list_platforms"})
        self.assertEqual(code, 0)
        self.assertEqual(response["status"], "ok")
        self.assertEqual(len(response["platforms"]), 3)

    def test_a_failing_request_exits_nonzero_with_a_readable_reason(self) -> None:
        code, response = self._run({"action": "validate", "config": {"platform": "nonsense"}})
        # Validation itself succeeds; it is the config that is bad.
        self.assertEqual(code, 0)
        self.assertFalse(response["validation"]["ok"])

    def test_an_unusable_request_reports_an_error_rather_than_a_traceback(self) -> None:
        code, response = self._run({"action": "preview_script", "config": {"platform": "nonsense"}})
        self.assertEqual(code, 1)
        self.assertEqual(response["status"], "error")
        self.assertIn("code", response)
        self.assertTrue(response["error"])


if __name__ == "__main__":
    unittest.main()
