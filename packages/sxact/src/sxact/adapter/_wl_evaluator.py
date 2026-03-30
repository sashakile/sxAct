"""Wolfram mini-interpreter: state management and expression evaluator.

Per-file XCore state (_XCoreState) and the recursive evaluator (_wl_evaluate)
that handles xCore builtins, special forms, and Wolfram structural equality.

Extracted from python_stub.py for modularity (sxAct-ckzw).
"""

from __future__ import annotations

from typing import Any

from sxact.adapter._wl_ast import (
    SYM_LIST,
    SYM_NULL,
    SYM_PI,
    SYM_PLUS,
    Sym,
    WExpr,
    wl_repr,
)


class _XCoreState:
    """Mutable xCore state for one test file (reset on teardown)."""

    DAGGER_CHAR = "†"
    LINK_CHAR = "⁀"

    # Known XCore names that ValidateSymbol should reject
    _XCORE_NAMES = frozenset(
        {
            "JustOne",
            "MapIfPlus",
            "ThreadArray",
            "SetNumberOfArguments",
            "TrueOrFalse",
            "ReportSet",
            "ReportSetOption",
            "CheckOptions",
            "SymbolJoin",
            "NoPattern",
            "HasDaggerCharacterQ",
            "MakeDaggerSymbol",
            "LinkSymbols",
            "UnlinkSymbol",
            "SubHead",
            "xUpSet",
            "xUpSetDelayed",
            "xUpAppendTo",
            "xUpDeleteCasesTo",
            "xTagSet",
            "xTagSetDelayed",
            "push_unevaluated",
            "xTension",
            "MakexTensions",
            "xEvaluateAt",
            "XHold",
            "ValidateSymbol",
            "FindSymbols",
            "register_symbol",
            "DeleteDuplicates",
            "DuplicateFreeQ",
            "Disclaimer",
        }
    )

    # Built-in numeric values — ValidateSymbol should reject these
    _NUMERIC_SYMS = frozenset({"Pi", "E", "I", "Infinity", "True", "False"})

    # Protected Wolfram names — ValidateSymbol should reject these
    _PROTECTED = frozenset({"List", "Plus", "Times", "Power", "Rule", "Null"})

    def __init__(self) -> None:
        # upvalue store: tag → {property → value}
        self._upvalue_store: dict[str, dict[str, Any]] = {}
        # variable store: name → value
        self._vars: dict[str, Any] = {
            # Pre-defined XCore global refs
            "DaggerCharacter": _XCoreState.DAGGER_CHAR,
            "LinkCharacter": _XCoreState.LINK_CHAR,
        }
        # symbol registry: name → package
        self._symbol_registry: dict[str, str] = {}

    def reset(self) -> None:
        self._upvalue_store.clear()
        self._vars.clear()
        self._symbol_registry.clear()

    # -------------------------------------------------------------------
    # Variable store helpers
    # -------------------------------------------------------------------

    def set_var(self, name: str, value: Any) -> None:
        self._vars[name] = value

    def get_var(self, name: str) -> Any:
        """Return the value of a variable, or a Sym(name) if unset."""
        return self._vars.get(name, Sym(name))

    # -------------------------------------------------------------------
    # xUpSet family
    # -------------------------------------------------------------------

    def x_up_set(self, prop: str, tag: str, value: Any) -> Any:
        d = self._upvalue_store.setdefault(tag, {})
        d[prop] = value
        return value

    def x_up_set_delayed(self, prop: str, tag: str, thunk: Any) -> None:
        d = self._upvalue_store.setdefault(tag, {})
        d[prop] = thunk

    def x_up_append_to(self, prop: str, tag: str, element: Any) -> list[Any]:
        d = self._upvalue_store.setdefault(tag, {})
        lst: list[Any] = d.setdefault(prop, [])
        lst.append(element)
        return lst

    def x_up_delete_cases_to(self, prop: str, tag: str, value: Any) -> None:
        d = self._upvalue_store.get(tag, {})
        if prop in d and isinstance(d[prop], list):
            d[prop] = [x for x in d[prop] if wl_repr(x) != wl_repr(value)]

    def x_up_get(self, prop: str, tag: str) -> Any:
        d = self._upvalue_store.get(tag, {})
        val = d.get(prop)
        if callable(val):
            return val()
        if val is None:
            return WExpr(Sym(prop), [Sym(tag)])  # unevaluated form
        return val

    # -------------------------------------------------------------------
    # xTagSet family  (stored as special property key "tag_<key>")
    # -------------------------------------------------------------------

    def x_tag_set(self, tag: str, key: Any, value: Any) -> Any:
        prop = f"__tag__{wl_repr(key)}"
        return self.x_up_set(prop, tag, value)

    def x_tag_set_delayed(self, tag: str, key: Any, thunk: Any) -> None:
        prop = f"__tag__{wl_repr(key)}"
        self.x_up_set_delayed(prop, tag, thunk)

    def x_tag_get(self, tag: str, key: Any) -> Any:
        prop = f"__tag__{wl_repr(key)}"
        return self.x_up_get(prop, tag)


