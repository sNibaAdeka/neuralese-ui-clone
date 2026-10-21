from pathlib import Path


PROJECT_ROOT = Path(__file__).parents[2]


def _read(relative_path: str) -> str:
    return (PROJECT_ROOT / relative_path).read_text(encoding="utf-8")


def test_windows_build_uses_the_current_checkout() -> None:
    script = _read("build.ps1")

    assert 'D:\\NRLSE\\nnets\\teachneurons' not in script
    assert "$ProjectRoot = (Resolve-Path $PSScriptRoot).Path" in script
    assert 'Join-Path $ProjectRoot "tools\\export_windows_with_runtime.ps1"' in script


def test_windows_build_passes_the_fresh_payload_and_brand_assets_to_setup() -> None:
    script = _read("build.ps1")

    assert 'Join-Path $InstallerRoot "game.zip"' in script
    assert 'Join-Path $ProjectRoot "neuralese.png"' in script
    assert "-PayloadZip $PayloadZip" in script
    assert "-LogoPng $LogoPng" in script


def test_windows_export_rejects_missing_or_stale_output() -> None:
    script = _read("tools/export_windows_with_runtime.ps1")

    assert "Remove-Item -LiteralPath $OutputPath -Force" in script
    assert 'throw "Godot export did not create the expected executable' in script
    assert 'throw "Godot export returned a stale executable' in script


def test_windows_executables_use_neuralese_icons() -> None:
    project = _read("project.godot")
    presets = _read("export_presets.cfg")

    assert 'config/windows_native_icon="res://icon.ico"' in project
    assert 'application/modify_resources=true' in presets
    assert 'application/icon="res://icon.ico"' in presets
    assert (PROJECT_ROOT / "icon.ico").stat().st_size > 1024


def test_managed_msi_workflow_installs_the_real_exported_application() -> None:
    workflow = _read(".github/workflows/build-managed-msi.yml")

    assert "MANAGED_MSI_PATH=" in workflow
    assert "MANAGED_EXE_SHA256=" in workflow
    assert "tools\\test_managed_msi.ps1" in workflow
    assert "Test real managed MSI installation" in workflow
    assert "timeout-minutes: 20" in workflow
    assert "if: always()" in workflow


def test_real_msi_smoke_test_covers_install_launch_identity_and_uninstall() -> None:
    script = _read("tools/test_managed_msi.ps1")

    assert 'msiexec.exe' in script
    assert '"/i"' in script
    assert '"--rendering-method", "gl_compatibility"' in script
    assert '"--headless"' not in script
    assert '"--quit-after", "180"' in script
    assert "RedirectStandardOutput" in script
    assert "RedirectStandardError" in script
    assert '"/x"' in script
    assert "ExpectedExeSha256" in script
    assert "Get-FileHash" in script
    assert "WaitForExit" in script
    assert "Kill($true)" in script
    assert 'Neuralese.exe' in script
    assert 'Neuralese.lnk' in script
    assert 'Find-ManagedArpEntries' in script


def test_installer_payload_overlays_current_builtin_datasets() -> None:
    script = _read("tools/prepare_windows_installer_payload.ps1")

    assert 'Join-Path $ProjectRoot "local_runtime\\datasets"' in script
    assert 'Join-Path $destRoot "datasets"' in script
    assert 'Copy-Item -LiteralPath $sourceDatasets' in script
    assert '"eco_ai\\train.npz"' in script
    assert (PROJECT_ROOT / "local_runtime/datasets/eco_ai/train.npz").is_file()


def test_installer_compiles_and_tests_checkout_runtime_before_archiving() -> None:
    script = _read("tools/prepare_windows_installer_payload.ps1")
    assert '$codeFingerprint = & $pythonExe' in script
    assert script.index('tools\\stage_runtime_code.py') < script.index("Compress-Archive")
    assert script.index("test_classification_training_e2e.py") < script.index("Compress-Archive")
    assert 'code_source = "checkout"' in script
    assert 'throw "Packaged runtime classification training smoke test failed"' in script


def test_exe_release_can_skip_msi_packaging_without_skipping_ci_gate() -> None:
    workflow = _read(".github/workflows/build-windows-branch.yml")
    assert "build_msi:" in workflow and "default: true" in workflow
    assert "if: github.event_name != 'workflow_dispatch' || inputs.build_msi" in workflow
    gate = workflow.split("- name: Verify commit CI status", 1)[1].split(
        "- name: Restore Godot download cache", 1
    )[0]
    assert "build_msi" not in gate
    assert "successful Verify check" in gate
