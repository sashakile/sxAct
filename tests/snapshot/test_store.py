"""Unit tests for sxact.snapshot.store.SnapshotStore.

All tests use tmp_path; no oracle or network access required.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from sxact.snapshot.runner import compute_oracle_hash
from sxact.snapshot.store import SnapshotLoadError, SnapshotStore


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _write_snapshot(
    oracle_dir: Path,
    meta_id: str,
    test_id: str,
    *,
    normalized_output: str = "T[-$1,-$2]",
    raw_output: str = "T[-a,-b]",
    properties: dict | None = None,
    hash_override: str | None = None,
) -> Path:
    """Write a valid snapshot JSON under oracle_dir/<meta_id>/<test_id>.json."""
    props = properties or {}
    h = hash_override or compute_oracle_hash(normalized_output, props)
    data = {
        "test_id": test_id,
        "oracle_version": "xAct 1.2.0",
        "mathematica_version": "14.0.0",
        "timestamp": "2026-01-22T10:30:00Z",
        "commands": "DefManifold[M,4,{a,b}]",
        "raw_output": raw_output,
        "normalized_output": normalized_output,
        "properties": props,
        "hash": h,
    }
    path = oracle_dir / meta_id / f"{test_id}.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")
    return path


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

class TestConstruction:
    def test_valid_dir_ok(self, tmp_path):
        store = SnapshotStore(tmp_path)
        assert store is not None

    def test_missing_dir_raises(self, tmp_path):
        with pytest.raises(ValueError, match="not found"):
            SnapshotStore(tmp_path / "nonexistent")


# ---------------------------------------------------------------------------
# load()
# ---------------------------------------------------------------------------

class TestLoad:
    def test_returns_none_for_missing(self, tmp_path):
        store = SnapshotStore(tmp_path)
        assert store.load("xcore/basic", "nonexistent") is None

    def test_loads_existing_snapshot(self, tmp_path):
        _write_snapshot(tmp_path, "xcore/basic", "tc_001")
        store = SnapshotStore(tmp_path)
        snap = store.load("xcore/basic", "tc_001")
        assert snap is not None
        assert snap.test_id == "tc_001"

    def test_loads_normalized_output(self, tmp_path):
        _write_snapshot(tmp_path, "pkg/a", "t1", normalized_output="delta[-$1,-$2]")
        store = SnapshotStore(tmp_path)
        snap = store.load("pkg/a", "t1")
        assert snap.normalized_output == "delta[-$1,-$2]"

    def test_loads_properties(self, tmp_path):
        _write_snapshot(tmp_path, "pkg/a", "t1", properties={"rank": 2, "type": "Tensor"})
        store = SnapshotStore(tmp_path)
        snap = store.load("pkg/a", "t1")
        assert snap.properties == {"rank": 2, "type": "Tensor"}

    def test_cache_returns_same_object(self, tmp_path):
        _write_snapshot(tmp_path, "p/q", "tc")
        store = SnapshotStore(tmp_path)
        s1 = store.load("p/q", "tc")
        s2 = store.load("p/q", "tc")
        assert s1 is s2

    def test_nested_meta_id(self, tmp_path):
        _write_snapshot(tmp_path, "a/b/c", "tc")
        store = SnapshotStore(tmp_path)
        snap = store.load("a/b/c", "tc")
        assert snap is not None
        assert snap.test_id == "tc"

    def test_malformed_json_raises(self, tmp_path):
        path = tmp_path / "pkg" / "tc.json"
        path.parent.mkdir(parents=True)
        path.write_text("not valid json", encoding="utf-8")
        store = SnapshotStore(tmp_path)
        with pytest.raises(SnapshotLoadError):
            store.load("pkg", "tc")

    def test_missing_required_fields_raises(self, tmp_path):
        path = tmp_path / "pkg" / "tc.json"
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps({"test_id": "tc"}), encoding="utf-8")
        store = SnapshotStore(tmp_path)
        with pytest.raises(SnapshotLoadError):
            store.load("pkg", "tc")


# ---------------------------------------------------------------------------
# verify_hash()
# ---------------------------------------------------------------------------

class TestVerifyHash:
    def test_valid_hash_passes(self, tmp_path):
        _write_snapshot(tmp_path, "p/q", "tc", normalized_output="X[-$1]")
        store = SnapshotStore(tmp_path)
        snap = store.load("p/q", "tc")
        assert store.verify_hash(snap) is True

    def test_tampered_normalized_output_fails(self, tmp_path):
        _write_snapshot(tmp_path, "p/q", "tc", normalized_output="X[-$1]")
        # Tamper: overwrite the file with a different normalized_output but keep the original hash
        path = tmp_path / "p" / "q" / "tc.json"
        data = json.loads(path.read_text())
        original_hash = data["hash"]
        data["normalized_output"] = "TAMPERED"
        path.write_text(json.dumps(data))

        store = SnapshotStore(tmp_path)
        snap = store.load("p/q", "tc")
        assert store.verify_hash(snap) is False

    def test_tampered_properties_fails(self, tmp_path):
        _write_snapshot(tmp_path, "p/q", "tc", properties={"rank": 2})
        path = tmp_path / "p" / "q" / "tc.json"
        data = json.loads(path.read_text())
        data["properties"]["rank"] = 99  # tamper
        path.write_text(json.dumps(data))

        store = SnapshotStore(tmp_path)
        snap = store.load("p/q", "tc")
        assert store.verify_hash(snap) is False

    def test_bad_hash_string_fails(self, tmp_path):
        _write_snapshot(tmp_path, "p/q", "tc", hash_override="sha256:000000000000")
        store = SnapshotStore(tmp_path)
        snap = store.load("p/q", "tc")
        assert store.verify_hash(snap) is False


# ---------------------------------------------------------------------------
# oracle_version()
# ---------------------------------------------------------------------------

class TestOracleVersion:
    def test_reads_version_file(self, tmp_path):
        (tmp_path / "VERSION").write_text("xAct 1.2.0, Mathematica 14.0\n")
        store = SnapshotStore(tmp_path)
        assert store.oracle_version() == "xAct 1.2.0, Mathematica 14.0"

    def test_missing_version_returns_unknown(self, tmp_path):
        store = SnapshotStore(tmp_path)
        assert store.oracle_version() == "unknown"


# ---------------------------------------------------------------------------
# list_snapshots()
# ---------------------------------------------------------------------------

class TestListSnapshots:
    def test_empty_dir(self, tmp_path):
        store = SnapshotStore(tmp_path)
        assert store.list_snapshots() == []

    def test_lists_all_snapshots(self, tmp_path):
        _write_snapshot(tmp_path, "a/b", "t1")
        _write_snapshot(tmp_path, "a/b", "t2")
        _write_snapshot(tmp_path, "c/d", "t3")
        store = SnapshotStore(tmp_path)
        snaps = store.list_snapshots()
        assert ("a/b", "t1") in snaps
        assert ("a/b", "t2") in snaps
        assert ("c/d", "t3") in snaps
        assert len(snaps) == 3

    def test_result_is_sorted(self, tmp_path):
        _write_snapshot(tmp_path, "z/z", "z")
        _write_snapshot(tmp_path, "a/a", "a")
        store = SnapshotStore(tmp_path)
        snaps = store.list_snapshots()
        assert snaps == sorted(snaps)