# ===========================================================================
# Helper: unwrap WExpr(List, [...]) to Python list
# ===========================================================================


def _unwrap_list(val: Any) -> list[Any]:
    """Convert WExpr(List, args) to Python list, or return list as-is."""
    if isinstance(val, list):
        return val
    if isinstance(val, WExpr) and val.head == SYM_LIST:
        return list(val.args)
    # Scalar → singleton list
    return [val]


# ===========================================================================
# Wolfram mini-evaluator
# ===========================================================================


def _wl_evaluate(expr: Any, state: _XCoreState) -> Any:
    """Recursively evaluate a Wolfram expression in the given state."""
    # Atoms
    if isinstance(expr, (int, float, str)):
        return expr
    if isinstance(expr, bool):
        return expr
    if expr is None:
        return SYM_NULL
    if isinstance(expr, Sym):
        # Try variable lookup first
        val = state._vars.get(expr.name)
        if val is not None:
            return val
        return expr
    if isinstance(expr, list):
        return [_wl_evaluate(x, state) for x in expr]
    if not isinstance(expr, WExpr):
        return expr

    # Compound expression: evaluate head
    head = expr.head
    head_name = head.name if isinstance(head, Sym) else None
    args = expr.args

    # --- Special forms (lazy evaluation) ---
    if head_name == "Catch":
        try:
            return _wl_evaluate(args[0], state)
        except Exception:
            return SYM_NULL

    if head_name == "ClearAll":
        for arg in args:
            name = arg.name if isinstance(arg, Sym) else str(arg)
            state._vars.pop(name, None)
            state._upvalue_store.pop(name, None)
        return SYM_NULL

    if head_name == "Set":
        # Assignment: lhs = rhs
        lhs, rhs = args[0], args[1]
        val = _wl_evaluate(rhs, state)
        if isinstance(lhs, Sym):
            state.set_var(lhs.name, val)
        return val

    if head_name == "xUpSet":
        # xUpSet[prop[tag], value]
        lhs, rhs = args[0], args[1]
        val = _wl_evaluate(rhs, state)
        if isinstance(lhs, WExpr) and isinstance(lhs.head, Sym):
            prop = lhs.head.name
            tag = lhs.args[0].name if isinstance(lhs.args[0], Sym) else str(lhs.args[0])
            return state.x_up_set(prop, tag, val)
        return val

    if head_name == "xUpSetDelayed":
        # xUpSetDelayed[prop[tag], expr] — semantically should be lazy (`:=`),
        # but for the current test suite eager evaluation is sufficient.
        lhs, rhs_expr = args[0], args[1]
        if isinstance(lhs, WExpr) and isinstance(lhs.head, Sym):
            prop = lhs.head.name
            tag = lhs.args[0].name if isinstance(lhs.args[0], Sym) else str(lhs.args[0])
            val = _wl_evaluate(rhs_expr, state)
            state.x_up_set(prop, tag, val)
        return SYM_NULL

    if head_name == "xUpAppendTo":
        # xUpAppendTo[prop[tag], element]
        lhs, element = args[0], args[1]
        element_val = _wl_evaluate(element, state)
        if isinstance(lhs, WExpr) and isinstance(lhs.head, Sym):
            prop = lhs.head.name
            tag = lhs.args[0].name if isinstance(lhs.args[0], Sym) else str(lhs.args[0])
            return state.x_up_append_to(prop, tag, element_val)
        return []

    if head_name == "xUpDeleteCasesTo":
        # xUpDeleteCasesTo[prop[tag], value]
        lhs, value = args[0], args[1]
        value_val = _wl_evaluate(value, state)
        if isinstance(lhs, WExpr) and isinstance(lhs.head, Sym):
            prop = lhs.head.name
            tag = lhs.args[0].name if isinstance(lhs.args[0], Sym) else str(lhs.args[0])
            state.x_up_delete_cases_to(prop, tag, value_val)
        return SYM_NULL

    if head_name == "xTagSet":
        # xTagSet[{tag, lhs_expr}, value]
        tag_pair, value = args[0], args[1]
        val = _wl_evaluate(value, state)
        if isinstance(tag_pair, WExpr) and tag_pair.head == SYM_LIST and len(tag_pair.args) == 2:
            tag_sym = tag_pair.args[0]
            lhs_expr = tag_pair.args[1]
            tag = tag_sym.name if isinstance(tag_sym, Sym) else str(tag_sym)
            state.x_tag_set(tag, lhs_expr, val)
        return val

    if head_name == "xTagSetDelayed":
        # xTagSetDelayed[{tag, lhs_expr}, rhs]
        tag_pair, rhs_expr = args[0], args[1]
        val = _wl_evaluate(rhs_expr, state)
        if isinstance(tag_pair, WExpr) and tag_pair.head == SYM_LIST and len(tag_pair.args) == 2:
            tag_sym = tag_pair.args[0]
            lhs_expr = tag_pair.args[1]
            tag = tag_sym.name if isinstance(tag_sym, Sym) else str(tag_sym)
            state.x_tag_set(tag, lhs_expr, val)
        return SYM_NULL

    if head_name == "AppendToUnevaluated":
        # AppendToUnevaluated[list_var, element] → push to list in state._vars
        var_sym, element = args[0], args[1]
        element_val = _wl_evaluate(element, state)
        if isinstance(var_sym, Sym):
            current = state.get_var(var_sym.name)
            if isinstance(current, WExpr) and current.head == SYM_LIST:
                # Convert to mutable Python list and store back
                lst = list(current.args)
                lst.append(element_val)
                new_expr = WExpr(SYM_LIST, lst)
                state.set_var(var_sym.name, new_expr)
                return new_expr
            elif isinstance(current, list):
                current.append(element_val)
                return WExpr(SYM_LIST, current)
        return SYM_NULL

    # --- Evaluate arguments eagerly for all other forms ---
    eargs = [_wl_evaluate(a, state) for a in args]

    # --- Handle upvalue lookups: prop[tag] ---
    if head_name is not None and len(eargs) == 1 and isinstance(eargs[0], Sym):
        # Check if this is an upvalue property lookup: upvProp[upvSym]
        # stored via xUpSet[upvProp[upvSym], value]
        tag_name = eargs[0].name
        d = state._upvalue_store.get(tag_name, {})
        if head_name in d:
            val = d[head_name]
            if callable(val):
                return val()
            return val

    # --- Tag store lookup: f[tag] after xTagSet[{f, f[tag]}, value] ---
    # xTagSet stores under tag=f.name, key=__tag__f[tag]
    if head_name is not None and len(eargs) == 1 and isinstance(eargs[0], Sym):
        tag_arg = eargs[0].name
        # The xTagSet was: xTagSet[{head_name, head_name[tag_arg]}, value]
        # stored under: _upvalue_store[head_name]["__tag__head_name[tag_arg]"]
        lhs_repr = f"{head_name}[{tag_arg}]"
        prop = f"__tag__{lhs_repr}"
        d = state._upvalue_store.get(head_name, {})
        if prop in d:
            val = d[prop]
            if callable(val):
                return val()
            return val

    # --- Standard library functions ---
    if head_name == "SymbolJoin":
        parts = []
        for a in eargs:
            if isinstance(a, Sym):
                parts.append(a.name)
            elif isinstance(a, str):
                parts.append(a)
            else:
                parts.append(str(a))
        return Sym("".join(parts))

    if head_name == "NoPattern":
        a = eargs[0]
        if isinstance(a, Sym):
            # x_  → Sym("x"),  x_Integer → Sym("x")
            name = a.name.rstrip("_")
            # Also strip type suffix like _Integer: find first _ and truncate
            if "_" in name:
                name = name[: name.index("_")]
            return Sym(name) if name else a
        if isinstance(a, WExpr):
            # NoPattern[f[x_, y_]] → f[x, y]: recursively strip patterns from args
            stripped_args = []
            for arg in a.args:
                stripped = _wl_evaluate(WExpr(Sym("NoPattern"), [arg]), state)
                stripped_args.append(stripped)
            return WExpr(a.head, stripped_args)
        return a

    if head_name == "HasDaggerCharacterQ":
        a = eargs[0]
        name = a.name if isinstance(a, Sym) else str(a)
        return _XCoreState.DAGGER_CHAR in name

    if head_name == "MakeDaggerSymbol":
        a = eargs[0]
        name = a.name if isinstance(a, Sym) else str(a)
        dg = _XCoreState.DAGGER_CHAR
        if dg in name:
            return Sym(name.replace(dg, ""))
        return Sym(name + dg)

    if head_name == "LinkSymbols":
        raw = eargs[0]
        if isinstance(raw, WExpr) and raw.head == SYM_LIST:
            lst = raw.args
        elif isinstance(raw, list):
            lst = raw
        else:
            lst = eargs
        names = []
        for s in lst:
            names.append(s.name if isinstance(s, Sym) else str(s))
        return Sym(_XCoreState.LINK_CHAR.join(names))

    if head_name == "UnlinkSymbol":
        a = eargs[0]
        name = a.name if isinstance(a, Sym) else str(a)
        parts = name.split(_XCoreState.LINK_CHAR)
        return [Sym(p) for p in parts]

    if head_name == "ValidateSymbol":
        a = eargs[0]
        name = a.name if isinstance(a, Sym) else str(a)
        if name in _XCoreState._XCORE_NAMES:
            raise RuntimeError(f"ValidateSymbol: {name!r} is already in use by xCore")
        if name in _XCoreState._NUMERIC_SYMS:
            raise RuntimeError(f"ValidateSymbol: {name!r} has a numeric value")
        if name in _XCoreState._PROTECTED:
            raise RuntimeError(f"ValidateSymbol: {name!r} is protected")
        return SYM_NULL

    if head_name == "FindSymbols":
        # FindSymbols[expr] → collect all symbols recursively
        if not eargs:
            return []

        def _collect_syms(x: Any) -> list[Sym]:
            if isinstance(x, Sym):
                return [x]
            if isinstance(x, WExpr):
                result: list[Sym] = []
                if isinstance(x.head, Sym):
                    result.append(x.head)
                for a in x.args:
                    result.extend(_collect_syms(a))
                return result
            if isinstance(x, list):
                result = []
                for a in x:
                    result.extend(_collect_syms(a))
                return result
            return []

        return _collect_syms(eargs[0])

    if head_name == "JustOne":
        lst = _unwrap_list(eargs[0])
        if len(lst) != 1:
            raise RuntimeError(f"JustOne: expected list with 1 element, got {len(lst)}")
        return lst[0]

    if head_name == "MapIfPlus":
        f, expr_arg = eargs[0], eargs[1]
        if isinstance(expr_arg, WExpr) and expr_arg.head == SYM_PLUS:
            mapped = [_apply(f, [a], state) for a in expr_arg.args]
            return WExpr(SYM_PLUS, mapped)
        return _apply(f, [expr_arg], state)

    if head_name == "CheckOptions":
        result = []
        for a in eargs:
            if isinstance(a, tuple) and len(a) == 2:
                result.append(a)
            elif isinstance(a, (list, WExpr)) and not isinstance(a, tuple):
                items = _unwrap_list(a)
                for item in items:
                    if isinstance(item, tuple) and len(item) == 2:
                        result.append(item)
                    else:
                        raise RuntimeError(f"CheckOptions: expected rule, got {wl_repr(item)}")
            else:
                raise RuntimeError(f"CheckOptions: expected rule, got {wl_repr(a)}")
        return result

    if head_name == "TrueOrFalse":
        return isinstance(eargs[0], bool)

    if head_name == "DeleteDuplicates":
        lst = _unwrap_list(eargs[0])
        seen: set[str] = set()
        out: list[Any] = []
        for x in lst:
            key = wl_repr(x)
            if key not in seen:
                seen.add(key)
                out.append(x)
        return out

    if head_name == "DuplicateFreeQ":
        lst = _unwrap_list(eargs[0])
        keys = [wl_repr(x) for x in lst]
        return len(keys) == len(set(keys))

    if head_name == "SubHead":
        return _sub_head(eargs[0])

    # --- Wolfram builtins ---
    if head_name == "StringQ":
        return isinstance(eargs[0], str)

    if head_name == "StringLength":
        a = eargs[0]
        if isinstance(a, str):
            return len(a)
        return 0

    if head_name == "AtomQ":
        a = eargs[0]
        return isinstance(a, (Sym, str, int, float, bool))

    if head_name == "SymbolName":
        a = eargs[0]
        if isinstance(a, Sym):
            return a.name
        return str(a)

    if head_name == "MemberQ":
        lst, elem = eargs[0], eargs[1]
        lst = _unwrap_list(lst)
        elem_repr = wl_repr(elem)
        return any(wl_repr(x) == elem_repr for x in lst)

    if head_name == "Head":
        a = eargs[0]
        if isinstance(a, WExpr):
            return a.head
        if isinstance(a, Sym):
            return Sym("Symbol")
        if isinstance(a, str):
            return Sym("String")
        if isinstance(a, bool):
            return Sym("Symbol")  # True/False are symbols in Wolfram
        if isinstance(a, int):
            return Sym("Integer")
        if isinstance(a, float):
            return Sym("Real")
        if isinstance(a, list):
            return SYM_LIST
        return Sym("Unknown")

    if head_name == "Length":
        a = eargs[0]
        if isinstance(a, list):
            return len(a)
        if isinstance(a, WExpr):
            return len(a.args)
        if isinstance(a, str):
            return len(a)
        return 0

    if head_name == "NumericQ":
        a = eargs[0]
        if isinstance(a, Sym) and a == SYM_PI:
            return True
        return isinstance(a, (int, float)) and not isinstance(a, bool)

    if head_name == "Plus":
        # Numeric addition when all args are numbers
        if all(isinstance(a, (int, float)) and not isinstance(a, bool) for a in eargs):
            return sum(eargs)
        # Symbolic addition
        return WExpr(SYM_PLUS, eargs)

    # --- Unknown function: return unevaluated WExpr ---
    return WExpr(head, eargs)


