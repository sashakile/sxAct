"""Write oracle snapshot directory from FileSnapshot results.

Produces the directory layout described in spec §5.6::

    oracle/
    ├── VERSION                  # "xAct 1.2.0, Mathematica 14.0"
    ├── config.toml              # Normalization settings
    ├── <meta_id>/
    │   ├── <test_id>.json       # Snapshot JSON
    │   └── <test_id>.wl        # Raw Wolfram output
    └── checksums.sha256         # SHA-256 of every JSON and .wl file

Public API::

    from sxact.snapshot.writer import write_oracle_dir
    write_oracle_dir(snapshots, Path("oracle/"), oracle_version="xAct 1.2.0")
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from sxact.snapshot.runner import FileSnapshot, TestSnapshot


# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------


def write_oracle_dir(
    snapshots: list[FileSnapshot],
    output_dir: Path,
    *,
    oracle_version: str = "xAct 1.2.0",
    mathematica_version: str = "unknown",
) -> None:
    """Write all snapshot files into *output_dir*.

    Creates the directory (and parents) if needed.  Existing files are
    overwritten so regeneration is idempotent.

    Args:
        snapshots:            One :class:`FileSnapshot` per test file processed.
        output_dir:           Root of the oracle directory tree to write.
        oracle_version:       xAct version string, e.g. ``"xAct 1.2.0"``.
        mathematica_version:  Mathematica version string, e.g. ``"14.0.0"``.
    """
    output_dir.mkdir(parents=True, exist_ok=True)

    _write_version(output_dir, oracle_version, mathematica_version)
    _write_config_toml(output_dir)

    written: list[Path] = []
    for file_snap in snapshots:
        pkg_dir = output_dir / file_snap.meta_id
        pkg_dir.mkdir(parents=True, exist_ok=True)

        for snap in file_snap.tests:
            json_path = pkg_dir / f"{snap.test_id}.json"
            wl_path = pkg_dir / f"{snap.test_id}.wl"

            _write_snapshot_json(json_path, snap)
            wl_path.write_text(snap.raw_output or "", encoding="utf-8")

            written.extend([json_path, wl_path])

    _write_checksums(output_dir, written)


# ---------------------------------------------------------------------------
# File writers
# ---------------------------------------------------------------------------


def _write_version(
    output_dir: Path, oracle_version: str, mathematica_version: str
) -> None:
    text = f"{oracle_version}, Mathematica {mathematica_version}\n"
    (output_dir / "VERSION").write_text(text, encoding="utf-8")


def _write_config_toml(output_dir: Path) -> None:
    content = (
        "# sxAct oracle normalization settings\n"
        "[normalization]\n"
        'dummy_index_prefix = "$"\n'
        "sort_commutative = true\n"
        "strip_whitespace = true\n"
    )
    (output_dir / "config.toml").write_text(content, encoding="utf-8")


def _write_snapshot_json(path: Path, snap: TestSnapshot) -> None:
    data = {
        "test_id": snap.test_id,
        "oracle_version": snap.oracle_version,
        "mathematica_version": snap.mathematica_version,
        "timestamp": snap.timestamp,
        "commands": snap.commands,
        "raw_output": snap.raw_output,
        "normalized_output": snap.normalized_output,
        "properties": snap.properties,
        "hash": snap.hash,
    }
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def _write_checksums(output_dir: Path, files: list[Path]) -> None:
    lines = []
    for fpath in sorted(files):
        digest = hashlib.sha256(fpath.read_bytes()).hexdigest()
        rel = fpath.relative_to(output_dir)
        lines.append(f"{digest}  {rel}\n")
    (output_dir / "checksums.sha256").write_text("".join(lines), encoding="utf-8")
