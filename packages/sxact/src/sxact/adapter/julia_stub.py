"""JuliaAdapter — concrete adapter backed by Julia XCore/XTensor via juliacall.

Uses the Python xCore runtime (_runtime.py) to lazily initialise Julia and
load XCore.jl once per process.  Evaluates Julia expressions translated from
the TOML test vocabulary (Wolfram → Julia syntax).

Per-file isolation is achieved by resetting XCore and XTensor global state on
teardown.

Actions that require xTensor (DefManifold, DefMetric, DefTensor, ToCanonical,
Contract, SignDetOfMetric, Simplify) are dispatched to the Julia XTensor module.
"""

from __future__ import annotations

import logging
import re
from typing import Any, ClassVar
from typing import Literal as _Literal

from sxact.adapter.base import (
    AdapterError,
    EqualityMode,
    NormalizedExpr,
    TestAdapter,
    VersionInfo,
)
from sxact.adapter.julia_names import (
    DEF_MANIFOLD as _JN_DEF_MANIFOLD,
)
from sxact.adapter.julia_names import (
    DEF_METRIC as _JN_DEF_METRIC,
)
from sxact.adapter.julia_names import (
    DEF_PERTURBATION as _JN_DEF_PERTURBATION,
)
from sxact.adapter.julia_names import (
    DEF_TENSOR as _JN_DEF_TENSOR,
)
from sxact.adapter.julia_names import (
    TENSOR_Q as _JN_TENSOR_Q,
)
from sxact.adapter.julia_names import (
    TO_CANONICAL as _JN_TO_CANONICAL,
)
from sxact.normalize import normalize as _normalize
from sxact.oracle.result import Result
from xact._bridge import (
    jl_call,
    jl_int,
    jl_str,
    jl_sym,
    jl_sym_list,
    timed_seval,
    validate_ident,
)

_log = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


_Symmetry = _Literal["Symmetric", "Antisymmetric"]


def _parse_symmetry(sym_str: str) -> _Symmetry | None:
    """Extract symmetry type from xAct symmetry string.

    Returns 'Symmetric', 'Antisymmetric', or None.
    GradedSymmetric maps to 'Antisymmetric' for Tier 3 numeric array generation.
    """
    if not sym_str:
        return None
    if sym_str.startswith("Symmetric"):
        return "Symmetric"
    if sym_str.startswith("Antisymmetric"):
        return "Antisymmetric"
    if sym_str.startswith("GradedSymmetric"):
        return "Antisymmetric"
    return None


# ---------------------------------------------------------------------------
# Context
# ---------------------------------------------------------------------------


class _JuliaContext:
    """Opaque per-file context for JuliaAdapter.

    Tracks manifold/metric/tensor definitions made during this context so that
    a TensorContext can be built for Tier 3 numeric comparison.
    """

    def __init__(self) -> None:
        self.alive: bool = True
        # Populated by _def_manifold / _def_metric / _def_tensor
        from sxact.compare.tensor_objects import Manifold, Metric, TensorField

        self._manifolds: list[Manifold] = []
        self._metrics: list[Metric] = []
        self._tensors: list[TensorField] = []


# ---------------------------------------------------------------------------
# Adapter
# ---------------------------------------------------------------------------


