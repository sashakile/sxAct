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

import warnings
from unittest.mock import MagicMock

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


class TestWolframLifecycle:
    """Unit tests for initialize() / teardown() — no oracle needed (uses mock)."""

    def _make_adapter(self, mock_oracle):
        """Return a WolframAdapter with the given mock injected."""
        adapter = WolframAdapter()
        adapter._oracle = mock_oracle
        return adapter

    # ------------------------------------------------------------------
    # teardown()
    # ------------------------------------------------------------------

    def test_teardown_calls_cleanup(self):
        """teardown() must invoke oracle.cleanup() exactly once."""
        oracle = MagicMock()
        oracle.cleanup.return_value = True
        adapter = self._make_adapter(oracle)
        from sxact.adapter.wolfram import _WolframContext

        ctx = _WolframContext(context_id="test-ctx")
        adapter.teardown(ctx)
        oracle.cleanup.assert_called_once()

    def test_teardown_marks_context_dead(self):
        """teardown() sets ctx.alive = False."""
        oracle = MagicMock()
        oracle.cleanup.return_value = True
        adapter = self._make_adapter(oracle)
        from sxact.adapter.wolfram import _WolframContext

        ctx = _WolframContext(context_id="test-ctx")
        assert ctx.alive is True
        adapter.teardown(ctx)
        assert ctx.alive is False

    def test_teardown_warns_on_cleanup_failure(self):
        """teardown() emits RuntimeWarning when cleanup() returns False."""
        oracle = MagicMock()
        oracle.cleanup.return_value = False
        adapter = self._make_adapter(oracle)
        from sxact.adapter.wolfram import _WolframContext

        ctx = _WolframContext(context_id="test-ctx")
        with warnings.catch_warnings(record=True) as caught:
            warnings.simplefilter("always")
            adapter.teardown(ctx)
        assert any(issubclass(w.category, RuntimeWarning) for w in caught), (
            "Expected RuntimeWarning when cleanup() returns False"
        )

    def test_teardown_does_not_raise_even_on_failure(self):
        """teardown() must never raise, even when cleanup() fails."""
        oracle = MagicMock()
        oracle.cleanup.return_value = False
        adapter = self._make_adapter(oracle)
        from sxact.adapter.wolfram import _WolframContext

        ctx = _WolframContext(context_id="test-ctx")
        with warnings.catch_warnings(record=True):
            warnings.simplefilter("always")
            adapter.teardown(ctx)  # must not raise

    # ------------------------------------------------------------------
    # initialize()
    # ------------------------------------------------------------------

    def test_initialize_checks_clean_state(self):
        """initialize() calls check_clean_state() before returning context."""
        oracle = MagicMock()
        oracle.health.return_value = True
        oracle.check_clean_state.return_value = (True, [])
        adapter = self._make_adapter(oracle)
        ctx = adapter.initialize()
        oracle.check_clean_state.assert_called_once()
        assert ctx is not None

    def test_initialize_raises_when_oracle_down(self):
        """initialize() raises AdapterError when oracle is unreachable."""
        from sxact.adapter.base import AdapterError

        oracle = MagicMock()
        oracle.health.return_value = False
        adapter = self._make_adapter(oracle)
        with pytest.raises(AdapterError):
            adapter.initialize()

    def test_initialize_restarts_on_dirty_state(self):
        """initialize() calls restart() and warns when kernel is dirty."""
        oracle = MagicMock()
        oracle.health.return_value = True
        oracle.check_clean_state.return_value = (False, ["DirtyManifold"])
        oracle.restart.return_value = True
        adapter = self._make_adapter(oracle)
        with warnings.catch_warnings(record=True) as caught:
            warnings.simplefilter("always")
            ctx = adapter.initialize()
        oracle.restart.assert_called_once()
        assert any(issubclass(w.category, RuntimeWarning) for w in caught), (
            "Expected RuntimeWarning about dirty kernel state"
        )
        assert ctx is not None

    def test_initialize_raises_if_restart_fails_on_dirty(self):
        """initialize() raises AdapterError when dirty and restart() fails."""
        from sxact.adapter.base import AdapterError

        oracle = MagicMock()
        oracle.health.return_value = True
        oracle.check_clean_state.return_value = (False, ["LeakedTensor"])
        oracle.restart.return_value = False
        adapter = self._make_adapter(oracle)
        with warnings.catch_warnings(record=True):
            warnings.simplefilter("always")
            with pytest.raises(AdapterError):
                adapter.initialize()

    def test_initialize_returns_context_with_uuid(self):
        """initialize() returns a context with a unique context_id string."""
        oracle = MagicMock()
        oracle.health.return_value = True
        oracle.check_clean_state.return_value = (True, [])
        adapter = self._make_adapter(oracle)
        ctx1 = adapter.initialize()
        ctx2 = adapter.initialize()
        assert ctx1.context_id != ctx2.context_id, (
            "Each initialize() call must produce a unique context_id"
        )
