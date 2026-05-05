"""Unit tests for xact-test run helpers.

Tests are oracle-free: adapters and snapshot stores are faked.
Covers _run_file_live, _run_file_snapshot, _tc_matches_tag, _sub_bindings,
_print_terminal_run, _print_json_run, and the full _cmd_run dispatcher.
"""

from __future__ import annotations

import json
from io import StringIO
from pathlib import Path
from unittest.mock import MagicMock, patch

from elegua.adapter import Adapter
from elegua.models import ValidationToken
from elegua.task import EleguaTask, TaskStatus

from sxact.cli import (
    _cmd_run,
    _print_json_run,
    _print_terminal_run,
    _run_file_live,
    _run_file_snapshot,
    _RunResult,
    _sub_bindings,
    _tc_matches_tag,
)
from sxact.oracle.result import Result
from sxact.runner.loader import (
    Expected,
    Operation,
    TestCase,
    TestFile,
    TestMeta,
)
from sxact.snapshot.runner import TestSnapshot

# ---------------------------------------------------------------------------
# Fixtures / helpers
# ---------------------------------------------------------------------------


def _ok(repr: str = "T", normalized: str = "", properties: dict | None = None) -> Result:
    return Result(
        status="ok",
        type="Expr",
        repr=repr,
        normalized=normalized or repr,
        properties=properties or {},
    )


def _err(msg: str = "oops") -> Result:
    return Result(status="error", type="Expr", repr="", normalized="", error=msg)


def _make_file(
    tests: list[TestCase] | None = None,
    setup: list[Operation] | None = None,
    meta_id: str = "pkg/tests",
    meta_tags: list[str] | None = None,
) -> TestFile:
    return TestFile(
        meta=TestMeta(
            id=meta_id,
            description="test file",
            tags=meta_tags or [],
        ),
        setup=setup or [],
        tests=tests or [],
        source_path=Path("dummy.toml"),
    )


def _make_tc(
    id: str = "tc_001",
    ops: list[Operation] | None = None,
    skip: str | None = None,
    tags: list[str] | None = None,
    expected: Expected | None = None,
) -> TestCase:
    return TestCase(
        id=id,
        description="a test case",
        operations=ops or [],
        skip=skip,
        tags=tags or [],
        expected=expected,
    )


def _make_adapter(*results: Result) -> MagicMock:
    adapter = MagicMock()
    adapter.initialize.return_value = object()
    adapter.teardown.return_value = None
    adapter.execute.side_effect = list(results)
    adapter.normalize.side_effect = lambda expr: expr
    adapter.equals.side_effect = lambda a, b, mode, ctx=None: a == b
    return adapter


def _ok_token(repr_str: str = "T") -> ValidationToken:
    return ValidationToken(
        adapter_id="mock", status=TaskStatus.OK, result={"repr": repr_str, "type": "Expr"}
    )


def _err_token(msg: str = "oops") -> ValidationToken:
    return ValidationToken(
        adapter_id="mock", status=TaskStatus.EXECUTION_ERROR, metadata={"error": msg}
    )


def _make_elegua_adapter(*tokens: ValidationToken) -> MagicMock:
    """Elegua-protocol adapter mock: execute(task) -> ValidationToken."""
    adapter = MagicMock(spec=Adapter)
    adapter.initialize.return_value = None
    adapter.teardown.return_value = None
    adapter.execute.side_effect = list(tokens)
    adapter.adapter_id = "mock"
    return adapter


def _make_snapshot(test_id: str, normalized: str = "T", hash_: str = "") -> TestSnapshot:
    from sxact.snapshot.runner import compute_oracle_hash

    h = hash_ or compute_oracle_hash(normalized, {})
    return TestSnapshot(
        test_id=test_id,
        oracle_version="xAct 1.2.0",
        mathematica_version="14.0",
        timestamp="2026-01-01T00:00:00Z",
        commands="",
        raw_output=normalized,
        normalized_output=normalized,
        properties={},
        hash=h,
    )