class JuliaAdapter(TestAdapter[_JuliaContext]):
    """Concrete adapter for the Julia XCore + XTensor backend."""

    # Tier 2 deferred actions
    _DEFERRED_ACTIONS: frozenset[str] = frozenset()

    # XCore module-level mutable state to reset on teardown
    _RESET_STMTS: ClassVar[list[str]] = ["xAct.reset_state!()"]

    def __init__(self) -> None:
        self._jl: Any = None
        self._xact_version: str = "unknown"
        self._julia_version: str = "unknown"
        # Action → handler registry.  Handlers that need ctx take (ctx, args);
        # handlers that don't take (args) only.  _CTX_ACTIONS lists the former.
        self._ACTION_HANDLERS: dict[str, str] = {
            "DefManifold": "_def_manifold",
            "DefMetric": "_def_metric",
            "DefTensor": "_def_tensor",
            "DefBasis": "_def_basis",
            "DefChart": "_def_chart",
            "ToCanonical": "_to_canonical",
            "Contract": "_contract",
            "CommuteCovDs": "_commute_covds",
            "SortCovDs": "_sort_covds",
            "DefPerturbation": "_def_perturbation",
            "CheckMetricConsistency": "_check_metric_consistency",
            "Perturb": "_perturb",
            "PerturbCurvature": "_perturb_curvature",
            "Simplify": "_simplify",
            "PerturbationOrder": "_perturbation_order",
            "PerturbationAtOrder": "_perturbation_at_order",
            "IntegrateByParts": "_integrate_by_parts",
            "TotalDerivativeQ": "_total_derivative_q",
            "VarD": "_vard",
            "SetBasisChange": "_set_basis_change",
            "ChangeBasis": "_change_basis",
            "GetJacobian": "_get_jacobian",
            "BasisChangeQ": "_basis_change_q",
            "SetComponents": "_set_components",
            "GetComponents": "_get_components",
            "ComponentValue": "_component_value",
            "CTensorQ": "_ctensor_q",
            "ToBasis": "_to_basis",
            "FromBasis": "_from_basis",
            "TraceBasisDummy": "_trace_basis_dummy",
            "Christoffel": "_christoffel",
            "CollectTensors": "_collect_tensors",
            "AllContractions": "_all_contractions",
            "SymmetryOf": "_symmetry_of",
            "MakeTraceFree": "_make_trace_free",
            "RiemannSimplify": "_riemann_simplify",
        }
        self._CTX_ACTIONS = frozenset({"DefManifold", "DefMetric", "DefTensor", "DefPerturbation"})

    def _ensure_ready(self) -> None:
        if self._jl is not None:
            return
        try:
            from xact.xcore._runtime import get_julia, get_xcore

            self._jl = get_julia()
            get_xcore()
            raw = self._jl.seval("string(VERSION)")
            self._julia_version = str(raw).strip()
            # Try to get xAct package version
            try:
                raw_xa = self._jl.seval("string(pkgversion(xAct))")
                self._xact_version = str(raw_xa).strip()
            except Exception:
                self._xact_version = "dev"
        except Exception as exc:
            raise AdapterError(f"Julia/XCore initialisation failed: {exc}") from exc

    # ------------------------------------------------------------------
    # Lifecycle
    # ------------------------------------------------------------------

    def initialize(self) -> _JuliaContext:
        try:
            self._ensure_ready()
        except AdapterError:
            raise
        except Exception as exc:
            raise AdapterError(f"Julia/XCore unavailable: {exc}") from exc
        return _JuliaContext()

    def teardown(self, ctx: _JuliaContext) -> None:
        ctx.alive = False
        if self._jl is None:
            return
        for stmt in self._RESET_STMTS:
            try:
                self._jl.seval(stmt)
            except Exception:
                import warnings

                warnings.warn(
                    f"JuliaAdapter.teardown: failed to execute '{stmt}'",
                    RuntimeWarning,
                    stacklevel=2,
                )

    # ------------------------------------------------------------------
    # Execution
    # ------------------------------------------------------------------

    def execute(self, ctx: _JuliaContext, action: str, args: dict[str, Any]) -> Result:
        if action not in self.supported_actions():
            raise ValueError(f"Unknown action: {action!r}")

        if action in self._DEFERRED_ACTIONS:
            return Result(
                status="error",
                type="",
                repr="",
                normalized="",
                error=f"action {action!r} is deferred to Tier 2",
            )

        self._ensure_ready()

        if action in self._ACTION_HANDLERS:
            return self._execute_xtensor(ctx, action, args)

        if action == "Evaluate":
            expr = args.get("expression", "")
            # Intercept numerical_tolerance comparisons BEFORE the early-return so
            # Max[Abs[Flatten[N[...]]]] tensor expressions are handled via ToCanonical.
            canonical_result = _try_numerical_tolerance_via_canonical(self._jl, expr)
            if canonical_result is not None:
                return canonical_result
            # If it looks like a tensor expression (contains Name[...] with index syntax),
            # return it as-is for later ToCanonical use — no Julia evaluation needed.
            # Exception: if the expression contains a comparison operator (===) it is a
            # law-check from the property runner and must be evaluated in Julia.
            if _is_tensor_expr(expr) and "===" not in expr:
                return Result(status="ok", type="Expr", repr=expr, normalized=_normalize(expr))
            return self._execute_expr(expr)
        if action == "Assert":
            return self._execute_assert(
                args.get("condition", ""),
                args.get("message"),
            )
        # Unreachable if supported_actions() is correct
        return Result(
            status="error",
            type="",
            repr="",
            normalized="",
            error=f"unhandled action: {action!r}",
        )

    def _execute_xtensor(self, ctx: _JuliaContext, action: str, args: dict[str, Any]) -> Result:
        """Dispatch xTensor actions via handler registry."""
        method_name = self._ACTION_HANDLERS.get(action)
        if method_name is None:
            return Result(
                status="error",
                type="",
                repr="",
                normalized="",
                error=f"unhandled xTensor action: {action!r}",
            )
        try:
            handler = getattr(self, method_name)
            result: Result
            if action in self._CTX_ACTIONS:
                result = handler(ctx, args)
            else:
                result = handler(args)
            return result
        except Exception as exc:
            import traceback as _tb

            tb_str = _tb.format_exc()
            return Result(
                status="error",
                type="",
                repr="",
                normalized="",
                error=f"{exc}\n{tb_str}",
            )

    def _def_manifold(self, ctx: _JuliaContext, args: dict[str, Any]) -> Result:
        from sxact.compare.tensor_objects import Manifold

        name = validate_ident(str(args["name"]), "manifold name")
        dim = int(args["dimension"])
        indices = list(args["indices"])
        jl_call(
            self._jl,
            _JN_DEF_MANIFOLD,
            jl_sym(name, "manifold name"),
            jl_int(dim),
            jl_sym_list(indices, "manifold indices"),
        )
        # Bind in Main scope as Symbols for Assert conditions:
        #   Dimension(Bm4) → Dimension(:Bm4); ManifoldQ(Bm4) → ManifoldQ(:Bm4)
        tangent_name = validate_ident(f"Tangent{name}", "tangent bundle name")
        self._jl.seval(f"Main.eval(:(global {name} = :{name}))")
        self._jl.seval(f"Main.eval(:(global {tangent_name} = :{tangent_name}))")
        for idx in indices:
            idx = validate_ident(idx, "manifold index")
            self._jl.seval(f"Main.eval(:(global {idx} = :{idx}))")
        ctx._manifolds.append(Manifold(name=name, dimension=dim))
        return Result(status="ok", type="Handle", repr=name, normalized=name)

    def _def_tensor(self, ctx: _JuliaContext, args: dict[str, Any]) -> Result:
        from sxact.compare.tensor_objects import TensorField

        name = validate_ident(str(args["name"]), "tensor name")
        indices = args["indices"]
        sym_str = args.get("symmetry") or ""
        idx_jl = "[" + ", ".join(jl_str(i) for i in indices) + "]"
        sym_arg = f", symmetry_str={jl_str(sym_str)}" if sym_str else ""

        # Support both "manifold" (single) and "manifolds" (list, multi-index-set)
        raw_manifolds = args.get("manifolds")
        if raw_manifolds is not None:
            # Multi-index-set: pass a Vector of Symbols to Julia
            manifold_names = [validate_ident(str(m), "manifold name") for m in raw_manifolds]
            jl_manifolds = "Symbol[" + ", ".join(f":{m}" for m in manifold_names) + "]"
            jl_call(
                self._jl,
                _JN_DEF_TENSOR,
                jl_sym(name, "tensor name"),
                idx_jl,
                jl_manifolds + sym_arg,
            )
            # Primary manifold for TensorContext = first in list
            primary_manifold_name = manifold_names[0] if manifold_names else None
        else:
            manifold = validate_ident(str(args["manifold"]), "manifold name")
            jl_call(
                self._jl,
                _JN_DEF_TENSOR,
                jl_sym(name, "tensor name"),
                idx_jl,
                jl_sym(manifold, "manifold name") + sym_arg,
            )
            primary_manifold_name = manifold

        # Bind tensor name in Main as a Symbol for TensorQ(Bts) etc.
        self._jl.seval(f"Main.eval(:(global {name} = :{name}))")
        # Record for TensorContext (Tier 3 numeric comparison)
        manifold_obj = next(
            (m for m in reversed(ctx._manifolds) if m.name == primary_manifold_name),
            ctx._manifolds[-1] if ctx._manifolds else None,
        )
        if manifold_obj is not None:
            symmetry = _parse_symmetry(sym_str)
            ctx._tensors.append(
                TensorField(
                    name=name,
                    rank=len(indices),
                    manifold=manifold_obj,
                    symmetry=symmetry,
                )
            )
        return Result(status="ok", type="Handle", repr=name, normalized=name)

    def _def_metric(self, ctx: _JuliaContext, args: dict[str, Any]) -> Result:
        import re as _re

        from sxact.compare.tensor_objects import Metric

        signdet = int(args["signdet"])
        metric_raw = str(args["metric"])
        covd = validate_ident(str(args["covd"]), "covariant derivative name")
        jl_call(
            self._jl,
            _JN_DEF_METRIC,
            jl_int(signdet),
            jl_str(metric_raw),
            jl_sym(covd, "covd name"),
        )
        # Bind the covd name in Main as a Symbol (for CovDQ assertions)
        self._jl.seval(f"Main.eval(:(global {covd} = :{covd}))")
        # Bind the metric tensor name in Main as a Symbol (for SignDetOfMetric assertions)
        m_name_match = _re.match(r"^(\w+)", metric_raw)
        metric_name = m_name_match.group(1) if m_name_match else None
        if metric_name:
            metric_name = validate_ident(metric_name, "metric name")
            self._jl.seval(f"Main.eval(:(global {metric_name} = :{metric_name}))")
        # Bind auto-created curvature tensor names in Main as Symbols
        for prefix in ("Riemann", "Ricci", "RicciScalar", "Einstein", "Weyl"):
            auto_name = validate_ident(f"{prefix}{covd}", "curvature tensor name")
            self._jl.seval(
                f"if XTensor.TensorQ(:{auto_name})\n"
                f"    Main.eval(:(global {auto_name} = :{auto_name}))\n"
                f"end"
            )
        # Record metric for TensorContext (use last manifold as the associated manifold)
        if metric_name and ctx._manifolds:
            # signdet == 1 → Euclidean (0 negative eigenvalues); -1 → Lorentzian (1 neg)
            signature = 1 if signdet == -1 else 0
            ctx._metrics.append(
                Metric(name=metric_name, manifold=ctx._manifolds[-1], signature=signature)
            )
        repr_str = metric_raw
        return Result(status="ok", type="Handle", repr=repr_str, normalized=repr_str)

    def _def_basis(self, args: dict[str, Any]) -> Result:
        import xact.api as _api

        name = validate_ident(str(args["name"]), "basis name")
        _api.def_basis(name, str(args["vbundle"]), list(args["cnumbers"]))
        self._jl.seval(f"Main.eval(:(global {name} = :{name}))")
        return Result(status="ok", type="Handle", repr=name, normalized=name)

    def _def_chart(self, args: dict[str, Any]) -> Result:
        import xact.api as _api

        name = validate_ident(str(args["name"]), "chart name")
        scalars = list(args["scalars"])
        _api.def_chart(name, str(args["manifold"]), list(args["cnumbers"]), scalars)
        self._jl.seval(f"Main.eval(:(global {name} = :{name}))")
        for sc in scalars:
            sc = validate_ident(sc, "chart scalar")
            self._jl.seval(f"Main.eval(:(global {sc} = :{sc}))")
        return Result(status="ok", type="Handle", repr=name, normalized=name)

    def _to_canonical(self, args: dict[str, Any]) -> Result:
        import xact.api as _api

        raw = _api.canonicalize(str(args["expression"]))
        return Result(status="ok", type="Expr", repr=raw, normalized=_normalize(raw))

    def _contract(self, args: dict[str, Any]) -> Result:
        import xact.api as _api

        raw = _api.contract(str(args["expression"]))
        return Result(status="ok", type="Expr", repr=raw, normalized=_normalize(raw))

    def _commute_covds(self, args: dict[str, Any]) -> Result:
        import xact.api as _api

        indices = list(args["indices"])
        if len(indices) != 2:
            return Result(
                status="error",
                type="",
                repr="",
                normalized="",
                error=f"CommuteCovDs: expected 2 indices, got {len(indices)}",
            )
        raw = _api.commute_covds(
            str(args["expression"]), str(args["covd"]), str(indices[0]), str(indices[1])
        )
        return Result(status="ok", type="Expr", repr=raw, normalized=_normalize(raw))

    def _sort_covds(self, args: dict[str, Any]) -> Result:
        import xact.api as _api

        raw = _api.sort_covds(str(args["expression"]), str(args["covd"]))
        return Result(status="ok", type="Expr", repr=raw, normalized=_normalize(raw))

    def _def_perturbation(self, ctx: _JuliaContext, args: dict[str, Any]) -> Result:
        tensor = validate_ident(str(args["tensor"]), "perturbation tensor")
        background = validate_ident(str(args["background"]), "background tensor")
        order = int(args["order"])
        jl_call(
            self._jl,
            _JN_DEF_PERTURBATION,
            jl_sym(tensor, "tensor"),
            jl_sym(background, "background"),
            jl_int(order),
        )
        # Bind the perturbation tensor name in Main as a Symbol (for PerturbationQ assertions)
        self._jl.seval(f"Main.eval(:(global {tensor} = :{tensor}))")
        return Result(status="ok", type="Handle", repr=tensor, normalized=tensor)

    def _perturb(self, args: dict[str, Any]) -> Result:
        import xact.api as _api

        s = _api.perturb(str(args["expr"]), int(args["order"]))
        return Result(status="ok", type="String", repr=s, normalized=s)

    def _check_metric_consistency(self, args: dict[str, Any]) -> Result:
        import xact.api as _api

        ok = _api.check_metric_consistency(str(args["metric"]))
        raw = "True" if ok else "False"
        return Result(status="ok", type="Bool", repr=raw, normalized=raw)

    def _perturbation_order(self, args: dict[str, Any]) -> Result:
        import xact.api as _api

        order = _api.perturbation_order(str(args["tensor"]))
        return Result(status="ok", type="Int", repr=str(order), normalized=str(order))

    def _perturbation_at_order(self, args: dict[str, Any]) -> Result:
        import xact.api as _api

        name = _api.perturbation_at_order(str(args["background"]), int(args["order"]))
        return Result(status="ok", type="String", repr=name, normalized=name)

    def _simplify(self, args: dict[str, Any]) -> Result:
        import xact.api as _api

        s = _api.simplify(str(args["expression"]))
        return Result(status="ok", type="String", repr=s, normalized=s)

    def _perturb_curvature(self, args: dict[str, Any]) -> Result:
        import xact.api as _api

        key = args.get("key")
        jl_dict = _api.perturb_curvature(
            str(args["covd"]),
            str(args["perturbation"]),
            order=int(args.get("order", 1)),
        )
        if key is not None:
            formula = jl_dict.get(str(key), "")
            return Result(status="ok", type="Expr", repr=formula, normalized=_normalize(formula))
        lines = [f"{k}: {v}" for k, v in sorted(jl_dict.items())]
        raw = "\n".join(lines)
        return Result(status="ok", type="Dict", repr=raw, normalized=raw)

    def _integrate_by_parts(self, args: dict[str, Any]) -> Result:
        import xact.api as _api

        s = _api.ibp(str(args["expression"]), str(args["covd"]))
        return Result(status="ok", type="Expr", repr=s, normalized=_normalize(s))

    def _total_derivative_q(self, args: dict[str, Any]) -> Result:
        import xact.api as _api

        is_true = _api.total_derivative_q(str(args["expression"]), str(args["covd"]))
        s = "True" if is_true else "False"
        return Result(status="ok", type="Bool", repr=s, normalized=s)

    def _vard(self, args: dict[str, Any]) -> Result:
        import xact.api as _api

        s = _api.var_d(str(args["expression"]), str(args["field"]), str(args["covd"]))
        return Result(status="ok", type="Expr", repr=s, normalized=_normalize(s))

    def _set_basis_change(self, args: dict[str, Any]) -> Result:
        import xact.api as _api

        from_basis = str(args["from_basis"])
        to_basis = str(args["to_basis"])
        _api.set_basis_change(from_basis, to_basis, list(args["matrix"]))
        repr_str = f"BasisChange({from_basis}, {to_basis})"
        return Result(status="ok", type="Handle", repr=repr_str, normalized=repr_str)

    def _change_basis(self, args: dict[str, Any]) -> Result:
        import xact.api as _api

        raw = _api.change_basis(
            str(args["expr"]),
            int(args["slot"]),
            str(args["from_basis"]),
            str(args["to_basis"]),
        )
        return Result(status="ok", type="Expr", repr=raw, normalized=_normalize(raw))

    def _get_jacobian(self, args: dict[str, Any]) -> Result:
        import xact.api as _api

        raw = _api.get_jacobian(str(args["basis1"]), str(args["basis2"]))
        return Result(status="ok", type="Scalar", repr=raw, normalized=raw)

    def _basis_change_q(self, args: dict[str, Any]) -> Result:
        import xact.api as _api

        ok = _api.basis_change_q(str(args["from_basis"]), str(args["to_basis"]))
        raw = "True" if ok else "False"
        return Result(status="ok", type="Bool", repr=raw, normalized=raw)

    def _set_components(self, args: dict[str, Any]) -> Result:
        import xact.api as _api

        tensor = str(args["tensor"])
        bases = [str(b) for b in args["bases"]]
        _api.set_components(tensor, list(args["array"]), bases, weight=int(args.get("weight", 0)))
        repr_str = f"CTensor({tensor}, {bases})"
        return Result(status="ok", type="Handle", repr=repr_str, normalized=repr_str)

    def _get_components(self, args: dict[str, Any]) -> Result:
        import xact.api as _api

        ct = _api.get_components(str(args["tensor"]), [str(b) for b in args["bases"]])
        raw = ct._julia_str or repr(ct)
        return Result(status="ok", type="Expr", repr=raw, normalized=raw)

    def _component_value(self, args: dict[str, Any]) -> Result:
        import xact.api as _api

        val = _api.component_value(
            str(args["tensor"]),
            [int(i) for i in args["indices"]],
            [str(b) for b in args["bases"]],
        )
        raw = str(val)
        return Result(status="ok", type="Scalar", repr=raw, normalized=raw)

    def _ctensor_q(self, args: dict[str, Any]) -> Result:
        import xact.api as _api

        ok = _api.ctensor_q(str(args["tensor"]), *[str(b) for b in args["bases"]])
        raw = "True" if ok else "False"
        return Result(status="ok", type="Bool", repr=raw, normalized=raw)

    def _to_basis(self, args: dict[str, Any]) -> Result:
        import xact.api as _api

        ct = _api.to_basis(str(args["expression"]), str(args["basis"]))
        raw = ct._julia_str or repr(ct)
        return Result(status="ok", type="Expr", repr=raw, normalized=raw)

    def _from_basis(self, args: dict[str, Any]) -> Result:
        import xact.api as _api

        raw = _api.from_basis(str(args["tensor"]), [str(b) for b in args["bases"]])
        return Result(status="ok", type="Expr", repr=raw, normalized=raw)

    def _trace_basis_dummy(self, args: dict[str, Any]) -> Result:
        import xact.api as _api

        ct = _api.trace_basis_dummy(str(args["tensor"]), [str(b) for b in args["bases"]])
        raw = ct._julia_str or repr(ct)
        return Result(status="ok", type="Expr", repr=raw, normalized=raw)

    def _christoffel(self, args: dict[str, Any]) -> Result:
        import xact.api as _api

        ct = _api.christoffel(
            str(args["metric"]),
            str(args["basis"]),
            metric_derivs=args.get("metric_derivs"),
        )
        raw = repr(ct)
        return Result(status="ok", type="Expr", repr=raw, normalized=raw)

    # ------------------------------------------------------------------
    # xTras actions
    # ------------------------------------------------------------------

    def _collect_tensors(self, args: dict[str, Any]) -> Result:
        import xact.api as _api

        s = _api.collect_tensors(str(args["expression"]))
        return Result(status="ok", type="String", repr=s, normalized=s)

    def _all_contractions(self, args: dict[str, Any]) -> Result:
        import xact.api as _api

        items = _api.all_contractions(str(args["expression"]), str(args["metric"]))
        s = ", ".join(items) if len(items) > 1 else (items[0] if items else "")
        return Result(status="ok", type="String", repr=s, normalized=s)

    def _symmetry_of(self, args: dict[str, Any]) -> Result:
        import xact.api as _api

        s = _api.symmetry_of(str(args["expression"]))
        return Result(status="ok", type="String", repr=s, normalized=s)

    def _make_trace_free(self, args: dict[str, Any]) -> Result:
        import xact.api as _api

        s = _api.make_trace_free(str(args["expression"]), str(args["metric"]))
        return Result(status="ok", type="String", repr=s, normalized=s)

    def _riemann_simplify(self, args: dict[str, Any]) -> Result:
        import xact.api as _api

        s = _api.riemann_simplify(
            str(args["expression"]), str(args["covd"]), level=int(args.get("level", 6))
        )
        return Result(status="ok", type="String", repr=s, normalized=_normalize(s))

    def _execute_expr(self, wolfram_expr: str) -> Result:
        julia_expr = _wl_to_jl(wolfram_expr)
        julia_expr = _postprocess_dimino(julia_expr)
        _bind_fresh_symbols(self._jl, julia_expr)
        _bind_wl_atoms(self._jl, julia_expr)
        try:
            # NOTE: seval with translator output — safety relies on _wl_to_jl
            # producing well-formed Julia. Will be addressed when translator is hardened.
            val = timed_seval(self._jl, julia_expr, label="execute_expr")
            # PythonCall adds "Julia: " prefix for custom types inside containers.
            # Strip it to get clean WL-compatible repr.
            raw = str(val).replace("Julia: ", "")
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
        # Check for tensor expression string comparisons first:
        # "$once == $twice" after binding substitution becomes two tensor expr strings.
        # These should be compared as strings, not evaluated as Julia.
        tensor_cmp = _try_tensor_string_comparison(wolfram_condition)
        if tensor_cmp is not None:
            passed, lhs_str, rhs_str = tensor_cmp
            if passed:
                return Result(status="ok", type="Bool", repr="True", normalized="True")
            msg = message or f"Assertion failed: {wolfram_condition!r}"
            return Result(
                status="error",
                type="Bool",
                repr=str(passed),
                normalized=str(passed),
                error=msg,
            )

        # Check for tensor // ToCanonical === value patterns (with optional || prefix).
        # These arise when the condition substitutes a tensor result and then
        # applies ToCanonical postfix, e.g.: "(Conv[coa] - Conv[coa]) // ToCanonical === 0"
        # Also handles: "TensorQ[$r] || ($r - Conw[-coa]) // ToCanonical === 0"
        to_canon_cmp = _try_to_canonical_comparison(wolfram_condition, self._jl)
        if to_canon_cmp is not None:
            passed, actual, expected = to_canon_cmp
            if passed:
                return Result(status="ok", type="Bool", repr="True", normalized="True")
            msg = message or f"Assertion failed: {wolfram_condition!r}"
            return Result(
                status="error",
                type="Bool",
                repr=str(passed),
                normalized=str(passed),
                error=msg,
            )

        julia_cond = _wl_to_jl(wolfram_condition)
        # If preprocessing reduced the condition to a trivially true "X == X" form,
        # return True immediately without calling Julia (avoids issues with unbound
        # symbol atoms that cannot be called as functions).
        if _is_trivially_equal(julia_cond):
            return Result(status="ok", type="Bool", repr="True", normalized="True")
        _bind_fresh_symbols(self._jl, julia_cond)
        _bind_wl_atoms(self._jl, julia_cond)
        try:
            # NOTE: seval with translator output — safety relies on _wl_to_jl
            # producing well-formed Julia. Will be addressed when translator is hardened.
            val = timed_seval(self._jl, julia_cond, label="execute_assert")
            passed = val is True or str(val).lower() == "true"
            if passed:
                return Result(status="ok", type="Bool", repr="True", normalized="True")
            # Assertion evaluated but returned false — this is a valid result,
            # not an error. Return status="ok" so snapshot comparators can
            # compare the "False" result against oracle snapshots.
            return Result(
                status="ok",
                type="Bool",
                repr="False",
                normalized="False",
            )
        except Exception as exc:
            # Julia evaluation threw — this is an infrastructure failure, not a
            # semantically false assertion.  Surface the error so callers (runner,
            # snapshot comparator) can distinguish crashes from logical failures.
            _log.warning(
                "Assert seval raised %s: %s (condition: %s)",
                type(exc).__name__,
                exc,
                wolfram_condition,
            )
            return Result(
                status="error",
                type="Bool",
                repr="False",
                normalized="False",
                error=f"{type(exc).__name__}: {exc}",
                diagnostics={"exception_type": type(exc).__name__},
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
        ctx: _JuliaContext | None = None,
    ) -> bool:
        # Tier 1 normalized string comparison only; semantic/numeric require oracle
        return a == b

    # ------------------------------------------------------------------
    # Introspection
    # ------------------------------------------------------------------

    def get_properties(self, expr: str, ctx: _JuliaContext | None = None) -> dict[str, Any]:
        return {}

    def get_version(self) -> VersionInfo:
        if self._jl is None:
            try:
                self._ensure_ready()
            except AdapterError:
                pass
        return VersionInfo(
            cas_name="Julia",
            cas_version=self._julia_version,
            adapter_version=f"0.1.0 (xAct {self._xact_version})",
        )

    def get_tensor_context(self, ctx: _JuliaContext, rng: Any | None = None) -> Any:
        """Build a TensorContext from the manifold/tensor state in *ctx*.

        Returns a :class:`~sxact.compare.sampling.TensorContext` populated with
        random component arrays for all tensors and metrics defined in this context.
        Pass the result to :func:`~sxact.compare.sampling.sample_numeric` for
        Tier 3 numeric comparison.

        Args:
            ctx: The active context (must have been used with ``DefManifold`` /
                 ``DefMetric`` / ``DefTensor`` calls).
            rng: Optional NumPy random generator for reproducibility.

        Returns:
            A ``TensorContext`` ready for substitution.
        """
        from sxact.compare.sampling import build_tensor_context

        return build_tensor_context(ctx._manifolds, ctx._metrics, ctx._tensors, rng=rng)


