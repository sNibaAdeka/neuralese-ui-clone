# Neuralese Builder — UI clone

This is the independent [UI clone](https://github.com/sNibaAdeka/neuralese-ui-clone/tree/codex/claude-design-integration), on branch `codex/claude-design-integration`. Open the checked-out Godot project to run this version. Screenshots are not a separate web application. See the [diagnosis, changes, real screenshots and verification limits](docs/builder-diagnostics-2026-10-22.md).

Neuralese Frontend is the desktop client for building, training, and testing neural network projects through a visual interface.

It is designed for learners who want to understand how models are assembled and iterated without starting from raw code.

Neuralese Backend (API) repo link: https://github.com/hex358/neuralese-api/

---

## What this app does

The frontend focuses on the full learning workflow:

- **Visual model building** through a node-graph editor (layers + connections).
- **Dataset workbench** for inspecting and preparing data.
- **Training orchestration UI** that sends model/data jobs to the backend.
- **Live project management** for lessons, class workflows, and experiments.
- **AI assistant integration hooks** used by in-app mentoring features.

The project is implemented in **Godot 4.x** and uses a modular autoload setup for global services such as networking, graph management, dataset helpers, and runtime orchestration.

---

## High-level architecture (frontend side)

At runtime, the client initializes several singleton-like services (autoloads) for key responsibilities:

- `web` → HTTP/SSE request layer for API calls.
- `sockets` → realtime communication.
- `graphs` → graph state and editing flow.
- `dsl_reg` / `parser` → graph and scripting-related parsing/registry flow.
- `dsreader` → dataset helper utilities.
- `nn` / `learner` → run and training orchestration from the UI side.
- `ui`, `glob`, `cookies` → global UI state, environment config, and auth/session helpers.

The frontend can switch connection mode for development/deployment contexts:

- **Remote** (default): hosted API endpoint resolved by `scripts/network_mode.gd`.
- **Localhost**: pass `--local-api` after `--`; uses `http://127.0.0.1:8081/`.
- **LAN**: pass `--lan-api` for the configured local-network host.

Local model training uses the Python runtime described below; it does not require a running HTTP backend. Remote assistant, account and server features still require their services.

---

## Main user workflows

1. **Create/open a project**
   - Start a project workspace and select an activity (lesson, sandbox experiment, class task).

2. **Build a model graph**
   - Add layers as nodes, connect flows, and adjust layer settings.
   - Use graph-level feedback to correct invalid architecture paths.

3. **Prepare data**
   - Import or edit datasets in the app.
   - Apply basic transformations and organize data for training.

4. **Train and observe**
   - Launch training from the frontend.
   - Monitor progress, metrics, and intermediate behavior.

5. **Iterate / export-ready workflow**
   - Refine architecture and parameters based on outcomes.
   - Continue until model behavior matches task goals.

---

## Running the frontend locally

### Prerequisites

- **Godot 4.7.1**, matching `project.godot` and the tests.
- **Python 3.11** in a project environment for local training; source downloads do not contain an installed Python runtime.

### Steps

1. Check out branch `codex/claude-design-integration` and import `project.godot` in Godot.
2. For local training, follow [local_runtime/README.md](local_runtime/README.md) to prepare the pinned dependencies in `local_runtime/python/`. This directory stays out of Git.
3. Run the main project with **F5**. A regular launch uses the builder startup. Classroom enrollment is an explicit [pilot mode](docs/builder-launch-mode.md).
4. Create a project or open a bundled example. Saved graph positions are preserved; **More → Arrange model** explicitly arranges the current graph.

From a terminal, `godot --path .` starts the project. For development against a local HTTP API use `godot --path . -- --local-api`; no source edit is needed.

EV3 configuration and safe bundle export are available from the Export window. See [the EV3 workflow](docs/ev3-export-workflow.md) for mapping, validation and current hardware limitations.

Opening source in the editor is not a packaged release. Windows/macOS exports need their platform runtime payload and manifest. Physical EV3, remote Axon and account flows require their respective hardware/services and cannot be validated by local editor tests alone.

---

## Who this README is for

This README is intended for new users and contributors who need a practical orientation to the Neuralese frontend app (what it is, how it works, and how to start it locally).

If you are integrating backend services, start from `scripts/web.gd` and `scripts/glob.gd` to understand API root selection and request flow.
