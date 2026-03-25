"""Integration tests for Layer 3 numeric tensor sampling (Tier 3 comparison).

Validates the end-to-end plumbing from TensorContext construction through
sample_numeric() without requiring a live oracle server.  A mock oracle with
pre-configured numeric responses exercises the full comparison logic.

Tests with a live oracle are gated by @pytest.mark.oracle.
"""

from __future__ import annotations

import numpy as np
import pytest

from sxact.compare.comparator import EqualityMode, compare
from sxact.compare.sampling import (
    TensorContext,
    build_tensor_context,
    sample_numeric,
)
from sxact.compare.tensor_objects import Manifold, Metric, TensorField
from sxact.oracle.result import Result

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _ok(repr_str: str) -> Result:
    return Result(status="ok", type="Expr", repr=repr_str, normalized=repr_str)


class _ConstantOracle:
    """Oracle that always returns the same numeric string for any expression."""

    def __init__(self, value: str) -> None:
        self._value = value
        self.calls: list[str] = []

    def evaluate(self, expr: str, timeout: int = 30) -> Result:
        self.calls.append(expr)
        return Result(
            status="ok",
            type="Scalar",
            repr=self._value,
            normalized=self._value,
        )


# ---------------------------------------------------------------------------
# TensorContext construction
# ---------------------------------------------------------------------------


class TestTensorContextConstruction:
    """Verify that build_tensor_context() populates arrays for all objects."""

    def test_empty_context(self) -> None:
        ctx = build_tensor_context([], [], [])
        assert ctx.manifolds == {}
        assert ctx.metric_arrays == {}
        assert ctx.tensor_arrays == {}

    def test_metric_array_shape(self) -> None:
        m = Manifold("M", 3)
        metric = Metric("g", m, signature=0)
        ctx = build_tensor_context([m], [metric], [], rng=np.random.default_rng(0))
        assert "g" in ctx.metric_arrays
        assert ctx.metric_arrays["g"].shape == (3, 3)

    def test_tensor_array_shape(self) -> None:
        m = Manifold("M", 4)
        tensor = TensorField("T", rank=2, manifold=m)
        ctx = build_tensor_context([m], [], [tensor], rng=np.random.default_rng(1))
        assert "T" in ctx.tensor_arrays
        assert ctx.tensor_arrays["T"].shape == (4, 4)

    def test_rank4_tensor(self) -> None:
        m = Manifold("M", 3)
        tensor = TensorField("R", rank=4, manifold=m, symmetry="Antisymmetric")
        ctx = build_tensor_context([m], [], [tensor], rng=np.random.default_rng(2))
        assert ctx.tensor_arrays["R"].shape == (3, 3, 3, 3)

    def test_manifold_registered(self) -> None:
        m = Manifold("M", 4)
        ctx = build_tensor_context([m], [], [])
        assert "M" in ctx.manifolds
        assert ctx.manifolds["M"].dimension == 4

    def test_reproducible_with_seed(self) -> None:
        m = Manifold("M", 3)
        tensor = TensorField("T", rank=2, manifold=m)
        ctx1 = build_tensor_context([m], [], [tensor], rng=np.random.default_rng(42))
        ctx2 = build_tensor_context([m], [], [tensor], rng=np.random.default_rng(42))
        np.testing.assert_array_equal(ctx1.tensor_arrays["T"], ctx2.tensor_arrays["T"])


# ---------------------------------------------------------------------------
# sample_numeric with TensorContext
# ---------------------------------------------------------------------------


