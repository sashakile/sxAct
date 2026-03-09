"""JuliaAdapter — concrete adapter backed by Julia XCore/XTensor via juliacall.

Uses the Python xCore runtime (_runtime.py) to lazily initialise Julia and
load XCore.jl once per process.  Evaluates Julia expressions translated from
the TOML test vocabulary (Wolfram → Julia syntax).

Per-file isolation is achieved by resetting XCore and XTensor global state on
teardown.

Actions that require xTensor (DefManifold, DefMetric, DefTensor, ToCanonical,
Contract, SignDetOfMetric) are now dispatched to the Julia XTensor module.
Simplify remains deferred (Tier 2).
"""

from __future__ import annotations

import re
import threading
from pathlib import Path
from typing import Any

from sxact.adapter.base import (
    AdapterError,
    EqualityMode,
    NormalizedExpr,
    TestAdapter,
    VersionInfo,
)
from sxact.normalize import normalize as _normalize
from sxact.oracle.result import Result


# ---------------------------------------------------------------------------
# XTensor lazy loader
# ---------------------------------------------------------------------------

_xtensor_lock = threading.Lock()
_xtensor_loaded = False


def _get_xtensor(jl: Any) -> None:
    """Load XPerm.jl and XTensor.jl into Julia (idempotent)."""
    global _xtensor_loaded
    if _xtensor_loaded:
        return
    with _xtensor_lock:
        if not _xtensor_loaded:
            # src/sxact/adapter/julia_stub.py → parents[2] = src/ → src/julia/
            julia_dir = (Path(__file__).parents[2] / "julia").resolve()
            xtensor_path = julia_dir / "XTensor.jl"
            if not xtensor_path.exists():
                raise FileNotFoundError(f"XTensor.jl not found at {xtensor_path}")
            jl.seval(f'include("{xtensor_path}")')
            # `using .XTensor` imports all XTensor exports into Main scope
            jl.seval("using .XTensor")
            # Bring XPerm WL compat functions into Main scope
            jl.seval("using .XTensor: XPerm")  # expose XPerm module in Main
            jl.seval("using .XPerm")  # expose XPerm exports in Main
            _xtensor_loaded = True


def _jl_escape(s: str) -> str:
    """Escape backslashes and double-quotes for Julia string literals."""
    return s.replace("\\", "\\\\").replace('"', '\\"')


# ---------------------------------------------------------------------------
# Context
# ---------------------------------------------------------------------------


class _JuliaContext:
    """Opaque per-file context for JuliaAdapter."""

    def __init__(self) -> None:
        self.alive: bool = True


# ---------------------------------------------------------------------------
# Adapter
# ---------------------------------------------------------------------------


