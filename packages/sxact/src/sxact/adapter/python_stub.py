"""PythonAdapter — concrete adapter with Python-native Wolfram mini-interpreter.

Implements a self-contained evaluator for the Wolfram-like expressions used in
the xCore TOML test suite, using only Python (no Julia runtime required at
test-evaluation time).

The mini-interpreter covers:
- Wolfram symbolic expressions: Sym (atom), WExpr (compound)
- xCore functions: SymbolJoin, HasDaggerCharacterQ, MakeDaggerSymbol,
  LinkSymbols, UnlinkSymbol, ValidateSymbol, JustOne, MapIfPlus,
  CheckOptions, TrueOrFalse, DeleteDuplicates, DuplicateFreeQ, SubHead,
  FindSymbols, NoPattern, xUpSet, xUpAppendTo, xUpDeleteCasesTo,
  xTagSet, xTagSetDelayed, AppendToUnevaluated
- Wolfram builtins: StringQ, StringLength, AtomQ, SymbolName, MemberQ,
  Head, Catch, ClearAll, Length, NumericQ, Plus
- Per-file state isolation via _XCoreState

Scope: xCore actions only (Evaluate, Assert).  xTensor actions are
reported as deferred errors.

Submodules (extracted for modularity, sxAct-ckzw):
- _wl_ast: Sym, WExpr data model and symbol singletons
- _wl_parser: recursive descent parser
- _wl_evaluator: XCoreState and expression evaluator
"""

from __future__ import annotations

from typing import Any

from sxact.adapter._wl_ast import wl_repr as _wl_repr
from sxact.adapter._wl_evaluator import (
    _eval_bool_result,
    _wl_evaluate,
    _XCoreState,
)
from sxact.adapter._wl_parser import _parse
from sxact.adapter.base import (
    EqualityMode,
    NormalizedExpr,
    TestAdapter,
    VersionInfo,
)
from sxact.normalize import normalize as _normalize
from sxact.oracle.result import Result

# ===========================================================================
# Context
# ===========================================================================


class _PythonContext:
    """Opaque per-file context for PythonAdapter."""

    def __init__(self) -> None:
        self.alive: bool = True
        self.state: _XCoreState = _XCoreState()


# ===========================================================================
# Adapter
# ===========================================================================


class PythonAdapter(TestAdapter[_PythonContext]):
    """Concrete adapter for the Python XCore backend.

    Evaluates xCore TOML test actions using a Python-native Wolfram
    mini-interpreter.  No Julia runtime is required.
    """

    # Tier 2 / xTensor deferred actions
    _DEFERRED_ACTIONS = frozenset(
        {
            "DefManifold",
            "DefMetric",
            "DefTensor",
            "ToCanonical",
            "Contract",
            "Simplify",
        }
    )

    # ------------------------------------------------------------------
    # Lifecycle
    # ------------------------------------------------------------------

    def initialize(self) -> _PythonContext:
        return _PythonContext()

    def teardown(self, ctx: _PythonContext) -> None:
        ctx.alive = False
        ctx.state.reset()

    # ------------------------------------------------------------------
    # Execution
    # ------------------------------------------------------------------

    def execute(self, ctx: _PythonContext, action: str, args: dict[str, Any]) -> Result:
        if action not in self.supported_actions():
            raise ValueError(f"Unknown action: {action!r}")

        if action in self._DEFERRED_ACTIONS:
            return Result(
                status="error",
                type="",
                repr="",
                normalized="",
                error=f"action {action!r} is deferred (xTensor not supported by PythonAdapter)",
            )

        if action == "Evaluate":
            return self._execute_expr(args.get("expression", ""), ctx.state)
        if action == "Assert":
            return self._execute_assert(
                args.get("condition", ""),
                args.get("message"),
                ctx.state,
            )
        return Result(
            status="error",
            type="",
            repr="",
            normalized="",
            error=f"unhandled action: {action!r}",
        )

    def _execute_expr(self, wolfram_expr: str, state: _XCoreState) -> Result:
        try:
            ast = _parse(wolfram_expr)
            val = _wl_evaluate(ast, state)
            raw = _wl_repr(val)
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

    def _execute_assert(
        self, wolfram_condition: str, message: str | None, state: _XCoreState
    ) -> Result:
        try:
            ast = _parse(wolfram_condition)
            val = _wl_evaluate(ast, state)
            passed = _eval_bool_result(val)
            if passed:
                return Result(status="ok", type="Bool", repr="True", normalized="True")
            msg = message or f"Assertion failed: {wolfram_condition!r} (got {_wl_repr(val)!r})"
            return Result(
                status="error",
                type="Bool",
                repr=_wl_repr(val),
                normalized=_wl_repr(val),
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
        return a == b

    # ------------------------------------------------------------------
    # Introspection
    # ------------------------------------------------------------------

    def get_properties(self, expr: str, ctx: _PythonContext | None = None) -> dict[str, Any]:
        return {}

    def get_version(self) -> VersionInfo:
        return VersionInfo(
            cas_name="Python",
            cas_version="3.x",
            adapter_version="0.2.0",
        )

    def supported_actions(self) -> frozenset[str]:
        return frozenset({"Evaluate", "Assert"}) | self._DEFERRED_ACTIONS