# ---------------------------------------------------------------------------
# Wolfram → Julia syntax translator
# ---------------------------------------------------------------------------


def _try_tensor_string_comparison(condition: str) -> tuple[bool, str, str] | None:
    """If `condition` is a tensor-expression string comparison, return (passed, lhs, rhs).

    Handles: "expr1 == expr2" where one or both sides are tensor expressions.
    Returns None if not a tensor expression comparison (use Julia eval instead).
    """
    # Only handle conditions of the form "lhs == rhs" (exactly one == that is not ===)
    # Split on " == " at top level
    parts = _top_level_split(condition, " == ")
    if len(parts) != 2:
        return None
    lhs, rhs = parts[0].strip(), parts[1].strip()
    # If either side is a tensor expression, do string comparison
    if _is_tensor_expr(lhs) or _is_tensor_expr(rhs):
        # Normalize both sides: strip whitespace, treat "0" == "0"
        lhs_n = _normalize(lhs)
        rhs_n = _normalize(rhs)
        return (lhs_n == rhs_n, lhs_n, rhs_n)
    return None


def _try_to_canonical_comparison(condition: str, jl: Any) -> tuple[bool, str, str] | None:
    """Handle conditions of the form: tensor_expr // ToCanonical === value.

    Also handles OR conditions: "clause1 || tensor_expr // ToCanonical === value"
    where ANY clause being true makes the whole condition true.

    Returns (passed, actual, expected) or None if the pattern doesn't match.
    """
    # If condition has top-level "||", split and try each part
    or_parts = _top_level_split(condition, " || ")
    if len(or_parts) > 1:
        any_matched = False
        # Try each clause; if any returns (True, ...) the whole thing passes
        for part in or_parts:
            part = part.strip()
            # Try ToCanonical comparison
            result = _try_single_to_canonical_comparison(part, jl)
            if result is not None:
                any_matched = True
                if result[0]:
                    return result
            # Try TensorQ[expr] — if expr is a tensor expression, check if tensor is registered
            tq_result = _try_tensor_q(part, jl)
            if tq_result is not None:
                any_matched = True
                if tq_result[0]:
                    return tq_result
            # Try simple string comparison
            tc_result = _try_tensor_string_comparison(part)
            if tc_result is not None:
                any_matched = True
                if tc_result[0]:
                    return tc_result
        if any_matched:
            return (False, "", "")
        return None

    return _try_single_to_canonical_comparison(condition, jl)


