"""WolframAdapter conformance tests.

Runs the shared adapter conformance suite against WolframAdapter.
Tests that require a live oracle are automatically skipped when the
oracle server is unreachable (AdapterError on initialize()).

Usage::

    # All tests (skips oracle tests if server is down):
    pytest tests/test_wolfram_adapter.py

    # With live oracle:
    pytest tests/test_wolfram_adapter.py -m oracle
"""

import pytest

from sxact.adapter.wolfram import WolframAdapter

# Re-export the entire conformance suite so pytest collects it against
# WolframAdapter when running this file.
from tests.test_adapter_conformance import *  # noqa: F401,F403


@pytest.fixture
def adapter_factory():
    """Override: use WolframAdapter as the adapter under test."""
    return WolframAdapter


# ---------------------------------------------------------------------------
# WolframAdapter-specific tests (require live oracle)
# ---------------------------------------------------------------------------

class TestWolframBuildExpr:
    """Unit tests for _build_expr() — no oracle needed."""

    def test_def_manifold(self):
        adapter = WolframAdapter()
        expr = adapter._build_expr(
            "DefManifold",
            {"name": "M", "dimension": 4, "indices": ["a", "b", "c", "d"]},
        )
        assert expr == "DefManifold[M, 4, {a, b, c, d}]"

    def test_def_metric(self):
        adapter = WolframAdapter()
        expr = adapter._build_expr(
            "DefMetric",
            {"signdet": -1, "metric": "g[-a,-b]", "covd": "CD"},
        )
        assert expr == "DefMetric[-1, g[-a,-b], CD]"

    def test_def_tensor_no_symmetry(self):
        adapter = WolframAdapter()
        expr = adapter._build_expr(
            "DefTensor",
            {"name": "T", "indices": ["-a", "-b"], "manifold": "M"},
        )
        assert expr == "DefTensor[T[-a,-b], M]"

    def test_def_tensor_with_symmetry(self):
        adapter = WolframAdapter()
        expr = adapter._build_expr(
            "DefTensor",
            {
                "name": "S",
                "indices": ["-a", "-b"],
                "manifold": "M",
                "symmetry": "Symmetric[{-a,-b}]",
            },
        )
        assert expr == "DefTensor[S[-a,-b], M, Symmetric[{-a,-b}]]"

    def test_evaluate(self):
        adapter = WolframAdapter()
        expr = adapter._build_expr("Evaluate", {"expression": "T[-a,-b] + S[-a,-b]"})
        assert expr == "T[-a,-b] + S[-a,-b]"

    def test_to_canonical(self):
        adapter = WolframAdapter()
        expr = adapter._build_expr("ToCanonical", {"expression": "T[-b,-a]"})
        assert expr == "ToCanonical[T[-b,-a]]"

    def test_simplify_no_assumptions(self):
        adapter = WolframAdapter()
        expr = adapter._build_expr("Simplify", {"expression": "x^2 - x^2"})
        assert expr == "Simplify[x^2 - x^2]"

    def test_simplify_with_assumptions(self):
        adapter = WolframAdapter()
        expr = adapter._build_expr(
            "Simplify", {"expression": "Sqrt[x^2]", "assumptions": "x > 0"}
        )
        assert expr == "Simplify[Sqrt[x^2], x > 0]"

    def test_contract(self):
        adapter = WolframAdapter()
        expr = adapter._build_expr("Contract", {"expression": "g[-a,b]*V[a]"})
        assert expr == "ContractMetric[g[-a,b]*V[a]]"

    def test_assert(self):
        adapter = WolframAdapter()
        expr = adapter._build_expr("Assert", {"condition": "Dimension[M] == 4"})
        assert expr == "Dimension[M] == 4"

    def test_unknown_action_raises(self):
        adapter = WolframAdapter()
        with pytest.raises(ValueError):
            adapter.execute(None, "NotAnAction", {})  # type: ignore[arg-type]


class TestWolframNormalize:
    """normalize() delegates to the pipeline — no oracle needed."""

    def test_delegates_to_pipeline(self):
        adapter = WolframAdapter()
        result = adapter.normalize("T[-a,-b] + T[-b,-a]")
        assert isinstance(result, str)
        # Pipeline strips and orders; just verify it's non-empty and stable
        assert result == adapter.normalize(result)

    def test_empty(self):
        adapter = WolframAdapter()
        assert adapter.normalize("") == ""
