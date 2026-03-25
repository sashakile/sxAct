"""Comparator tests using MockOracleClient — no live server required.

Covers Tier 2 (symbolic) and Tier 3 (numeric) code paths that would
otherwise require a running Docker oracle.
"""

from __future__ import annotations

from sxact.compare import compare
from sxact.compare.comparator import EqualityMode
from sxact.oracle.result import Result
from tests.conftest import MockOracleClient


def _ok(repr_: str, normalized: str = "") -> Result:
    return Result(status="ok", type="Expr", repr=repr_, normalized=normalized or repr_)


class TestTier2WithMock:
    """Tier 2: symbolic diff=0 — mock the oracle Simplify call."""

    def test_equal_expressions_simplify_to_zero(self) -> None:
        diff_expr = "Simplify[(a^2 + 2*a*b + b^2) - ((a+b)^2)]"
        oracle = MockOracleClient(
            {
                diff_expr: Result(status="ok", type="Expr", repr="0", normalized="0"),
            }
        )
        lhs = _ok("a^2 + 2*a*b + b^2", "a^2 + 2 a b + b^2")
        rhs = _ok("(a+b)^2", "(a + b)^2")
        result = compare(lhs, rhs, oracle)
        assert result.equal
        assert result.tier == 2
        assert result.confidence == 1.0

    def test_unequal_expressions_nonzero_diff(self) -> None:
        diff_expr = "Simplify[(x) - (2*x)]"
        oracle = MockOracleClient(
            {
                diff_expr: Result(status="ok", type="Expr", repr="-x", normalized="-x"),
            }
        )
        lhs = _ok("x", "x")
        rhs = _ok("2*x", "2 x")
        result = compare(lhs, rhs, oracle)
        assert not result.equal
        assert result.tier == 2
        assert result.diff is not None

    def test_oracle_error_propagates_as_not_equal(self) -> None:
        diff_expr = "Simplify[(T[-a,-b]) - (S[-a,-b])]"
        oracle = MockOracleClient(
            {
                diff_expr: Result(
                    status="error",
                    type="",
                    repr="",
                    normalized="",
                    error="kernel crash",
                ),
            }
        )
        lhs = _ok("T[-a,-b]", "T[-$1,-$2]")
        rhs = _ok("S[-a,-b]", "S[-$1,-$2]")
        result = compare(lhs, rhs, oracle)
        assert not result.equal
        assert result.tier == 2
        assert "Oracle error" in (result.diff or "")

    def test_tier1_short_circuits_before_oracle(self) -> None:
        """When normalized strings match, oracle must NOT be called."""
        oracle = MockOracleClient()  # no responses; any call would fail
        lhs = _ok("T[-a,-b]", "T[-$1,-$2]")
        rhs = _ok("T[-x,-y]", "T[-$1,-$2]")
        result = compare(lhs, rhs, oracle)
        assert result.equal
        assert result.tier == 1
        assert oracle.calls == []

    def test_normalized_mode_skips_oracle(self) -> None:
        oracle = MockOracleClient()
        lhs = _ok("x", "x")
        rhs = _ok("2*x", "2 x")
        result = compare(lhs, rhs, oracle, mode=EqualityMode.NORMALIZED)
        assert not result.equal
        assert oracle.calls == []

    def test_mock_health_returns_true(self) -> None:
        oracle = MockOracleClient()
        assert oracle.health() is True

    def test_mock_cleanup_returns_true(self) -> None:
        oracle = MockOracleClient()
        assert oracle.cleanup() is True

    def test_mock_records_calls(self) -> None:
        expr = "Simplify[(a) - (a)]"
        oracle = MockOracleClient(
            {
                expr: Result(status="ok", type="Expr", repr="0", normalized="0"),
            }
        )
        lhs = _ok("a", "a_diff")
        rhs = _ok("a", "a")
        compare(lhs, rhs, oracle)
        assert expr in oracle.calls

    def test_unrecognized_expr_returns_error_result(self) -> None:
        oracle = MockOracleClient()
        result = oracle.evaluate("UnknownExpr[x]")
        assert result.status == "error"
        assert result.error is not None

    def test_evaluate_with_xact_uses_responses(self) -> None:
        oracle = MockOracleClient(
            {
                "SomeExpr": Result(status="ok", type="Expr", repr="42", normalized="42"),
            }
        )
        result = oracle.evaluate_with_xact("SomeExpr", context_id="test")
        assert result.status == "ok"
        assert result.repr == "42"
        assert "SomeExpr" in oracle.calls
