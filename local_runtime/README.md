# Neuralese FullyLocal Runtime

This folder contains the Python runtime launched by `scripts/run_manager.gd` when `FullyLocalConfig.TRAINING` is enabled.

The trainer accepts two dataset sources:

- `builtin_numpy`: checked-in numpy datasets under `local_runtime/datasets/<name>/`.
- `godot_json`: a raw, uncompressed JSON export of a user-created Godot dataset written into the local training job directory by `scripts/run_manager.gd`.

The Godot-side RLE/block dataset cache is only for websocket dataset upload. FullyLocal training bypasses it and reads the raw project dataset from `glob.dataset_datas`.

Development setup on Windows:

```powershell
.\local_runtime\setup_local_python.ps1 -Python C:\path\to\python3.11.exe
python .\local_runtime\tools\build_builtin_datasets.py
```

The shipped app should include `local_runtime/python/` with `numpy`, `onnx`, `onnxruntime-training-cpu`, and `lmdb` installed. Godot looks for:

- `res://local_runtime/python/python.exe`
- `res://local_runtime/python/Scripts/python.exe`
- executable-adjacent `local_runtime/python/python.exe`
- executable-adjacent `local_runtime/python/Scripts/python.exe`

`setup_local_python.ps1` always rebuilds the isolated directory instead of
installing over an old venv. It also rewrites `runtime_packages.lock.json` with
the Python ABI, pinned package versions, the requirements hash, and distribution
metadata hashes. This prevents stale package metadata from surviving a runtime
upgrade under a renamed wheel.
- fallback `python` on `PATH`

Development setup on macOS/Linux (from the repository root, Python 3.11):

```sh
python3.11 -m venv local_runtime/python
local_runtime/python/bin/python -m pip install --index-url https://pypi.org/simple -r local_runtime/requirements.txt
local_runtime/python/bin/python -m pip check
```

Use a fresh project environment; do not install these packages into the global
Python environment or layer them over a different ONNX Runtime distribution.
The Godot editor bootstrap also discovers `local_runtime/python/bin/python3`
and `local_runtime/python/bin/python`. The `onnxruntime-training-cpu` package is
required: inference-only `onnxruntime` does not provide the training API.
The pinned 1.19.2 release provides CPython 3.11 macOS universal2 wheels.

`runtime_packages.lock.json` contains the Windows distribution metadata snapshot.
Do not replace its platform-specific metadata hashes with a macOS/Linux snapshot.
The generator includes every exact pin from requirements and normalizes CRLF/LF
for the requirements checksum. An exported application still requires a packaged
runtime and its platform manifest; creating this editor venv does not build or
verify a Windows/macOS release.

Progress is written as JSON lines to `user://fullylocal/jobs/<job_id>/progress.jsonl`. Stop requests are sent by creating `user://fullylocal/jobs/<job_id>/stop`.

The legacy Neuralese `.ds` converter for project-specific datasets is `local_runtime/neuralese_local/legacy_ds.py`. It currently backs the checked-in `car_track` numpy dataset.
