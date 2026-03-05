"""Tests for tensor_objects.py and the extended sampling.py."""

from __future__ import annotations

import numpy as np
import pytest

from sxact.compare.tensor_objects import (
    Manifold,
    Metric,
    TensorField,
    random_manifold,
    random_metric_array,
    random_tensor_array,
    _symmetrize,
    _antisymmetrize,
)
from sxact.compare.sampling import (
    Sample,
    SamplingResult,
    TensorContext,
    build_tensor_context,
    _extract_variables,
    _numpy_to_wl,
)


# ---------------------------------------------------------------------------
# Manifold / Metric / TensorField dataclasses
# ---------------------------------------------------------------------------

class TestManifold:
    def test_basic_creation(self):
        m = Manifold("M", 4)
        assert m.name == "M"
        assert m.dimension == 4

    def test_invalid_dimension(self):
        with pytest.raises(ValueError):
            Manifold("M", 0)


class TestRandomManifold:
    def test_dimension_in_range(self):
        import random
        rng = random.Random(42)
        for _ in range(20):
            m = random_manifold(rng=rng)
            assert 2 <= m.dimension <= 4


class TestRandomMetricArray:
    def test_shape(self):
        m = Manifold("M", 3)
        metric = Metric("g", m)
        arr = random_metric_array(metric, np.random.default_rng(0))
        assert arr.shape == (3, 3)

    def test_symmetric(self):
        m = Manifold("M", 4)
        metric = Metric("g", m)
        arr = random_metric_array(metric, np.random.default_rng(1))
        np.testing.assert_allclose(arr, arr.T, atol=1e-12)

    def test_well_conditioned(self):
        """Condition number should be reasonable (< 1000 for small random matrices)."""
        m = Manifold("M", 4)
        metric = Metric("g", m, signature=0)
        rng = np.random.default_rng(7)
        for _ in range(5):
            arr = random_metric_array(metric, rng)
            cond = np.linalg.cond(arr)
            assert cond < 1000, f"Condition number {cond:.1f} too large"

    def test_lorentzian_has_negative_eigenvalue(self):
        m = Manifold("M", 4)
        metric = Metric("g", m, signature=1)
        arr = random_metric_array(metric, np.random.default_rng(2))
        eigenvalues = np.linalg.eigvalsh(arr)
        assert (eigenvalues < 0).sum() == 1, "Lorentzian metric should have 1 negative eigenvalue"


class TestRandomTensorArray:
    def test_shape_rank1(self):
        m = Manifold("M", 4)
        t = TensorField("T", rank=1, manifold=m)
        arr = random_tensor_array(t, np.random.default_rng(0))
        assert arr.shape == (4,)

    def test_shape_rank2(self):
        m = Manifold("M", 3)
        t = TensorField("T", rank=2, manifold=m)
        arr = random_tensor_array(t, np.random.default_rng(0))
        assert arr.shape == (3, 3)

    def test_symmetric_rank2(self):
        m = Manifold("M", 4)
        t = TensorField("T", rank=2, manifold=m, symmetry="Symmetric")
        arr = random_tensor_array(t, np.random.default_rng(5))
        np.testing.assert_allclose(arr, arr.T, atol=1e-12)

    def test_antisymmetric_rank2(self):
        m = Manifold("M", 4)
        t = TensorField("T", rank=2, manifold=m, symmetry="Antisymmetric")
        arr = random_tensor_array(t, np.random.default_rng(6))
        np.testing.assert_allclose(arr, -arr.T, atol=1e-12)

    def test_no_symmetry_is_general(self):
        m = Manifold("M", 3)
        t = TensorField("T", rank=2, manifold=m, symmetry=None)
        arr = random_tensor_array(t, np.random.default_rng(8))
        assert arr.shape == (3, 3)
        # General tensor: T != T^T in general
        # (not enforced, just check shape)


# ---------------------------------------------------------------------------
# Symmetrize / Antisymmetrize internals
# ---------------------------------------------------------------------------

class TestSymmetrize:
    def test_rank2_result_symmetric(self):
        arr = np.array([[1.0, 2.0], [3.0, 4.0]])
        sym = _symmetrize(arr)
        np.testing.assert_allclose(sym, sym.T, atol=1e-12)

    def test_already_symmetric_unchanged(self):
        arr = np.array([[1.0, 2.0], [2.0, 3.0]])
        sym = _symmetrize(arr)
        np.testing.assert_allclose(sym, arr, atol=1e-12)