_TENSOR_Q_RE = re.compile(r"^TensorQ\[(\w+)(?:\[.*\])?\]$")


def _try_tensor_q(condition: str, jl: Any) -> tuple[bool, str, str] | None:
    """Handle TensorQ[TensorExpr] conditions.

    If the condition is TensorQ[Name[...]] or TensorQ[Name], checks if Name
    is a registered tensor via XTensor.TensorQ.

    Returns (True, "True", "True") if the tensor is registered, else None.
    """
    m = _TENSOR_Q_RE.match(condition.strip())
    if m is None:
        return None
    tensor_name = m.group(1)
    try:
        val = jl_call(jl, _JN_TENSOR_Q, jl_sym(tensor_name, "tensor name"))
        if val is True or str(val).lower() == "true":
            return (True, "True", "True")
        return (False, "False", "True")
    except Exception:
        return None


def _try_single_to_canonical_comparison(condition: str, jl: Any) -> tuple[bool, str, str] | None:
    """Handle a single (no ||) condition of the form: tensor_expr // ToCanonical === value."""
    # Pattern: something // ToCanonical === something_else
    # Split on " === " first to find the comparison value
    parts_strict = _top_level_split(condition, " === ")
    if len(parts_strict) != 2:
        return None

    lhs_raw, rhs_raw = parts_strict[0].strip(), parts_strict[1].strip()

    # LHS must contain "// ToCanonical" at the top level
    lhs_parts = _top_level_split(lhs_raw, " // ToCanonical")
    if len(lhs_parts) < 2:
        lhs_parts = _top_level_split(lhs_raw, "// ToCanonical")
    if len(lhs_parts) < 2:
        return None

    tensor_expr = lhs_parts[0].strip()
    # Strip outer parens from tensor_expr
    if tensor_expr.startswith("(") and tensor_expr.endswith(")"):
        tensor_expr = tensor_expr[1:-1].strip()

    # Must be a tensor expression
    if not _is_tensor_expr(tensor_expr):
        return None

    # Call XTensor.ToCanonical on the tensor expression
    try:
        result = str(jl_call(jl, _JN_TO_CANONICAL, jl_str(tensor_expr)))
    except Exception:
        return None

    # Compare result to rhs
    expected = rhs_raw.strip()
    actual_n = _normalize(result)
    expected_n = _normalize(expected)
    return (actual_n == expected_n, actual_n, expected_n)


