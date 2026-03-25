"""Thread-safety tests for xact Python API.

Validates that:
1. Concurrent _ensure_init calls initialize Julia exactly once
2. Double-checked locking is correct (fast path + lock path)
3. reset() does not corrupt shared state under contention
4. Concurrent API operations are safe (GIL + single Julia thread)

All tests mock the Julia bridge to avoid Julia compilation overhead.
"""

from __future__ import annotations

import threading
import time
from typing import Any
from unittest.mock import MagicMock, patch

import pytest

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _make_mock_runtime() -> tuple[MagicMock, MagicMock]:
    """Create mock Julia runtime (jl_Main, xAct_module)."""
    mock_jl = MagicMock(name="jl_Main")
    mock_xact = MagicMock(name="xAct_module")
    mock_jl.xAct = mock_xact

    # Wire up xAct function returns
    mock_xact.reset_state_b.return_value = None
    mock_xact.Dimension.return_value = 4
    mock_xact.def_manifold_b.return_value = "M"
    mock_xact.def_metric_b.return_value = "g[-a,-b]"
    mock_xact.ToCanonical.return_value = "g[-a, -b]"
    mock_xact.Contract.return_value = "4"
    mock_xact.Simplify.return_value = "4"

    return mock_jl, mock_xact


def _patch_api_init(mock_jl: MagicMock, mock_xact: MagicMock) -> tuple[Any, Any]:
    """Patch xact.api globals to use mocks, return originals for restore."""
    import xact.api as api

    orig_jl, orig_xact = api._jl, api._xAct
    api._jl = mock_jl
    api._xAct = mock_xact
    return orig_jl, orig_xact


def _restore_api_init(orig_jl: Any, orig_xact: Any) -> None:
    """Restore xact.api globals."""
    import xact.api as api

    api._jl = orig_jl
    api._xAct = orig_xact


# ---------------------------------------------------------------------------
# Tests: Concurrent Initialization
# ---------------------------------------------------------------------------


class TestConcurrentInit:
    """Multiple threads racing to initialize _ensure_init."""

    def test_init_called_exactly_once_under_contention(self):
        """Only one thread should execute get_julia(); others wait and reuse."""
        import xact.api as api

        orig_jl, orig_xact = api._jl, api._xAct
        try:
            # Force uninitialized state
            api._jl = None
            api._xAct = None

            mock_jl, mock_xact = _make_mock_runtime()
            init_count = 0
            count_lock = threading.Lock()

            real_get_julia = MagicMock(return_value=mock_jl)

            def slow_get_julia() -> MagicMock:
                nonlocal init_count
                # Simulate slow Julia startup
                time.sleep(0.05)
                with count_lock:
                    init_count += 1
                return real_get_julia()

            errors: list[Exception] = []
            barrier = threading.Barrier(8)

            def worker() -> None:
                try:
                    barrier.wait(timeout=5)
                    api._ensure_init()
                except Exception as e:
                    errors.append(e)

            with patch("xact.xcore._runtime.get_julia", side_effect=slow_get_julia):
                threads = [threading.Thread(target=worker, name=f"init-{i}") for i in range(8)]
                for t in threads:
                    t.start()
                for t in threads:
                    t.join(timeout=10)

            assert not errors, f"Errors: {errors}"
            # get_julia should only be called once
            assert init_count == 1, f"get_julia called {init_count} times"

        finally:
            api._jl = orig_jl
            api._xAct = orig_xact

    def test_fast_path_skips_lock_after_init(self):
        """Once initialized, _ensure_init must return without acquiring lock."""
        import xact.api as api

        mock_jl, mock_xact = _make_mock_runtime()
        orig_jl, orig_xact = api._jl, api._xAct
        try:
            api._jl = mock_jl
            api._xAct = mock_xact

            # Time 1000 calls — should be fast (no lock contention)
            start = time.monotonic()
            for _ in range(1000):
                api._ensure_init()
            elapsed = time.monotonic() - start

            # 1000 no-op calls should take well under 1s
            assert elapsed < 1.0, f"Fast path too slow: {elapsed:.3f}s"

        finally:
            api._jl = orig_jl
            api._xAct = orig_xact

    def test_runtime_init_called_once_under_contention(self):
        """xact.xcore._runtime._ensure_initialized is also race-safe."""
        import xact.xcore._runtime as rt

        orig_jl, orig_xcore = rt._jl, rt._xcore
        try:
            rt._jl = None
            rt._xcore = None

            init_count = 0
            count_lock = threading.Lock()

            mock_jl = MagicMock(name="jl_Main")
            mock_xact = MagicMock(name="xAct")
            mock_jl.xAct = mock_xact
            mock_jl.seval.return_value = None

            def counting_init() -> None:
                nonlocal init_count
                time.sleep(0.05)
                with count_lock:
                    init_count += 1
                rt._jl = mock_jl
                rt._xcore = mock_xact

            errors: list[Exception] = []
            barrier = threading.Barrier(6)

            def worker() -> None:
                try:
                    barrier.wait(timeout=5)
                    rt._ensure_initialized()
                except Exception as e:
                    errors.append(e)

            with patch.object(rt, "_init_julia", side_effect=counting_init):
                threads = [threading.Thread(target=worker, name=f"rt-{i}") for i in range(6)]
                for t in threads:
                    t.start()
                for t in threads:
                    t.join(timeout=10)

            assert not errors, f"Errors: {errors}"
            assert init_count == 1, f"_init_julia called {init_count} times"

        finally:
            rt._jl = orig_jl
            rt._xcore = orig_xcore