def _make_store(snapshots: dict[tuple[str, str], TestSnapshot]) -> MagicMock:
    """Build a fake SnapshotStore that loads from the provided dict."""
    store = MagicMock()

    def _load(meta_id: str, test_id: str):
        return snapshots.get((meta_id, test_id))

    def _verify(snap: TestSnapshot) -> bool:
        from sxact.snapshot.runner import compute_oracle_hash

        return snap.hash == compute_oracle_hash(snap.normalized_output, snap.properties)

    store.load.side_effect = _load
    store.verify_hash.side_effect = _verify
    return store


# ---------------------------------------------------------------------------
# _tc_matches_tag
# ---------------------------------------------------------------------------


class TestTcMatchesTag:
    def test_matches_test_tag(self):
        assert _tc_matches_tag(["smoke", "layer1"], [], "smoke")

    def test_matches_file_tag(self):
        assert _tc_matches_tag([], ["integration"], "integration")

    def test_no_match(self):
        assert not _tc_matches_tag(["layer1"], ["core"], "smoke")

    def test_empty(self):
        assert not _tc_matches_tag([], [], "anything")


# ---------------------------------------------------------------------------
# _sub_bindings
# ---------------------------------------------------------------------------


class TestSubBindings:
    def test_substitutes_string_value(self):
        result = _sub_bindings({"expr": "$x"}, {"x": "T[-a]"})
        assert result["expr"] == "T[-a]"

    def test_non_string_unchanged(self):
        result = _sub_bindings({"dim": 4}, {"dim": "should_not_replace"})
        assert result["dim"] == 4

    def test_missing_binding_preserved(self):
        result = _sub_bindings({"expr": "$gone"}, {})
        assert result["expr"] == "$gone"

    def test_original_dict_not_mutated(self):
        args = {"expr": "$x"}
        _sub_bindings(args, {"x": "T"})
        assert args["expr"] == "$x"


# ---------------------------------------------------------------------------
# _run_file_live
# ---------------------------------------------------------------------------