# Regex matching fresh property-test symbols generated by property_runner.py.
# Pattern: "px" + one-or-more uppercase letters + generator name (lowercase) + suffix (lowercase).
# Examples: pxBAGsbq, pxKBIsbr, pxBKYsbt, pxLYPabu
_FRESH_SYMBOL_RE = re.compile(r"\bpx[A-Z]+[a-z]+\b")

# Regex matching the property runner's numerical_tolerance comparison expression.
_NUMERICAL_TOL_RE = re.compile(r"^Max\[Abs\[Flatten\[N\[(.+)\]\]\]\]$", re.DOTALL)

# XTensor functions that take a string argument and return a string result.
_XPERM_STRING_FUNCS = ("ToCanonical", "Contract")


def _preprocess_xperm_calls(jl: Any, expr: str) -> str:
    """Recursively evaluate ToCanonical[...] and Contract[...] calls in expr.

    Replaces each such call with its Julia string result so that the
    remaining expression can be passed to XTensor.ToCanonical for final
    canonicalization.
    """
    _MAX_PREPROCESS_ITERS = 50
    for func_name in _XPERM_STRING_FUNCS:
        func_prefix = func_name + "["
        iters = 0
        while func_prefix in expr:
            iters += 1
            if iters > _MAX_PREPROCESS_ITERS:
                _log.warning(
                    "Exceeded %d iterations preprocessing %s calls; breaking",
                    _MAX_PREPROCESS_ITERS,
                    func_name,
                )
                break
            pos = expr.find(func_prefix)
            start = pos + len(func_prefix)
            depth = 1
            i = start
            while i < len(expr) and depth > 0:
                if expr[i] == "[":
                    depth += 1
                elif expr[i] == "]":
                    depth -= 1
                i += 1
            inner = expr[start : i - 1]
            # Recursively preprocess the inner expression first
            inner_processed = _preprocess_xperm_calls(jl, inner)
            try:
                result = str(jl_call(jl, f"XTensor.{func_name}", jl_str(inner_processed)))
            except Exception:
                # If preprocessing fails, leave the call in place
                break
            expr = expr[:pos] + result + expr[i:]
    return expr


def _try_numerical_tolerance_via_canonical(jl: Any, wolfram_expr: str) -> Result | None:
    """Intercept Max[Abs[Flatten[N[(lhs) - (rhs)]]]] for tensor expressions.

    The property runner generates this pattern for numerical_tolerance checks.
    For the Julia symbolic adapter, we instead apply ToCanonical to the
    difference expression.  If the result is "0" (the tensors are equal by
    symmetry), return "0.0" (passes the < tolerance check).

    Returns None if the expression doesn't match the pattern or if we cannot
    determine a canonical result.
    """
    m = _NUMERICAL_TOL_RE.match(wolfram_expr.strip())
    if not m:
        return None
    inner = m.group(1).strip()
    if not _is_tensor_expr(inner):
        return None

    # Use inner directly as diff_expr.
    # The property runner always generates (lhs) - (rhs), and XTensor._parse_sum!
    # has paren-depth tracking so it handles nested paren groups correctly.
    # Stripping parens from a multi-term rhs would lose sign distribution
    # (e.g. "(T+S) - (S+T)" → "T+S - S+T = 2T" instead of 0).
    diff_expr = inner

    # Preprocess any nested ToCanonical/Contract calls
    try:
        preprocessed = _preprocess_xperm_calls(jl, diff_expr)
    except Exception:
        preprocessed = diff_expr

    # Apply ToCanonical to the whole difference
    try:
        result = str(jl_call(jl, _JN_TO_CANONICAL, jl_str(preprocessed)))
    except Exception:
        return None

    if result == "0":
        return Result(status="ok", type="Float", repr="0.0", normalized="0.0")

    # Try to interpret as a numeric value (e.g. if all terms cancel to a number)
    try:
        float(result)
        return Result(status="ok", type="Float", repr=result, normalized=result)
    except ValueError:
        pass

    return None


# Julia reserved keywords that must NOT be re-bound as Symbols.
_JULIA_KEYWORDS: frozenset[str] = frozenset(
    {
        "abstract",
        "baremodule",
        "begin",
        "break",
        "catch",
        "const",
        "continue",
        "do",
        "else",
        "elseif",
        "end",
        "export",
        "false",
        "finally",
        "for",
        "function",
        "global",
        "if",
        "import",
        "in",
        "isa",
        "let",
        "local",
        "macro",
        "module",
        "mutable",
        "new",
        "nothing",
        "primitive",
        "quote",
        "return",
        "struct",
        "true",
        "try",
        "type",
        "using",
        "where",
        "while",
    }
)

# Identifiers that are known Julia built-in names and should not be shadowed.
_JULIA_BUILTINS: frozenset[str] = frozenset(
    {
        "length",
        "unique",
        "string",
        "println",
        "print",
        "show",
        "collect",
        "filter",
        "map",
        "push",
        "pop",
        "sort",
        "sum",
        "prod",
        "any",
        "all",
        "issubset",
        "in",
        "vcat",
        "hcat",
        "first",
        "last",
        "isempty",
        "empty",
        "haskey",
        "get",
        "Dict",
        "Set",
        "Vector",
        "Matrix",
        "Tuple",
        "Array",
        "Int",
        "Float64",
        "Bool",
        "Symbol",
        "String",
        "Expr",
        "Nothing",
    }
)

# Regex to find all identifiers in a Julia expression (not inside strings).
_IDENTIFIER_RE = re.compile(r"\b([A-Za-z_]\w*)\b")

# Mapping from WL built-in head names to the Julia operator Symbol they correspond to.
# Used when MemberQ checks reference WL operator names like Plus, Times, etc.,
# but FindSymbols returns Julia operator Symbols like :+, :*, etc.
_WL_OP_TO_JULIA: dict[str, str] = {
    "Plus": "+",
    "Times": "*",
    "Power": "^",
    "Subtract": "-",
    "Divide": "/",
}


def _bind_wl_atoms(jl: Any, julia_expr: str) -> None:
    """Bind WL atom-like identifiers in *julia_expr* as Julia Symbols in Main.

    Scans the expression for identifiers that:
    1. Are NOT Julia keywords or known built-in names
    2. Are NOT followed by ``(`` (i.e., not function calls)
    3. Are NOT inside string literals

    These are treated as WL symbolic atoms and pre-bound as Julia Symbols
    (``Main.x = :x``) so that functions like ``SubHead``, ``NoPattern``,
    ``MemberQ``, and ``FindSymbols`` receive the right types.

    This is idempotent: re-binding an already-bound symbol is harmless.
    """
    # Scan token by token, skipping string literals
    expr = julia_expr
    n = len(expr)
    i = 0
    candidates: set[str] = set()
    while i < n:
        ch = expr[i]
        # Skip string literals
        if ch == '"':
            i += 1
            while i < n:
                if expr[i] == "\\":
                    i += 2
                    continue
                if expr[i] == '"':
                    i += 1
                    break
                i += 1
            continue
        # Identifier token
        if ch.isalpha() or ch == "_":
            j = i
            while j < n and (expr[j].isalnum() or expr[j] == "_"):
                j += 1
            name = expr[i:j]
            # Skip if followed by ( — that's a function call, not an atom
            k = j
            while k < n and expr[k] == " ":
                k += 1
            if k < n and expr[k] == "(":
                i = j
                continue
            # Skip Julia keywords and known built-ins
            if name in _JULIA_KEYWORDS or name in _JULIA_BUILTINS:
                i = j
                continue
            # Skip numeric literals start (shouldn't happen here but be safe)
            if name[0].isdigit():
                i = j
                continue
            candidates.add(name)
            i = j
            continue
        i += 1

    for sym in candidates:
        try:
            # Only bind if the symbol is not already defined in Julia Main.
            # This prevents overwriting Perm/tensor objects defined during setup.
            already_defined = bool(jl.seval(f"isdefined(Main, :{sym})"))
            if already_defined:
                continue
            if sym in _WL_OP_TO_JULIA:
                # WL operator head name (e.g. Plus) → Julia operator Symbol (e.g. :+)
                julia_sym = _WL_OP_TO_JULIA[sym]
                jl.seval(f'Main.eval(:(global {sym} = Symbol("{julia_sym}")))')
            else:
                jl.seval(f"Main.eval(:(global {sym} = :{sym}))")
        except Exception:
            pass  # If binding fails, skip — symbol may already be defined correctly