class TestSampleNumericWithTensorContext:
    """Verify sample_numeric() uses TensorContext and interprets oracle responses."""

    def _make_tensor_ctx(self) -> TensorContext:
        m = Manifold("M", 2)
        tensor = TensorField("T", rank=2, manifold=m)
        return build_tensor_context([m], [], [tensor], rng=np.random.default_rng(0))

    def test_oracle_returns_zero_means_equal(self) -> None:
        """When oracle says max|lhs-rhs| = 0, expressions are equal."""
        oracle = _ConstantOracle("0")
        lhs = _ok("T")
        rhs = _ok("T")
        ctx = self._make_tensor_ctx()

        result = sample_numeric(lhs, rhs, oracle, tensor_ctx=ctx)

        assert result.equal
        assert result.confidence == 1.0
        assert len(result.samples) == 1

    def test_oracle_returns_nonzero_means_unequal(self) -> None:
        """When oracle says max|lhs-rhs| > tol, expressions differ."""
        oracle = _ConstantOracle("3.5")
        lhs = _ok("T")
        rhs = _ok("-T")
        ctx = self._make_tensor_ctx()

        result = sample_numeric(lhs, rhs, oracle, tensor_ctx=ctx)

        assert not result.equal
        assert result.confidence == 0.0

    def test_sign_error_detected(self) -> None:
        """A deliberate sign flip in one index must be detected by Tier 3."""
        # lhs = T[-a,-b], rhs = -T[-a,-b]  →  diff = 2T ≠ 0
        oracle = _ConstantOracle("2.718")  # some non-zero value
        lhs = _ok("T[-a,-b]")
        rhs = _ok("-T[-a,-b]")
        ctx = self._make_tensor_ctx()

        result = sample_numeric(lhs, rhs, oracle, tensor_ctx=ctx)

        assert not result.equal, "Sign error should be detected by Tier 3"

    def test_oracle_called_once_in_tensor_mode(self) -> None:
        """Tensor mode evaluates exactly one compound WL expression."""
        oracle = _ConstantOracle("0")
        lhs = _ok("T")
        rhs = _ok("T")
        ctx = self._make_tensor_ctx()

        sample_numeric(lhs, rhs, oracle, tensor_ctx=ctx)

        assert len(oracle.calls) == 1
        # The oracle call should be the Max[Abs[Flatten[N[...]]]] form
        assert oracle.calls[0].startswith("Max[Abs[Flatten[N[")

    def test_wl_array_substitution_in_oracle_call(self) -> None:
        """Oracle expression must include tensor substitution rules."""
        oracle = _ConstantOracle("0")
        m = Manifold("M", 2)
        tensor = TensorField("MyTensor", rank=1, manifold=m)
        ctx = build_tensor_context([m], [], [tensor], rng=np.random.default_rng(5))

        sample_numeric(_ok("MyTensor"), _ok("MyTensor"), oracle, tensor_ctx=ctx)

        assert len(oracle.calls) == 1
        assert "MyTensor" in oracle.calls[0]
        # Substitution rule should be present
        assert "MyTensor ->" in oracle.calls[0]

    def test_empty_tensor_context_returns_no_samples(self) -> None:
        """An empty TensorContext (no arrays) cannot produce samples."""
        oracle = _ConstantOracle("0")
        empty_ctx = TensorContext()

        result = sample_numeric(_ok("T"), _ok("T"), oracle, tensor_ctx=empty_ctx)

        # No arrays → _evaluate_with_tensor_ctx returns None → no samples
        assert len(result.samples) == 0


# ---------------------------------------------------------------------------
# compare() with EqualityMode.NUMERIC and TensorContext
# ---------------------------------------------------------------------------


class TestComparatorTier3WithTensorContext:
    """Verify compare() uses TensorContext when falling through to Tier 3."""

    def _make_tensor_ctx(self) -> TensorContext:
        m = Manifold("M", 2)
        tensor = TensorField("F", rank=2, manifold=m, symmetry="Antisymmetric")
        return build_tensor_context([m], [], [tensor], rng=np.random.default_rng(10))

    def test_tier3_correct_expression_passes(self) -> None:
        """Tier 3 passes when oracle confirms the difference is zero."""
        # Tier 2 will fail (no Simplify on "F - F" without oracle seeing 0 from Simplify)
        # We force NUMERIC mode and stub oracle to return "0" for Max[Abs[...]]
        oracle = _ConstantOracle("0")
        lhs = _ok("F[-a,-b]")
        rhs = _ok("F[-a,-b]")
        ctx = self._make_tensor_ctx()

        cmp = compare(lhs, rhs, oracle, mode=EqualityMode.NUMERIC, tensor_ctx=ctx)

        # Tier 1 should catch this (same string)
        assert cmp.equal
        assert cmp.tier == 1

    def test_tier3_sign_error_fails(self) -> None:
        """Tier 3 fails when oracle detects non-zero difference (sign error)."""
        # Tier 2 oracle returns non-"0" for Simplify, Tier 3 oracle returns non-zero
        oracle = _ConstantOracle("1.5")
        lhs = _ok("F[-a,-b]")
        rhs = _ok("F[-b,-a]")  # wrong sign for antisymmetric tensor
        ctx = self._make_tensor_ctx()

        cmp = compare(lhs, rhs, oracle, mode=EqualityMode.NUMERIC, tensor_ctx=ctx)

        assert not cmp.equal
        assert cmp.tier == 3

    def test_tier3_used_when_tier2_fails(self) -> None:
        """compare() reaches Tier 3 when Tier 1 and Tier 2 both fail."""

        class _StubOracle:
            """Returns Simplify failure then numeric result."""

            def __init__(self) -> None:
                self.calls: list[str] = []

            def evaluate(self, expr: str, timeout: int = 30) -> Result:
                self.calls.append(expr)
                if expr.startswith("Simplify["):
                    # Tier 2: return a non-zero symbolic diff
                    return Result(
                        status="ok",
                        type="Scalar",
                        repr="nonzero",
                        normalized="nonzero",
                    )
                # Tier 3: Max[Abs[Flatten[...]]]
                return Result(
                    status="ok",
                    type="Scalar",
                    repr="0",
                    normalized="0",
                )

        oracle = _StubOracle()
        lhs = _ok("F[-a,-b]")
        rhs = _ok("F[-a,-b] + 0")  # normalized differently → Tier 1 fails
        m = Manifold("M", 2)
        tensor = TensorField("F", rank=2, manifold=m)
        tensor_ctx = build_tensor_context([m], [], [tensor], rng=np.random.default_rng(7))

        cmp = compare(lhs, rhs, oracle, mode=EqualityMode.NUMERIC, tensor_ctx=tensor_ctx)

        assert cmp.tier == 3
        assert cmp.equal
        # Verify oracle was called for both Tier 2 and Tier 3
        tier2_calls = [c for c in oracle.calls if c.startswith("Simplify[")]
        tier3_calls = [c for c in oracle.calls if c.startswith("Max[")]
        assert len(tier2_calls) == 1
        assert len(tier3_calls) == 1


