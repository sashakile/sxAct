"""Tests for three-tier comparator."""

import pytest

from sxact.compare import compare
from sxact.compare.comparator import EqualityMode
from sxact.oracle.result import Result


class TestTier1ExactMatch:
    """Tier 1: Normalized string comparison (pure Python, no oracle)."""

    def test_identical_normalized_strings(self) -> None:
        lhs = Result(
            status="ok",
            type="Expr",
            repr="T[-a, -b]",
            normalized="T[-$1, -$2]",
        )
        rhs = Result(
            status="ok",
            type="Expr",
            repr="T[-a, -b]",
            normalized="T[-$1, -$2]",
        )
        result = compare(lhs, rhs, oracle=None)
        assert result.equal
        assert result.tier == 1
        assert result.confidence == 1.0

    def test_different_raw_same_normalized(self) -> None:
        lhs = Result(
            status="ok",
            type="Expr",
            repr="T[-a, -b]",
            normalized="T[-$1, -$2]",
        )
        rhs = Result(
            status="ok",
            type="Expr",
            repr="T[-x, -y]",
            normalized="T[-$1, -$2]",
        )
        result = compare(lhs, rhs, oracle=None)
        assert result.equal
        assert result.tier == 1

    def test_different_normalized_strings(self) -> None:
        lhs = Result(
            status="ok",
            type="Expr",
            repr="T[-a, -b]",
            normalized="T[-$1, -$2]",
        )
        rhs = Result(
            status="ok",
            type="Expr",
            repr="2*T[-a, -b]",
            normalized="2 T[-$1, -$2]",
        )
        result = compare(lhs, rhs, oracle=None)
        assert not result.equal
        assert result.tier == 1
        assert result.diff is not None


class TestTier2SymbolicEquality:
    """Tier 2: Symbolic diff=0 via oracle Simplify."""

    @pytest.mark.oracle
    def test_expanded_polynomial_equality(self, oracle) -> None:
        """(a+b)^2 == a^2 + 2*a*b + b^2."""
        lhs = Result(
            status="ok",
            type="Expr",
            repr="(a+b)^2",
            normalized="(a + b)^2",
        )
        rhs = Result(
            status="ok",
            type="Expr",
            repr="a^2 + 2*a*b + b^2",
            normalized="a^2 + 2 a b + b^2",
        )
        result = compare(lhs, rhs, oracle)
        assert result.equal
        assert result.tier == 2

    @pytest.mark.oracle
    def test_algebraic_identity(self, oracle) -> None:
        """Test simple algebraic identity: 2*x - x == x."""
        lhs = Result(
            status="ok",
            type="Scalar",
            repr="2*x - x",
            normalized="2 x - x",
        )
        rhs = Result(
            status="ok",
            type="Scalar",
            repr="x",
            normalized="x",
        )
        result = compare(lhs, rhs, oracle)
        assert result.equal
        assert result.tier == 2

    @pytest.mark.oracle
    def test_symbolic_inequality(self, oracle) -> None:
        """Expressions that are not symbolically equal."""
        lhs = Result(
            status="ok",
            type="Expr",
            repr="T[-a,-b]",
            normalized="T[-$1, -$2]",
        )
        rhs = Result(
            status="ok",
            type="Expr",
            repr="3*T[-a,-b]",
            normalized="3 T[-$1, -$2]",
        )
        result = compare(lhs, rhs, oracle)
        assert not result.equal


class TestTier3NumericSampling:
    """Tier 3: Numeric sampling fallback."""

    @pytest.mark.oracle
    def test_numeric_sampling_match(self, oracle) -> None:
        """Expressions that evaluate to same numeric values when symbolic fails."""
        lhs = Result(
            status="ok",
            type="Scalar",
            repr="f[x] + f[x]",
            normalized="f[x] + f[x]",
        )
        rhs = Result(
            status="ok",
            type="Scalar",
            repr="2*f[x]",
            normalized="2 f[x]",
        )
        result = compare(lhs, rhs, oracle, mode=EqualityMode.NUMERIC)
        assert result.equal
        assert result.tier in (2, 3)
        if result.tier == 3:
            assert result.confidence < 1.0


class TestErrorHandling:
    """Error cases and edge conditions."""

    def test_error_status_lhs(self) -> None:
        lhs = Result(
            status="error",
            type="",
            repr="",
            normalized="",
            error="Evaluation failed",
        )
        rhs = Result(
            status="ok",
            type="Expr",
            repr="T[-a,-b]",
            normalized="T[-$1, -$2]",
        )
        result = compare(lhs, rhs, oracle=None)
        assert not result.equal
        assert result.diff is not None

    def test_error_status_rhs(self) -> None:
        lhs = Result(
            status="ok",
            type="Expr",
            repr="T[-a,-b]",
            normalized="T[-$1, -$2]",
        )
        rhs = Result(
            status="error",
            type="",
            repr="",
            normalized="",
            error="Timeout",
        )
        result = compare(lhs, rhs, oracle=None)
        assert not result.equal

    def test_empty_normalized_strings(self) -> None:
        lhs = Result(status="ok", type="Expr", repr="", normalized="")
        rhs = Result(status="ok", type="Expr", repr="", normalized="")
        result = compare(lhs, rhs, oracle=None)
        assert result.equal
        assert result.tier == 1