def _bind_fresh_symbols(jl: Any, julia_expr: str) -> None:
    """Bind any fresh property-test symbols found in *julia_expr* as Julia Symbols in Main.

    The property runner generates names like ``pxBAGsbq`` (lowercase-start, prefixed
    with ``px`` + uppercase block).  These are unknown Julia identifiers and cause
    ``UndefVarError`` if evaluated directly.  We pre-bind each one as the corresponding
    Julia Symbol (``Main.pxBAGsbq = :pxBAGsbq``) so XCore functions that accept
    ``Symbol`` arguments receive the right value.
    """
    for sym in _FRESH_SYMBOL_RE.findall(julia_expr):
        try:
            already_defined = bool(jl.seval(f"isdefined(Main, :{sym})"))
            if not already_defined:
                jl.seval(f"Main.eval(:(global {sym} = :{sym}))")
        except Exception:
            pass


_WL_KEYWORDS: dict[str, str] = {
    "True": "true",
    "False": "false",
    "Null": "nothing",
    "Length": "length",
}

# Regex that matches tensor index notation.
# Two patterns combined (either is sufficient):
#   1. `-[a-z]`         — covariant index: Sps[-spa], Riemann[-a,-b]
#   2. `\w+\[[a-z]{2,}` — contravariant multi-letter index: Conv[coa], QGTorsion[qga,...]
# xPerm uses integers, single-letter lowercase, or capitalized names — none match.
_TENSOR_EXPR_RE = re.compile(r"-[a-z]|\w+\[[a-z]{2,}")


def _is_tensor_expr(expr: str) -> bool:
    """True if the expression looks like a tensor algebra expression (not a Julia predicate)."""
    return bool(_TENSOR_EXPR_RE.search(expr))


def _top_level_split(s: str, sep: str) -> list[str]:
    """Split `s` on `sep` but only at depth 0 (not inside brackets or strings)."""
    parts: list[str] = []
    depth = 0
    in_string = False
    string_char = ""
    current: list[str] = []
    i = 0
    n = len(s)
    while i < n:
        ch = s[i]
        # Track string literals (single or double quotes)
        if ch in ('"', "'") and not in_string:
            in_string = True
            string_char = ch
            current.append(ch)
        elif in_string and ch == string_char:
            in_string = False
            current.append(ch)
        elif in_string:
            current.append(ch)
        elif ch in "([{":
            depth += 1
            current.append(ch)
        elif ch in ")]}":
            depth -= 1
            current.append(ch)
        elif s[i : i + len(sep)] == sep and depth == 0:
            parts.append("".join(current))
            current = []
            i += len(sep)
            continue
        else:
            current.append(ch)
        i += 1
    parts.append("".join(current))
    return parts


def _rewrite_postfix(expr: str) -> str:
    """Rewrite Wolfram postfix // operator: 'expr // f' → 'f(expr)'.

    Handles top-level occurrences only (not inside brackets).
    Multiple chained applications are handled left-to-right.
    """
    # Find top-level // occurrences (not inside brackets)
    while True:
        depth = 0
        pos = -1
        for i, ch in enumerate(expr):
            if ch in "([{":
                depth += 1
            elif ch in ")]}":
                depth -= 1
            elif ch == "/" and depth == 0 and i + 1 < len(expr) and expr[i + 1] == "/":
                pos = i
                break
        if pos == -1:
            break
        lhs = expr[:pos].rstrip()
        rhs = expr[pos + 2 :].lstrip()
        # rhs should be a function name (possibly with args), or just a name
        # Wrap: f(lhs) if rhs is a bare name; f(lhs, ...) if rhs has args
        m = re.match(r"^([A-Za-z_]\w*)$", rhs)
        if m:
            expr = f"{rhs}({lhs})"
        else:
            # Could be SubsetQ[...] or similar — just wrap the lhs as first arg
            expr = f"({lhs}) |> {rhs}"
        break  # one pass
    return expr


_SCHREIER_ORBIT_RE = re.compile(r"SchreierOrbit\[([^,\[]+),\s*GenSet\[([^\]]+)\],\s*([^\]]+)\]")
_SCHREIER_ORBITS_RE = re.compile(r"SchreierOrbits\[GenSet\[([^\]]+)\],\s*([^\]]+)\]")

# Post-process Dimino after WL→Julia translation.
# Matches: Dimino(GenSet(g1, g2, ...))
# Captures the comma-separated generator names after Julia translation.
_DIMINO_GENSET_POST_RE = re.compile(r"\bDimino\(GenSet\(([^)]+)\)\)")


def _postprocess_dimino(julia_expr: str) -> str:
    """Inject name registry into Dimino(GenSet(...)) calls (post WL→Julia translation).

    Dimino(GenSet(g1, g2, ...)) → Dimino(GenSet(g1, g2, ...), ["g1"=>g1, "g2"=>g2, ...])
    """

    def replace_dimino(m: re.Match[str]) -> str:
        gens_str = m.group(1).strip()
        gen_names = [g.strip() for g in gens_str.split(",")]
        pairs = ", ".join(f'"{nm}"=>{nm}' for nm in gen_names)
        return f"Dimino(GenSet({gens_str}), [{pairs}])"

    return _DIMINO_GENSET_POST_RE.sub(replace_dimino, julia_expr)


# WL pattern notation: strip Blank/BlankSequence/BlankNullSequence suffixes.
# Matches: word_Type, word__, word_, word___ (in that priority order).
# The pattern must start with a lowercase letter (WL pattern variable convention)
# followed by one or more underscores and an optional uppercase-starting type name.
# Examples: x_ → x, x_Integer → x, x__ → x, y___ → y, myVar_Real → myVar
# We avoid stripping uppercase symbols like _Symbol (bare blank), which are
# handled separately.  The capture group [a-z][a-zA-Z0-9]* excludes underscores
# so x__/x___ are fully stripped.  The (?![a-z]) lookahead prevents matching
# underscores in snake_case Julia names like check_perturbation_order.
_WL_PATTERN_RE = re.compile(r"\b([a-z][a-zA-Z0-9]*)_+(?![a-z])(?:[A-Z]\w*)?")

_PREFIX_AT_RE = re.compile(r"(\b[A-Za-z_]\w*)\s*@(?!@)")


def _preprocess_prefix_at(expr: str) -> str:
    """Transform WL prefix application f@expr → f[expr].

    WL's single ``@`` is prefix function application: ``f@x = f[x]``.
    We convert to bracket notation so the main character-pass in ``_wl_to_jl``
    can then translate ``f[...]`` → ``f(...)``.
    We only replace ``@`` that immediately follows an identifier (not ``@@``).
    """
    # Strategy: find each `identifier@` and wrap the following expression
    # in WL brackets. Since the following expression is always a balanced
    # sub-expression (identifier, function-call, or bracketed list) we can
    # scan forward to find the end.
    result = []
    i = 0
    n = len(expr)
    while i < n:
        m = _PREFIX_AT_RE.search(expr, i)
        if m is None:
            result.append(expr[i:])
            break
        result.append(expr[i : m.start()])
        func_name = m.group(1)
        result.append(func_name)
        result.append("[")
        j = m.end()  # position after the @
        # Find the end of the following expression (one balanced token)
        # Skip whitespace
        while j < n and expr[j] == " ":
            j += 1
        if j < n and expr[j] in "([{":
            # Balanced bracket: copy until matching close
            open_ch = expr[j]
            close_ch = {"(": ")", "[": "]", "{": "}"}[open_ch]
            depth = 1
            result.append(expr[j])
            j += 1
            while j < n and depth > 0:
                if expr[j] == open_ch:
                    depth += 1
                elif expr[j] == close_ch:
                    depth -= 1
                result.append(expr[j])
                j += 1
        else:
            # Identifier or number: copy until non-identifier char,
            # then include any immediately following bracket expression
            k = j
            while k < n and (expr[k].isalnum() or expr[k] == "_"):
                k += 1
            result.append(expr[j:k])
            j = k
            # If followed by a bracket, include it too
            if j < n and expr[j] in "([{":
                open_ch = expr[j]
                close_ch = {"(": ")", "[": "]", "{": "}"}[open_ch]
                depth = 1
                result.append(expr[j])
                j += 1
                while j < n and depth > 0:
                    if expr[j] == open_ch:
                        depth += 1
                    elif expr[j] == close_ch:
                        depth -= 1
                    result.append(expr[j])
                    j += 1
        result.append("]")
        i = j
    return "".join(result)