# ---------------------------------------------------------------------------
# JuliaAdapter state tracking (requires Julia runtime)
# ---------------------------------------------------------------------------


@pytest.mark.julia
class TestJuliaAdapterTensorContextTracking:
    """Verify that JuliaAdapter.execute() populates TensorContext state.

    Requires Julia and the XTensor module to be available.
    """

    @pytest.fixture(autouse=True)
    def _skip_without_julia(self) -> None:
        pytest.importorskip(
            "juliacall",
            reason="juliacall not available; skipping Julia adapter tests",
        )

    def test_def_manifold_records_manifold(self) -> None:
        from sxact.adapter.julia_stub import JuliaAdapter

        adapter = JuliaAdapter()
        ctx = adapter.initialize()
        try:
            adapter.execute(
                ctx,
                "DefManifold",
                {"name": "TM4", "dimension": 4, "indices": ["ta", "tb", "tc", "td"]},
            )
            assert len(ctx._manifolds) == 1
            assert ctx._manifolds[0].name == "TM4"
            assert ctx._manifolds[0].dimension == 4
        finally:
            adapter.teardown(ctx)

    def test_def_metric_records_metric(self) -> None:
        from sxact.adapter.julia_stub import JuliaAdapter

        adapter = JuliaAdapter()
        ctx = adapter.initialize()
        try:
            adapter.execute(
                ctx,
                "DefManifold",
                {"name": "TM5", "dimension": 4, "indices": ["ma", "mb", "mc", "md"]},
            )
            adapter.execute(
                ctx,
                "DefMetric",
                {"signdet": -1, "metric": "tg[-ma,-mb]", "covd": "TCD5"},
            )
            assert len(ctx._metrics) == 1
            assert ctx._metrics[0].name == "tg"
            assert ctx._metrics[0].signature == 1  # Lorentzian
        finally:
            adapter.teardown(ctx)

    def test_def_tensor_records_tensor(self) -> None:
        from sxact.adapter.julia_stub import JuliaAdapter

        adapter = JuliaAdapter()
        ctx = adapter.initialize()
        try:
            adapter.execute(
                ctx,
                "DefManifold",
                {"name": "TM6", "dimension": 3, "indices": ["na", "nb", "nc"]},
            )
            adapter.execute(
                ctx,
                "DefTensor",
                {
                    "name": "TS6",
                    "indices": ["-na", "-nb"],
                    "manifold": "TM6",
                    "symmetry": "Symmetric[{-na,-nb}]",
                },
            )
            assert len(ctx._tensors) == 1
            assert ctx._tensors[0].name == "TS6"
            assert ctx._tensors[0].rank == 2
            assert ctx._tensors[0].symmetry == "Symmetric"
        finally:
            adapter.teardown(ctx)

    def test_get_tensor_context_returns_populated_context(self) -> None:
        from sxact.adapter.julia_stub import JuliaAdapter

        adapter = JuliaAdapter()
        ctx = adapter.initialize()
        try:
            adapter.execute(
                ctx,
                "DefManifold",
                {"name": "TM7", "dimension": 4, "indices": ["xa", "xb", "xc", "xd"]},
            )
            adapter.execute(
                ctx,
                "DefTensor",
                {
                    "name": "TX7",
                    "indices": ["-xa", "-xb"],
                    "manifold": "TM7",
                },
            )
            tensor_ctx = adapter.get_tensor_context(ctx, rng=np.random.default_rng(99))
            assert "TX7" in tensor_ctx.tensor_arrays
            assert tensor_ctx.tensor_arrays["TX7"].shape == (4, 4)
        finally:
            adapter.teardown(ctx)