class JuliaAdapter(TestAdapter[_JuliaContext]):
    """Concrete adapter for the Julia XCore + XTensor backend."""

    # Actions handled by XTensor
    _XTENSOR_ACTIONS = frozenset(
        {"DefManifold", "DefMetric", "DefTensor", "ToCanonical", "Contract"}
    )

    # Tier 2 deferred actions
    _DEFERRED_ACTIONS = frozenset({"Simplify"})

    # XCore module-level mutable state to reset on teardown
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

    def __init__(self) -> None:
        self._jl: Any = None
        self._julia_version: str = "unknown"

    def _ensure_ready(self) -> None:
        if self._jl is not None:
            return
        try:
            from sxact.xcore._runtime import get_julia

            self._jl = get_julia()
            raw = self._jl.seval("string(VERSION)")
            self._julia_version = str(raw).strip()
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
                pass  # teardown must not raise
        # Reset XTensor state if loaded
        if _xtensor_loaded:
            try:
                self._jl.seval("XTensor.reset_state!()")
            except Exception:
                pass

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
        _get_xtensor(self._jl)

        if action in self._XTENSOR_ACTIONS:
            return self._execute_xtensor(action, args)

        if action == "Evaluate":
            expr = args.get("expression", "")
            # If it looks like a tensor expression (contains Name[...] with index syntax),
            # return it as-is for later ToCanonical use — no Julia evaluation needed.
            # Exception: if the expression contains a comparison operator (===) it is a
            # law-check from the property runner and must be evaluated in Julia.
            if _is_tensor_expr(expr) and "===" not in expr:
                return Result(
                    status="ok", type="Expr", repr=expr, normalized=_normalize(expr)
                )
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

    def _execute_xtensor(self, action: str, args: dict[str, Any]) -> Result:
        """Dispatch xTensor actions to Julia XTensor module."""
        try:
            _get_xtensor(self._jl)
        except Exception as exc:
            return Result(
                status="error",
                type="",
                repr="",
                normalized="",
                error=f"XTensor load failed: {exc}",
            )

        try:
            if action == "DefManifold":
                return self._def_manifold(args)
            if action == "DefTensor":
                return self._def_tensor(args)
            if action == "DefMetric":
                return self._def_metric(args)
            if action == "ToCanonical":
                return self._to_canonical(args)
            if action == "Contract":
                return self._contract(args)
        except Exception as exc:
            return Result(
                status="error", type="", repr="", normalized="", error=str(exc)
            )
        return Result(
            status="error",
            type="",
            repr="",
            normalized="",
            error=f"unhandled xTensor action: {action!r}",
        )

    def _def_manifold(self, args: dict[str, Any]) -> Result:
        name = str(args["name"])
        dim = int(args["dimension"])
        indices = list(args["indices"])
        idxs = "[" + ", ".join(f":{i}" for i in indices) + "]"
        self._jl.seval(f"XTensor.def_manifold!(:{name}, {dim}, {idxs})")
        # Bind in Main scope as Symbols for Assert conditions:
        #   Dimension(Bm4) → Dimension(:Bm4); ManifoldQ(Bm4) → ManifoldQ(:Bm4)
        self._jl.seval(f"Main.eval(:(global {name} = :{name}))")
        self._jl.seval(f"Main.eval(:(global Tangent{name} = :Tangent{name}))")
        for idx in indices:
            self._jl.seval(f"Main.eval(:(global {idx} = :{idx}))")
        return Result(status="ok", type="Handle", repr=name, normalized=name)

    def _def_tensor(self, args: dict[str, Any]) -> Result:
        name = str(args["name"])
        indices = args["indices"]
        manifold = str(args["manifold"])
        sym_str = args.get("symmetry") or ""
        idx_jl = "[" + ", ".join(f'"{_jl_escape(i)}"' for i in indices) + "]"
        sym_arg = f', symmetry_str="{_jl_escape(sym_str)}"' if sym_str else ""
        self._jl.seval(f"XTensor.def_tensor!(:{name}, {idx_jl}, :{manifold}{sym_arg})")
        # Bind tensor name in Main as a Symbol for TensorQ(Bts) etc.
        self._jl.seval(f"Main.eval(:(global {name} = :{name}))")
        return Result(status="ok", type="Handle", repr=name, normalized=name)

    def _def_metric(self, args: dict[str, Any]) -> Result:
        import re as _re

        signdet = int(args["signdet"])
        metric_raw = str(args["metric"])
        metric_str = _jl_escape(metric_raw)
        covd = str(args["covd"])
        self._jl.seval(f'XTensor.def_metric!({signdet}, "{metric_str}", :{covd})')
        # Bind the metric tensor name in Main as a Symbol (for SignDetOfMetric assertions)
        m_name_match = _re.match(r"^(\w+)", metric_raw)
        if m_name_match:
            metric_name = m_name_match.group(1)
            self._jl.seval(f"Main.eval(:(global {metric_name} = :{metric_name}))")
        # Bind auto-created curvature tensor names in Main as Symbols
        for prefix in ("Riemann", "Ricci", "RicciScalar", "Einstein", "Weyl"):
            auto_name = f"{prefix}{covd}"
            self._jl.seval(
                f"if XTensor.TensorQ(:{auto_name})\n"
                f"    Main.eval(:(global {auto_name} = :{auto_name}))\n"
                f"end"
            )
        repr_str = metric_raw
        return Result(status="ok", type="Handle", repr=repr_str, normalized=repr_str)

    def _to_canonical(self, args: dict[str, Any]) -> Result:
        expr = _jl_escape(str(args["expression"]))
        result = self._jl.seval(f'XTensor.ToCanonical("{expr}")')
        raw = str(result)
        return Result(status="ok", type="Expr", repr=raw, normalized=_normalize(raw))

    def _contract(self, args: dict[str, Any]) -> Result:
        expr = _jl_escape(str(args["expression"]))
        result = self._jl.seval(f'XTensor.Contract("{expr}")')
        raw = str(result)
        return Result(status="ok", type="Expr", repr=raw, normalized=_normalize(raw))

    def _execute_expr(self, wolfram_expr: str) -> Result:
        julia_expr = _wl_to_jl(wolfram_expr)
        julia_expr = _postprocess_dimino(julia_expr)
        _bind_fresh_symbols(self._jl, julia_expr)
        try:
            val = self._jl.seval(julia_expr)
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
        _bind_fresh_symbols(self._jl, julia_cond)
        try:
            val = self._jl.seval(julia_cond)
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
        except Exception:
            # Julia evaluation of the condition threw — treat as assertion failure.
            # With oracle_is_axiom=true, this produces a stable "False" oracle.
            return Result(
                status="ok",
                type="Bool",
                repr="False",
                normalized="False",
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

    def get_properties(
        self, expr: str, ctx: _JuliaContext | None = None
    ) -> dict[str, Any]:
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
            adapter_version="0.1.0",
        )


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


