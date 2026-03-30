"""Action recognizer — map WL AST to sxAct action dicts.

Given a parsed WL AST (from :mod:`wl_parser`), inspects the head to determine
the sxAct action and extracts structured arguments.  Handles:

- Wolfram→sxAct name mapping (ContractMetric→Contract, etc.)
- Context-sensitive extraction (DefTensor first arg, VarD chained call)
- Assignments → ``store_as`` field
- Comparisons → ``Assert`` actions
- Unrecognized heads → ``Evaluate``
"""

from __future__ import annotations

import warnings
from collections.abc import Callable
from typing import Any

from xact.translate.wl_parser import WLExpr, WLLeaf, WLNode, parse, parse_session
from xact.translate.wl_serializer import serialize

# ---------------------------------------------------------------------------
# Wolfram → sxAct name mapping (where they differ)
# ---------------------------------------------------------------------------

_WL_TO_SXACT: dict[str, str] = {
    "ContractMetric": "Contract",
    "ChristoffelP": "Christoffel",
    "IBP": "IntegrateByParts",
    "Jacobian": "GetJacobian",
}

# All recognized xAct function heads (sxAct action names)
_DEFINITION_ACTIONS = frozenset(
    {
        "DefManifold",
        "DefMetric",
        "DefTensor",
        "DefBasis",
        "DefChart",
        "DefPerturbation",
    }
)

_KNOWN_HEADS: frozenset[str] = frozenset(
    {
        # Definitions
        "DefManifold",
        "DefMetric",
        "DefTensor",
        "DefBasis",
        "DefChart",
        "DefPerturbation",
        # Expression/computation
        "ToCanonical",
        "Simplify",
        "ContractMetric",
        "CommuteCovDs",
        "SortCovDs",
        "Perturb",
        "PerturbCurvature",
        "Perturbation",
        "PerturbationOrder",
        "PerturbationAtOrder",
        "CheckMetricConsistency",
        "IBP",
        "TotalDerivativeQ",
        "VarD",
        "SetBasisChange",
        "ChangeBasis",
        "Jacobian",
        "BasisChangeQ",
        "SetComponents",
        "GetComponents",
        "ComponentValue",
        "CTensorQ",
        "ToBasis",
        "FromBasis",
        "TraceBasisDummy",
        "ChristoffelP",
        # PerturbCurvature keys
        "Christoffel1",
        "Riemann1",
        "Ricci1",
        "RicciScalar1",
    }
)

# Heads that use chained application: Head[arg1][arg2]
_CHAINED_HEADS = frozenset({"VarD", "ToBasis", "FromBasis"})

# PerturbCurvature key names
_PERTURB_CURVATURE_KEYS = frozenset({"Christoffel1", "Riemann1", "Ricci1", "RicciScalar1"})


# ---------------------------------------------------------------------------
# Action dict type
# ---------------------------------------------------------------------------

ActionDict = dict[str, Any]


# ---------------------------------------------------------------------------
# Core recognizer
# ---------------------------------------------------------------------------


def _get_head_name(node: WLNode) -> str | None:
    """Get the string head name from a node, unwrapping one level of chaining."""
    if isinstance(node.head, str):
        return node.head
    if isinstance(node.head, WLNode) and isinstance(node.head.head, str):
        return node.head.head
    return None


def _ser(expr: WLExpr) -> str:
    """Shorthand for serialize."""
    return serialize(expr)


def recognize(expr: WLExpr) -> ActionDict:
    """Convert a single WL AST into an action dict.

    Returns a dict with at minimum ``{"action": ..., "args": {...}}``.
    May also include ``"store_as"`` for assignments.
    """
    # --- Assignment: Set[lhs, rhs] ---
    if isinstance(expr, WLNode) and expr.head == "Set":
        lhs = expr.args[0]
        rhs = expr.args[1]
        store_as = _ser(lhs)
        inner = recognize(rhs)
        inner["store_as"] = store_as
        return inner

    # --- Comparison: Equal / SameQ → Assert ---
    if isinstance(expr, WLNode) and expr.head in ("Equal", "SameQ"):
        return {
            "action": "Assert",
            "args": {"condition": _ser(expr)},
        }

    # --- Bare leaf (no function call) → Evaluate ---
    if isinstance(expr, WLLeaf):
        return {
            "action": "Evaluate",
            "args": {"expression": expr.value},
        }

    assert isinstance(expr, WLNode)

    # --- Chained application: Head[arg1][arg2] ---
    head_name = _get_head_name(expr)
    if head_name is not None and isinstance(expr.head, WLNode):
        return _recognize_chained(head_name, expr.head, expr.args)

    # --- Simple function call ---
    if isinstance(expr.head, str):
        return _recognize_simple(expr.head, expr.args)

    # --- Nested node head we can't unwrap → Evaluate ---
    return {
        "action": "Evaluate",
        "args": {"expression": _ser(expr)},
    }


