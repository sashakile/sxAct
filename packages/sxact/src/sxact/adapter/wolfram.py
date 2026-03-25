"""WolframAdapter — TestAdapter wrapping the Oracle HTTP client.

Lifecycle per test file::

    adapter = WolframAdapter()
    ctx = adapter.initialize()          # verifies oracle health, creates context_id
    try:
        result = adapter.execute(ctx, "DefManifold", {"name": "M", ...})
        ...
    finally:
        adapter.teardown(ctx)           # marks context dead; oracle context expires naturally
"""

from __future__ import annotations

import uuid
from typing import Any

from sxact.adapter.base import (
    AdapterError,
    EqualityMode,
    NormalizedExpr,
    TestAdapter,
    VersionInfo,
)
from sxact.normalize import normalize as _normalize
from sxact.oracle.client import OracleClient
from sxact.oracle.result import Result

# ---------------------------------------------------------------------------
# Context
# ---------------------------------------------------------------------------


class _WolframContext:
    """Per-file context for WolframAdapter.

    Holds a UUID context_id passed to the oracle so the server can isolate
    symbol definitions between test files.
    """

    def __init__(self, context_id: str) -> None:
        self.context_id = context_id
        self.alive: bool = True


# ---------------------------------------------------------------------------
# Adapter
# ---------------------------------------------------------------------------


