"""Elegua comparison layer functions for xAct expression normalization.

Provides domain-specific layer functions that plug into elegua's
ComparisonPipeline:

- ``compare_canonical``: L3 canonical layer — normalizes both token
  reprs with ``ast_normalize`` and returns OK if they are equal.
- ``make_compare_numeric``: factory for L4 invariant layer — wraps
  ``sample_numeric`` with a captured oracle and returns a LayerFn.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from elegua.comparison import LayerFn
from elegua.models import ValidationToken
from elegua.task import TaskStatus

from sxact.normalize import ast_normalize

if TYPE_CHECKING:
    from sxact.compare.sampling import TensorContext
    from sxact.oracle.result import Result


def _make_result(repr_str: str) -> Result:
    from sxact.oracle.result import Result

    return Result(status="ok", type="Expr", repr=repr_str, normalized=repr_str)


def make_compare_numeric(
    oracle: Any,
    *,
    n: int = 10,
    seed: int = 42,
    tensor_ctx: TensorContext | None = None,
    confidence_threshold: float = 0.95,
) -> LayerFn:
    """Factory that returns an L4 numeric sampling layer for ComparisonPipeline.

    The returned ``LayerFn`` extracts the ``repr`` string from each token,
    converts them to minimal ``Result`` objects, and delegates to
    ``sxact.compare.sampling.sample_numeric``.

    Args:
        oracle:               Any object with an ``evaluate(expr) -> Result``
                              method (typically ``sxact.oracle.OracleClient``).
        n:                    Number of scalar realizations per comparison.
        seed:                 Random seed for reproducibility.
        tensor_ctx:           Optional tensor substitution context.
        confidence_threshold: Minimum match fraction to report equal.

    Raises:
        TypeError: if ``oracle`` is None.
    """
    if oracle is None:
        raise TypeError("oracle must not be None — pass an OracleClient instance")

    from sxact.compare.sampling import sample_numeric

    def compare_numeric(token_a: ValidationToken, token_b: ValidationToken) -> TaskStatus:
        if token_a.result is None or token_b.result is None:
            return TaskStatus.MATH_MISMATCH
        repr_a = token_a.result.get("repr")
        repr_b = token_b.result.get("repr")
        if repr_a is None or repr_b is None:
            return TaskStatus.MATH_MISMATCH
        lhs = _make_result(str(repr_a))
        rhs = _make_result(str(repr_b))
        sampling = sample_numeric(
            lhs,
            rhs,
            oracle,
            n=n,
            seed=seed,
            tensor_ctx=tensor_ctx,
            confidence_threshold=confidence_threshold,
        )
        return TaskStatus.OK if sampling.equal else TaskStatus.MATH_MISMATCH

    return compare_numeric


def compare_canonical(token_a: ValidationToken, token_b: ValidationToken) -> TaskStatus:
    """Layer 3 (canonical): normalize both reprs and compare.

    Extracts the ``repr`` string from each token's result dict, applies
    ``ast_normalize`` to both, and returns ``OK`` if they are equal.

    Returns ``MATH_MISMATCH`` if either result is absent or has no ``repr``.
    """
    if token_a.result is None or token_b.result is None:
        return TaskStatus.MATH_MISMATCH
    repr_a = token_a.result.get("repr")
    repr_b = token_b.result.get("repr")
    if repr_a is None or repr_b is None:
        return TaskStatus.MATH_MISMATCH
    if ast_normalize(str(repr_a)) == ast_normalize(str(repr_b)):
        return TaskStatus.OK
    return TaskStatus.MATH_MISMATCH