def _recognize_chained(head_name: str, inner_node: WLNode, outer_args: list[WLExpr]) -> ActionDict:
    """Handle chained calls like VarD[field][expr], ToBasis[basis][expr]."""
    if head_name == "VarD":
        variable = _ser(inner_node.args[0]) if inner_node.args else ""
        expression = _ser(outer_args[0]) if outer_args else ""
        return {
            "action": "VarD",
            "args": {
                "variable": variable,
                "expression": expression,
                # covd not available in Wolfram form
            },
        }

    if head_name in ("ToBasis", "FromBasis"):
        basis = _ser(inner_node.args[0]) if inner_node.args else ""
        expression = _ser(outer_args[0]) if outer_args else ""
        return {
            "action": head_name,
            "args": {
                "basis": basis,
                "expression": expression,
            },
        }

    # Unknown chained call → Evaluate
    return {
        "action": "Evaluate",
        "args": {"expression": _ser(WLNode(head=inner_node, args=outer_args))},
    }


def _recognize_simple(head: str, args: list[WLExpr]) -> ActionDict:
    """Recognize a simple Head[args...] call via dispatch table."""
    # Check PerturbCurvature keys first (dynamic set)
    if head in _PERTURB_CURVATURE_KEYS:
        return {
            "action": "PerturbCurvature",
            "args": {"key": head, "covd": _ser(args[0]) if args else ""},
        }

    handler = _HEAD_HANDLERS.get(head)
    if handler is not None:
        return handler(args)

    # --- Unrecognized head → Evaluate with warning ---
    _INTERNAL_HEADS = {"Plus", "Times", "Power", "List", "Rule", "Greater", "Less"}
    if head not in _KNOWN_HEADS and head not in _INTERNAL_HEADS:
        warnings.warn(
            f"Unrecognized function {head!r} — treating as Evaluate. "
            f"Known xAct functions: DefManifold, DefMetric, DefTensor, "
            f"ToCanonical, Simplify, Contract, ...",
            UserWarning,
            stacklevel=3,
        )

    return {
        "action": "Evaluate",
        "args": {"expression": _ser(WLNode(head=head, args=args))},
    }


# ---------------------------------------------------------------------------
# Handler functions for _HEAD_HANDLERS dispatch table
# ---------------------------------------------------------------------------


def _h_def_manifold(args: list[WLExpr]) -> ActionDict:
    return {
        "action": "DefManifold",
        "args": {
            "name": _ser(args[0]) if len(args) > 0 else "",
            "dimension": _to_int_or_str(args[1]) if len(args) > 1 else 0,
            "indices": _list_to_strings(args[2]) if len(args) > 2 else [],
        },
    }


def _h_def_metric(args: list[WLExpr]) -> ActionDict:
    result: ActionDict = {
        "action": "DefMetric",
        "args": {
            "signdet": _to_int_or_str(args[0]) if len(args) > 0 else 0,
            "metric": _ser(args[1]) if len(args) > 1 else "",
            "covd": _ser(args[2]) if len(args) > 2 else "",
        },
    }
    if len(args) > 3:
        result["args"]["extra"] = _ser(args[3])
    return result


def _h_def_basis(args: list[WLExpr]) -> ActionDict:
    return {
        "action": "DefBasis",
        "args": {
            "name": _ser(args[0]) if len(args) > 0 else "",
            "vbundle": _ser(args[1]) if len(args) > 1 else "",
            "cnumbers": _list_to_values(args[2]) if len(args) > 2 else [],
        },
    }


def _h_def_chart(args: list[WLExpr]) -> ActionDict:
    return {
        "action": "DefChart",
        "args": {
            "name": _ser(args[0]) if len(args) > 0 else "",
            "manifold": _ser(args[1]) if len(args) > 1 else "",
            "cnumbers": _list_to_values(args[2]) if len(args) > 2 else [],
            "scalars": _list_to_strings(args[3]) if len(args) > 3 else [],
        },
    }


def _h_def_perturbation(args: list[WLExpr]) -> ActionDict:
    return {
        "action": "DefPerturbation",
        "args": {
            "name": _ser(args[0]) if len(args) > 0 else "",
            "metric": _ser(args[1]) if len(args) > 1 else "",
            "parameter": _ser(args[2]) if len(args) > 2 else "",
        },
    }


def _h_simplify(args: list[WLExpr]) -> ActionDict:
    result: ActionDict = {
        "action": "Simplify",
        "args": {"expression": _ser(args[0]) if args else ""},
    }
    if len(args) > 1:
        result["args"]["assumptions"] = _ser(args[1])
    return result