def _try_to_canonical_comparison(
    condition: str, jl: Any
) -> tuple[bool, str, str] | None:
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
        val = jl.seval(f"XTensor.TensorQ(:{tensor_name})")
        if val is True or str(val).lower() == "true":
            return (True, "True", "True")
        return (False, "False", "True")
    except Exception:
        return None


def _try_single_to_canonical_comparison(
    condition: str, jl: Any
) -> tuple[bool, str, str] | None:
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
        escaped = _jl_escape(tensor_expr)
        result = str(jl.seval(f'XTensor.ToCanonical("{escaped}")'))
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


def _bind_fresh_symbols(jl: Any, julia_expr: str) -> None:
    """Bind any fresh property-test symbols found in *julia_expr* as Julia Symbols in Main.

    The property runner generates names like ``pxBAGsbq`` (lowercase-start, prefixed
    with ``px`` + uppercase block).  These are unknown Julia identifiers and cause
    ``UndefVarError`` if evaluated directly.  We pre-bind each one as the corresponding
    Julia Symbol (``Main.pxBAGsbq = :pxBAGsbq``) so XCore functions that accept
    ``Symbol`` arguments receive the right value.
    """
    for sym in _FRESH_SYMBOL_RE.findall(julia_expr):
        jl.seval(f"Main.eval(:(global {sym} = :{sym}))")


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
    """Split `s` on `sep` but only at depth 0 (not inside brackets)."""
    parts = []
    depth = 0
    current = []
    i = 0
    n = len(s)
    while i < n:
        ch = s[i]
        if ch in "([{":
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


_SCHREIER_ORBIT_RE = re.compile(
    r"SchreierOrbit\[([^,\[]+),\s*GenSet\[([^\]]+)\],\s*([^\]]+)\]"
)
_SCHREIER_ORBITS_RE = re.compile(r"SchreierOrbits\[GenSet\[([^\]]+)\],\s*([^\]]+)\]")

# Post-process Dimino after WL→Julia translation.
# Matches: Dimino(GenSet(g1, g2, ...))
# Captures the comma-separated generator names after Julia translation.
_DIMINO_GENSET_POST_RE = re.compile(r"\bDimino\(GenSet\(([^)]+)\)\)")


def _postprocess_dimino(julia_expr: str) -> str:
    """Inject name registry into Dimino(GenSet(...)) calls (post WL→Julia translation).

    Dimino(GenSet(g1, g2, ...)) → Dimino(GenSet(g1, g2, ...), ["g1"=>g1, "g2"=>g2, ...])
    """

    def replace_dimino(m: "re.Match[str]") -> str:
        gens_str = m.group(1).strip()
        gen_names = [g.strip() for g in gens_str.split(",")]
        pairs = ", ".join(f'"{nm}"=>{nm}' for nm in gen_names)
        return f"Dimino(GenSet({gens_str}), [{pairs}])"

    return _DIMINO_GENSET_POST_RE.sub(replace_dimino, julia_expr)


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

    def replace_single(m: "re.Match[str]") -> str:
        pt = m.group(1).strip()
        gens = m.group(2).strip()
        n = m.group(3).strip()
        gen_names = [g.strip() for g in gens.split(",")]
        names_arr = "[" + ", ".join(f'"{name}"' for name in gen_names) + "]"
        gens_arr = "[" + ", ".join(gen_names) + "]"
        return f"SchreierOrbit({pt}, {gens_arr}, {n}, {names_arr})"

    def replace_multi(m: "re.Match[str]") -> str:
        gens = m.group(1).strip()
        n = m.group(2).strip()
        gen_names = [g.strip() for g in gens.split(",")]
        names_arr = "[" + ", ".join(f'"{name}"' for name in gen_names) + "]"
        gens_arr = "[" + ", ".join(gen_names) + "]"
        return f"SchreierOrbits({gens_arr}, {n}, {names_arr})"

    expr = _SCHREIER_ORBITS_RE.sub(replace_multi, expr)
    expr = _SCHREIER_ORBIT_RE.sub(replace_single, expr)
    return expr


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

    Abstract Wolfram symbols used as atoms (e.g. ``a``, ``b``) are left
    as-is; they will cause Julia ``UndefVarError`` for tests that rely on
    Wolfram's symbolic algebra — those tests correctly fail in Julia.
    """
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
        if ch.isalpha() or ch == "_":
            j = i
            while j < n and (expr[j].isalnum() or expr[j] == "_"):
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
                else:
                    # Function call: translate name if keyword-mapped, then emit name(
                    translated = _WL_KEYWORDS.get(name, name)
                    out.append(translated + "(")
                    stack.append("call")
                    i = j + 1
            else:
                out.append(_WL_KEYWORDS.get(name, name))
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