# ---------------------------------------------------------------------------
# Tests: Double-Checked Locking Correctness
# ---------------------------------------------------------------------------


class TestDoubleCheckedLocking:
    """Verify the double-checked locking pattern handles edge cases."""

    def test_second_check_inside_lock_prevents_duplicate(self):
        """Thread that loses the lock race must see the winner's result."""
        import xact.api as api

        orig_jl, orig_xact = api._jl, api._xAct
        try:
            api._jl = None
            api._xAct = None

            mock_jl, mock_xact = _make_mock_runtime()
            results: list[tuple[Any, Any]] = [None] * 2  # type: ignore[list-item]

            call_count = 0
            call_lock = threading.Lock()

            def slow_get_julia() -> MagicMock:
                nonlocal call_count
                with call_lock:
                    call_count += 1
                time.sleep(0.1)  # Simulate slow init
                return mock_jl

            def worker(i: int) -> None:
                results[i] = api._ensure_init()

            with patch("xact.xcore._runtime.get_julia", side_effect=slow_get_julia):
                t0 = threading.Thread(target=worker, args=(0,))
                t1 = threading.Thread(target=worker, args=(1,))
                t0.start()
                time.sleep(0.01)  # Ensure t0 enters lock first
                t1.start()
                t0.join(timeout=5)
                t1.join(timeout=5)

            # Both must return the same objects
            assert results[0] is not None
            assert results[1] is not None
            assert results[0][1] is results[1][1], "Both threads must see same xAct module"
            assert call_count == 1, f"get_julia called {call_count} times"

        finally:
            api._jl = orig_jl
            api._xAct = orig_xact

    def test_init_failure_allows_retry(self):
        """If init fails, subsequent calls should retry (not cache failure)."""
        import xact.xcore._runtime as rt

        orig_jl, orig_xcore = rt._jl, rt._xcore
        try:
            rt._jl = None
            rt._xcore = None

            call_count = 0

            def failing_init() -> None:
                nonlocal call_count
                call_count += 1
                raise ImportError("Julia not found")

            with patch.object(rt, "_init_julia", side_effect=failing_init):
                with pytest.raises(ImportError):
                    rt._ensure_initialized()

            assert call_count == 1
            # After failure, state should be clean for retry
            assert rt._jl is None
            assert rt._xcore is None

            # Second attempt should also call _init_julia (not cache the error)
            with patch.object(rt, "_init_julia", side_effect=failing_init):
                with pytest.raises(ImportError):
                    rt._ensure_initialized()

            assert call_count == 2

        finally:
            rt._jl = orig_jl
            rt._xcore = orig_xcore


# ---------------------------------------------------------------------------
# Tests: Concurrent Operations
# ---------------------------------------------------------------------------