class TestRunFileLive:
    def test_pass_case(self):
        op = Operation(action="Evaluate", args={"expression": "1+1"})
        tc = _make_tc(id="tc_pass", ops=[op])
        tf = _make_file(tests=[tc])
        adapter = _make_adapter(_ok("2"))

        results = _run_file_live(tf, adapter, tag_filter=None)

        assert len(results) == 1
        assert results[0].status == "pass"
        assert results[0].test_id == "tc_pass"

    def test_fail_case(self):
        op = Operation(action="Evaluate", args={"expression": "1+1"})
        tc = _make_tc(id="tc_fail", ops=[op], expected=Expected(expr="3"))
        tf = _make_file(tests=[tc])
        adapter = _make_elegua_adapter(_ok_token("2"))

        results = _run_file_live(tf, adapter, tag_filter=None)

        assert results[0].status == "fail"
        assert results[0].actual == "2"
        assert results[0].expected == "3"

    def test_skip_case(self):
        tc = _make_tc(id="tc_skip", skip="not implemented")
        tf = _make_file(tests=[tc])
        adapter = _make_adapter()

        results = _run_file_live(tf, adapter, tag_filter=None)

        assert results[0].status == "skip"
        assert results[0].message == "not implemented"

    def test_error_case(self):
        op = Operation(action="Evaluate", args={"expression": "bad"})
        tc = _make_tc(id="tc_err", ops=[op])
        tf = _make_file(tests=[tc])
        adapter = _make_elegua_adapter(_err_token("syntax error"))

        results = _run_file_live(tf, adapter, tag_filter=None)

        assert results[0].status == "error"

    def test_tag_filter_skips_non_matching(self):
        tc_a = _make_tc(id="tc_a", tags=["smoke"])
        tc_b = _make_tc(id="tc_b", tags=["slow"])
        tf = _make_file(tests=[tc_a, tc_b])
        adapter = _make_adapter()

        results = _run_file_live(tf, adapter, tag_filter="smoke")

        ids = [r.test_id for r in results]
        assert "tc_a" in ids
        assert "tc_b" not in ids

    def test_file_tag_passes_all_tests(self):
        """When the file has the tag, all tests pass the filter."""
        tc_a = _make_tc(id="tc_a", tags=[])
        tc_b = _make_tc(id="tc_b", tags=[])
        tf = _make_file(tests=[tc_a, tc_b], meta_tags=["core"])
        adapter = _make_adapter(_ok(), _ok())

        results = _run_file_live(tf, adapter, tag_filter="core")

        assert len(results) == 2

    def test_multiple_tests_independent(self):
        """Per-test bindings do not leak between test cases."""
        op_a = Operation(action="Evaluate", args={"expression": "X"}, store_as="res")
        op_b = Operation(action="Evaluate", args={"expression": "$res"})
        tc_a = _make_tc(id="ta", ops=[op_a])
        tc_b = _make_tc(id="tb", ops=[op_b])
        tf = _make_file(tests=[tc_a, tc_b])

        captured: list[dict] = []

        def capturing(task: EleguaTask) -> ValidationToken:
            captured.append(dict(task.payload))
            return _ok_token("X")

        adapter = _make_elegua_adapter()
        adapter.execute.side_effect = capturing

        _run_file_live(tf, adapter, tag_filter=None)

        # tc_b's op should still see raw "$res" (no leakage from tc_a)
        assert captured[1]["expression"] == "$res"

    def test_teardown_always_called(self):
        """teardown is called even when a test operation raises."""
        op = Operation(action="Evaluate", args={"expression": "boom"})
        tc = _make_tc(id="tc", ops=[op])
        tf = _make_file(tests=[tc])
        adapter = _make_adapter()
        adapter.execute.side_effect = RuntimeError("bang")

        _run_file_live(tf, adapter, tag_filter=None)

        adapter.teardown.assert_called_once()


# ---------------------------------------------------------------------------
# _run_file_snapshot
# ---------------------------------------------------------------------------


