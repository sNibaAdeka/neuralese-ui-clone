from __future__ import annotations

import email
import hashlib
import json
import importlib.util
import subprocess
from pathlib import Path
from types import SimpleNamespace

import pytest


ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "local_runtime"
LOCK = RUNTIME / "runtime_packages.lock.json"
REQUIREMENTS = RUNTIME / "requirements.txt"


def _normalize(name: str) -> str:
    return name.lower().replace("_", "-").replace(".", "-")


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _site_packages() -> Path | None:
    embedded = RUNTIME / "python" / "Lib" / "site-packages"
    return embedded if embedded.is_dir() else None


def _installed_metadata(site_packages: Path) -> list[dict[str, str | Path]]:
    result = []
    for path in site_packages.glob("*.dist-info/METADATA"):
        message = email.message_from_bytes(path.read_bytes())
        result.append(
            {
                "name": message.get("Name", ""),
                "version": message.get("Version", ""),
                "path": path,
            }
        )
    return result


def _manifest_tool():
    spec = importlib.util.spec_from_file_location(
        "runtime_package_manifest", ROOT / "tools" / "write_local_runtime_package_manifest.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_runtime_lock_covers_every_exact_requirement():
    manifest = json.loads(LOCK.read_text(encoding="utf-8"))
    assert manifest["schema"] == 1
    assert manifest["python"] == {"implementation": "cpython", "major_minor": "3.11"}
    assert manifest["requirements_sha256"] == hashlib.sha256(
        REQUIREMENTS.read_bytes().replace(b"\r\n", b"\n")
    ).hexdigest()
    names = [_normalize(item["name"]) for item in manifest["packages"]]
    assert len(names) == len(set(names)), "Duplicate packages in runtime lock"
    pins = _manifest_tool().read_pinned_requirements(REQUIREMENTS)
    assert {_normalize(item["name"]): item["version"] for item in manifest["packages"]} == pins
    assert pins["onnxruntime-training-cpu"] == "1.19.2"
    assert pins["pyserial"] == "3.5"
    for package in manifest["packages"]:
        digest = package["metadata_sha256"]
        assert len(digest) == 64 and all(char in "0123456789abcdef" for char in digest)


def test_embedded_runtime_has_one_locked_ort_training_distribution():
    manifest = json.loads(LOCK.read_text(encoding="utf-8"))
    packages = {_normalize(item["name"]): item for item in manifest["packages"]}
    site_packages = _site_packages()
    if site_packages is None:
        pytest.skip("Windows embedded runtime is absent; installed metadata/imports need a Windows build")
    installed = _installed_metadata(site_packages)
    ort_training = [
        item
        for item in installed
        if _normalize(str(item["name"])).startswith("onnxruntime-training")
    ]
    assert [(item["name"], item["version"]) for item in ort_training] == [
        ("onnxruntime-training-cpu", "1.19.2")
    ]

    by_name = {_normalize(str(item["name"])): item for item in installed}
    for name, locked in packages.items():
        assert sum(_normalize(str(item["name"])) == name for item in installed) == 1
        current = by_name[name]
        assert current["version"] == locked["version"]
        assert _sha256(Path(current["path"])) == locked["metadata_sha256"]

    python_exe = RUNTIME / "python" / "python.exe"
    if not python_exe.is_file():
        python_exe = RUNTIME / "python" / "Scripts" / "python.exe"
    assert python_exe.is_file(), "Windows runtime Python executable is absent"
    imported = json.loads(
        subprocess.check_output(
            [
                str(python_exe),
                "-c",
                (
                    "import json,numpy,onnx,onnxruntime,lmdb,serial;"
                    "print(json.dumps({'numpy':numpy.__version__,'onnx':onnx.__version__,"
                    "'onnxruntime-training-cpu':onnxruntime.__version__,"
                    "'lmdb':lmdb.__version__,'pyserial':serial.VERSION}))"
                ),
            ],
            text=True,
        )
    )
    for name, version in imported.items():
        assert version == packages[name]["version"]


@pytest.mark.parametrize("line", ["numpy>=1.0", "numpy==1.*", "-r other.txt", "numpy==1.0; os_name == 'nt'", ""])
def test_manifest_generator_rejects_unrepresentable_requirements(tmp_path, line):
    requirements = tmp_path / "requirements.txt"
    requirements.write_text(line, encoding="utf-8")
    with pytest.raises(RuntimeError):
        _manifest_tool().read_pinned_requirements(requirements)


def test_manifest_generator_reads_all_pins_and_ignores_comments(tmp_path):
    requirements = tmp_path / "requirements.txt"
    requirements.write_text("# optional bleak==0.22.3\nnumpy==1.26.4\n\npyserial==3.5 # robot USB\n", encoding="utf-8")
    assert _manifest_tool().read_pinned_requirements(requirements) == {
        "numpy": "1.26.4", "pyserial": "3.5"
    }
    requirements.write_text("PySerial==3.5\npyserial==3.5\n", encoding="utf-8")
    with pytest.raises(RuntimeError, match="Duplicate"):
        _manifest_tool().read_pinned_requirements(requirements)


def _fake_distribution(tmp_path, name, version):
    directory = tmp_path / (name + "-" + version + ".dist-info")
    directory.mkdir(exist_ok=True)
    (directory / "METADATA").write_text(f"Name: {name}\nVersion: {version}\n", encoding="utf-8")
    return SimpleNamespace(metadata={"Name": name}, version=version, _path=directory)


@pytest.mark.parametrize("problem", ["missing", "wrong-version", "duplicate", "missing-metadata", "duplicate-ort"])
def test_manifest_generator_rejects_incoherent_installed_packages(tmp_path, monkeypatch, problem):
    requirements = tmp_path / "requirements.txt"
    requirements.write_text("onnxruntime-training-cpu==1.19.2\npyserial==3.5\n", encoding="utf-8")
    distributions = [_fake_distribution(tmp_path, "onnxruntime-training-cpu", "1.19.2")]
    if problem != "missing":
        serial = _fake_distribution(tmp_path, "pyserial", "3.4" if problem == "wrong-version" else "3.5")
        distributions.append(serial)
        if problem == "duplicate":
            distributions.append(serial)
        elif problem == "missing-metadata":
            (serial._path / "METADATA").unlink()
        elif problem == "duplicate-ort":
            distributions.append(_fake_distribution(tmp_path, "onnxruntime-training", "1.15.1"))
    tool = _manifest_tool()
    monkeypatch.setattr(tool.importlib.metadata, "distributions", lambda: distributions)
    with pytest.raises(RuntimeError):
        tool.build_manifest(requirements)


def test_manifest_generator_locks_every_installed_pin_with_real_metadata_hash(tmp_path, monkeypatch):
    requirements = tmp_path / "requirements.txt"
    requirements.write_text("onnxruntime-training-cpu==1.19.2\npyserial==3.5\n", encoding="utf-8")
    distributions = [
        _fake_distribution(tmp_path, "onnxruntime-training-cpu", "1.19.2"),
        _fake_distribution(tmp_path, "pyserial", "3.5"),
    ]
    tool = _manifest_tool()
    monkeypatch.setattr(tool.importlib.metadata, "distributions", lambda: distributions)
    manifest = tool.build_manifest(requirements)
    assert manifest["requirements_sha256"] == _sha256(requirements)
    assert manifest["packages"] == [
        {"name": item.metadata["Name"], "version": item.version,
         "metadata_sha256": _sha256(item._path / "METADATA")}
        for item in distributions
    ]


def test_requirements_checksum_is_stable_across_windows_checkouts(tmp_path):
    requirements = tmp_path / "requirements.txt"
    content = b"numpy==1.26.4\n# USB robot link\npyserial==3.5\n"
    tool = _manifest_tool()
    requirements.write_bytes(content)
    expected = hashlib.sha256(content).hexdigest()
    assert tool.requirements_sha256(requirements) == expected
    requirements.write_bytes(content.replace(b"\n", b"\r\n"))
    assert tool.requirements_sha256(requirements) == expected
    requirements.write_bytes(content.replace(b"3.5", b"3.6"))
    assert tool.requirements_sha256(requirements) != expected
