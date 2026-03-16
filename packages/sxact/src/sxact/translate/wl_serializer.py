"""Re-serialize a WL AST subtree to infix string form.

Used by the action recognizer to extract expression arguments as strings
that both Wolfram and Julia adapters accept.

    >>> from sxact.translate.wl_parser import parse
    >>> from sxact.translate.wl_serializer import serialize
    >>> serialize(parse("T[-a,-b] - T[-b,-a]"))
    'T[-a,-b] - T[-b,-a]'
"""

from __future__ import annotations

from sxact.translate.wl_parser import WLExpr, WLLeaf, WLNode


def serialize(expr: WLExpr) -> str:
    """Convert a WL AST back to infix surface syntax."""
    if isinstance(expr, WLLeaf):
        return expr.value

    assert isinstance(expr, WLNode)
    head = expr.head

    if head == "List":
        items = ", ".join(serialize(a) for a in expr.args)
        return "{" + items + "}"

    if head == "Plus":
        return _serialize_plus(expr.args)

    if head == "Times":
        return _serialize_times(expr.args)

    if head == "Power":
        base = _wrap_if_needed(expr.args[0], _POWER_PREC)
        exp = serialize(expr.args[1])
        return f"{base}^{exp}"

    if head == "Set":
        lhs = serialize(expr.args[0])
        rhs = serialize(expr.args[1])
        return f"{lhs} = {rhs}"

    if head == "Equal":
        lhs = serialize(expr.args[0])
        rhs = serialize(expr.args[1])
        return f"{lhs} == {rhs}"

    if head == "SameQ":
        lhs = serialize(expr.args[0])
        rhs = serialize(expr.args[1])
        return f"{lhs} === {rhs}"

    if head == "Rule":
        lhs = serialize(expr.args[0])
        rhs = serialize(expr.args[1])
        return f"{lhs} -> {rhs}"

    # Function call: Head[args] or chained Head[args1][args2]
    if isinstance(head, str):
        args_str = ", ".join(serialize(a) for a in expr.args)
        return f"{head}[{args_str}]"

    # Chained application: head is a Node
    head_str = serialize(head)
    args_str = ", ".join(serialize(a) for a in expr.args)
    return f"{head_str}[{args_str}]"


# ---------------------------------------------------------------------------
# Precedence helpers
# ---------------------------------------------------------------------------

_PLUS_PREC = 1
_TIMES_PREC = 2
_POWER_PREC = 3


def _precedence(expr: WLExpr) -> int:
    if isinstance(expr, WLNode) and isinstance(expr.head, str):
        if expr.head == "Plus":
            return _PLUS_PREC
        if expr.head == "Times":
            return _TIMES_PREC
        if expr.head == "Power":
            return _POWER_PREC
    return 99


def _wrap_if_needed(expr: WLExpr, min_prec: int) -> str:
    s = serialize(expr)
    if _precedence(expr) < min_prec:
        return f"({s})"
    return s


def _is_neg_one(expr: WLExpr) -> bool:
    return isinstance(expr, WLLeaf) and expr.value == "-1"


def _serialize_plus(args: list[WLExpr]) -> str:
    if not args:
        return "0"
    parts: list[str] = []
    for i, arg in enumerate(args):
        # Check if this term is Times[-1, something] → show as "- something"
        neg_term = _extract_negated(arg)
        if neg_term is not None:
            term_str = _wrap_if_needed(neg_term, _PLUS_PREC + 1)
            if i == 0:
                parts.append(f"-{term_str}")
            else:
                parts.append(f" - {term_str}")
        else:
            term_str = serialize(arg)
            if i == 0:
                parts.append(term_str)
            else:
                parts.append(f" + {term_str}")
    return "".join(parts)


def _extract_negated(expr: WLExpr) -> WLExpr | None:
    """If expr is Times[-1, X], return X. Otherwise None."""
    if (
        isinstance(expr, WLNode)
        and expr.head == "Times"
        and len(expr.args) >= 2
        and _is_neg_one(expr.args[0])
    ):
        rest = expr.args[1:]
        if len(rest) == 1:
            return rest[0]
        return WLNode(head="Times", args=rest, pos=expr.pos)
    return None


def _serialize_times(args: list[WLExpr]) -> str:
    if not args:
        return "1"
    # Check for leading -1 → negate
    if _is_neg_one(args[0]):
        inner = args[1:]
        if not inner:
            return "-1"
        if len(inner) == 1:
            return f"-{_wrap_if_needed(inner[0], _TIMES_PREC)}"
        inner_str = _serialize_times(inner)
        return f"-{inner_str}"

    parts: list[str] = []
    for arg in args:
        # Check for Power[x, -1] → show as division? No, keep as multiplication
        parts.append(_wrap_if_needed(arg, _TIMES_PREC))
    # Use space-separated implicit multiplication (Wolfram style)
    return " ".join(parts)
