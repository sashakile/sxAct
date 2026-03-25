"""Persistent Wolfram kernel manager using WSTP via wolframclient."""

import shutil
import threading
from concurrent.futures import ThreadPoolExecutor
from concurrent.futures import TimeoutError as FuturesTimeout
from typing import Any

from wolframclient.evaluation import WolframLanguageSession
from wolframclient.language import wlexpr

INIT_SCRIPT = "/oracle/init.wl"


class KernelManager:
    """Manages a persistent Wolfram kernel with xAct pre-loaded."""

    def __init__(self) -> None:
        self._lock = threading.RLock()
        self._session: WolframLanguageSession | None = None
        self._executor = ThreadPoolExecutor(max_workers=1)
        self._kernel_path = shutil.which("WolframKernel")
        self._xact_loaded = False

    def start(self) -> None:
        """Start the kernel and load xAct."""
        if not self._kernel_path:
            raise RuntimeError("WolframKernel not found on PATH; set an explicit kernel path.")
        self._session = WolframLanguageSession(kernel_path=self._kernel_path)
        self._session.start()
        self._xact_loaded = False

    def _ensure_xact(self) -> None:
        """Load xAct if not already loaded."""
        if not self._xact_loaded and self._session is not None:
            self._session.evaluate(wlexpr(f'Get["{INIT_SCRIPT}"]'))
            self._xact_loaded = True

    def ensure(self) -> None:
        """Ensure kernel is running."""
        if self._session is None:
            self.start()

    def stop(self) -> None:
        """Stop the kernel."""
        if self._session is not None:
            try:
                self._session.terminate()
            except Exception:
                pass
            finally:
                self._session = None
                self._xact_loaded = False

    def restart(self) -> None:
        """Restart the kernel."""
        self.stop()
        self.start()

    def cleanup(self) -> tuple[bool, str | None, str | None]:
        """Clear Global context symbols and reset xAct registries.

        Sends a cleanup script that removes all user-defined Global symbols
        and resets xAct internal registry lists (Manifolds, Tensors).
        Safe to call after each test file to restore a pristine kernel state.

        Returns (ok: bool, result: str|None, error: str|None)
        """
        cleanup_wl = (
            'Unprotect["Global`*"]; '
            'ClearAll["Global`*"]; '
            'Remove["Global`*"]; '
            "Manifolds = {}; "
            "Tensors = {}; "
            'If[NameQ["DefaultMetric"], ClearAll[DefaultMetric]]; '
            '"cleanup-ok"'
        )
        with self._lock:
            self.ensure()
            self._ensure_xact()

            def _do_eval() -> Any:
                assert self._session is not None
                return self._session.evaluate(wlexpr(cleanup_wl))

            fut = self._executor.submit(_do_eval)
            try:
                result = fut.result(timeout=30)
                return True, str(result), None
            except FuturesTimeout:
                self.restart()
                return False, None, "cleanup timed out (kernel restarted)"
            except Exception as e:
                return False, None, f"{type(e).__name__}: {e}"

    def check_clean_state(self) -> tuple[bool, list[str]]:
        """Check whether the kernel has no lingering manifold/tensor definitions.

        Returns (is_clean: bool, leaked_symbols: list[str]).
        ``is_clean`` is True when both Manifolds and Tensors registries are
        empty.  ``leaked_symbols`` lists the registry contents on failure.
        """
        check_wl = (
            "Module[{m = If[ListQ[Manifolds], Manifolds, {}], "
            "         t = If[ListQ[Tensors], Tensors, {}]}, "
            '  StringJoin["M:", ToString[Length[m]], ",T:", ToString[Length[t]], '
            '    ",", StringRiffle[Join[ToString /@ m, ToString /@ t], ","]]]'
        )
        with self._lock:
            self.ensure()
            self._ensure_xact()

            def _do_eval() -> Any:
                assert self._session is not None
                return self._session.evaluate(wlexpr(check_wl))

            fut = self._executor.submit(_do_eval)
            try:
                result_str = str(fut.result(timeout=10)).strip().strip('"')
                # Parse "M:0,T:0," or "M:2,T:3,sym1,sym2,..."
                parts = result_str.split(",", 2)
                m_count = int(parts[0].replace("M:", "")) if len(parts) > 0 else -1
                t_count = int(parts[1].replace("T:", "")) if len(parts) > 1 else -1
                leaked = parts[2].split(",") if len(parts) > 2 and parts[2] else []
                leaked = [s for s in leaked if s]
                return (m_count == 0 and t_count == 0), leaked
            except (FuturesTimeout, Exception):
                return False, ["check_clean_state evaluation failed"]

    def evaluate(
        self,
        expr: str,
        timeout_s: int,
        with_xact: bool = False,
        context_id: str | None = None,
    ) -> tuple[bool, str | None, str | None]:
        """
        Evaluate an expression.

        Args:
            expr: The Wolfram expression to evaluate.
            timeout_s: Timeout in seconds.
            with_xact: Whether to ensure xAct is loaded first.
            context_id: Optional unique context ID for isolation. When provided,
                wraps the expression in a Block that sets $Context to a unique
                namespace, preventing symbol pollution between tests.

        Returns (ok: bool, result: str|None, error: str|None)
        """
        with self._lock:
            self.ensure()

            # Wrap expression in a unique per-context_id Wolfram namespace.
            # Block temporarily sets $Context to a unique "SxAct{id}`" context
            # and prepends it to $ContextPath so xAct symbols remain accessible.
            # ToExpression delays parsing until after $Context is switched,
            # preventing Global` pollution (wolframclient parses early).
            if context_id:
                safe_id = "".join(c for c in context_id if c.isalnum())
                unique_ctx = f"SxAct{safe_id}`"
                escaped_expr = expr.replace("\\", "\\\\").replace('"', '\\"')
                wrapped_expr = (
                    f'Block[{{$Context = "{unique_ctx}", '
                    f'$ContextPath = Prepend[$ContextPath, "{unique_ctx}"]}}, '
                    f'ToExpression["{escaped_expr}"]]'
                )
            else:
                wrapped_expr = expr

            def _do_eval() -> Any:
                if with_xact:
                    self._ensure_xact()
                assert self._session is not None
                return self._session.evaluate(wlexpr(wrapped_expr))

            fut = self._executor.submit(_do_eval)
            try:
                result = fut.result(timeout=timeout_s)
                return True, str(result), None
            except FuturesTimeout:
                self.restart()
                return (
                    False,
                    None,
                    f"Evaluation timed out after {timeout_s}s (kernel restarted)",
                )
            except Exception as e:
                self.restart()
                return False, None, f"{type(e).__name__}: {e} (kernel restarted)"