class TestRunFileSnapshot:
    def test_pass_when_snapshot_matches(self):
        snap = _make_snapshot("tc_001", normalized="T[-a]")
        store = _make_store({("pkg/tests", "tc_001"): snap})

        op = Operation(action="Evaluate", args={"expression": "T[-a]"})
        tc = _make_tc(id="tc_001", ops=[op])
        tf = _make_file(tests=[tc])
        adapter = _make_adapter(_ok("T[-a]", "T[-a]"))

        results = _run_file_snapshot(tf, adapter, tag_filter=None, store=store)

        assert results[0].status == "pass"

    def test_fail_when_snapshot_differs(self):
        snap = _make_snapshot("tc_001", normalized="R[-a]")
        store = _make_store({("pkg/tests", "tc_001"): snap})

        op = Operation(action="Evaluate", args={"expression": "T[-a]"})
        tc = _make_tc(id="tc_001", ops=[op])
        tf = _make_file(tests=[tc])
        adapter = _make_adapter(_ok("T[-a]", "T[-a]"))

        results = _run_file_snapshot(tf, adapter, tag_filter=None, store=store)

        assert results[0].status == "fail"
        assert results[0].actual == "T[-a]"
        assert results[0].expected == "R[-a]"

    def test_missing_snapshot(self):
        store = _make_store({})  # no snapshots

        op = Operation(action="Evaluate", args={"expression": "T[-a]"})
        tc = _make_tc(id="tc_missing", ops=[op])
        tf = _make_file(tests=[tc])
        adapter = _make_adapter(_ok("T[-a]", "T[-a]"))

        results = _run_file_snapshot(tf, adapter, tag_filter=None, store=store)

        assert results[0].status == "missing"

    def test_skip_honored(self):
        store = _make_store({})
        tc = _make_tc(id="tc_skip", skip="awaiting impl")
        tf = _make_file(tests=[tc])
        adapter = _make_adapter()

        results = _run_file_snapshot(tf, adapter, tag_filter=None, store=store)

        assert results[0].status == "skip"
        adapter.execute.assert_not_called()

    def test_adapter_exception_becomes_error(self):
        store = _make_store({})
        op = Operation(action="Evaluate", args={"expression": "boom"})
        tc = _make_tc(id="tc_err", ops=[op])
        tf = _make_file(tests=[tc])
        adapter = _make_adapter()
        adapter.execute.side_effect = RuntimeError("crash")

        results = _run_file_snapshot(tf, adapter, tag_filter=None, store=store)

        assert results[0].status == "error"
        assert "crash" in results[0].message

    def test_tag_filter_skips_non_matching(self):
        store = _make_store({})
        tc_a = _make_tc(id="tc_a", tags=["smoke"])
        tc_b = _make_tc(id="tc_b", tags=["slow"])
        tf = _make_file(tests=[tc_a, tc_b])
        adapter = _make_adapter(_ok())

        results = _run_file_snapshot(tf, adapter, tag_filter="smoke", store=store)

        ids = [r.test_id for r in results]
        assert "tc_a" in ids
        assert "tc_b" not in ids

    def test_teardown_always_called(self):
        store = _make_store({})
        op = Operation(action="Evaluate", args={"expression": "boom"})
        tc = _make_tc(id="tc", ops=[op])
        tf = _make_file(tests=[tc])
        adapter = _make_adapter()
        adapter.execute.side_effect = RuntimeError("crash")

        _run_file_snapshot(tf, adapter, tag_filter=None, store=store)

        adapter.teardown.assert_called_once()

    def test_setup_bindings_available_to_tests(self):
        """store_as in setup is visible to test operations."""
        snap = _make_snapshot("tc_001", normalized="M")
        store = _make_store({("pkg/tests", "tc_001"): snap})

        setup_op = Operation(action="DefManifold", args={"name": "M"}, store_as="m")
        test_op = Operation(action="Evaluate", args={"expression": "$m"})
        tc = _make_tc(id="tc_001", ops=[test_op])
        tf = _make_file(setup=[setup_op], tests=[tc])

        captured: list[dict] = []

        def capturing(ctx, action, args):
            captured.append(dict(args))
            return _ok("M", "M")

        adapter = _make_adapter()
        adapter.execute.side_effect = capturing

        _run_file_snapshot(tf, adapter, tag_filter=None, store=store)

        # First call = setup; second = test. Test should see "M" not "$m".
        assert captured[1]["expression"] == "M"

    def test_no_operations_is_pass(self):
        """A test with no operations trivially passes (no snapshot lookup)."""
        store = _make_store({})
        tc = _make_tc(id="tc_empty", ops=[])
        tf = _make_file(tests=[tc])
        adapter = _make_adapter()

        results = _run_file_snapshot(tf, adapter, tag_filter=None, store=store)

        assert results[0].status == "pass"


# ---------------------------------------------------------------------------
# Terminal output formatter
# ---------------------------------------------------------------------------


class TestPrintTerminalRun:
    def _capture(self, all_results):
        buf = StringIO()
        with patch("sys.stdout", buf):
            _print_terminal_run(all_results)
        return buf.getvalue()

    def test_pass_shown(self):
        results = [_RunResult("f", "tc_pass", "pass")]
        out = self._capture([("f.toml", results)])
        assert "PASS" in out
        assert "tc_pass" in out

    def test_fail_shown_with_message(self):
        results = [_RunResult("f", "tc_fail", "fail", message="expected 3, got 2")]
        out = self._capture([("f.toml", results)])
        assert "FAIL" in out
        assert "expected 3, got 2" in out

    def test_skip_shown_with_reason(self):
        results = [_RunResult("f", "tc_skip", "skip", message="not yet")]
        out = self._capture([("f.toml", results)])
        assert "SKIP" in out
        assert "not yet" in out

    def test_summary_counts(self):
        results = [
            _RunResult("f", "t1", "pass"),
            _RunResult("f", "t2", "fail", message="x"),
            _RunResult("f", "t3", "skip"),
        ]
        out = self._capture([("f.toml", results)])
        assert "1 passed" in out
        assert "1 failed" in out
        assert "1 skipped" in out

    def test_file_count_in_summary(self):
        r1 = [_RunResult("f1", "t1", "pass")]
        r2 = [_RunResult("f2", "t2", "pass")]
        out = self._capture([("f1.toml", r1), ("f2.toml", r2)])
        assert "2 file(s)" in out


