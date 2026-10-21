# UI integration review

Branch: `codex/claude-design-integration`. Based on `dataset-workspace-dev`
commit `ed5e17268da603645fd7e16b6526c6e15597ae5f`, which includes the native
dataset workspace on top of `dev`.

This branch integrates the graph design, neutral workspace shell, dataset and
simulation styling, export controls, and the original hand-drawn Axon mascot
with finite reactions. Controls use the application's existing state and
handlers. It also includes the compatibility, lifecycle, save-thread and
simulation-worker fixes exercised while integrating the interface, together
with their regression tests. Generated node catalogs were regenerated using
the repository tooling.

Open `project.godot` in Godot 4.7.1 and allow asset import. The application uses
the separate `Neuralese-Dev-Design` user-data directory. Fonts and their OFL
licenses, mascot sheets, dataset previews, shaders, UID files and import
settings are included. Engine import caches are not required.

For review without a remote session, launch with `-- --local-api` (the local
API is expected at port 8081). For a scripted desktop review, add
`--claude-design-check --design-output=<absolute-output-directory>` after `--`;
this uses a disposable project copy and writes screenshots. Verification
commands are documented in `AGENTS.md`.

Known limits:

- The Windows runtime lock now covers all requirements, including pyserial,
  and uses a stable CRLF/LF checksum. Its generator has regression coverage;
  running the packaged Windows interpreter still requires a Windows build.
- Live Axon responses and full server training require a valid server session
  and have not been verified. No server responses or training progress are faked.
- Physical EV3, micro:bit and SPIKE hardware was not connected for validation.
- Full built-in MNIST export still warns about the missing local `.ds` file;
  portability of all 70,000 examples is not confirmed. Test CSV export works.
Verified corrections include the compact toolbar, brighter finite mascot
reactions, semantic node colors, keyboard/focus states, CSV header/delimiter
preview, reconnect undo/redo, complete table columns and checked HTTP exports.
Data cards and menus share neutral surfaces and control radii. Worker shutdown
also closes an owned child that is still bootstrapping, so quitting the app
during runtime warm-up does not leave a process holding output pipes.

A real local runtime trained a small synthetic dataset through Godot's worker,
performed prediction and exported ONNX with identical outputs before/after
export. This is a functional smoke test, not a model-quality benchmark.
See `local_runtime/README.md` for a project-scoped Python 3.11 setup.

The separate private source snapshot excludes local environments, caches,
logs, sensitive operational documents and prebuilt runtime archives. It keeps
required project assets, bundled dataset provenance and third-party notices.
The original working clone and its Git history remain available locally.
