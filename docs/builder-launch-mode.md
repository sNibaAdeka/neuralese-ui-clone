# Builder and pilot launch modes

Opening the project in Godot or starting a regular export uses the ordinary
builder startup. It does not ask the classroom-only “Who is working now?”
identity. Existing profile, tutorial and project state still follow the standard
startup coordinator; this mode does not bypass startup or erase saved state.

For an explicit local pilot run, pass `--pilot` as a Godot user argument (after
`--`). For a dedicated exported pilot build, add `neuralese_pilot` to that
export preset's Custom Features. Ordinary presets leave this feature absent.

Pilot enrollment configuration remains required for a pilot launch. The existing
environment/fallback resolution and student/teacher rules are unchanged. Merely
having an enrollment configuration or a saved session does not opt a regular
builder launch into the pilot flow. No extra in-app mode control is introduced.

The production mode resolver is `scripts/startup/builder_launch_mode.gd`, used
by `glob.PILOT_MODE`. `test_builder_launch_mode.gd` checks the default and explicit
opt-ins; `test_startup_flow_coordinator.gd` checks that the standard route does
not open the pilot identity dialog and that the pilot route remains available.