def _h_commute_covds(args: list[WLExpr]) -> ActionDict:
    result: ActionDict = {
        "action": "CommuteCovDs",
        "args": {"expression": _ser(args[0]) if args else ""},
    }
    if len(args) > 1:
        result["args"]["covd"] = _ser(args[1])
    if len(args) > 2:
        result["args"]["indices"] = _ser(args[2])
    return result


def _h_sort_covds(args: list[WLExpr]) -> ActionDict:
    result: ActionDict = {
        "action": "SortCovDs",
        "args": {"expression": _ser(args[0]) if args else ""},
    }
    if len(args) > 1:
        result["args"]["covd"] = _ser(args[1])
    return result


def _h_perturb(args: list[WLExpr]) -> ActionDict:
    result: ActionDict = {
        "action": "Perturb",
        "args": {"expression": _ser(args[0]) if args else ""},
    }
    if len(args) > 1:
        result["args"]["order"] = _to_int_or_str(args[1])
    return result


def _h_perturbation(args: list[WLExpr]) -> ActionDict:
    result: ActionDict = {
        "action": "PerturbCurvature",
        "args": {"expression": _ser(args[0]) if args else ""},
    }
    if len(args) > 1:
        result["args"]["order"] = _to_int_or_str(args[1])
    return result


def _h_perturbation_at_order(args: list[WLExpr]) -> ActionDict:
    result: ActionDict = {
        "action": "PerturbationAtOrder",
        "args": {"expression": _ser(args[0]) if args else ""},
    }
    if len(args) > 1:
        result["args"]["order"] = _to_int_or_str(args[1])
    return result


def _h_check_metric_consistency(args: list[WLExpr]) -> ActionDict:
    result: ActionDict = {
        "action": "CheckMetricConsistency",
        "args": {"metric": _ser(args[0]) if args else ""},
    }
    if len(args) > 1:
        result["args"]["covd"] = _ser(args[1])
    return result


def _h_ibp(args: list[WLExpr]) -> ActionDict:
    result: ActionDict = {
        "action": "IntegrateByParts",
        "args": {"expression": _ser(args[0]) if args else ""},
    }
    if len(args) > 1:
        result["args"]["covd"] = _ser(args[1])
    return result


def _h_total_derivative_q(args: list[WLExpr]) -> ActionDict:
    result: ActionDict = {
        "action": "TotalDerivativeQ",
        "args": {"expression": _ser(args[0]) if args else ""},
    }
    if len(args) > 1:
        result["args"]["covd"] = _ser(args[1])
    return result


def _h_set_basis_change(args: list[WLExpr]) -> ActionDict:
    return {
        "action": "SetBasisChange",
        "args": {
            "basis1": _ser(args[0]) if len(args) > 0 else "",
            "basis2": _ser(args[1]) if len(args) > 1 else "",
            "matrix": _ser(args[2]) if len(args) > 2 else "",
        },
    }


def _h_component_value(args: list[WLExpr]) -> ActionDict:
    return {
        "action": "ComponentValue",
        "args": {
            "tensor": _ser(args[0]) if len(args) > 0 else "",
            "indices": _list_to_values(args[1]) if len(args) > 1 else [],
            "basis": _ser(args[2]) if len(args) > 2 else "",
        },
    }


_ActionHandler = Callable[[list[WLExpr]], ActionDict]


def _h_expr(action: str, key: str = "expression") -> _ActionHandler:
    """Factory: single-arg handler returning {action, args: {key: ser(arg0)}}."""

    def handler(args: list[WLExpr]) -> ActionDict:
        return {"action": action, "args": {key: _ser(args[0]) if args else ""}}

    return handler


def _h_two_arg(action: str, k1: str, k2: str) -> _ActionHandler:
    """Factory: two-arg handler returning {action, args: {k1: ser(0), k2: ser(1)}}."""

    def handler(args: list[WLExpr]) -> ActionDict:
        return {
            "action": action,
            "args": {
                k1: _ser(args[0]) if len(args) > 0 else "",
                k2: _ser(args[1]) if len(args) > 1 else "",
            },
        }

    return handler


# ---------------------------------------------------------------------------
# DefTensor context-sensitive extraction
# ---------------------------------------------------------------------------