def _preprocess_apply_op(expr: str) -> str:
    """Transform f @@ {a, b, c} → f(a, b, c) (WL Apply with list).

    `f @@ {a, b, c}` in Wolfram is equivalent to `f[a, b, c]`.
    We convert to `f(a, b, c)` so that Julia sees a normal function call.
    The inner WL list `{a, b, c}` is replaced with `(a, b, c)` (the content
    without outer braces), and `_wl_to_jl` continues to translate any
    remaining WL syntax inside.
    """
    result: list[str] = []
    i = 0
    n = len(expr)
    while i < n:
        if i + 1 < n and expr[i : i + 2] == "@@":
            j = i + 2
            while j < n and expr[j] == " ":
                j += 1
            if j < n and expr[j] == "{":
                # Find matching closing }
                depth = 1
                k = j + 1
                while k < n and depth > 0:
                    if expr[k] in "{[":
                        depth += 1
                    elif expr[k] in "}]":
                        depth -= 1
                    k += 1
                # Strip trailing whitespace before @@ so f @@ {args} → f(args)
                while result and result[-1] == " ":
                    result.pop()
                # Replace @@ {inner} with (inner)
                inner = expr[j + 1 : k - 1]
                result.append("(")
                result.append(inner)
                result.append(")")
                i = k
                continue
            # @@ followed by arbitrary expression: f @@ expr → f(expr...)
            while result and result[-1] == " ":
                result.pop()
            k = j
            depth = 0
            while k < n:
                if expr[k] in "([{":
                    depth += 1
                elif expr[k] in ")]}":
                    if depth == 0:
                        break
                    depth -= 1
                k += 1
            inner = expr[j:k]
            result.append("(")
            result.append(inner)
            result.append("...)")
            i = k
            continue
        result.append(expr[i])
        i += 1
    return "".join(result)


# WL machine-precision backtick notation: 1.234`5.678\ Second → 1.234
# Covers both forms: with precision digits (1.23`4.56\ Unit) and without (1.23`\ Unit)
_WL_BACKTICK_RE = re.compile(r"(\d+\.\d+)`[\d.]*\\?\s*\w*")

# WL list destructuring: {a, b} = expr  →  (a, b) = expr
# Only matches bare-identifier LHS (no nested braces) followed by = not ==
_WL_DESTRUCT_RE = re.compile(r"\{([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)\}\s*(=)(?!=)")


def _preprocess_timing_destruct(expr: str) -> str:
    """Transform WL list destructuring {a, b, ...} = expr → (a, b, ...) = expr."""
    return _WL_DESTRUCT_RE.sub(lambda m: f"({m.group(1)}) {m.group(2)}", expr)


def _preprocess_schreier_orbit(expr: str) -> str:
    """Transform SchreierOrbit/SchreierOrbits calls to inject generator names.

    SchreierOrbit[pt, GenSet[g1,...], n]  →  SchreierOrbit(pt, [g1,...], n, ["g1",...])
    SchreierOrbits[GenSet[g1,...], n]     →  SchreierOrbits([g1,...], n, ["g1",...])
    """

    def replace_single(m: re.Match[str]) -> str:
        pt = m.group(1).strip()
        gens = m.group(2).strip()
        n = m.group(3).strip()
        gen_names = [g.strip() for g in gens.split(",")]
        names_arr = "[" + ", ".join(f'"{name}"' for name in gen_names) + "]"
        gens_arr = "[" + ", ".join(gen_names) + "]"
        return f"SchreierOrbit({pt}, {gens_arr}, {n}, {names_arr})"

    def replace_multi(m: re.Match[str]) -> str:
        gens = m.group(1).strip()
        n = m.group(2).strip()
        gen_names = [g.strip() for g in gens.split(",")]
        names_arr = "[" + ", ".join(f'"{name}"' for name in gen_names) + "]"
        gens_arr = "[" + ", ".join(gen_names) + "]"
        return f"SchreierOrbits({gens_arr}, {n}, {names_arr})"

    expr = _SCHREIER_ORBITS_RE.sub(replace_multi, expr)
    expr = _SCHREIER_ORBIT_RE.sub(replace_single, expr)
    return expr


def _preprocess_wl_patterns(expr: str) -> str:
    """Strip WL pattern (Blank) notation from identifiers.

    Converts WL pattern variables to their base symbol name:
    - ``x_``        → ``x``   (Blank pattern)
    - ``x_Integer`` → ``x``   (typed Blank pattern)
    - ``x__``       → ``x``   (BlankSequence)
    - ``x___``      → ``x``   (BlankNullSequence)

    Only strips from lowercase-starting identifiers (WL pattern variable
    convention).  Uppercase-only identifiers like ``_Symbol`` (bare blanks)
    are untouched — they are handled separately (e.g. the ``Cases`` rewrite).
    """
    return _WL_PATTERN_RE.sub(r"\1", expr)


def _wl_subhead(wl_arg: str) -> str:
    """Extract the outermost function head from a WL expression string.

    For ``f[x, y]`` → ``"f"``.
    For ``f[g[x]]`` → ``"f"``.
    For a bare symbol ``x`` → ``"x"``.

    Used to rewrite ``SubHead[f[x]]`` → ``:f`` in Julia without needing to
    construct a Julia Expr from bound symbols.
    """
    wl_arg = wl_arg.strip()
    # Find the first [ — everything before it is the head
    pos = wl_arg.find("[")
    if pos == -1:
        # Bare atom: SubHead[x] === x → head is x itself
        return wl_arg
    return wl_arg[:pos]


def _is_trivially_equal(julia_cond: str) -> bool:
    """Return True if *julia_cond* is syntactically of the form ``X == X``.

    After WL pattern stripping and NoPattern/SubHead preprocessing, some
    conditions reduce to ``f(x, y) == f(x, y)`` where both sides are identical.
    These cannot be evaluated in Julia when ``f`` is a Symbol (not callable),
    but they are trivially true by syntactic identity.

    Handles ``==`` (from ``===``) and ``&&``/``||`` conjunctions of trivially
    equal clauses.
    """
    julia_cond = julia_cond.strip()
    # Split on == at top level
    parts = _top_level_split(julia_cond, " == ")
    if len(parts) == 2:
        return parts[0].strip() == parts[1].strip()
    return False


def _preprocess_nopattern(expr: str) -> str:
    """Replace ``NoPattern[...]`` with its argument (NoPattern is identity).

    In WL, ``NoPattern[x_]`` strips the pattern wrapper and returns ``x``.
    After ``_preprocess_wl_patterns`` has already stripped ``x_`` → ``x``,
    ``NoPattern[x]`` is equivalent to ``x``.  This preprocessor removes the
    ``NoPattern[...]`` wrapper so the remaining expression evaluates correctly
    in Julia without needing to call a function on a potentially unbound symbol.

    Must be applied AFTER ``_preprocess_wl_patterns`` so that pattern
    variables like ``x_`` are already reduced to ``x``.
    """
    result: list[str] = []
    i = 0
    n = len(expr)
    while i < n:
        if expr[i : i + 10] == "NoPattern[":
            # Find the matching ]
            depth = 1
            j = i + 10
            while j < n and depth > 0:
                if expr[j] == "[":
                    depth += 1
                elif expr[j] == "]":
                    depth -= 1
                j += 1
            # Replace NoPattern[inner] with just inner
            inner = expr[i + 10 : j - 1]
            result.append(inner)
            i = j
            continue
        result.append(expr[i])
        i += 1
    return "".join(result)


def _preprocess_subhead(expr: str) -> str:
    """Rewrite ``SubHead[...]`` in WL notation to a Julia Symbol literal.

    ``SubHead[f[x]]``   → ``:f``
    ``SubHead[f[g[x]]]`` → ``:f``
    ``SubHead[x]``       → ``:x``

    This avoids the impossible Julia translation of ``SubHead(f(x))`` when
    ``f`` is a Symbol (calling a Symbol as a function is invalid in Julia).

    The rewrite happens before the main WL→Julia translation so the resulting
    ``:name`` literal passes through the character loop unchanged.
    """
    result: list[str] = []
    i = 0
    n = len(expr)
    while i < n:
        # Look for SubHead[
        if expr[i : i + 8] == "SubHead[":
            # Find the matching ]
            depth = 1
            j = i + 8
            while j < n and depth > 0:
                if expr[j] == "[":
                    depth += 1
                elif expr[j] == "]":
                    depth -= 1
                j += 1
            inner = expr[i + 8 : j - 1]
            head = _wl_subhead(inner)
            result.append(f":{head}")
            i = j
            continue
        result.append(expr[i])
        i += 1
    return "".join(result)


