"""Unit tests for sxact.runner.isolation.IsolatedContext.

All tests are oracle-free: the adapter is a lightweight fake.
Key invariants under test:
  - Setup bindings are available to all tests in a file.
  - Per-test bindings do not leak to subsequent tests.
  - teardown is always called (success or exception).
  - Skipped tests are not executed.
  - Adapter errors produce "error" status, not exceptions.
"""

from __future__ import annotations

from pathlib import Path
from unittest.mock import MagicMock

import pytest

from sxact.oracle.result import Result
from sxact.runner.isolation import (
    IsolatedContext,
    _sub_refs,
    _substitute_bindings,
)
from sxact.runner.loader import (
    Expected,
    ExpectedProperties,
    Operation,
    TestCase,
    TestFile,
    TestMeta,
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _ok(repr: str, normalized: str = "", properties: dict | None = None) -> Result:
    return Result(
        status="ok",
        type="Expr",
        repr=repr,
        normalized=normalized or repr,
        properties=properties or {},
    )


def _err(msg: str) -> Result:
    return Result(status="error", type="Expr", repr="", normalized="", error=msg)


def _make_file(
    setup: list[Operation] | None = None,
    tests: list[TestCase] | None = None,
    meta_id: str = "test/file",
) -> TestFile:
    return TestFile(
        meta=TestMeta(id=meta_id, description="test"),
        setup=setup or [],
        tests=tests or [],
        source_path=Path("dummy.toml"),
    )


def _make_tc(
    id: str = "tc_001",
    ops: list[Operation] | None = None,
    skip: str | None = None,
    expected: Expected | None = None,
) -> TestCase:
    return TestCase(
        id=id,
        description="a test",
        operations=ops or [],
        skip=skip,
        expected=expected,
    )


def _make_adapter(*results: Result) -> MagicMock:
    """Return a fake adapter that yields *results* in order from execute()."""
    adapter = MagicMock()
    adapter.initialize.return_value = object()
    adapter.teardown.return_value = None
    adapter.execute.side_effect = list(results)
    adapter.normalize.side_effect = lambda expr: expr  # identity normalization
    adapter.equals.side_effect = lambda a, b, mode, ctx=None: a == b
    return adapter


# ---------------------------------------------------------------------------
# _sub_refs / _substitute_bindings
# ---------------------------------------------------------------------------


class TestSubRefs:
    def test_no_refs(self):
        assert _sub_refs("ToCanonical[T]", {}) == "ToCanonical[T]"

    def test_substitutes_ref(self):
        assert _sub_refs("$lhs", {"lhs": "T[-a,-b]"}) == "T[-a,-b]"

    def test_missing_ref_preserved(self):
        assert _sub_refs("$gone", {}) == "$gone"

    def test_partial_name_not_matched(self):
        # $lhs2 must not match binding for $lhs
        assert _sub_refs("$lhs2", {"lhs": "X"}) == "$lhs2"


class TestSubstituteBindings:
    def test_string_values_substituted(self):
        result = _substitute_bindings({"expr": "$x"}, {"x": "T"})
        assert result == {"expr": "T"}

    def test_non_string_values_unchanged(self):
        result = _substitute_bindings({"dim": 4, "indices": ["a", "b"]}, {"a": "X"})
        assert result == {"dim": 4, "indices": ["a", "b"]}

    def test_original_not_mutated(self):
        args = {"expr": "$x"}
        _substitute_bindings(args, {"x": "T"})
        assert args["expr"] == "$x"


# ---------------------------------------------------------------------------
# Context manager protocol
# ---------------------------------------------------------------------------


class TestContextManager:
    def test_initialize_called_on_enter(self):
        adapter = _make_adapter()
        tf = _make_file()
        with IsolatedContext(adapter, tf):
            adapter.initialize.assert_called_once()

    def test_teardown_called_on_clean_exit(self):
        adapter = _make_adapter()
        tf = _make_file()
        with IsolatedContext(adapter, tf):
            pass
        adapter.teardown.assert_called_once()

    def test_teardown_called_on_exception(self):
        adapter = _make_adapter()
        tf = _make_file()
        with pytest.raises(ValueError), IsolatedContext(adapter, tf):
            raise ValueError("boom")
        adapter.teardown.assert_called_once()

    def test_run_test_outside_context_raises(self):
        adapter = _make_adapter()
        tf = _make_file()
        ctx = IsolatedContext(adapter, tf)
        tc = _make_tc(ops=[Operation(action="Evaluate", args={"expression": "1"})])
        with pytest.raises(RuntimeError, match="context manager"):
            ctx.run_test(tc)


# ---------------------------------------------------------------------------
# Setup bindings
# ---------------------------------------------------------------------------


class TestSetupBindings:
    def test_setup_runs_before_tests(self):
        """Setup op is executed; its store_as value is available to tests."""
        setup_op = Operation(action="DefManifold", args={"name": "M"}, store_as="manifold")
        test_op = Operation(action="Evaluate", args={"expression": "$manifold"})
        tc = _make_tc(ops=[test_op])
        tf = _make_file(setup=[setup_op], tests=[tc])

        captured: list[dict] = []
        results = [_ok("M"), _ok("M")]

        def capturing_execute(ctx, action, args):
            captured.append(dict(args))
            return results.pop(0)

        adapter = _make_adapter()
        adapter.execute.side_effect = capturing_execute

        with IsolatedContext(adapter, tf) as iso:
            iso.run_test(tc)

        # Second call (the test op) should have $manifold substituted
        assert captured[1]["expression"] == "M"

    def test_setup_bindings_available_to_all_tests(self):
        """Both tests can use the same setup binding."""
        setup_op = Operation(action="DefManifold", args={"name": "M"}, store_as="m")
        tc1 = _make_tc(id="t1", ops=[Operation(action="Evaluate", args={"expression": "$m"})])
        tc2 = _make_tc(id="t2", ops=[Operation(action="Evaluate", args={"expression": "$m"})])
        tf = _make_file(setup=[setup_op], tests=[tc1, tc2])

        captured: list[dict] = []

        def capturing_execute(ctx, action, args):
            captured.append(dict(args))
            return _ok("M")

        adapter = _make_adapter()
        adapter.execute.side_effect = capturing_execute

        with IsolatedContext(adapter, tf) as iso:
            iso.run_test(tc1)
            iso.run_test(tc2)

        # calls: [setup, t1-op, t2-op] — both test ops should get "M"
        assert captured[1]["expression"] == "M"
        assert captured[2]["expression"] == "M"


# ---------------------------------------------------------------------------
# Per-test binding isolation
# ---------------------------------------------------------------------------


class TestBindingIsolation:
    def test_per_test_binding_does_not_leak(self):
        """A binding set in test A must not be visible in test B."""
        op_a = Operation(action="Evaluate", args={"expression": "X"}, store_as="result")
        # Test B tries to use $result — it should be unresolved ($result) because
        # it was not set in setup and B runs after A.
        op_b = Operation(action="Evaluate", args={"expression": "$result"})

        tc_a = _make_tc(id="ta", ops=[op_a])
        tc_b = _make_tc(id="tb", ops=[op_b])
        tf = _make_file(tests=[tc_a, tc_b])

        captured: list[dict] = []

        def capturing_execute(ctx, action, args):
            captured.append(dict(args))
            return _ok("X")

        adapter = _make_adapter()
        adapter.execute.side_effect = capturing_execute

        with IsolatedContext(adapter, tf) as iso:
            iso.run_test(tc_a)
            iso.run_test(tc_b)

        # tc_b's op should still have the raw "$result" token (unsubstituted)
        assert captured[1]["expression"] == "$result"

    def test_within_test_bindings_propagate(self):
        """store_as in op1 must be visible to op2 within the same test."""
        op1 = Operation(action="Evaluate", args={"expression": "T"}, store_as="lhs")
        op2 = Operation(action="ToCanonical", args={"expression": "$lhs"})
        tc = _make_tc(ops=[op1, op2])
        tf = _make_file(tests=[tc])

        captured: list[dict] = []

        def capturing_execute(ctx, action, args):
            captured.append(dict(args))
            return _ok("T")

        adapter = _make_adapter()
        adapter.execute.side_effect = capturing_execute

        with IsolatedContext(adapter, tf) as iso:
            iso.run_test(tc)

        assert captured[1]["expression"] == "T"


# ---------------------------------------------------------------------------
# Skip handling
# ---------------------------------------------------------------------------


class TestSkip:
    def test_skipped_test_returns_skip_status(self):
        tc = _make_tc(skip="not implemented yet")
        tf = _make_file(tests=[tc])
        adapter = _make_adapter()

        with IsolatedContext(adapter, tf) as iso:
            result = iso.run_test(tc)

        assert result.status == "skip"
        assert result.message == "not implemented yet"
        adapter.execute.assert_not_called()

    def test_non_skipped_test_is_executed(self):
        tc = _make_tc(ops=[Operation(action="Evaluate", args={"expression": "1"})])
        tf = _make_file(tests=[tc])
        adapter = _make_adapter(_ok("1"))

        with IsolatedContext(adapter, tf) as iso:
            result = iso.run_test(tc)

        assert result.status == "pass"


# ---------------------------------------------------------------------------
# Adapter error handling
# ---------------------------------------------------------------------------


class TestAdapterErrors:
    def test_adapter_error_result_produces_error_status(self):
        """When execute returns status='error', run_test returns 'error', not 'fail'."""
        tc = _make_tc(ops=[Operation(action="Evaluate", args={"expression": "bad"})])
        tf = _make_file(tests=[tc])
        adapter = _make_adapter(_err("syntax error"))

        with IsolatedContext(adapter, tf) as iso:
            result = iso.run_test(tc)

        assert result.status == "error"
        assert "syntax error" in (result.message or "")

    def test_execute_exception_produces_error_status(self):
        """When execute raises, run_test returns 'error' and teardown still runs."""
        tc = _make_tc(ops=[Operation(action="Evaluate", args={"expression": "boom"})])
        tf = _make_file(tests=[tc])
        adapter = _make_adapter()
        adapter.execute.side_effect = RuntimeError("connection lost")

        with IsolatedContext(adapter, tf) as iso:
            result = iso.run_test(tc)

        assert result.status == "error"
        assert "connection lost" in (result.message or "")
        adapter.teardown.assert_called_once()


# ---------------------------------------------------------------------------
# Expected comparison
# ---------------------------------------------------------------------------


class TestExpectedComparison:
    def test_pass_when_no_expected(self):
        tc = _make_tc(ops=[Operation(action="Evaluate", args={"expression": "1+1"})])
        tf = _make_file(tests=[tc])
        adapter = _make_adapter(_ok("2"))

        with IsolatedContext(adapter, tf) as iso:
            result = iso.run_test(tc)

        assert result.status == "pass"

    def test_pass_on_expr_match(self):
        exp = Expected(expr="2")
        tc = _make_tc(
            ops=[Operation(action="Evaluate", args={"expression": "1+1"})],
            expected=exp,
        )
        tf = _make_file(tests=[tc])
        # normalize is identity; equals checks equality
        adapter = _make_adapter(_ok("2"))

        with IsolatedContext(adapter, tf) as iso:
            result = iso.run_test(tc)

        assert result.status == "pass"

    def test_fail_on_expr_mismatch(self):
        exp = Expected(expr="3")
        tc = _make_tc(
            ops=[Operation(action="Evaluate", args={"expression": "1+1"})],
            expected=exp,
        )
        tf = _make_file(tests=[tc])
        adapter = _make_adapter(_ok("2"))

        with IsolatedContext(adapter, tf) as iso:
            result = iso.run_test(tc)

        assert result.status == "fail"
        assert result.actual == "2"
        assert result.expected == "3"

    def test_pass_on_normalized_match(self):
        exp = Expected(normalized="T[-$1,-$2]")
        tc = _make_tc(
            ops=[Operation(action="Evaluate", args={"expression": "T[-a,-b]"})],
            expected=exp,
        )
        tf = _make_file(tests=[tc])
        adapter = _make_adapter(_ok("T[-a,-b]", "T[-$1,-$2]"))
        # Override normalize to return the normalized field from the result
        adapter.normalize.side_effect = lambda expr: "T[-$1,-$2]" if expr == "T[-a,-b]" else expr

        with IsolatedContext(adapter, tf) as iso:
            result = iso.run_test(tc)

        assert result.status == "pass"

    def test_fail_on_normalized_mismatch(self):
        exp = Expected(normalized="T[-$1,-$2]")
        tc = _make_tc(
            ops=[Operation(action="Evaluate", args={"expression": "R[-a,-b]"})],
            expected=exp,
        )
        tf = _make_file(tests=[tc])
        adapter = _make_adapter(_ok("R[-a,-b]", "R[-$1,-$2]"))
        adapter.normalize.side_effect = lambda expr: "R[-$1,-$2]" if "R" in expr else expr

        with IsolatedContext(adapter, tf) as iso:
            result = iso.run_test(tc)

        assert result.status == "fail"

    def test_pass_on_is_zero_true(self):
        exp = Expected(is_zero=True)
        tc = _make_tc(
            ops=[Operation(action="Simplify", args={"expression": "T-T"})],
            expected=exp,
        )
        tf = _make_file(tests=[tc])
        adapter = _make_adapter(_ok("0"))
        # normalize("0") == "0", normalize("0") == "0" → actually_zero = True
        adapter.normalize.side_effect = lambda expr: expr

        with IsolatedContext(adapter, tf) as iso:
            result = iso.run_test(tc)

        assert result.status == "pass"

    def test_fail_on_is_zero_mismatch(self):
        exp = Expected(is_zero=True)
        tc = _make_tc(
            ops=[Operation(action="Simplify", args={"expression": "T"})],
            expected=exp,
        )
        tf = _make_file(tests=[tc])
        adapter = _make_adapter(_ok("T"))
        adapter.normalize.side_effect = lambda expr: expr

        with IsolatedContext(adapter, tf) as iso:
            result = iso.run_test(tc)

        assert result.status == "fail"

    def test_pass_on_properties_rank(self):
        exp = Expected(properties=ExpectedProperties(rank=2))
        tc = _make_tc(
            ops=[Operation(action="Evaluate", args={"expression": "T[-a,-b]"})],
            expected=exp,
        )
        tf = _make_file(tests=[tc])
        adapter = _make_adapter(_ok("T[-a,-b]", properties={"rank": 2}))

        with IsolatedContext(adapter, tf) as iso:
            result = iso.run_test(tc)

        assert result.status == "pass"

    def test_fail_on_properties_rank_mismatch(self):
        exp = Expected(properties=ExpectedProperties(rank=3))
        tc = _make_tc(
            ops=[Operation(action="Evaluate", args={"expression": "T[-a,-b]"})],
            expected=exp,
        )
        tf = _make_file(tests=[tc])
        adapter = _make_adapter(_ok("T[-a,-b]", properties={"rank": 2}))

        with IsolatedContext(adapter, tf) as iso:
            result = iso.run_test(tc)

        assert result.status == "fail"
        assert result.expected == "3"
        assert result.actual == "2"


# ---------------------------------------------------------------------------
# expect_error handling
# ---------------------------------------------------------------------------


class TestExpectError:
    def test_pass_when_adapter_returns_error(self):
        """expect_error=True + adapter error → pass."""
        exp = Expected(expect_error=True)
        tc = _make_tc(
            ops=[Operation(action="Evaluate", args={"expression": "bad"})],
            expected=exp,
        )
        tf = _make_file(tests=[tc])
        adapter = _make_adapter(_err("syntax error"))

        with IsolatedContext(adapter, tf) as iso:
            result = iso.run_test(tc)

        assert result.status == "pass"

    def test_pass_when_adapter_raises_exception(self):
        """expect_error=True + exception → pass."""
        exp = Expected(expect_error=True)
        tc = _make_tc(
            ops=[Operation(action="Evaluate", args={"expression": "boom"})],
            expected=exp,
        )
        tf = _make_file(tests=[tc])
        adapter = _make_adapter()
        adapter.execute.side_effect = RuntimeError("connection lost")

        with IsolatedContext(adapter, tf) as iso:
            result = iso.run_test(tc)

        assert result.status == "pass"

    def test_fail_when_no_error_but_expected(self):
        """expect_error=True + success → fail."""
        exp = Expected(expect_error=True)
        tc = _make_tc(
            ops=[Operation(action="Evaluate", args={"expression": "1+1"})],
            expected=exp,
        )
        tf = _make_file(tests=[tc])
        adapter = _make_adapter(_ok("2"))

        with IsolatedContext(adapter, tf) as iso:
            result = iso.run_test(tc)

        assert result.status == "fail"
        assert "Expected error" in (result.message or "")

    def test_error_status_without_expect_error(self):
        """Without expect_error, adapter error → error (unchanged behavior)."""
        tc = _make_tc(
            ops=[Operation(action="Evaluate", args={"expression": "bad"})],
        )
        tf = _make_file(tests=[tc])
        adapter = _make_adapter(_err("syntax error"))

        with IsolatedContext(adapter, tf) as iso:
            result = iso.run_test(tc)

        assert result.status == "error"
