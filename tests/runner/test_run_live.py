"""Tests for _run_file_live using elegua.IsolatedRunner.

All tests are oracle-free: the adapter is a lightweight elegua stub.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

from elegua.adapter import Adapter
from elegua.models import ValidationToken
from elegua.task import EleguaTask, TaskStatus

from sxact.cli.run import _run_file_live
from sxact.runner.loader import Expected, Operation, TestCase, TestFile, TestMeta


# ---------------------------------------------------------------------------
# Stub elegua adapter
# ---------------------------------------------------------------------------


class _StubElegua(Adapter):
    """Minimal elegua Adapter for testing _run_file_live."""

    def __init__(self, tokens: list[ValidationToken] | None = None) -> None:
        self._tokens = list(tokens or [])
        self._call_idx = 0
        self.initialized = False
        self.torn_down = False

    @property
    def adapter_id(self) -> str:
        return "stub"

    def initialize(self) -> None:
        self.initialized = True

    def teardown(self) -> None:
        self.torn_down = True

    def execute(self, task: EleguaTask) -> ValidationToken:
        if self._call_idx < len(self._tokens):
            token = self._tokens[self._call_idx]
        else:
            token = ValidationToken(
                adapter_id="stub",
                status=TaskStatus.OK,
                result={"repr": "42", "type": "Expr"},
            )
        self._call_idx += 1
        return token


def _ok_token(repr_str: str = "42") -> ValidationToken:
    return ValidationToken(
        adapter_id="stub",
        status=TaskStatus.OK,
        result={"repr": repr_str, "type": "Expr"},
    )


def _error_token(msg: str = "kernel error") -> ValidationToken:
    return ValidationToken(
        adapter_id="stub",
        status=TaskStatus.EXECUTION_ERROR,
        metadata={"error": msg},
    )


# ---------------------------------------------------------------------------
# Helpers to build sxact loader types
# ---------------------------------------------------------------------------


def _make_tf(
    tests: list[TestCase],
    setup: list[Operation] | None = None,
    file_id: str = "test/suite",
) -> TestFile:
    return TestFile(
        meta=TestMeta(id=file_id, description="test"),
        setup=setup or [],
        tests=tests,
        source_path=Path("dummy.toml"),
    )


def _make_tc(
    ops: list[Operation] | None = None,
    expected: Expected | None = None,
    skip: str | None = None,
    tags: list[str] | None = None,
    tc_id: str = "tc_001",
) -> TestCase:
    return TestCase(
        id=tc_id,
        description="a test",
        operations=ops or [Operation(action="Evaluate", args={"expression": "1"})],
        expected=expected,
        skip=skip,
        tags=tags or [],
    )


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


class TestRunFileLiveBasic:
    def test_no_expected_returns_pass(self) -> None:
        tf = _make_tf([_make_tc()])
        adapter = _StubElegua([_ok_token("2")])
        results = _run_file_live(tf, adapter, None)
        assert len(results) == 1
        assert results[0].status == "pass"

    def test_expr_match_returns_pass(self) -> None:
        tf = _make_tf([_make_tc(expected=Expected(expr="2"))])
        adapter = _StubElegua([_ok_token("2")])
        results = _run_file_live(tf, adapter, None)
        assert results[0].status == "pass"

    def test_expr_mismatch_returns_fail(self) -> None:
        tf = _make_tf([_make_tc(expected=Expected(expr="3"))])
        adapter = _StubElegua([_ok_token("2")])
        results = _run_file_live(tf, adapter, None)
        assert results[0].status == "fail"
        assert results[0].actual == "2"
        assert results[0].expected == "3"

    def test_skip_returns_skip(self) -> None:
        tf = _make_tf([_make_tc(skip="not implemented")])
        adapter = _StubElegua()
        results = _run_file_live(tf, adapter, None)
        assert results[0].status == "skip"
        assert results[0].message == "not implemented"

    def test_file_id_populated(self) -> None:
        tf = _make_tf([_make_tc()], file_id="xcore/basics")
        adapter = _StubElegua([_ok_token()])
        results = _run_file_live(tf, adapter, None)
        assert results[0].file_id == "xcore/basics"

    def test_test_id_populated(self) -> None:
        tf = _make_tf([_make_tc(tc_id="my_test_001")])
        adapter = _StubElegua([_ok_token()])
        results = _run_file_live(tf, adapter, None)
        assert results[0].test_id == "my_test_001"

    def test_adapter_lifecycle_called(self) -> None:
        tf = _make_tf([_make_tc()])
        adapter = _StubElegua([_ok_token()])
        _run_file_live(tf, adapter, None)
        assert adapter.initialized
        assert adapter.torn_down


class TestRunFileLiveTagFilter:
    def test_tag_filter_includes_matching(self) -> None:
        tc = _make_tc(tags=["xcore"], tc_id="match")
        tf = _make_tf([tc])
        adapter = _StubElegua([_ok_token()])
        results = _run_file_live(tf, adapter, "xcore")
        assert len(results) == 1
        assert results[0].test_id == "match"

    def test_tag_filter_excludes_non_matching(self) -> None:
        tc = _make_tc(tags=["xtensor"], tc_id="no_match")
        tf = _make_tf([tc])
        adapter = _StubElegua([_ok_token()])
        results = _run_file_live(tf, adapter, "xcore")
        assert len(results) == 0

    def test_no_tag_filter_includes_all(self) -> None:
        tcs = [_make_tc(tc_id=f"tc_{i}") for i in range(3)]
        adapter = _StubElegua([_ok_token()] * 3)
        tf = _make_tf(tcs)
        results = _run_file_live(tf, adapter, None)
        assert len(results) == 3


class TestRunFileLiveMultipleTests:
    def test_returns_result_for_each_test(self) -> None:
        tcs = [_make_tc(tc_id=f"t{i}") for i in range(3)]
        adapter = _StubElegua([_ok_token()] * 3)
        tf = _make_tf(tcs)
        results = _run_file_live(tf, adapter, None)
        assert len(results) == 3
        assert [r.test_id for r in results] == ["t0", "t1", "t2"]


class TestRunFileLiveErrorEscalation:
    def test_execution_error_no_expected_escalates_to_error(self) -> None:
        tf = _make_tf([_make_tc()])
        adapter = _StubElegua([_error_token("syntax error")])
        results = _run_file_live(tf, adapter, None)
        assert results[0].status == "error"
        assert results[0].message == "syntax error"

    def test_execution_error_with_expr_expected_does_not_escalate(self) -> None:
        # Escalation only fires when verdict is "pass"; a non-pass verdict is not escalated.
        tf = _make_tf([_make_tc(expected=Expected(expr="99"))])
        adapter = _StubElegua([_error_token("kernel crash")])
        results = _run_file_live(tf, adapter, None)
        # evaluate_expected sees no result.error and no matching expr → "fail", not escalated
        assert results[0].status == "fail"

    def test_execution_error_no_metadata_escalates_with_fallback_message(self) -> None:
        token = ValidationToken(adapter_id="stub", status=TaskStatus.EXECUTION_ERROR)
        tf = _make_tf([_make_tc()])
        adapter = _StubElegua([token])
        results = _run_file_live(tf, adapter, None)
        assert results[0].status == "error"
        assert results[0].message == "execution error"
