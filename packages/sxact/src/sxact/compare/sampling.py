"""Numeric sampling for expression comparison.

Substitutes random values for free variables and compares numeric results.
Supports both scalar variables and tensor component arrays.

Confidence scoring
------------------
``sample_numeric`` now returns a ``SamplingResult`` that includes a
``confidence`` score (fraction of realizations that matched).  The old
``list[Sample]`` is still available as ``SamplingResult.samples``.

Tensor sampling
---------------
Pass a ``TensorContext`` to ``sample_numeric`` to enable tensor component
substitution.  Each named tensor in the context receives a random component
array; the oracle evaluates the expression with numeric substitution rules.
"""

from __future__ import annotations

import random
import re
from collections.abc import Mapping
from dataclasses import dataclass, field
from typing import TYPE_CHECKING, Any

import numpy as np

if TYPE_CHECKING:
    from sxact.oracle import OracleClient
    from sxact.oracle.result import Result
    from sxact.compare.tensor_objects import Manifold, Metric, TensorField


# ---------------------------------------------------------------------------
# Sample — single realization
# ---------------------------------------------------------------------------


@dataclass
class Sample:
    """Result of a single numeric sample comparison."""

    substitution: Mapping[str, float | np.ndarray[Any, np.dtype[Any]]]
    lhs_value: float | None
    rhs_value: float | None
    match: bool
    tolerance: float = 1e-10


# ---------------------------------------------------------------------------
# SamplingResult — aggregate of multiple realizations
# ---------------------------------------------------------------------------


@dataclass
class SamplingResult:
    """Aggregate result from multiple numeric sampling realizations.

    Attributes:
        samples:    Individual Sample results.
        confidence: Fraction of samples that matched (0.0–1.0).
                    1.0 means all realizations agreed; 0.0 means none did.
        equal:      True when confidence >= threshold (default 0.95).
    """

    samples: list[Sample]
    confidence: float
    equal: bool

    @classmethod
    def from_samples(
        cls, samples: list[Sample], threshold: float = 0.95
    ) -> "SamplingResult":
        if not samples:
            return cls(samples=[], confidence=0.0, equal=False)
        matches = sum(1 for s in samples if s.match)
        confidence = matches / len(samples)
        return cls(
            samples=samples, confidence=confidence, equal=confidence >= threshold
        )


# ---------------------------------------------------------------------------
# Tensor substitution context
# ---------------------------------------------------------------------------


@dataclass
class TensorContext:
    """Tensor components to substitute during numeric sampling.

    Build this from the adapter context by listing the tensors and metrics
    that appear in the expression being sampled.

    Attributes:
        manifolds:  Manifold objects keyed by name.
        metrics:    Metric objects keyed by name, with their numeric arrays.
        tensors:    Tensor objects keyed by name, with their numeric arrays.
    """

    manifolds: dict[str, "Manifold"] = field(default_factory=dict)
    metric_arrays: dict[str, np.ndarray[Any, np.dtype[Any]]] = field(
        default_factory=dict
    )
    tensor_arrays: dict[str, np.ndarray[Any, np.dtype[Any]]] = field(
        default_factory=dict
    )


