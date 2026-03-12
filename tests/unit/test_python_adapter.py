"""Tests for PythonAdapter.

Imports the conformance suite so all protocol contracts are verified,
then adds Python-adapter-specific tests.
"""

from __future__ import annotations

import pytest

from sxact.adapter.python_adapter import PythonAdapter
from sxact.adapter.base import AdapterError

# ---------------------------------------------------------------------------
# Conformance suite
# ---------------------------------------------------------------------------


@pytest.fixture
def adapter_factory():
    return PythonAdapter


# Import conformance tests — they are discovered automatically by pytest
from tests.test_adapter_conformance import *  # noqa: F401, F403, E402


# ---------------------------------------------------------------------------
# PythonAdapter-specific tests
# ---------------------------------------------------------------------------


class TestPythonAdapterSpecific:
    def test_cas_name_is_python(self):
        adapter = PythonAdapter()
        version = adapter.get_version()
        assert version.cas_name == "Python"

    def test_adapter_version_non_empty(self):
        adapter = PythonAdapter()
        assert adapter.get_version().adapter_version != ""

    def test_xtensor_actions_return_error(self):
        """xTensor actions must return error Results, not raise."""
        adapter = PythonAdapter()
        try:
            ctx = adapter.initialize()
        except AdapterError:
            pytest.skip("Julia runtime unavailable")

        xtensor_actions = [
            "DefManifold",
            "DefMetric",
            "DefTensor",
            "ToCanonical",
            "Contract",
            "Simplify",
        ]
        for action in xtensor_actions:
            result = adapter.execute(
                ctx,
                action,
                {
                    "name": "M",
                    "dimension": 4,
                    "indices": ["a", "b"],
                    "metric": "g",
                    "covd": "CD",
                    "signdet": 1,
                    "expression": "T[-a]",
                },
            )
            assert result.status == "error", f"{action} should return error Result"
            assert "xTensor" in result.error or "not yet ported" in result.error

        adapter.teardown(ctx)

    def test_evaluate_simple_expression(self):
        """Evaluate a simple xCore expression that doesn't need xTensor."""
        adapter = PythonAdapter()
        try:
            ctx = adapter.initialize()
        except AdapterError:
            pytest.skip("Julia runtime unavailable")

        result = adapter.execute(ctx, "Evaluate", {"expression": "1 + 1"})
        # Either it works or returns an error — it must not raise
        assert result.status in ("ok", "error")

        adapter.teardown(ctx)

    def test_teardown_idempotent(self):
        """teardown() must be safe to call multiple times."""
        adapter = PythonAdapter()
        try:
            ctx = adapter.initialize()
        except AdapterError:
            pytest.skip("Julia runtime unavailable")

        adapter.teardown(ctx)
        adapter.teardown(ctx)  # second call must not raise

    def test_normalize_returns_string(self):
        adapter = PythonAdapter()
        result = adapter.normalize("T[-a, -b] + S[-b, -a]")
        assert isinstance(result, str)

    def test_normalize_idempotent(self):
        adapter = PythonAdapter()
        expr = "T[-a,-b] + S[-b,-a]"
        once = adapter.normalize(expr)
        twice = adapter.normalize(once)
        assert once == twice
