from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
import re
import sys
from pathlib import Path


SCHEMA_VERSION = 1


def _normalize(name: str) -> str:
    return name.lower().replace("_", "-").replace(".", "-")


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def requirements_sha256(requirements: Path) -> str:
    # Git may check text out with CRLF on Windows. Lock the same requirements
    # across platforms while retaining every other byte, including comments.
    return hashlib.sha256(requirements.read_bytes().replace(b"\r\n", b"\n")).hexdigest()


def read_pinned_requirements(requirements: Path) -> dict[str, str]:
    """Read direct runtime pins; fail closed if the lock cannot represent a line."""
    pins: dict[str, str] = {}
    for number, raw in enumerate(requirements.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        match = re.fullmatch(r"([A-Za-z0-9][A-Za-z0-9_.-]*)==([^\s;]+)", line)
        if match is None or "*" in match[2]:
            raise RuntimeError(f"Expected an exact package pin at {requirements}:{number}")
        name, version = _normalize(match[1]), match[2]
        if name in pins:
            raise RuntimeError(f"Duplicate runtime requirement: {name}")
        pins[name] = version
    if not pins:
        raise RuntimeError("Runtime requirements contain no exact package pins")
    return pins


def build_manifest(requirements: Path) -> dict:
    pins = read_pinned_requirements(requirements)
    distributions = list(importlib.metadata.distributions())
    ort_training = [
        distribution
        for distribution in distributions
        if _normalize(distribution.metadata.get("Name") or "").startswith(
            "onnxruntime-training"
        )
    ]
    if len(ort_training) != 1:
        installed = [
            f"{item.metadata.get('Name')}=={item.version}" for item in ort_training
        ]
        raise RuntimeError(
            "Expected exactly one ONNX Runtime Training distribution; found "
            + repr(installed)
        )

    packages = []
    for name, version in pins.items():
        matches = [
            item for item in distributions
            if _normalize(item.metadata.get("Name") or "") == name
        ]
        if len(matches) != 1:
            raise RuntimeError(
                f"Expected one required local runtime distribution {name}; found {len(matches)}"
            )
        distribution = matches[0]
        if distribution.version != version:
            raise RuntimeError(
                f"Runtime distribution {name} is {distribution.version}; expected {version}"
            )
        metadata_path = Path(distribution._path) / "METADATA"
        if not metadata_path.is_file():
            raise RuntimeError(f"Distribution metadata is missing: {metadata_path}")
        packages.append(
            {
                "name": name,
                "version": distribution.version,
                "metadata_sha256": _sha256(metadata_path),
            }
        )

    return {
        "schema": SCHEMA_VERSION,
        "python": {
            "implementation": sys.implementation.name,
            "major_minor": f"{sys.version_info.major}.{sys.version_info.minor}",
        },
        "requirements_sha256": requirements_sha256(requirements),
        "packages": packages,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--requirements", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    manifest = build_manifest(args.requirements.resolve())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.output.with_suffix(args.output.suffix + ".tmp")
    temporary.write_text(
        json.dumps(manifest, sort_keys=True, indent=2) + "\n",
        encoding="utf-8",
    )
    temporary.replace(args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
