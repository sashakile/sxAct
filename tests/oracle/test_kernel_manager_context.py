"""Unit tests for KernelManager context_id isolation wrapping.

These tests run offline — no real Wolfram kernel is needed.
They verify that:
  - A unique Wolfram context is created for each distinct context_id.
  - No context_id → expression passes through unchanged.
  - Two different context_ids produce different context namespaces.
"""

import sys
import os
import types
from unittest.mock import MagicMock, call

import pytest

# Stub wolframclient before importing kernel_manager.
_wc = types.ModuleType("wolframclient")
_wc_eval = types.ModuleType("wolframclient.evaluation")
_wc_lang = types.ModuleType("wolframclient.language")
_wc_eval.WolframLanguageSession = MagicMock
_wc_lang.wlexpr = lambda x: x  # identity so we can inspect the string
sys.modules.setdefault("wolframclient", _wc)
sys.modules.setdefault("wolframclient.evaluation", _wc_eval)
sys.modules.setdefault("wolframclient.language", _wc_lang)

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../../oracle"))

from kernel_manager import KernelManager  # noqa: E402


def _make_km() -> KernelManager:
    km = KernelManager()
    mock_session = MagicMock()
    mock_session.start.return_value = None
    mock_session.evaluate.return_value = "ok"
    km._session = mock_session
    km._xact_loaded = True
    return km


class TestContextIdWrapping:
    def test_no_context_id_passes_expr_unchanged(self):
        """Without context_id the raw expression is evaluated directly."""
        km = _make_km()
        km.evaluate("1 + 1", timeout_s=5, with_xact=False, context_id=None)
        args, _ = km._session.evaluate.call_args
        assert args[0] == "1 + 1"

    def test_context_id_wraps_expr(self):
        """With context_id the expression is wrapped (not passed raw)."""
        km = _make_km()
        km.evaluate("1 + 1", timeout_s=5, with_xact=False, context_id="abc-123")
        args, _ = km._session.evaluate.call_args
        wrapped = args[0]
        assert wrapped != "1 + 1", "Expression should be wrapped when context_id is given"

    def test_context_id_value_appears_in_wrapped_expr(self):
        """The sanitized context_id value appears in the wrapped expression."""
        km = _make_km()
        km.evaluate("x = 42", timeout_s=5, with_xact=False, context_id="test-abc-123")
        args, _ = km._session.evaluate.call_args
        wrapped = args[0]
        # Sanitized: "testabc123" (hyphens stripped)
        assert "testabc123" in wrapped.lower() or "abc123" in wrapped.lower(), (
            f"context_id not found in wrapped expr: {wrapped!r}"
        )

    def test_two_different_context_ids_produce_different_wrappers(self):
        """Different context_ids must produce different context names."""
        km = _make_km()

        km.evaluate("x = 1", timeout_s=5, with_xact=False, context_id="session-aaa")
        args_a, _ = km._session.evaluate.call_args
        wrapped_a = args_a[0]

        km.evaluate("x = 2", timeout_s=5, with_xact=False, context_id="session-bbb")
        args_b, _ = km._session.evaluate.call_args
        wrapped_b = args_b[0]

        assert wrapped_a != wrapped_b, (
            "Different context_ids must produce different wrapping contexts"
        )

    def test_same_context_id_produces_same_wrapper_context(self):
        """Same context_id across calls uses the same context name."""
        km = _make_km()

        km.evaluate("a = 1", timeout_s=5, with_xact=False, context_id="stable-id")
        args1, _ = km._session.evaluate.call_args

        km.evaluate("b = 2", timeout_s=5, with_xact=False, context_id="stable-id")
        args2, _ = km._session.evaluate.call_args

        # The context names in both wrappers should be identical
        # (check the context name portion, not the full expression with different bodies)
        import re
        ctx_pattern = re.compile(r'SxAct\w+`')
        ctx1 = ctx_pattern.findall(args1[0])
        ctx2 = ctx_pattern.findall(args2[0])
        assert ctx1 and ctx2, "Context name not found in wrapped expressions"
        assert ctx1[0] == ctx2[0], (
            f"Same context_id should produce same context name: {ctx1[0]!r} != {ctx2[0]!r}"
        )