def _wl_to_jl(expr: str) -> str:
    """Translate basic Wolfram xCore notation to Julia syntax.

    Handles:
    - f[args] → f(args)          (function application)
    - {a, b}  → [a, b]           (list literals)
    - ===     → ==                (structural equality → value equality)
    - True / False / Null → true / false / nothing
    - expr // f → f(expr)         (Wolfram postfix application)
    - $Name   → Name              (dollar-prefix strip)
    - SubsetQ[A, B] → issubset(B, A)  (note: args reversed in Julia)
    - \\[Equal] → ==              (Wolfram Unicode Equal operator)
    - SchreierOrbit[pt, GenSet[g1,...], n] → SchreierOrbit(pt, [...], n, ["g1",...])
    - x_, x_Type patterns → x    (WL pattern notation stripped)

    Abstract Wolfram symbols used as atoms (e.g. ``a``, ``b``) are left
    as-is; they will cause Julia ``UndefVarError`` for tests that rely on
    Wolfram's symbolic algebra — those tests correctly fail in Julia.
    """
    # Pre-process SubHead[f[x]] → :f (extract outermost WL head as a Julia Symbol).
    # Must run before pattern stripping and bracket translation so that f[x]
    # is still in WL notation when the head is extracted.
    expr = _preprocess_subhead(expr)

    # Pre-process WL pattern notation: x_ → x, x_Integer → x, etc.
    # Must run before NoPattern expansion and other passes.
    expr = _preprocess_wl_patterns(expr)

    # Pre-process NoPattern[...] → its argument (NoPattern is identity).
    # Must run after _preprocess_wl_patterns so x_ has been reduced to x.
    expr = _preprocess_nopattern(expr)

    # Pre-process WL prefix @: f@expr → f[expr] (f @ g returns f applied to g).
    # This must run before Apply @@ handling.
    expr = _preprocess_prefix_at(expr)

    # Pre-process Apply @@ operator: f @@ {a,b,c} → f(a,b,c)
    expr = _preprocess_apply_op(expr)

    # Pre-process SchreierOrbit to inject generator names before main translation
    expr = _preprocess_schreier_orbit(expr)

    # Pre-process WL list destructuring {a, b} = expr → (a, b) = expr
    expr = _preprocess_timing_destruct(expr)

    # Strip WL machine-precision backtick notation: 1.234`5.678\ Second → 1.234
    expr = _WL_BACKTICK_RE.sub(r"\1", expr)

    # Handle Wolfram Unicode operator escapes
    expr = expr.replace("\\[Equal]", "==")
    # WL Rule infix: a -> b → a => b (Pair), but NOT inside strings
    # Also handle :> (RuleDelayed)
    expr = expr.replace(":>", "=>")
    # Only convert -> that isn't part of --> or other patterns
    expr = re.sub(r"(?<![=-])->(?!>)", "=>", expr)

    # Handle // postfix operator: rewrite "expr // f" → "f(expr)"
    # Apply before other translations to restructure correctly.
    # This is a simple left-to-right rewrite (handles one level of nesting).
    expr = _rewrite_postfix(expr)

    # Strip dollar-prefix from $Name patterns
    expr = re.sub(r"\$([A-Za-z_]\w*)", r"\1", expr)

    # Replace === before the character pass so the placeholder is unambiguous
    expr = expr.replace("===", "\x00")

    out: list[str] = []
    i = 0
    n = len(expr)
    stack: list[str] = []  # "call" or "list"

    while i < n:
        ch = expr[i]

        # String literals — pass through verbatim (no translation inside)
        if ch == '"':
            j = i + 1
            while j < n:
                if expr[j] == "\\":
                    j += 2
                    continue
                if expr[j] == '"':
                    break
                j += 1
            out.append(expr[i : j + 1])
            i = j + 1
            continue

        # Identifier: may be a keyword-mapped name or a function call
        # Include ⁀ (U+2040 tie) for WL SymbolJoin compound names
        if ch.isalpha() or ch == "_":
            j = i
            while j < n and (expr[j].isalnum() or expr[j] in ("_", "\u2040")):
                j += 1
            name = expr[i:j]
            if j < n and expr[j] == "[":
                if name == "SubsetQ":
                    # SubsetQ[A, B] → issubset(B, A): reverse args, emit placeholder
                    # Find the matching ]
                    depth2 = 1
                    k = j + 1
                    while k < n and depth2 > 0:
                        if expr[k] == "[":
                            depth2 += 1
                        elif expr[k] == "]":
                            depth2 -= 1
                        k += 1
                    inner = expr[j + 1 : k - 1]
                    # Split on top-level comma
                    parts = _top_level_split(inner, ",")
                    if len(parts) == 2:
                        a_jl = _wl_to_jl(parts[0].strip())
                        b_jl = _wl_to_jl(parts[1].strip())
                        out.append(f"issubset({b_jl}, {a_jl})")
                    else:
                        out.append(f"issubset({_wl_to_jl(inner)})")
                    i = k
                elif name == "Cases":
                    # Cases[expr, _Symbol, Infinity] → FindSymbols(expr)
                    # This handles the WL pattern-matching form used in xCore property tests.
                    depth2 = 1
                    k = j + 1
                    while k < n and depth2 > 0:
                        if expr[k] == "[":
                            depth2 += 1
                        elif expr[k] == "]":
                            depth2 -= 1
                        k += 1
                    inner = expr[j + 1 : k - 1]
                    parts = _top_level_split(inner, ",")
                    # Check for the _Symbol pattern: Cases[expr, _Symbol, Infinity]
                    if (
                        len(parts) == 3
                        and parts[1].strip() == "_Symbol"
                        and parts[2].strip() == "Infinity"
                    ):
                        out.append(f"FindSymbols({_wl_to_jl(parts[0].strip())})")
                    else:
                        # Generic fallback: emit as regular function call
                        out.append(f"Cases({_wl_to_jl(inner)})")
                    i = k
                elif name == "StringQ":
                    # StringQ[x] → isa(x, String)
                    depth2 = 1
                    k = j + 1
                    while k < n and depth2 > 0:
                        if expr[k] == "[":
                            depth2 += 1
                        elif expr[k] == "]":
                            depth2 -= 1
                        k += 1
                    inner = _wl_to_jl(expr[j + 1 : k - 1].strip())
                    out.append(f"isa({inner}, String)")
                    i = k
                elif name == "StringLength":
                    # StringLength[x] → length(x)
                    depth2 = 1
                    k = j + 1
                    while k < n and depth2 > 0:
                        if expr[k] == "[":
                            depth2 += 1
                        elif expr[k] == "]":
                            depth2 -= 1
                        k += 1
                    inner = _wl_to_jl(expr[j + 1 : k - 1].strip())
                    out.append(f"length({inner})")
                    i = k
                elif name == "Catch":
                    # Catch[expr] → try expr catch e nothing end
                    depth2 = 1
                    k = j + 1
                    while k < n and depth2 > 0:
                        if expr[k] == "[":
                            depth2 += 1
                        elif expr[k] == "]":
                            depth2 -= 1
                        k += 1
                    inner = _wl_to_jl(expr[j + 1 : k - 1].strip())
                    out.append(f"try {inner} catch e nothing end")
                    i = k
                elif name == "ClearAll":
                    # ClearAll[syms...] → nothing (no-op in Julia)
                    depth2 = 1
                    k = j + 1
                    while k < n and depth2 > 0:
                        if expr[k] == "[":
                            depth2 += 1
                        elif expr[k] == "]":
                            depth2 -= 1
                        k += 1
                    out.append("nothing")
                    i = k
                elif name in ("Rule", "RuleDelayed"):
                    # Rule[key, val] → (key => val)
                    depth2 = 1
                    k = j + 1
                    while k < n and depth2 > 0:
                        if expr[k] == "[":
                            depth2 += 1
                        elif expr[k] == "]":
                            depth2 -= 1
                        k += 1
                    inner = expr[j + 1 : k - 1]
                    parts = _top_level_split(inner, ",")
                    if len(parts) == 2:
                        lhs = _wl_to_jl(parts[0].strip())
                        rhs = _wl_to_jl(parts[1].strip())
                        out.append(f"({lhs} => {rhs})")
                    else:
                        out.append(f"Rule({_wl_to_jl(inner)})")
                    i = k
                elif name == "Head":
                    # Head[x] → typeof(x) (approximate WL Head)
                    depth2 = 1
                    k = j + 1
                    while k < n and depth2 > 0:
                        if expr[k] == "[":
                            depth2 += 1
                        elif expr[k] == "]":
                            depth2 -= 1
                        k += 1
                    inner = _wl_to_jl(expr[j + 1 : k - 1].strip())
                    out.append(f"typeof({inner})")
                    i = k
                else:
                    # Function call: translate name if keyword-mapped, then emit name(
                    translated = _WL_KEYWORDS.get(name, name)
                    out.append(translated + "(")
                    stack.append("call")
                    i = j + 1
            else:
                translated = _WL_KEYWORDS.get(name, name)
                # Names with ⁀ need Symbol("...") syntax in Julia
                if "\u2040" in translated:
                    out.append(f'Symbol("{translated}")')
                else:
                    out.append(translated)
                i = j
            continue

        # List open {
        if ch == "{":
            out.append("[")
            stack.append("list")
            i += 1
            continue

        # List close }
        if ch == "}":
            out.append("]")
            if stack and stack[-1] == "list":
                stack.pop()
            i += 1
            continue

        # Close bracket ] — closes a function call or a bare list
        if ch == "]":
            if stack and stack[-1] == "call":
                out.append(")")
                stack.pop()
            else:
                out.append("]")
                if stack and stack[-1] == "list":
                    stack.pop()
            i += 1
            continue

        # Bare open bracket [ (shouldn't appear in Wolfram, but handle safely)
        if ch == "[":
            out.append("[")
            stack.append("list")
            i += 1
            continue

        # Equality placeholder (was ===)
        if ch == "\x00":
            out.append("==")
            i += 1
            continue

        out.append(ch)
        i += 1

    return "".join(out)
