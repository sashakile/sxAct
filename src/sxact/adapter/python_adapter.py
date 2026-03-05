"""PythonAdapter — concrete adapter backed by sxact.xcore (Julia-via-juliacall).

sxact.xcore is a Python API over Julia XCore.jl.  Evaluation therefore goes
through the Julia runtime; the "Python" in the name refers to the public API
surface (snake_case Python functions) rather than a native Python CAS.

Per-file isolation: same XCore state reset as JuliaAdapter (clear registries
on teardown).

Actions that require xTensor (DefManifold, DefMetric, DefTensor,
ToCanonical, Contract, Simplify) return error Results since xTensor is not
yet ported to Julia/Python.
"""

from __future__ import annotations

from typing import Any

from sxact.adapter.base import (
    AdapterError,
    EqualityMode,
    NormalizedExpr,
    TestAdapter,
    VersionInfo,
)
from sxact.adapter.julia_stub import _wl_to_jl  # reuse the Wolfram→Julia translator
from sxact.normalize import normalize as _normalize
from sxact.oracle.result import Result


# ---------------------------------------------------------------------------
# Context
# ---------------------------------------------------------------------------

class _PythonContext:
    """Opaque per-file context for PythonAdapter."""

    def __init__(self) -> None:
        self.alive: bool = True


# ---------------------------------------------------------------------------
# Adapter
# ---------------------------------------------------------------------------

_XTENSOR_ACTIONS = frozenset(
    {"DefManifold", "DefMetric", "DefTensor", "ToCanonical", "Contract", "Simplify"}
)

# XCore module-level mutable state to reset on teardown (mirrors JuliaAdapter)
_RESET_STMTS = [
    "empty!(XCore._symbol_registry)",
    "empty!(XCore._upvalue_store)",
    "empty!(XCore._xtensions)",
    "empty!(XCore.xPermNames)",
    "empty!(XCore.xTensorNames)",
    "empty!(XCore.xCoreNames)",
    "empty!(XCore.xTableauNames)",
    "empty!(XCore.xCobaNames)",
    "empty!(XCore.InvarNames)",
    "empty!(XCore.HarmonicsNames)",
    "empty!(XCore.xPertNames)",
    "empty!(XCore.SpinorsNames)",
    "empty!(XCore.EMNames)",
]


class PythonAdapter(TestAdapter[_PythonContext]):
    """Concrete adapter for the Python/sxact.xcore backend.

    Evaluates expressions by translating Wolfram syntax to Julia and
    executing them through the shared Julia XCore runtime (juliacall).

    This adapter exercises the same Julia XCore.jl implementation as
    JuliaAdapter but is surfaced under a 'Python' CAS label to represent
    the sxact.xcore Python package as the test subject.

    When a pure-Python (non-Julia) XCore implementation exists, this adapter
    can be updated to route through it instead.
    """

    def __init__(self) -> None:
        self._jl: Any = None
        self._xcore_version: str = "unknown"
        self._julia_version: str = "unknown"

    def _ensure_ready(self) -> None:
        if self._jl is not None:
            return
        try:
            from sxact.xcore._runtime import get_julia, get_xcore
            self._jl = get_julia()
            xc = get_xcore()
            raw_jl = self._jl.seval("string(VERSION)")
            self._julia_version = str(raw_jl).strip()
            # Try to get XCore package version
            try:
                raw_xc = self._jl.seval(
                    'string(pkgversion(XCore))'
                )
                self._xcore_version = str(raw_xc).strip()
            except Exception:
                self._xcore_version = "dev"
        except Exception as exc:
            raise AdapterError(
                f"sxact.xcore (Julia runtime) initialisation failed: {exc}"
            ) from exc

    # ------------------------------------------------------------------
    # Lifecycle
    # ------------------------------------------------------------------

    def initialize(self) -> _PythonContext:
        try:
            self._ensure_ready()
        except AdapterError:
            raise
        except Exception as exc:
            raise AdapterError(f"sxact.xcore unavailable: {exc}") from exc
        return _PythonContext()

    def teardown(self, ctx: _PythonContext) -> None:
        ctx.alive = False
        if self._jl is None:
            return
        for stmt in _RESET_STMTS:
            try:
                self._jl.seval(stmt)
            except Exception:
                pass  # teardown must not raise

    # ------------------------------------------------------------------
    # Execution
    # ------------------------------------------------------------------

    def execute(self, ctx: _PythonContext, action: str, args: dict[str, Any]) -> Result:
        if action not in self.supported_actions():
            raise ValueError(f"Unknown action: {action!r}")

        if action in _XTENSOR_ACTIONS:
            return Result(
                status="error",
                type="",
                repr="",
                normalized="",
                error=f"action {action!r} requires xTensor (not yet ported to Python/Julia)",
            )

        self._ensure_ready()

        if action == "Evaluate":
            return self._execute_expr(args.get("expression", ""))
        if action == "Assert":
            return self._execute_assert(
                args.get("condition", ""),
                args.get("message"),
            )
        return Result(
            status="error", type="", repr="", normalized="",
            error=f"unhandled action: {action!r}",
        )

    def _execute_expr(self, wolfram_expr: str) -> Result:
        julia_expr = _wl_to_jl(wolfram_expr)
        try:
            val = self._jl.seval(julia_expr)
            raw = str(val)
            return Result(
                status="ok",
                type="Expr",
                repr=raw,
                normalized=_normalize(raw),
            )
        except Exception as exc:
            return Result(
                status="error",
                type="",
                repr="",
                normalized="",
                error=str(exc),
            )

    def _execute_assert(self, wolfram_condition: str, message: str | None) -> Result:
        julia_cond = _wl_to_jl(wolfram_condition)
        try:
            val = self._jl.seval(julia_cond)
            passed = val is True or str(val).lower() == "true"
            if passed:
                return Result(status="ok", type="Bool", repr="True", normalized="True")
            msg = message or f"Assertion failed: {wolfram_condition}"
            return Result(
                status="error",
                type="Bool",
                repr=str(val),
                normalized=str(val),
                error=msg,
            )
        except Exception as exc:
            return Result(
                status="error",
                type="Bool",
                repr="",
                normalized="",
                error=str(exc),
            )

    # ------------------------------------------------------------------
    # Comparison
    # ------------------------------------------------------------------

    def normalize(self, expr: str) -> NormalizedExpr:
        return NormalizedExpr(_normalize(expr))

    def equals(
        self,
        a: NormalizedExpr,
        b: NormalizedExpr,
        mode: EqualityMode,
        ctx: _PythonContext | None = None,
    ) -> bool:
        return a == b  # Tier 1 only; semantic/numeric require oracle

    # ------------------------------------------------------------------
    # Introspection
    # ------------------------------------------------------------------

    def get_properties(self, expr: str, ctx: _PythonContext | None = None) -> dict[str, Any]:
        return {}

    def get_version(self) -> VersionInfo:
        if self._jl is None:
            try:
                self._ensure_ready()
            except AdapterError:
                pass
        return VersionInfo(
            cas_name="Python",
            cas_version=self._xcore_version,
            adapter_version="0.1.0",
            extra={"julia_version": self._julia_version},
        )