def build_tensor_context(
    manifolds: list["Manifold"],
    metrics: list["Metric"],
    tensors: list["TensorField"],
    rng: np.random.Generator | None = None,
) -> TensorContext:
    """Generate random component arrays for all provided tensor objects.

    Args:
        manifolds: Manifold definitions.
        metrics:   Metric definitions (each references a Manifold by name).
        tensors:   Tensor field definitions.
        rng:       NumPy random generator (reproducible if seeded).

    Returns:
        A TensorContext ready for substitution.
    """
    from sxact.compare.tensor_objects import (
        random_metric_array,
        random_tensor_array,
    )

    rng = rng or np.random.default_rng()
    ctx = TensorContext()
    for m in manifolds:
        ctx.manifolds[m.name] = m
    for metric in metrics:
        ctx.metric_arrays[metric.name] = random_metric_array(metric, rng)
    for tensor in tensors:
        ctx.tensor_arrays[tensor.name] = random_tensor_array(tensor, rng)
    return ctx


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def sample_numeric(
    lhs: "Result",
    rhs: "Result",
    oracle: "OracleClient",
    n: int = 10,
    seed: int = 42,
    tensor_ctx: TensorContext | None = None,
    confidence_threshold: float = 0.95,
) -> SamplingResult:
    """Sample expressions numerically to check equivalence.

    Args:
        lhs:                  Left-hand side Result.
        rhs:                  Right-hand side Result.
        oracle:               OracleClient for evaluation.
        n:                    Number of scalar realizations.
        seed:                 Random seed for reproducibility.
        tensor_ctx:           Optional tensor substitution context.
        confidence_threshold: Minimum fraction of matches to report equal.

    Returns:
        SamplingResult with confidence score and per-sample details.
    """
    variables = _extract_variables(lhs.repr) | _extract_variables(rhs.repr)
    rng = random.Random(seed)
    samples: list[Sample] = []

    if tensor_ctx is not None:
        # Tensor mode: use pre-generated component arrays
        sample = _evaluate_with_tensor_ctx(lhs.repr, rhs.repr, tensor_ctx, oracle)
        if sample is not None:
            samples.append(sample)
        return SamplingResult.from_samples(samples, confidence_threshold)

    if not variables:
        result = _evaluate_numeric_diff(lhs.repr, rhs.repr, {}, oracle)
        if result:
            samples.append(result)
        return SamplingResult.from_samples(samples, confidence_threshold)

    for _ in range(n):
        substitution = {var: rng.uniform(0.1, 10.0) for var in variables}
        result = _evaluate_numeric_diff(lhs.repr, rhs.repr, substitution, oracle)
        if result:
            samples.append(result)

    return SamplingResult.from_samples(samples, confidence_threshold)


# ---------------------------------------------------------------------------
# Internal helpers — scalars
# ---------------------------------------------------------------------------

_MATH_CONSTANTS = frozenset({"e", "i", "E", "I", "Pi"})

# Wolfram built-in operator heads whose arguments are free expressions (not indices).
_WOLFRAM_OPERATORS = frozenset(
    {
        "Plus",
        "Times",
        "Power",
        "Subtract",
        "Minus",
        "Divide",
        "Sin",
        "Cos",
        "Tan",
        "ArcSin",
        "ArcCos",
        "ArcTan",
        "Sinh",
        "Cosh",
        "Tanh",
        "ArcSinh",
        "ArcCosh",
        "ArcTanh",
        "Exp",
        "Log",
        "Log10",
        "Log2",
        "Sqrt",
        "Abs",
        "Re",
        "Im",
        "Conjugate",
        "Factorial",
        "N",
        "Simplify",
        "FullSimplify",
        "Expand",
        "Factor",
    }
)

_IDENT_RE = re.compile(r"^[a-zA-Z][a-zA-Z0-9_]*$")


def _collect_ast_vars(node: object) -> set[str]:
    """Walk an AST node and collect free variable symbols."""
    from sxact.normalize.ast_parser import Leaf, Node

    if isinstance(node, Leaf):
        val = node.value
        if _IDENT_RE.match(val):
            return {val}
        return set()

    assert isinstance(node, Node)
    # Only recurse into args of known Wolfram operators.
    # Unknown heads (user tensors) treat their args as indices.
    if isinstance(node.head, str) and node.head in _WOLFRAM_OPERATORS:
        result: set[str] = set()
        for arg in node.args:
            result |= _collect_ast_vars(arg)
        return result
    return set()