def _sub_head(expr: Any) -> Any:
    """Return the innermost atomic head (SubHead)."""
    if isinstance(expr, Sym):
        return expr
    if isinstance(expr, WExpr):
        return _sub_head(expr.head)
    return expr


def _apply(f: Any, args: list[Any], state: _XCoreState) -> Any:
    """Apply f to args in the context of state."""
    if isinstance(f, Sym):
        return _wl_evaluate(WExpr(f, args), state)
    if callable(f):
        return f(*args)
    return WExpr(f, args)


# ===========================================================================
# Evaluate a parsed Wolfram AST with special handling for structural equality
# ===========================================================================


def _eval_sameq(lhs: Any, rhs: Any, state: _XCoreState) -> bool:
    """Evaluate === (SameQ): structural/physical equality."""
    lv = _wl_evaluate(lhs, state)
    rv = _wl_evaluate(rhs, state)
    return _wl_same(lv, rv)


def _wl_same(a: Any, b: Any) -> bool:
    """Structural equality à la Wolfram SameQ."""
    # Canonicalize True/False
    a = _canon(a)
    b = _canon(b)
    if type(a) is not type(b):
        # Allow int==float comparison
        if isinstance(a, (int, float)) and isinstance(b, (int, float)):
            return a == b
        return False
    if isinstance(a, list):
        return len(a) == len(b) and all(_wl_same(x, y) for x, y in zip(a, b, strict=True))
    if isinstance(a, WExpr):
        return (
            isinstance(b, WExpr)
            and _wl_same(a.head, b.head)
            and len(a.args) == len(b.args)
            and all(_wl_same(x, y) for x, y in zip(a.args, b.args, strict=True))
        )
    if isinstance(a, tuple) and isinstance(b, tuple):
        return len(a) == len(b) and all(_wl_same(x, y) for x, y in zip(a, b, strict=True))
    return bool(a == b)