class WolframAdapter(TestAdapter[_WolframContext]):
    """Concrete adapter for the Wolfram/xAct backend.

    Wraps :class:`~sxact.oracle.client.OracleClient`, mapping the abstract
    test action vocabulary to Wolfram/xAct expression strings and forwarding
    them via ``evaluate_with_xact()``.

    Args:
        base_url: Oracle HTTP server base URL.  Defaults to
                  ``http://localhost:8765``.
        timeout:  Default per-call timeout in seconds.  Defaults to 60.
    """

    def __init__(
        self,
        base_url: str = "http://localhost:8765",
        timeout: int = 60,
    ) -> None:
        self._oracle = OracleClient(base_url)
        self._timeout = timeout

    # ------------------------------------------------------------------
    # Lifecycle
    # ------------------------------------------------------------------

    def initialize(self) -> _WolframContext:
        """Create a fresh isolated context, raising AdapterError if the oracle is down.

        Performs a pre-test leak check.  If the kernel is dirty (non-empty
        Manifolds or Tensors), triggers a hard kernel restart as a fallback.
        Raises AdapterError if the oracle is unreachable or restart fails.
        """
        if not self._oracle.health():
            raise AdapterError(f"Wolfram oracle unavailable at {self._oracle.base_url}")
        is_clean, leaked = self._oracle.check_clean_state()
        if not is_clean:
            import warnings

            warnings.warn(
                f"Kernel dirty before test file (leaked: {leaked}); triggering hard restart.",
                RuntimeWarning,
                stacklevel=2,
            )
            if not self._oracle.restart():
                raise AdapterError(
                    f"Kernel state dirty and restart failed; leaked symbols: {leaked}"
                )
        return _WolframContext(context_id=str(uuid.uuid4()))

    def teardown(self, ctx: _WolframContext) -> None:
        """Clean xAct state and mark context dead.

        Calls the oracle /cleanup endpoint to remove Global symbols and reset
        Manifolds/Tensors registries.  Safe to call multiple times; does not
        raise on cleanup failure (logs a warning instead).
        """
        ctx.alive = False
        if not self._oracle.cleanup():
            import warnings

            warnings.warn(
                "Oracle cleanup failed after test file; kernel state may be dirty for next test.",
                RuntimeWarning,
                stacklevel=2,
            )

    # ------------------------------------------------------------------
    # Execution
    # ------------------------------------------------------------------

    def supported_actions(self) -> frozenset[str]:
        """Actions this adapter can translate to Wolfram expressions."""
        return frozenset(
            {
                "DefManifold",
                "DefMetric",
                "DefTensor",
                "Evaluate",
                "ToCanonical",
                "Simplify",
                "Contract",
                "Assert",
                "Christoffel",
                "DefPerturbation",
                "Perturb",
                "PerturbCurvature",
                "PerturbationOrder",
                "PerturbationAtOrder",
                "CommuteCovDs",
                "SortCovDs",
                "CheckMetricConsistency",
                "IntegrateByParts",
                "TotalDerivativeQ",
                "VarD",
                "SetBasisChange",
                "ChangeBasis",
                "GetJacobian",
                "BasisChangeQ",
                "SetComponents",
                "GetComponents",
                "ComponentValue",
                "CTensorQ",
                "ToBasis",
                "FromBasis",
                "TraceBasisDummy",
            }
        )

    def execute(self, ctx: _WolframContext, action: str, args: dict[str, Any]) -> Result:
        if action not in self.supported_actions():
            raise ValueError(f"Unknown action: {action!r}")

        try:
            wolfram_expr = self._build_expr(action, args)
        except KeyError as exc:
            return Result(
                status="error",
                type="",
                repr="",
                normalized="",
                error=f"Missing required argument for {action}: {exc}",
            )

        context_id = ctx.context_id if ctx.alive else None
        result = self._oracle.evaluate_with_xact(
            wolfram_expr,
            timeout=self._timeout,
            context_id=context_id,
        )

        # Assert: treat non-True oracle result as test failure
        if action == "Assert" and result.status == "ok":
            if result.repr.strip() != "True":
                msg = args.get("message") or f"Assertion failed: {args.get('condition', '')}"
                return Result(
                    status="error",
                    type="Bool",
                    repr=result.repr,
                    normalized=result.normalized,
                    error=msg,
                )
            return Result(
                status="ok",
                type="Bool",
                repr="True",
                normalized="True",
            )

        return result

    def _build_expr(self, action: str, args: dict[str, Any]) -> str:
        """Translate action + args to a Wolfram expression string.

        Raises:
            KeyError: if a required arg is absent.
        """
        if action == "DefManifold":
            idx_str = ", ".join(args["indices"])
            return f"DefManifold[{args['name']}, {args['dimension']}, {{{idx_str}}}]"

        if action == "DefMetric":
            return f"DefMetric[{args['signdet']}, {args['metric']}, {args['covd']}]"

        if action == "DefTensor":
            idx_str = ",".join(args["indices"])
            tensor_slot = f"{args['name']}[{idx_str}]"
            manifold = args.get("manifold") or ""
            symmetry = args.get("symmetry") or ""
            parts = [p for p in (tensor_slot, manifold, symmetry) if p]
            return f"DefTensor[{', '.join(parts)}]"

        if action == "Evaluate":
            return str(args["expression"])

        if action == "ToCanonical":
            return f"ToCanonical[{args['expression']}]"

        if action == "Simplify":
            expr = args["expression"]
            assumptions = args.get("assumptions") or ""
            if assumptions:
                return f"Simplify[{expr}, {assumptions}]"
            return f"Simplify[{expr}]"

        if action == "Contract":
            return f"ContractMetric[{args['expression']}]"

        if action == "Assert":
            return str(args["condition"])

        if action == "Christoffel":
            return f"ChristoffelP[{args['covd']}]"

        if action == "DefPerturbation":
            return f"DefPerturbation[{args['name']}, {args['metric']}, {args['parameter']}]"

        if action == "Perturb":
            return f"Perturb[{args['expression']}, {args['order']}]"

        if action == "PerturbCurvature":
            # In xAct, this is usually automatic or part of Perturb
            # but we can return the formula key if requested
            key = args.get("key")
            if key:
                return f"{key}[{args['covd']}]"
            return f"Perturbation[{args['expression']}, {args['order']}]"

        if action == "PerturbationOrder":
            return f"PerturbationOrder[{args['expression']}]"

        if action == "PerturbationAtOrder":
            return f"PerturbationAtOrder[{args['expression']}, {args['order']}]"

        if action == "CommuteCovDs":
            return f"CommuteCovDs[{args['expression']}, {args['cd1']}, {args['cd2']}]"

        if action == "SortCovDs":
            return f"SortCovDs[{args['expression']}, {args['covd']}]"

        if action == "CheckMetricConsistency":
            return f"CheckMetricConsistency[{args['metric']}, {args['covd']}]"

        if action == "IntegrateByParts":
            return f"IBP[{args['expression']}, {args['covd']}]"

        if action == "TotalDerivativeQ":
            return f"TotalDerivativeQ[{args['expression']}, {args['covd']}]"

        if action == "VarD":
            return f"VarD[{args['variable']}][{args['expression']}]"

        if action == "SetBasisChange":
            return f"SetBasisChange[{args['basis1']}, {args['basis2']}, {args['matrix']}]"

        if action == "ChangeBasis":
            return f"ChangeBasis[{args['expression']}, {args['target_basis']}]"

        if action == "GetJacobian":
            return f"Jacobian[{args['basis1']}, {args['basis2']}]"

        if action == "BasisChangeQ":
            return f"BasisChangeQ[{args['basis1']}, {args['basis2']}]"

        if action == "SetComponents":
            return f"SetComponents[{args['tensor']}, {args['components']}]"

        if action == "GetComponents":
            return f"GetComponents[{args['tensor']}, {args['basis']}]"

        if action == "ComponentValue":
            return f"{args['tensor']}[{','.join(map(str, args['indices']))}]"

        if action == "CTensorQ":
            return f"CTensorQ[{args['tensor']}]"

        if action == "ToBasis":
            return f"ToBasis[{args['basis']}][{args['expression']}]"

        if action == "FromBasis":
            return f"FromBasis[{args['basis']}][{args['expression']}]"

        if action == "TraceBasisDummy":
            return f"TraceBasisDummy[{args['expression']}]"

        raise ValueError(f"Unknown action: {action!r}")  # unreachable

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
        ctx: _WolframContext | None = None,
    ) -> bool:
        # Tier 1: normalized string comparison (always attempted first)
        if a == b:
            return True
        if mode == EqualityMode.NORMALIZED:
            return False

        # Tier 2: semantic — ask oracle whether Simplify[a - b] === 0
        if ctx is not None and ctx.alive:
            semantic_expr = f"TrueQ[Simplify[({a}) - ({b})] === 0]"
            eval_result = self._oracle.evaluate_with_xact(
                semantic_expr,
                timeout=self._timeout,
                context_id=ctx.context_id,
            )
            if eval_result.status == "ok" and eval_result.repr == "True":
                return True
        if mode == EqualityMode.SEMANTIC:
            return False

        # Tier 3: numeric sampling
        from sxact.compare.sampling import sample_numeric

        lhs_result = Result(status="ok", type="Expr", repr=str(a), normalized=str(a))
        rhs_result = Result(status="ok", type="Expr", repr=str(b), normalized=str(b))
        sampling = sample_numeric(lhs_result, rhs_result, self._oracle)
        return sampling.equal

    # ------------------------------------------------------------------
    # Introspection
    # ------------------------------------------------------------------

    def get_properties(self, expr: str, ctx: _WolframContext | None = None) -> dict[str, Any]:
        return {}

    def get_version(self) -> VersionInfo:
        cas_version = "unknown"
        if self._oracle.health():
            try:
                ev = self._oracle.evaluate("$VersionNumber // ToString")
                if ev.status == "ok" and ev.repr:
                    cas_version = ev.repr.strip().strip('"')
            except Exception:
                pass
        return VersionInfo(
            cas_name="Wolfram",
            cas_version=cas_version,
            adapter_version="0.1.0",
        )
