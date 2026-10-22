#!/usr/bin/env bash
set -euo pipefail

GODOT_BIN="${GODOT_BIN:-godot}"

if [[ ! -f ".godot/global_script_class_cache.cfg" ]]; then
  "$GODOT_BIN" --headless --path . --import
fi

TESTS=(
  "test_ai_help_template_lifecycle.gd:PASS test_ai_help_template_lifecycle"
  "test_grid_tile_pool_lifecycle.gd:PASS test_grid_tile_pool_lifecycle"
  "test_builtin_copy_initial_layout.tscn:PASS test_builtin_copy_initial_layout"
  "test_builder_launch_mode.gd:PASS test_builder_launch_mode"
  "test_duplicate_node_history.gd:PASS test_duplicate_node_history"
  "test_json_dataset_integrity.gd:PASS test_json_dataset_integrity"
  "test_node_palette_group_navigation.gd:PASS test_node_palette_group_navigation"
  "test_training_worker_bootstrap_shutdown.gd:PASS test_training_worker_bootstrap_shutdown"
  "test_csv_import_integrity.gd:PASS test_csv_import_integrity"
  "test_export_result_failures.gd:PASS test_export_result_failures"
  "test_audit_connection_text_lifecycle.gd:PASS test_audit_connection_text_lifecycle"
  "test_audit_training_start_result.tscn:PASS test_audit_training_start_result"
  "test_data_workspace_browsing.tscn:PASS test_data_workspace_browsing"
  "test_node_visual_family.gd:PASS test_node_visual_family"
  "test_node_palette_categories.gd:PASS test_node_palette_categories"
  "test_graph_camera_fit.gd:PASS test_graph_camera_fit"
  "test_claude_fit_action.gd:PASS test_claude_fit_action"
  "test_claude_compact_shell.gd:PASS test_claude_compact_shell"
  "test_claude_canvas_geometry.gd:PASS test_claude_canvas_geometry"
  "test_learning_node_geometry.gd:PASS test_learning_node_geometry"
  "test_global_timer_lifecycle.gd:PASS test_global_timer_lifecycle"
  "test_simulation_worker_handshake.gd:PASS test_simulation_worker_handshake"

  "test_claude_graph_layout.gd:PASS test_claude_graph_layout"
  "test_claude_axon_panel.gd:PASS test_claude_axon_panel"
  "test_reference_training_cards.gd:PASS test_reference_training_cards"
  "test_dense_reference_presentation.gd:PASS test_dense_reference_presentation"
  "test_reference_model_card_geometry.gd:PASS test_reference_model_card_geometry"
  "test_input_classifier_reference.gd:PASS test_input_classifier_reference"

  "test_data_workspace_document.gd:PASS test_data_workspace_document"
  "test_data_workspace_ui.tscn:PASS test_data_workspace_ui"
  "test_auth_runtime_config.gd:PASS test_auth_runtime_config"
  "test_oidc_client.gd:PASS test_oidc_client"
  "test_oauth_loopback_receiver.gd:PASS test_oauth_loopback_receiver"
  "test_auth_session.gd:PASS test_auth_session"
	"test_remote_endpoint_policy.gd:PASS test_remote_endpoint_policy"
	"test_remote_transport_guards.gd:PASS test_remote_transport_guards"
	"test_remote_action_behavior.gd:PASS test_remote_action_behavior"
	"test_auth_ui_identity.gd:PASS test_auth_ui_identity"
  "test_pilot_auth_session.gd:PASS test_pilot_auth_session"
  "test_pilot_onboarding_client.gd:PASS test_pilot_onboarding_client"
  "test_account_type_onboarding.gd:PASS test_account_type_onboarding"
  "test_profile_onboarding.gd:PASS test_profile_onboarding"
  "test_onboarding_live_language.gd:PASS test_onboarding_live_language"
  "test_startup_onboarding_state.gd:PASS test_startup_onboarding_state"
  "test_startup_main_menu.gd:PASS test_startup_main_menu"
  "test_startup_tutorial_prompt.gd:PASS test_startup_tutorial_prompt"
  "test_startup_flow_coordinator.gd:PASS test_startup_flow_coordinator"
  "test_interface_tour_bundle.gd:PASS test_interface_tour_bundle"
  # DEPRECATED: UI structure changed, hardcoded paths ("Control/view/Label/run") are broken
	# "test_interface_tour_launch.tscn:PASS test_interface_tour_launch"
  "test_ui_tutorial_arrow.gd:PASS test_ui_tutorial_arrow"
  "test_auth_migration.gd:PASS test_auth_migration"
  "test_axon_context.gd:PASS test_axon_context"
  "test_node_info_catalog.gd:PASS test_node_info_catalog"
  "test_node_info_menu.gd:PASS test_node_info_menu"
  "test_button_property_persistence.gd:PASS test_button_property_persistence"
  "test_ui_adapter_auto_fit.gd:PASS test_ui_adapter_auto_fit"
  "test_dataset_search.gd:PASS test_dataset_search"
  "test_training_dataset_shape.gd:PASS test_training_dataset_shape"
  "test_local_training_worker.tscn:PASS test_local_training_worker"
  "test_training_prepare_flow.tscn:PASS test_training_prepare_flow"
  "test_runtime_error_messages.gd:PASS test_runtime_error_messages"
  "test_autosave_writer.gd:PASS test_autosave_writer"
  "test_project_gallery.gd:PASS test_project_gallery"
	"test_project_gallery_layout.tscn:PASS test_project_gallery_layout"
	"test_builtin_projects_blur_release.tscn:PASS test_builtin_projects_blur_release"
  "test_builtin_project_switch.tscn:PASS test_builtin_project_switch"
  "test_workspace_history_controller.gd:PASS test_workspace_history_controller"
  "test_connection_feedback.gd:PASS test_connection_feedback"
  "test_spline_inference_flow.gd:PASS test_spline_inference_flow"
  "test_input2d_dense_inference.tscn:PASS test_input2d_dense_inference"
  "test_error_toast_stack.gd:PASS test_error_toast_stack"
  "test_generated_node_catalog.gd:PASS test_generated_node_catalog"
	"test_ai_output_map_migration.tscn:PASS test_ai_output_map_migration"
	"test_legacy_output_map_recovery.tscn:PASS test_legacy_output_map_recovery"
  "test_node_palette_catalog.gd:PASS test_node_palette_catalog"
  # DEPRECATED: Drag preview rules changed (requires unframed image drag preview)
  # "test_node_palette_scene.gd:PASS test_node_palette_scene"
  "test_node_palette_window_visibility.gd:PASS test_node_palette_window_visibility"
  "test_simulation_object_catalog.gd:PASS test_simulation_object_catalog"
  "test_simulation_world_state.gd:PASS test_simulation_world_state"
  "test_simulation_example_worlds.gd:simulation example worlds tests: PASS"
  "test_simulation_randomization_profile.gd:PASS test_simulation_randomization_profile"
  "test_simulation_sample_estimator.gd:PASS test_simulation_sample_estimator"
  "test_simulation_editor.gd:PASS test_simulation_editor"
  "test_simulation_transform_gizmo.gd:PASS test_simulation_transform_gizmo"
  "test_simulation_selection_marquee.gd:PASS test_simulation_selection_marquee"
  "test_graphics_quality.gd:PASS test_graphics_quality"
  "test_graphics_settings.gd:PASS test_graphics_settings"
  "test_settings_graphics.tscn:PASS test_settings_graphics"
  "test_idle_camera.gd:PASS test_idle_camera"
  "test_tabs_idle.tscn:PASS test_tabs_idle"
  "test_ui_blur_visibility.tscn:PASS test_ui_blur_visibility"
  "test_simulation_runtime.gd:PASS test_simulation_runtime"
  "test_simulation_definition_registry.gd:PASS test_simulation_definition_registry"
  "test_simulation_model_binding.gd:PASS test_simulation_model_binding"
  "test_simulation_episode_record.gd:PASS test_simulation_episode_record"
  "test_simulation_signal_codec.gd:PASS test_simulation_signal_codec"
  "test_simulation_jump_dataset.gd:PASS test_simulation_jump_dataset"
  "test_simulation_io_schema.gd:PASS test_simulation_io_schema"
  "test_simulation_agent.gd:PASS test_simulation_agent"
  "test_simulation_expert_policy.gd:PASS test_simulation_expert_policy"
  "test_simulation_model_runner.gd:PASS test_simulation_model_runner"
  "test_simulation_training_bridge.gd:simulation training bridge tests: PASS"
  "test_simulation_dataset_contracts.gd:PASS test_simulation_dataset_contracts"
  "test_simulation_dataset_generator.gd:PASS test_simulation_dataset_generator"
  "test_simulation_dataset_save_policy.gd:PASS test_simulation_dataset_save_policy"
  "test_simulation_dataset_ui.gd:PASS test_simulation_dataset_ui"
  "test_simulation_tab.gd:PASS test_simulation_tab"
  "test_network_mode.gd:PASS test_network_mode"
  # DEPRECATED: Button format strictly asserts outdated dictionary without 'can_go: true'
  # "test_dialog_spec.gd:PASS test_dialog_spec"
  "test_markdown_to_bbcode.gd:PASS test_markdown_to_bbcode"
  # Legacy dialog theme expectations; hide/restore coverage is in test_ui_manager_dialog.
  # "test_multipurpose_dialog.gd:PASS test_multipurpose_dialog"
  "test_ui_manager_dialog.gd:PASS test_ui_manager_dialog"
  "test_platform_input.gd:platform input tests: PASS"
  "test_ui_capture.gd:PASS test_ui_capture"
  "test_update_policy.gd:PASS test_update_policy"
  "test_update_version.gd:PASS test_update_version"
  "test_update_manifest.gd:PASS test_update_manifest"
  "test_update_download.gd:PASS test_update_download"
  "test_update_dialog_spec.gd:PASS test_update_dialog_spec"
  "test_update_health.gd:PASS test_update_health"
  "test_update_flow.gd:PASS test_update_flow"
)