def _extract_variables(expr: str) -> set[str]:
    """Extract free scalar variable names from an expression.

    For FullForm expressions (e.g. ``Plus[a, b]``) the AST parser is used so
    that multi-character names and arbitrarily nested brackets are handled
    correctly.  For infix expressions (e.g. ``a*x + b``) that the parser
    cannot consume, the function falls back to iterative bracket-stripping
    followed by a regex identifier scan.

    Excludes mathematical constants ``e`` (Euler), ``i`` (imaginary unit),
    ``E``, ``I``, and ``Pi``.
    """
    try:
        from sxact.normalize.ast_parser import parse

        tree = parse(expr)
        return _collect_ast_vars(tree) - _MATH_CONSTANTS
    except Exception:
        pass

    # Regex fallback for infix notation: strip nested brackets iteratively.
    stripped = expr
    while True:
        reduced = re.sub(r"\[[^\]]*\]", "", stripped)
        if reduced == stripped:
            break
        stripped = reduced

    pattern = r"\b([a-zA-Z][a-zA-Z0-9_]*)\b"
    matches = re.findall(pattern, stripped)
    return {m for m in matches if m not in _MATH_CONSTANTS}


def _evaluate_numeric_diff(
    lhs_expr: str,
    rhs_expr: str,
    substitution: dict[str, float],
    oracle: "OracleClient",
    tolerance: float = 1e-10,
) -> Sample | None:
    """Evaluate the numeric difference between two scalar expressions via oracle."""
    rules = ", ".join(f"{var} -> {val}" for var, val in substitution.items())
    if rules:
        eval_expr = f"N[({lhs_expr}) - ({rhs_expr}) /. {{{rules}}}]"
    else:
        eval_expr = f"N[({lhs_expr}) - ({rhs_expr})]"

    result = oracle.evaluate(eval_expr)

    if result.status != "ok" or not result.repr:
        return None

    try:
        diff_value = float(result.repr.strip())
        match = abs(diff_value) < tolerance
        return Sample(
            substitution=substitution,
            lhs_value=None,
            rhs_value=None,
            match=match,
            tolerance=tolerance,
        )
    except ValueError:
        return None


# ---------------------------------------------------------------------------
# Internal helpers — tensors
# ---------------------------------------------------------------------------


def _evaluate_with_tensor_ctx(
    lhs_expr: str,
    rhs_expr: str,
    ctx: TensorContext,
    oracle: "OracleClient",
    tolerance: float = 1e-10,
) -> Sample | None:
    """Evaluate tensor expressions by substituting numeric component arrays.

    Builds Wolfram substitution rules of the form::

        T -> Table[array[[i,j,...]], {i,1,n},{j,1,n}]

    and evaluates ``N[lhs - rhs /. rules]`` via the oracle, then checks
    whether all resulting components are within tolerance of zero.
    """
    rules_parts: list[str] = []

    for name, arr in {**ctx.metric_arrays, **ctx.tensor_arrays}.items():
        wl_array = _numpy_to_wl(arr)
        rules_parts.append(f"{name} -> {wl_array}")

    substitution_repr: dict[str, float | np.ndarray[Any, np.dtype[Any]]] = {
        **ctx.metric_arrays,
        **ctx.tensor_arrays,
    }

    if not rules_parts:
        return None

    rules_str = ", ".join(rules_parts)
    eval_expr = f"Max[Abs[Flatten[N[({lhs_expr}) - ({rhs_expr}) /. {{{rules_str}}}]]]]"

    result = oracle.evaluate(eval_expr)

    if result.status != "ok" or not result.repr:
        return None

    try:
        max_diff = float(result.repr.strip())
        match = max_diff < tolerance
        return Sample(
            substitution=substitution_repr,
            lhs_value=None,
            rhs_value=None,
            match=match,
            tolerance=tolerance,
        )
    except ValueError:
        return None


def _numpy_to_wl(arr: np.ndarray[Any, np.dtype[Any]]) -> str:
    """Convert a numpy array to a Wolfram List literal.

    Examples:
        [1.0, 2.0]          -> '{1.0, 2.0}'
        [[1.0, 2.0],[3,4]]  -> '{{1.0, 2.0}, {3.0, 4.0}}'
    """
    if arr.ndim == 0:
        return str(float(arr))
    if arr.ndim == 1:
        inner = ", ".join(f"{v:.10g}" for v in arr)
        return "{" + inner + "}"
    inner = ", ".join(_numpy_to_wl(arr[i]) for i in range(arr.shape[0]))
    return "{" + inner + "}"
