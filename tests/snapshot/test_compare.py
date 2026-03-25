"""Unit tests for sxact.snapshot.compare.SnapshotComparator.

All tests use tmp_path and pre-written snapshot files; no oracle required.
"""

from __future__ import annotations

import json
from pathlib import Path

from sxact.oracle.result import Result
from sxact.snapshot.compare import SnapshotComparator, SnapshotCompareResult
from sxact.snapshot.runner import compute_oracle_hash
from sxact.snapshot.store import SnapshotStore

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _write_snapshot(
    oracle_dir: Path,
    meta_id: str,
    test_id: str,
    *,
    normalized_output: str = "T[-$1,-$2]",
    properties: dict | None = None,
    hash_override: str | None = None,
) -> None:
    props = properties or {}
    h = hash_override or compute_oracle_hash(normalized_output, props)
    data = {
        "test_id": test_id,
        "oracle_version": "xAct 1.2.0",
        "mathematica_version": "14.0.0",
        "timestamp": "2026-01-22T10:30:00Z",
        "commands": "...",
        "raw_output": "T[-a,-b]",
        "normalized_output": normalized_output,
        "properties": props,
        "hash": h,
    }
    path = oracle_dir / meta_id / f"{test_id}.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data), encoding="utf-8")


def _ok(normalized: str = "T[-$1,-$2]", properties: dict | None = None) -> Result:
    return Result(
        status="ok",
        type="Expr",
        repr="T[-a,-b]",
        normalized=normalized,
        properties=properties or {},
    )


def _err(msg: str = "boom") -> Result:
    return Result(status="error", type="", repr="", normalized="", error=msg)


def _make_comparator(oracle_dir: Path) -> SnapshotComparator:
    return SnapshotComparator(SnapshotStore(oracle_dir))


# ---------------------------------------------------------------------------
# SnapshotCompareResult helpers
# ---------------------------------------------------------------------------


class TestSnapshotCompareResultHelpers:
    def test_passed_true_on_pass(self):
        r = SnapshotCompareResult("t", "pass", "x", "x", "")
        assert r.passed is True

    def test_passed_false_on_fail(self):
        r = SnapshotCompareResult("t", "fail", "x", "y", "diff")
        assert r.passed is False

    def test_passed_false_on_missing(self):
        r = SnapshotCompareResult("t", "missing", "x", None, "no snap")
        assert r.passed is False

    def test_passed_false_on_hash_mismatch(self):
        r = SnapshotCompareResult("t", "hash_mismatch", "x", "x", "bad hash")
        assert r.passed is False


# ---------------------------------------------------------------------------
# missing snapshot
# ---------------------------------------------------------------------------


class TestMissingSnapshot:
    def test_missing_snapshot_gives_missing_outcome(self, tmp_path):
        cmp = _make_comparator(tmp_path)
        result = cmp.compare("xcore/basic", "no_such_test", _ok())
        assert result.outcome == "missing"
        assert result.test_id == "no_such_test"
        assert result.expected_normalized is None

    def test_missing_details_mentions_snapshot_command(self, tmp_path):
        cmp = _make_comparator(tmp_path)
        result = cmp.compare("x", "y", _ok())
        assert "xact-test snapshot" in result.details


# ---------------------------------------------------------------------------
# hash mismatch
# ---------------------------------------------------------------------------


class TestHashMismatch:
    def test_corrupted_hash_gives_hash_mismatch(self, tmp_path):
        _write_snapshot(tmp_path, "p/q", "tc", hash_override="sha256:000000000000")
        cmp = _make_comparator(tmp_path)
        result = cmp.compare("p/q", "tc", _ok("T[-$1,-$2]"))
        assert result.outcome == "hash_mismatch"

    def test_hash_mismatch_details_suggest_regen(self, tmp_path):
        _write_snapshot(tmp_path, "p/q", "tc", hash_override="sha256:000000000000")
        cmp = _make_comparator(tmp_path)
        result = cmp.compare("p/q", "tc", _ok())
        assert "xact-test snapshot" in result.details


# ---------------------------------------------------------------------------
# adapter error result
# ---------------------------------------------------------------------------


class TestAdapterError:
    def test_error_result_gives_fail(self, tmp_path):
        _write_snapshot(tmp_path, "p/q", "tc")
        cmp = _make_comparator(tmp_path)
        result = cmp.compare("p/q", "tc", _err("kernel crash"))
        assert result.outcome == "fail"
        assert "error" in result.details.lower()
        assert "kernel crash" in result.details


# ---------------------------------------------------------------------------
# pass cases
# ---------------------------------------------------------------------------