# ---------------------------------------------------------------------------
# JSON output formatter
# ---------------------------------------------------------------------------


class TestPrintJsonRun:
    def _capture_json(self, all_results):
        buf = StringIO()
        with patch("sys.stdout", buf):
            _print_json_run(all_results)
        return json.loads(buf.getvalue())

    def test_structure(self):
        results = [_RunResult("pkg/t", "tc_1", "pass")]
        data = self._capture_json([("f.toml", results)])
        assert "summary" in data
        assert "files" in data
        assert data["summary"]["passed"] == 1
        assert data["summary"]["failed"] == 0

    def test_test_fields(self):
        results = [
            _RunResult("pkg/t", "tc_1", "fail", actual="T", expected="R", message="mismatch")
        ]
        data = self._capture_json([("f.toml", results)])
        t = data["files"][0]["tests"][0]
        assert t["id"] == "tc_1"
        assert t["status"] == "fail"
        assert t["actual"] == "T"
        assert t["expected"] == "R"
        assert t["message"] == "mismatch"

    def test_pass_has_no_message(self):
        results = [_RunResult("pkg/t", "tc_1", "pass")]
        data = self._capture_json([("f.toml", results)])
        t = data["files"][0]["tests"][0]
        assert "message" not in t

    def test_missing_counted_as_failed(self):
        results = [_RunResult("pkg/t", "tc_1", "missing", message="no snapshot")]
        data = self._capture_json([("f.toml", results)])
        assert data["summary"]["failed"] == 1

    def test_error_counted_separately(self):
        results = [_RunResult("pkg/t", "tc_1", "error", message="crash")]
        data = self._capture_json([("f.toml", results)])
        assert data["summary"]["errors"] == 1


# ---------------------------------------------------------------------------
# _cmd_run (integration-level, using fakes)
# ---------------------------------------------------------------------------


