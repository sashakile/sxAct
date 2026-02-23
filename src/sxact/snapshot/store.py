"""SnapshotStore: loads and indexes oracle snapshots from the oracle directory.

Provides hash-verified snapshot lookup by (meta_id, test_id) so the test
runner can compare target adapter results against stored oracle output without
requiring a live Wolfram Engine.

Public API::

    from sxact.snapshot.store import SnapshotStore
    store = SnapshotStore(Path("oracle/"))
    snap = store.load("xcore/basic", "def_manifold_ok")
    ok = store.verify_hash(snap)
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Optional

from sxact.snapshot.runner import TestSnapshot, compute_oracle_hash


class SnapshotStore:
    """Read-only view of an oracle snapshot directory.

    Each snapshot lives at ``<oracle_dir>/<meta_id>/<test_id>.json``.
    The store is lazily loaded: individual snapshots are read on first access
    and cached for the lifetime of the store.

    Args:
        oracle_dir: Root of the oracle snapshot tree (contains VERSION,
                    config.toml, and sub-directories per package).

    Raises:
        ValueError: if *oracle_dir* does not exist.
    """

    def __init__(self, oracle_dir: Path) -> None:
        if not oracle_dir.exists():
            raise ValueError(f"Oracle directory not found: {oracle_dir}")
        self._root = oracle_dir
        self._cache: dict[tuple[str, str], TestSnapshot] = {}

    # ------------------------------------------------------------------
    # Snapshot lookup
    # ------------------------------------------------------------------

    def load(self, meta_id: str, test_id: str) -> Optional[TestSnapshot]:
        """Load a snapshot by (meta_id, test_id).

        Snapshots are cached; repeated calls return the same object.

        Args:
            meta_id: Test file meta ID, e.g. ``"xcore/basic"``.
            test_id: Test case ID, e.g. ``"def_manifold_ok"``.

        Returns:
            The :class:`~sxact.snapshot.runner.TestSnapshot`, or ``None`` if
            the snapshot file does not exist.

        Raises:
            SnapshotLoadError: if the file exists but cannot be parsed.
        """
        key = (meta_id, test_id)
        if key in self._cache:
            return self._cache[key]

        path = self._root / meta_id / f"{test_id}.json"
        if not path.exists():
            return None

        snap = _load_json(path)
        self._cache[key] = snap
        return snap

    def verify_hash(self, snap: TestSnapshot) -> bool:
        """Return True if the snapshot's embedded hash matches its content.

        Args:
            snap: A :class:`~sxact.snapshot.runner.TestSnapshot` previously
                  returned by :meth:`load`.
        """
        expected = compute_oracle_hash(snap.normalized_output, snap.properties)
        return snap.hash == expected

    # ------------------------------------------------------------------
    # Metadata
    # ------------------------------------------------------------------

    def oracle_version(self) -> str:
        """Read the oracle version string from VERSION, or return ``"unknown"``."""
        vfile = self._root / "VERSION"
        if vfile.exists():
            return vfile.read_text(encoding="utf-8").strip()
        return "unknown"

    def list_snapshots(self) -> list[tuple[str, str]]:
        """Return all ``(meta_id, test_id)`` pairs found in the store.

        Scans the directory tree; does not use the cache.
        """
        result = []
        for json_path in sorted(self._root.rglob("*.json")):
            try:
                rel = json_path.relative_to(self._root)
            except ValueError:
                continue
            parts = rel.parts
            if len(parts) < 2:
                continue
            test_id = parts[-1].removesuffix(".json")
            meta_id = "/".join(parts[:-1])
            result.append((meta_id, test_id))
        return result


# ---------------------------------------------------------------------------
# Error type
# ---------------------------------------------------------------------------

class SnapshotLoadError(ValueError):
    """Raised when a snapshot JSON file exists but cannot be parsed."""

    def __init__(self, message: str, *, path: Path) -> None:
        super().__init__(message)
        self.path = path


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _load_json(path: Path) -> TestSnapshot:
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as exc:
        raise SnapshotLoadError(f"Cannot read snapshot {path}: {exc}", path=path) from exc

    missing = [f for f in ("test_id", "normalized_output", "hash") if f not in raw]
    if missing:
        raise SnapshotLoadError(
            f"Snapshot {path} missing required fields: {missing}", path=path
        )

    return TestSnapshot(
        test_id=raw["test_id"],
        oracle_version=raw.get("oracle_version", ""),
        mathematica_version=raw.get("mathematica_version", ""),
        timestamp=raw.get("timestamp", ""),
        commands=raw.get("commands", ""),
        raw_output=raw.get("raw_output", ""),
        normalized_output=raw["normalized_output"],
        properties=raw.get("properties", {}),
        hash=raw["hash"],
    )
