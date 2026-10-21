# Verification — 21 October 2026

Verified locally with Godot 4.7.1 and a project-scoped Python 3.11 environment:

- Full Godot runner: 110 passed. The autosave unwritable-directory test intentionally logs its rejected write. No unexpected engine errors in final focused checks.
- Python node/docs/release/integration suites: 130 passed, 1 skipped, 42 subtests passed. The skip is actual Windows interpreter verification on macOS.
- Generated node registry and all 21 scenes passed.
- Four resident-training-worker Python tests passed, including parent death during warm-up.
- Real Godot training on synthetic data: start, progress, completion, prediction, ONNX export and stop passed. Full ONNX validation and CPU execution passed; exported predictions match Godot predictions (maximum absolute difference 0.0).
- Native rendered smoke: 27 screenshots covering desktop/narrow layouts, CSV preview, 12-column table scrolling, data editing, menus/keyboard, graph undo/redo, save/reload and simulation controls.

This is not complete product coverage: live Axon/server authentication, physical robots, Windows installer execution, packaged macOS runtime and all model/loss/export combinations were not verified. Tiny synthetic training is not evidence of general model quality.

The source snapshot preserves project assets and third-party notices but omits local runtimes, caches, logs, operational secret documents and historical Git objects. Runtime setup is documented in local_runtime/README.md. Source provenance and authors are recorded at repository root.