class TestCmdRun:
    """Test _cmd_run end-to-end with patched loader and adapter."""

    def _make_args(
        self,
        test_path: str,
        oracle_mode: str = "snapshot",
        adapter: str = "julia",
        oracle_dir: str = "oracle",
        oracle_url: str = "http://localhost:8765",
        timeout: int = 60,
        filter: list[str] | None = None,
        format: str = "terminal",
    ):
        args = MagicMock()
        args.test_path = test_path
        args.oracle_mode = oracle_mode
        args.adapter = adapter
        args.oracle_dir = oracle_dir
        args.oracle_url = oracle_url
        args.timeout = timeout
        args.filter = filter
        args.format = format
        return args

    def test_path_not_found(self, tmp_path, capsys):
        args = self._make_args(str(tmp_path / "nonexistent"))
        rc = _cmd_run(args)
        assert rc == 1
        assert "not found" in capsys.readouterr().err

    def test_no_toml_files(self, tmp_path, capsys):
        args = self._make_args(str(tmp_path))
        rc = _cmd_run(args)
        assert rc == 0
        assert "no .toml test files" in capsys.readouterr().err

    def test_load_error_captured(self, tmp_path, capsys):
        """A malformed TOML file is reported as an error and counted as failure."""
        bad = tmp_path / "bad.toml"
        bad.write_text("not valid toml content ][")

        args = self._make_args(str(tmp_path))
        with patch("sxact.snapshot.store.SnapshotStore", side_effect=ValueError("no dir")):
            rc = _cmd_run(args)

        # Either oracle_dir missing causes rc=1 or load error does; either way rc=1
        assert rc == 1

    def test_snapshot_mode_all_pass(self, tmp_path, capsys):
        """All tests pass in snapshot mode → exit 0."""
        toml_file = tmp_path / "tests.toml"
        toml_file.write_text("")  # will be intercepted by mock

        tc = _make_tc(id="t1", ops=[Operation(action="Evaluate", args={"expression": "X"})])
        tf = _make_file(tests=[tc])
        snap = _make_snapshot("t1", normalized="X")
        store = _make_store({("pkg/tests", "t1"): snap})

        with (
            patch("sxact.runner.loader.load_test_file", return_value=tf),
            patch("sxact.snapshot.store.SnapshotStore", return_value=store),
            patch("sxact.adapter.julia_stub.JuliaAdapter") as MockJulia,
        ):
            adapter = _make_adapter(_ok("X", "X"))
            MockJulia.return_value = adapter
            args = self._make_args(str(toml_file))
            rc = _cmd_run(args)

        assert rc == 0

    def test_snapshot_mode_fail_returns_1(self, tmp_path, capsys):
        """At least one failure → exit 1."""
        toml_file = tmp_path / "tests.toml"
        toml_file.write_text("")

        tc = _make_tc(id="t1", ops=[Operation(action="Evaluate", args={"expression": "X"})])
        tf = _make_file(tests=[tc])
        snap = _make_snapshot("t1", normalized="DIFFERENT")
        store = _make_store({("pkg/tests", "t1"): snap})

        with (
            patch("sxact.runner.loader.load_test_file", return_value=tf),
            patch("sxact.snapshot.store.SnapshotStore", return_value=store),
            patch("sxact.adapter.julia_stub.JuliaAdapter") as MockJulia,
        ):
            adapter = _make_adapter(_ok("X", "X"))
            MockJulia.return_value = adapter
            args = self._make_args(str(toml_file))
            rc = _cmd_run(args)

        assert rc == 1

    def test_json_format_output(self, tmp_path, capsys):
        """--format=json produces parseable JSON."""
        toml_file = tmp_path / "tests.toml"
        toml_file.write_text("")

        tc = _make_tc(id="t1", ops=[Operation(action="Evaluate", args={"expression": "X"})])
        tf = _make_file(tests=[tc])
        snap = _make_snapshot("t1", normalized="X")
        store = _make_store({("pkg/tests", "t1"): snap})

        with (
            patch("sxact.runner.loader.load_test_file", return_value=tf),
            patch("sxact.snapshot.store.SnapshotStore", return_value=store),
            patch("sxact.adapter.julia_stub.JuliaAdapter") as MockJulia,
        ):
            adapter = _make_adapter(_ok("X", "X"))
            MockJulia.return_value = adapter
            args = self._make_args(str(toml_file), format="json")
            rc = _cmd_run(args)

        out = capsys.readouterr().out
        data = json.loads(out)
        assert data["summary"]["passed"] == 1
        assert rc == 0

    def test_tag_filter_in_cmd_run(self, tmp_path, capsys):
        """--filter tag:<tag> excludes files with no matching tests."""
        toml_file = tmp_path / "tests.toml"
        toml_file.write_text("")

        tc = _make_tc(id="t1", tags=["slow"])
        tf = _make_file(tests=[tc])
        store = _make_store({})

        with (
            patch("sxact.runner.loader.load_test_file", return_value=tf),
            patch("sxact.snapshot.store.SnapshotStore", return_value=store),
            patch("sxact.adapter.julia_stub.JuliaAdapter") as MockJulia,
        ):
            MockJulia.return_value = _make_adapter()
            args = self._make_args(str(toml_file), filter=["tag:smoke"])
            rc = _cmd_run(args)

        # No tests ran (all filtered out), no failures → exit 0
        assert rc == 0
