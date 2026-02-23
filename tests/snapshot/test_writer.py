"""Unit tests for sxact.snapshot.writer.

All tests use tmp_path; no oracle or network access required.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

import pytest

from sxact.snapshot.runner import FileSnapshot, TestSnapshot, compute_oracle_hash
from sxact.snapshot.writer import write_oracle_dir


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_snapshot(
    test_id: str = "tc_001",
    raw_output: str = "T[-a,-b]",
    normalized_output: str = "T[-$1,-$2]",
    properties: dict | None = None,
) -> TestSnapshot:
    props = properties or {}
    return TestSnapshot(
        test_id=test_id,
        oracle_version="xAct 1.2.0",
        mathematica_version="14.0.0",
        timestamp="2026-01-22T10:30:00Z",
        commands="DefManifold[M,4,{a,b}]\nT[-a,-b]",
        raw_output=raw_output,
        normalized_output=normalized_output,
        properties=props,
        hash=compute_oracle_hash(normalized_output, props),
    )


def _make_file_snap(
    meta_id: str = "xcore/basic",
    tests: list[TestSnapshot] | None = None,
) -> FileSnapshot:
    return FileSnapshot(
        meta_id=meta_id,
        source_path=Path("dummy.toml"),
        tests=tests or [_make_snapshot()],
    )


# ---------------------------------------------------------------------------
# Directory structure
# ---------------------------------------------------------------------------

class TestDirectoryStructure:
    def test_creates_output_dir(self, tmp_path):
        out = tmp_path / "oracle"
        write_oracle_dir([], out)
        assert out.is_dir()

    def test_creates_nested_output_dir(self, tmp_path):
        out = tmp_path / "a" / "b" / "oracle"
        write_oracle_dir([], out)
        assert out.is_dir()

    def test_version_file_created(self, tmp_path):
        write_oracle_dir([], tmp_path / "o")
        assert (tmp_path / "o" / "VERSION").exists()

    def test_config_toml_created(self, tmp_path):
        write_oracle_dir([], tmp_path / "o")
        assert (tmp_path / "o" / "config.toml").exists()

    def test_checksums_file_created(self, tmp_path):
        write_oracle_dir([], tmp_path / "o")
        assert (tmp_path / "o" / "checksums.sha256").exists()

    def test_snapshot_json_created(self, tmp_path):
        snap = _make_file_snap(meta_id="xcore/basic", tests=[_make_snapshot("tc_001")])
        write_oracle_dir([snap], tmp_path / "o")
        assert (tmp_path / "o" / "xcore" / "basic" / "tc_001.json").exists()

    def test_snapshot_wl_created(self, tmp_path):
        snap = _make_file_snap(meta_id="xcore/basic", tests=[_make_snapshot("tc_001")])
        write_oracle_dir([snap], tmp_path / "o")
        assert (tmp_path / "o" / "xcore" / "basic" / "tc_001.wl").exists()

    def test_multiple_packages(self, tmp_path):
        s1 = _make_file_snap("pkg/a", [_make_snapshot("t1")])
        s2 = _make_file_snap("pkg/b", [_make_snapshot("t2")])
        write_oracle_dir([s1, s2], tmp_path / "o")
        assert (tmp_path / "o" / "pkg" / "a" / "t1.json").exists()
        assert (tmp_path / "o" / "pkg" / "b" / "t2.json").exists()

    def test_multiple_tests_same_file(self, tmp_path):
        snaps = [_make_snapshot("t1"), _make_snapshot("t2")]
        fs = _make_file_snap("core/m", snaps)
        write_oracle_dir([fs], tmp_path / "o")
        assert (tmp_path / "o" / "core" / "m" / "t1.json").exists()
        assert (tmp_path / "o" / "core" / "m" / "t2.json").exists()


# ---------------------------------------------------------------------------
# VERSION file content
# ---------------------------------------------------------------------------

class TestVersionFile:
    def test_default_content(self, tmp_path):
        write_oracle_dir([], tmp_path / "o")
        text = (tmp_path / "o" / "VERSION").read_text()
        assert "xAct 1.2.0" in text
        assert "Mathematica" in text

    def test_custom_versions(self, tmp_path):
        write_oracle_dir(
            [],
            tmp_path / "o",
            oracle_version="xAct 2.0.0",
            mathematica_version="15.0.1",
        )
        text = (tmp_path / "o" / "VERSION").read_text()
        assert "xAct 2.0.0" in text
        assert "15.0.1" in text


# ---------------------------------------------------------------------------
# Snapshot JSON content
# ---------------------------------------------------------------------------

class TestSnapshotJson:
    def test_all_fields_present(self, tmp_path):
        ts = _make_snapshot("tc_001", raw_output="T[-a,-b]", normalized_output="T[-$1,-$2]")
        write_oracle_dir([_make_file_snap("xcore/basic", [ts])], tmp_path / "o")

        data = json.loads((tmp_path / "o" / "xcore" / "basic" / "tc_001.json").read_text())
        assert data["test_id"] == "tc_001"
        assert data["oracle_version"] == "xAct 1.2.0"
        assert data["mathematica_version"] == "14.0.0"
        assert data["timestamp"] == "2026-01-22T10:30:00Z"
        assert "commands" in data
        assert data["raw_output"] == "T[-a,-b]"
        assert data["normalized_output"] == "T[-$1,-$2]"
        assert "properties" in data
        assert data["hash"].startswith("sha256:")

    def test_hash_matches_spec(self, tmp_path):
        normalized = "T[-$1,-$2]"
        props = {"rank": 2}
        ts = _make_snapshot("tc", normalized_output=normalized, properties=props)
        write_oracle_dir([_make_file_snap("p/q", [ts])], tmp_path / "o")

        data = json.loads((tmp_path / "o" / "p" / "q" / "tc.json").read_text())
        expected_hash = compute_oracle_hash(normalized, props)
        assert data["hash"] == expected_hash

    def test_wl_file_contains_raw_output(self, tmp_path):
        ts = _make_snapshot("tc", raw_output="T[-a,-b]")
        write_oracle_dir([_make_file_snap("p/q", [ts])], tmp_path / "o")
        wl = (tmp_path / "o" / "p" / "q" / "tc.wl").read_text()
        assert wl == "T[-a,-b]"

    def test_wl_file_empty_when_no_output(self, tmp_path):
        ts = _make_snapshot("tc", raw_output="")
        write_oracle_dir([_make_file_snap("p/q", [ts])], tmp_path / "o")
        wl = (tmp_path / "o" / "p" / "q" / "tc.wl").read_text()
        assert wl == ""


# ---------------------------------------------------------------------------
# Checksums
# ---------------------------------------------------------------------------

class TestChecksums:
    def test_checksums_exist(self, tmp_path):
        ts = _make_snapshot("tc_001")
        write_oracle_dir([_make_file_snap("a/b", [ts])], tmp_path / "o")
        assert (tmp_path / "o" / "checksums.sha256").exists()

    def test_checksums_correct(self, tmp_path):
        ts = _make_snapshot("tc_001")
        out = tmp_path / "o"
        write_oracle_dir([_make_file_snap("a/b", [ts])], out)

        lines = (out / "checksums.sha256").read_text().splitlines()
        # Each line: "<hex>  <path>"
        for line in lines:
            digest, rel_str = line.split("  ", 1)
            fpath = out / rel_str
            actual = hashlib.sha256(fpath.read_bytes()).hexdigest()
            assert actual == digest, f"Checksum mismatch for {rel_str}"

    def test_empty_snapshots_no_data_files(self, tmp_path):
        write_oracle_dir([], tmp_path / "o")
        checksums = (tmp_path / "o" / "checksums.sha256").read_text()
        assert checksums == ""

    def test_checksums_sorted(self, tmp_path):
        snaps = [_make_snapshot("z_test"), _make_snapshot("a_test")]
        out = tmp_path / "o"
        write_oracle_dir([_make_file_snap("p/q", snaps)], out)
        lines = (out / "checksums.sha256").read_text().splitlines()
        paths = [line.split("  ", 1)[1] for line in lines]
        assert paths == sorted(paths)

    def test_idempotent_regeneration(self, tmp_path):
        """Writing twice should produce identical checksums."""
        ts = _make_snapshot("tc")
        out = tmp_path / "o"
        write_oracle_dir([_make_file_snap("a/b", [ts])], out)
        first = (out / "checksums.sha256").read_text()
        write_oracle_dir([_make_file_snap("a/b", [ts])], out)
        second = (out / "checksums.sha256").read_text()
        assert first == second