class TestPass:
    def test_matching_normalized_passes(self, tmp_path):
        _write_snapshot(tmp_path, "a/b", "tc", normalized_output="T[-$1,-$2]")
        cmp = _make_comparator(tmp_path)
        result = cmp.compare("a/b", "tc", _ok("T[-$1,-$2]"))
        assert result.outcome == "pass"
        assert result.passed

    def test_pass_details_empty(self, tmp_path):
        _write_snapshot(tmp_path, "a/b", "tc", normalized_output="X")
        cmp = _make_comparator(tmp_path)
        result = cmp.compare("a/b", "tc", _ok("X"))
        assert result.details == ""

    def test_pass_preserves_actual_normalized(self, tmp_path):
        _write_snapshot(tmp_path, "a/b", "tc", normalized_output="X")
        cmp = _make_comparator(tmp_path)
        result = cmp.compare("a/b", "tc", _ok("X"))
        assert result.actual_normalized == "X"
        assert result.expected_normalized == "X"

    def test_empty_snapshot_properties_skips_prop_check(self, tmp_path):
        """Snapshot with no properties should pass even if actual has properties."""
        _write_snapshot(tmp_path, "a/b", "tc", normalized_output="X", properties={})
        cmp = _make_comparator(tmp_path)
        result = cmp.compare("a/b", "tc", _ok("X", {"rank": 2}))
        assert result.outcome == "pass"

    def test_matching_properties_passes(self, tmp_path):
        props = {"rank": 2, "type": "Tensor"}
        _write_snapshot(tmp_path, "a/b", "tc", normalized_output="X", properties=props)
        cmp = _make_comparator(tmp_path)
        result = cmp.compare("a/b", "tc", _ok("X", props))
        assert result.outcome == "pass"


# ---------------------------------------------------------------------------
# fail cases — normalized mismatch
# ---------------------------------------------------------------------------


class TestNormalizedMismatch:
    def test_different_normalized_fails(self, tmp_path):
        _write_snapshot(tmp_path, "a/b", "tc", normalized_output="T[-$1,-$2]")
        cmp = _make_comparator(tmp_path)
        result = cmp.compare("a/b", "tc", _ok("S[-$1,-$2]"))
        assert result.outcome == "fail"

    def test_fail_details_shows_both_values(self, tmp_path):
        _write_snapshot(tmp_path, "a/b", "tc", normalized_output="expected_val")
        cmp = _make_comparator(tmp_path)
        result = cmp.compare("a/b", "tc", _ok("actual_val"))
        assert "actual_val" in result.details
        assert "expected_val" in result.details

    def test_actual_and_expected_accessible(self, tmp_path):
        _write_snapshot(tmp_path, "a/b", "tc", normalized_output="Y")
        cmp = _make_comparator(tmp_path)
        result = cmp.compare("a/b", "tc", _ok("X"))
        assert result.actual_normalized == "X"
        assert result.expected_normalized == "Y"


# ---------------------------------------------------------------------------
# fail cases — property mismatch
# ---------------------------------------------------------------------------


class TestPropertyMismatch:
    def test_wrong_rank_fails(self, tmp_path):
        _write_snapshot(tmp_path, "a/b", "tc", normalized_output="X", properties={"rank": 2})
        cmp = _make_comparator(tmp_path)
        result = cmp.compare("a/b", "tc", _ok("X", {"rank": 4}))
        assert result.outcome == "fail"
        assert "rank" in result.details

    def test_missing_property_key_fails(self, tmp_path):
        _write_snapshot(tmp_path, "a/b", "tc", normalized_output="X", properties={"rank": 2})
        cmp = _make_comparator(tmp_path)
        # actual has no properties at all
        result = cmp.compare("a/b", "tc", _ok("X", {}))
        assert result.outcome == "fail"

    def test_multiple_property_mismatches_reported(self, tmp_path):
        snap_props = {"rank": 2, "type": "Tensor"}
        _write_snapshot(tmp_path, "a/b", "tc", normalized_output="X", properties=snap_props)
        cmp = _make_comparator(tmp_path)
        result = cmp.compare("a/b", "tc", _ok("X", {"rank": 4, "type": "Scalar"}))
        assert "rank" in result.details
        assert "type" in result.details

    def test_extra_actual_properties_ignored(self, tmp_path):
        """Actual having MORE properties than snapshot should still pass."""
        _write_snapshot(tmp_path, "a/b", "tc", normalized_output="X", properties={"rank": 2})
        cmp = _make_comparator(tmp_path)
        result = cmp.compare("a/b", "tc", _ok("X", {"rank": 2, "manifold": "M"}))
        assert result.outcome == "pass"


# ---------------------------------------------------------------------------
# test_id field
# ---------------------------------------------------------------------------


class TestTestId:
    def test_result_carries_test_id(self, tmp_path):
        _write_snapshot(tmp_path, "a/b", "my_tc")
        cmp = _make_comparator(tmp_path)
        result = cmp.compare("a/b", "my_tc", _ok())
        assert result.test_id == "my_tc"

    def test_missing_result_carries_test_id(self, tmp_path):
        cmp = _make_comparator(tmp_path)
        result = cmp.compare("a/b", "ghost_tc", _ok())
        assert result.test_id == "ghost_tc"