class TestConcurrentOperations:
    """Multiple threads calling API functions with mocked Julia bridge."""

    def test_concurrent_api_calls_all_succeed(self):
        """Different API functions called concurrently must all return."""
        import xact.api as api

        mock_jl, mock_xact = _make_mock_runtime()
        orig = _patch_api_init(mock_jl, mock_xact)
        try:
            results: dict[str, Any] = {}
            results_lock = threading.Lock()
            errors: list[Exception] = []
            barrier = threading.Barrier(3)

            def do_reset() -> None:
                try:
                    barrier.wait(timeout=5)
                    api.reset()
                    with results_lock:
                        results["reset"] = True
                except Exception as e:
                    errors.append(e)

            def do_dimension() -> None:
                try:
                    barrier.wait(timeout=5)
                    d = api.dimension("M")
                    with results_lock:
                        results["dimension"] = d
                except Exception as e:
                    errors.append(e)

            def do_canonicalize() -> None:
                try:
                    barrier.wait(timeout=5)
                    r = api.canonicalize("g[-b,-a]")
                    with results_lock:
                        results["canonicalize"] = r
                except Exception as e:
                    errors.append(e)

            threads = [
                threading.Thread(target=do_reset, name="reset"),
                threading.Thread(target=do_dimension, name="dim"),
                threading.Thread(target=do_canonicalize, name="canon"),
            ]
            for t in threads:
                t.start()
            for t in threads:
                t.join(timeout=10)

            assert not errors, f"Errors: {errors}"
            assert results.get("reset") is True
            assert results.get("dimension") == 4
            assert results.get("canonicalize") == "g[-a, -b]"

        finally:
            _restore_api_init(*orig)

    def test_many_threads_same_operation(self):
        """N threads calling the same function must all get correct results."""
        import xact.api as api

        mock_jl, mock_xact = _make_mock_runtime()
        orig = _patch_api_init(mock_jl, mock_xact)
        try:
            n_threads = 10
            results: list[int | None] = [None] * n_threads
            errors: list[Exception] = []
            barrier = threading.Barrier(n_threads)

            def worker(i: int) -> None:
                try:
                    barrier.wait(timeout=5)
                    results[i] = api.dimension("M")
                except Exception as e:
                    errors.append(e)

            threads = [
                threading.Thread(target=worker, args=(i,), name=f"dim-{i}")
                for i in range(n_threads)
            ]
            for t in threads:
                t.start()
            for t in threads:
                t.join(timeout=10)

            assert not errors, f"Errors: {errors}"
            assert all(r == 4 for r in results), f"Results: {results}"

        finally:
            _restore_api_init(*orig)


# ---------------------------------------------------------------------------
# Tests: Reset Race Conditions
# ---------------------------------------------------------------------------


class TestResetRace:
    """reset() called while other threads are operating."""

    def test_reset_concurrent_with_operations(self):
        """reset() interleaved with other API calls must not raise."""
        import xact.api as api

        mock_jl, mock_xact = _make_mock_runtime()
        orig = _patch_api_init(mock_jl, mock_xact)
        try:
            errors: list[Exception] = []
            stop = threading.Event()

            def busy_worker() -> None:
                while not stop.is_set():
                    try:
                        api.dimension("M")
                    except Exception as e:
                        errors.append(e)
                        break

            def resetter() -> None:
                for _ in range(5):
                    try:
                        api.reset()
                        time.sleep(0.01)
                    except Exception as e:
                        errors.append(e)
                        break

            workers = [threading.Thread(target=busy_worker, name=f"busy-{i}") for i in range(3)]
            reset_thread = threading.Thread(target=resetter, name="resetter")

            for w in workers:
                w.start()
            reset_thread.start()

            reset_thread.join(timeout=10)
            stop.set()
            for w in workers:
                w.join(timeout=5)

            assert not errors, f"Errors during concurrent reset: {errors}"

        finally:
            _restore_api_init(*orig)

    def test_reset_does_not_null_xact_reference(self):
        """reset() calls reset_state_b() but must not clear _xAct/_jl."""
        import xact.api as api

        mock_jl, mock_xact = _make_mock_runtime()
        orig = _patch_api_init(mock_jl, mock_xact)
        try:
            api.reset()

            # _xAct and _jl must still be set after reset
            assert api._xAct is not None, "_xAct cleared by reset()"
            assert api._jl is not None, "_jl cleared by reset()"

            # reset_state_b should have been called
            mock_xact.reset_state_b.assert_called()

        finally:
            _restore_api_init(*orig)