class TestAntisymmetrize:
    def test_rank2_result_antisymmetric(self):
        arr = np.array([[1.0, 2.0], [3.0, 4.0]])
        asym = _antisymmetrize(arr)
        np.testing.assert_allclose(asym, -asym.T, atol=1e-12)

    def test_diagonal_is_zero(self):
        arr = np.random.default_rng(0).standard_normal((4, 4))
        asym = _antisymmetrize(arr)
        np.testing.assert_allclose(np.diag(asym), 0, atol=1e-12)


# ---------------------------------------------------------------------------
# SamplingResult
# ---------------------------------------------------------------------------

class TestSamplingResult:
    def test_empty_samples(self):
        r = SamplingResult.from_samples([])
        assert not r.equal
        assert r.confidence == 0.0

    def test_all_matching(self):
        samples = [Sample({}, None, None, True) for _ in range(10)]
        r = SamplingResult.from_samples(samples)
        assert r.equal
        assert r.confidence == 1.0

    def test_none_matching(self):
        samples = [Sample({}, None, None, False) for _ in range(10)]
        r = SamplingResult.from_samples(samples)
        assert not r.equal
        assert r.confidence == 0.0

    def test_partial_confidence(self):
        samples = (
            [Sample({}, None, None, True) for _ in range(9)]
            + [Sample({}, None, None, False)]
        )
        r = SamplingResult.from_samples(samples, threshold=0.95)
        # 9/10 = 0.9 < 0.95 threshold → not equal
        assert not r.equal
        assert abs(r.confidence - 0.9) < 1e-9


# ---------------------------------------------------------------------------
# TensorContext / build_tensor_context
# ---------------------------------------------------------------------------

class TestBuildTensorContext:
    def test_empty_context(self):
        ctx = build_tensor_context([], [], [])
        assert ctx.manifolds == {}
        assert ctx.metric_arrays == {}
        assert ctx.tensor_arrays == {}

    def test_metric_in_context(self):
        m = Manifold("M", 3)
        metric = Metric("g", m)
        ctx = build_tensor_context([m], [metric], [], rng=np.random.default_rng(0))
        assert "g" in ctx.metric_arrays
        assert ctx.metric_arrays["g"].shape == (3, 3)

    def test_tensor_in_context(self):
        m = Manifold("M", 4)
        t = TensorField("R", rank=4, manifold=m, symmetry="Antisymmetric")
        ctx = build_tensor_context([m], [], [t], rng=np.random.default_rng(0))
        assert "R" in ctx.tensor_arrays
        assert ctx.tensor_arrays["R"].shape == (4, 4, 4, 4)


# ---------------------------------------------------------------------------
# _numpy_to_wl
# ---------------------------------------------------------------------------

class TestNumpyToWl:
    def test_scalar(self):
        arr = np.array(3.14)
        result = _numpy_to_wl(arr)
        assert "3.14" in result

    def test_vector(self):
        arr = np.array([1.0, 2.0, 3.0])
        result = _numpy_to_wl(arr)
        assert result.startswith("{")
        assert result.endswith("}")
        assert "1" in result and "2" in result and "3" in result

    def test_matrix(self):
        arr = np.array([[1.0, 2.0], [3.0, 4.0]])
        result = _numpy_to_wl(arr)
        assert result.startswith("{{")
        assert result.endswith("}}")


# ---------------------------------------------------------------------------
# _extract_variables (regression: unchanged behavior)
# ---------------------------------------------------------------------------

class TestExtractVariables:
    def test_single_letter(self):
        assert "x" in _extract_variables("a*x + b")

    def test_excludes_e_i(self):
        result = _extract_variables("e + i + x")
        assert "e" not in result
        assert "i" not in result
        assert "x" in result

    def test_inside_brackets_excluded(self):
        # Indices inside brackets should not be extracted as scalar vars
        result = _extract_variables("T[a, b]")
        # The function strips bracket content first
        assert "a" not in result
        assert "b" not in result

    def test_nested_brackets_excluded(self):
        # T[a,b][c] has three indices — none are free variables
        result = _extract_variables("T[a,b][c]")
        assert "a" not in result
        assert "b" not in result
        assert "c" not in result

    def test_multichar_variable_fullform(self):
        # FullForm expression with multi-character variable names
        result = _extract_variables("Plus[var1, var2]")
        assert "var1" in result
        assert "var2" in result

    def test_multichar_variable_infix(self):
        # Infix expression with multi-character variable names (regex fallback)
        result = _extract_variables("var1 + var2")
        assert "var1" in result
        assert "var2" in result

    def test_operator_args_are_variables(self):
        # In FullForm, args of known operators are free variables
        result = _extract_variables("Plus[x, y]")
        assert "x" in result
        assert "y" in result