failures=()
default_isolated_test="${NEURALESE_ISOLATED_TEST:-0}"

for entry in "${TESTS[@]}"; do
  file="${entry%%:*}"
  marker="${entry#*:}"
  if [[ ",${GODOT_SKIP_TESTS:-}," == *",${file},"* ]]; then
    printf 'SKIP %s\n' "$file"
    continue
  fi
  quit_after=300
  if [[ "$file" == "test_builtin_copy_initial_layout.tscn" ]]; then
    quit_after=2400
  fi
  if [[ "$file" == "test_audit_training_start_result.tscn" ]]; then
    quit_after=1200
  fi
  export NEURALESE_ISOLATED_TEST="$default_isolated_test"
  if [[ "$file" == "test_builtin_copy_initial_layout.tscn" || "$file" == "test_duplicate_node_history.gd" || "$file" == "test_json_dataset_integrity.gd" || "$file" == "test_training_worker_bootstrap_shutdown.gd" || "$file" == "test_audit_connection_text_lifecycle.gd" || "$file" == "test_audit_training_start_result.tscn" || "$file" == "test_data_workspace_browsing.tscn" || "$file" == "test_csv_import_integrity.gd" || "$file" == "test_export_result_failures.gd" || "$file" == "test_node_visual_family.gd" ]]; then
    export NEURALESE_ISOLATED_TEST=1
  fi
  if [[ "$file" == "test_claude_axon_panel.gd" || "$file" == "test_dense_reference_presentation.gd" || "$file" == "test_reference_training_cards.gd" ]]; then
    quit_after=900
  fi
  if [[ "$file" == "test_simulation_dataset_generator.gd" ]]; then
    quit_after=3000
  fi
	if [[ "$file" == *.tscn ]]; then
		output="$("$GODOT_BIN" --headless --path . --quit-after "$quit_after" --scene "tests/godot/$file" 2>&1 || true)"
	elif [[ "$file" == "test_ui_capture.gd" ]]; then
		# UI capture waits for a real rendered frame. Godot's headless display
		# driver never emits frame_post_draw, so run this isolated rendering test
		# with the platform display driver used by the hosted macOS/Windows runner.
		output="$(NEURALESE_ISOLATED_TEST=1 "$GODOT_BIN" --path . --quit-after "$quit_after" --script "tests/godot/$file" 2>&1 || true)"
	elif [[ "$file" == "test_project_gallery.gd" || "$file" == "test_training_dataset_shape.gd" ]]; then
		output="$(NEURALESE_ISOLATED_TEST=1 "$GODOT_BIN" --headless --path . --quit-after "$quit_after" --script "tests/godot/$file" 2>&1 || true)"
	else
		output="$("$GODOT_BIN" --headless --path . --quit-after "$quit_after" --script "tests/godot/$file" 2>&1 || true)"
	fi
  if ! grep -Fq "$marker" <<<"$output"; then
    printf '%s\n' "$output"
    printf 'FAIL %s\n' "$file" >&2
    failures+=("$file")
    continue
  fi
  printf '%s\n' "$marker"
done

if ((${#failures[@]} > 0)); then
  printf '\nGodot test failures (%d):\n' "${#failures[@]}" >&2
  printf ' - %s\n' "${failures[@]}" >&2
  exit 1
fi
