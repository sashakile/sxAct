"""Tests that KernelManager correctly serializes concurrent evaluate() calls."""

import os
import sys
import threading
import time
import types
from unittest.mock import MagicMock

# Stub out wolframclient before importing kernel_manager so tests run offline.
_wc = types.ModuleType("wolframclient")
_wc_eval = types.ModuleType("wolframclient.evaluation")
_wc_lang = types.ModuleType("wolframclient.language")
_wc_eval.WolframLanguageSession = MagicMock
_wc_lang.wlexpr = lambda x: x
sys.modules.setdefault("wolframclient", _wc)
sys.modules.setdefault("wolframclient.evaluation", _wc_eval)
sys.modules.setdefault("wolframclient.language", _wc_lang)

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../../oracle"))

from kernel_manager import KernelManager  # noqa: E402


def _make_km(evaluate_fn=None) -> KernelManager:
    """Create a KernelManager with a mocked session."""
    km = KernelManager()
    mock_session = MagicMock()
    mock_session.start.return_value = None
    if evaluate_fn is not None:
        mock_session.evaluate.side_effect = evaluate_fn
    else:
        mock_session.evaluate.return_value = "ok"
    km._session = mock_session
    km._xact_loaded = True
    return km


class TestKernelManagerConcurrency:
    """Verify RLock serializes concurrent requests without deadlock."""

    def test_concurrent_evaluate_calls_serialize(self):
        """Multiple threads calling evaluate() must not run concurrently."""
        call_order = []
        call_lock = threading.Lock()

        def slow_evaluate(expr):
            with call_lock:
                call_order.append(("start", threading.current_thread().name))
            time.sleep(0.05)
            with call_lock:
                call_order.append(("end", threading.current_thread().name))
            return "ok"

        km = _make_km(evaluate_fn=slow_evaluate)
        errors = []

        def worker():
            try:
                km.evaluate("1+1", timeout_s=5, with_xact=False)
            except Exception as e:
                errors.append(e)

        threads = [threading.Thread(target=worker, name=f"t{i}") for i in range(3)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=5)

        assert not errors, f"Errors in worker threads: {errors}"

        # Verify no overlap: every "start" must be followed by its "end"
        # before the next "start".
        active = 0
        for event, _ in call_order:
            if event == "start":
                active += 1
            else:
                active -= 1
            assert active <= 1, f"Concurrent evaluations detected: {call_order}"

    def test_rlock_is_reentrant(self):
        """RLock must not deadlock when same thread re-acquires it."""
        km = _make_km()
        with km._lock, km._lock:  # must not deadlock
            pass
