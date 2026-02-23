"""JuliaAdapter stub — returns not-implemented for all execution requests.

Purpose:
  (1) Validates the adapter interface design is complete and implementable.
  (2) Provides a placeholder the CLI runner can exercise end-to-end before
      the real Julia XCore implementation exists.

Passes the adapter conformance suite (tests/test_adapter_conformance.py).
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
from sxact.oracle.result import Result


class _JuliaContext:
    """Opaque per-file context for JuliaAdapter."""

    def __init__(self) -> None:
        self.alive: bool = True


class JuliaAdapter(TestAdapter[_JuliaContext]):
    """Stub adapter for the Julia XCore backend.

    All execution methods return a Result with status='error' and
    error='not implemented'.  Lifecycle and comparison methods behave
    minimally but correctly so the conformance suite passes.
    """

    # ------------------------------------------------------------------
    # Lifecycle
    # ------------------------------------------------------------------

    def initialize(self) -> _JuliaContext:
        return _JuliaContext()

    def teardown(self, ctx: _JuliaContext) -> None:
        ctx.alive = False  # idempotent, must not raise

    # ------------------------------------------------------------------
    # Execution
    # ------------------------------------------------------------------

    def execute(self, ctx: _JuliaContext, action: str, args: dict[str, Any]) -> Result:
        if action not in self.supported_actions():
            raise ValueError(f"Unknown action: {action!r}")
        return Result(
            status="error",
            type="Expr",
            repr="",
            normalized="",
            error="not implemented",
        )

    # ------------------------------------------------------------------
    # Comparison
    # ------------------------------------------------------------------

    def normalize(self, expr: str) -> NormalizedExpr:
        return NormalizedExpr(expr.strip())

    def equals(
        self,
        a: NormalizedExpr,
        b: NormalizedExpr,
        mode: EqualityMode,
        ctx: _JuliaContext | None = None,
    ) -> bool:
        return a == b

    # ------------------------------------------------------------------
    # Introspection
    # ------------------------------------------------------------------

    def get_properties(self, expr: str, ctx: _JuliaContext | None = None) -> dict[str, Any]:
        return {}

    def get_version(self) -> VersionInfo:
        return VersionInfo(
            cas_name="Julia",
            cas_version="0.0.0",
            adapter_version="0.1.0-stub",
        )