def _extract_def_tensor(args: list[WLExpr]) -> ActionDict:
    """Extract DefTensor[T[-a,-b], M, Symmetric[{-a,-b}]].

    The first argument is a declaration (name + indices), not a function call.
    """
    result: ActionDict = {"action": "DefTensor", "args": {}}

    if not args:
        return result

    first = args[0]
    if isinstance(first, WLNode) and isinstance(first.head, str):
        # T[-a,-b] → name="T", indices=["-a","-b"]
        result["args"]["name"] = first.head
        result["args"]["indices"] = [_ser(a) for a in first.args]
    elif isinstance(first, WLLeaf):
        # Scalar tensor: DefTensor[S, M]
        result["args"]["name"] = first.value
        result["args"]["indices"] = []
    else:
        result["args"]["name"] = _ser(first)
        result["args"]["indices"] = []

    if len(args) > 1:
        result["args"]["manifold"] = _ser(args[1])

    if len(args) > 2:
        result["args"]["symmetry"] = _ser(args[2])

    return result


# ---------------------------------------------------------------------------
# Dispatch table: WL head name → handler(args) → ActionDict
# ---------------------------------------------------------------------------

_HEAD_HANDLERS: dict[str, _ActionHandler] = {
    # Definitions
    "DefManifold": _h_def_manifold,
    "DefMetric": _h_def_metric,
    "DefTensor": _extract_def_tensor,
    "DefBasis": _h_def_basis,
    "DefChart": _h_def_chart,
    "DefPerturbation": _h_def_perturbation,
    # Single-expression actions
    "ToCanonical": _h_expr("ToCanonical"),
    "ContractMetric": _h_expr("Contract"),
    "PerturbationOrder": _h_expr("PerturbationOrder"),
    "TraceBasisDummy": _h_expr("TraceBasisDummy"),
    "CTensorQ": _h_expr("CTensorQ", key="tensor"),
    "ChristoffelP": _h_expr("Christoffel", key="covd"),
    # Two-arg actions
    "ChangeBasis": _h_two_arg("ChangeBasis", "expression", "target_basis"),
    "Jacobian": _h_two_arg("GetJacobian", "basis1", "basis2"),
    "BasisChangeQ": _h_two_arg("BasisChangeQ", "basis1", "basis2"),
    "SetComponents": _h_two_arg("SetComponents", "tensor", "components"),
    "GetComponents": _h_two_arg("GetComponents", "tensor", "basis"),
    # Complex handlers
    "Simplify": _h_simplify,
    "CommuteCovDs": _h_commute_covds,
    "SortCovDs": _h_sort_covds,
    "Perturb": _h_perturb,
    "Perturbation": _h_perturbation,
    "PerturbationAtOrder": _h_perturbation_at_order,
    "CheckMetricConsistency": _h_check_metric_consistency,
    "IBP": _h_ibp,
    "TotalDerivativeQ": _h_total_derivative_q,
    "SetBasisChange": _h_set_basis_change,
    "ComponentValue": _h_component_value,
}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _to_int_or_str(expr: WLExpr) -> int | str:
    """Convert a leaf to int if it looks numeric, else string."""
    if isinstance(expr, WLLeaf):
        try:
            return int(expr.value)
        except ValueError:
            return expr.value
    # Negation: Times[-1, N]
    if (
        isinstance(expr, WLNode)
        and expr.head == "Times"
        and len(expr.args) == 2
        and isinstance(expr.args[0], WLLeaf)
        and expr.args[0].value == "-1"
        and isinstance(expr.args[1], WLLeaf)
    ):
        try:
            return -int(expr.args[1].value)
        except ValueError:
            pass
    return serialize(expr)


def _list_to_strings(expr: WLExpr) -> list[str]:
    """Convert a List node to list of serialized strings."""
    if isinstance(expr, WLNode) and expr.head == "List":
        return [_ser(a) for a in expr.args]
    return [_ser(expr)]


def _list_to_values(expr: WLExpr) -> list[int | str]:
    """Convert a List node to list of int/str values."""
    if isinstance(expr, WLNode) and expr.head == "List":
        return [_to_int_or_str(a) for a in expr.args]
    return [_to_int_or_str(expr)]


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def wl_to_action(source: str) -> ActionDict:
    """Parse a single WL expression and return its action dict.

    >>> wl_to_action("DefManifold[M, 4, {a, b, c, d}]")
    {'action': 'DefManifold', 'args': {'name': 'M', 'dimension': 4, 'indices': ['a', 'b', 'c', 'd']}}
    """
    tree = parse(source)
    return recognize(tree)


def wl_to_actions(source: str) -> list[ActionDict]:
    """Parse a multi-statement WL session and return action dicts.

    >>> wl_to_actions("DefManifold[M, 4, {a,b}]; DefMetric[-1, g[-a,-b], CD]")
    [{'action': 'DefManifold', ...}, {'action': 'DefMetric', ...}]
    """
    trees = parse_session(source)
    return [recognize(t) for t in trees]