def _canon(v: Any) -> Any:
    """Canonicalize value for comparison (normalize List WExpr → list, etc.)."""
    if isinstance(v, WExpr) and v.head == SYM_LIST:
        return [_canon(x) for x in v.args]
    if isinstance(v, Sym) and v.name == "Null":
        return SYM_NULL
    return v


def _eval_bool_result(val: Any) -> bool:
    """Convert an evaluated value to Python bool."""
    if val is True or val is False:
        return bool(val)
    if isinstance(val, Sym):
        return val.name == "True"
    if isinstance(val, bool):
        return val
    return False


# ===========================================================================
# Override evaluate to handle And/Or/SameQ/Equal/Greater at dispatch level
# ===========================================================================

# Patch _wl_evaluate to handle structural equality and boolean ops
_orig_wl_evaluate = _wl_evaluate


def _wl_evaluate(expr: Any, state: _XCoreState) -> Any:  # type: ignore[no-redef]
    """Evaluate, with extra handling for SameQ, Equal, And, Or, Greater."""
    if not isinstance(expr, WExpr):
        return _orig_wl_evaluate(expr, state)

    head_name = expr.head.name if isinstance(expr.head, Sym) else None

    if head_name == "SameQ":
        lv = _wl_evaluate(expr.args[0], state)
        rv = _wl_evaluate(expr.args[1], state)
        return _wl_same(_canon(lv), _canon(rv))

    if head_name == "Equal":
        lv = _wl_evaluate(expr.args[0], state)
        rv = _wl_evaluate(expr.args[1], state)
        return _wl_same(_canon(lv), _canon(rv))

    if head_name == "Greater":
        lv = _wl_evaluate(expr.args[0], state)
        rv = _wl_evaluate(expr.args[1], state)
        try:
            return lv > rv
        except TypeError:
            return False

    if head_name == "And":
        for arg in expr.args:
            val = _wl_evaluate(arg, state)
            if not _eval_bool_result(val):
                return False
        return True

    if head_name == "Or":
        for arg in expr.args:
            val = _wl_evaluate(arg, state)
            if _eval_bool_result(val):
                return True
        return False

    if head_name == "Subtract":
        lv = _wl_evaluate(expr.args[0], state)
        rv = _wl_evaluate(expr.args[1], state)
        try:
            return lv - rv
        except TypeError:
            return WExpr(Sym("Subtract"), [lv, rv])

    if head_name == "Times":
        lv = _wl_evaluate(expr.args[0], state)
        rv = _wl_evaluate(expr.args[1], state)
        try:
            return lv * rv
        except TypeError:
            return WExpr(Sym("Times"), [lv, rv])

    return _orig_wl_evaluate(expr, state)
