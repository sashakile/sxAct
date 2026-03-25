"""Three-tier comparator for expression equivalence.

Comparison tiers:
1. Tier 1: Normalized string comparison (pure Python)
2. Tier 2: Symbolic diff=0 via oracle Simplify
3. Tier 3: Numeric sampling fallback
"""

from dataclasses import dataclass
from enum import Enum, auto
from typing import TYPE_CHECKING, Optional

from sxact.compare.sampling import TensorContext, sample_numeric

if TYPE_CHECKING:
    from sxact.oracle import OracleClient
    from sxact.oracle.result import Result


class EqualityMode(Enum):
    """Mode for equality comparison."""

    NORMALIZED = auto()
    SYMBOLIC = auto()
    NUMERIC = auto()


@dataclass
class CompareResult:
    """Result of comparing two expressions.

    Attributes:
        equal: Whether the expressions are equal
        tier: Which tier determined equality (1, 2, or 3)
        confidence: Confidence level (1.0 for tiers 1-2, <1.0 for tier 3)
        diff: Description of difference if not equal
    """

    equal: bool
    tier: int
    confidence: float = 1.0
    diff: str | None = None


def compare(
    lhs: "Result",
    rhs: "Result",
    oracle: Optional["OracleClient"],
    mode: EqualityMode = EqualityMode.SYMBOLIC,
    tensor_ctx: Optional["TensorContext"] = None,
) -> CompareResult:
    """Compare two Results for equivalence using three-tier strategy.

    Args:
        lhs:        Left-hand side Result
        rhs:        Right-hand side Result
        oracle:     OracleClient for symbolic/numeric comparison (optional for tier 1)
        mode:       Maximum tier to use for comparison
        tensor_ctx: Optional tensor context for Tier 3 tensor sampling

    Returns:
        CompareResult indicating equality and which tier determined it
    """
    if lhs.status != "ok":
        return CompareResult(
            equal=False,
            tier=1,
            diff=f"LHS error: {lhs.error or lhs.status}",
        )

    if rhs.status != "ok":
        return CompareResult(
            equal=False,
            tier=1,
            diff=f"RHS error: {rhs.error or rhs.status}",
        )

    tier1_result = _compare_tier1(lhs, rhs)
    if tier1_result.equal or mode == EqualityMode.NORMALIZED:
        return tier1_result

    if oracle is None:
        return tier1_result

    tier2_result = _compare_tier2(lhs, rhs, oracle)
    if tier2_result.equal or mode == EqualityMode.SYMBOLIC:
        return tier2_result

    return _compare_tier3(lhs, rhs, oracle, tensor_ctx=tensor_ctx)


def _compare_tier1(lhs: "Result", rhs: "Result") -> CompareResult:
    """Tier 1: Normalized string comparison."""
    if lhs.normalized == rhs.normalized:
        return CompareResult(equal=True, tier=1, confidence=1.0)

    return CompareResult(
        equal=False,
        tier=1,
        diff=f"Normalized mismatch: '{lhs.normalized}' != '{rhs.normalized}'",
    )


def _compare_tier2(lhs: "Result", rhs: "Result", oracle: "OracleClient") -> CompareResult:
    """Tier 2: Symbolic diff=0 via oracle Simplify."""
    diff_expr = f"Simplify[({lhs.repr}) - ({rhs.repr})]"

    result = oracle.evaluate(diff_expr)

    if result.status != "ok":
        return CompareResult(
            equal=False,
            tier=2,
            diff=f"Oracle error: {result.error}",
        )

    simplified = result.repr.strip() if result.repr else ""

    if simplified == "0":
        return CompareResult(equal=True, tier=2, confidence=1.0)

    return CompareResult(
        equal=False,
        tier=2,
        diff=f"Symbolic diff: {simplified}",
    )


def _compare_tier3(
    lhs: "Result",
    rhs: "Result",
    oracle: "OracleClient",
    tensor_ctx: Optional["TensorContext"] = None,
) -> CompareResult:
    """Tier 3: Numeric sampling fallback."""
    result = sample_numeric(lhs, rhs, oracle, tensor_ctx=tensor_ctx)

    if not result.samples:
        return CompareResult(
            equal=False,
            tier=3,
            diff="No numeric samples could be evaluated",
        )

    n = len(result.samples)
    matches = sum(1 for s in result.samples if s.match)

    if result.equal:
        return CompareResult(equal=True, tier=3, confidence=result.confidence)

    return CompareResult(
        equal=False,
        tier=3,
        confidence=result.confidence,
        diff=f"Numeric mismatch: {matches}/{n} samples matched",
    )
