"""Normalization passes that operate on AST trees produced by :mod:`.ast_parser`.

Each pass is a pure function that accepts and returns an :class:`~.ast_parser.Expr`.

Passes (applied in order by :func:`ast_normalize`):
1. :func:`sort_commutative`  — sort ``Plus``/``Times`` children by structural key
2. :func:`canonicalize_indices` — rename index leaves to ``$1``, ``$2``, …
3. :func:`flatten_coefficients` — simplify ``Times[-1, x]`` → ``Neg`` and ``Times[1, x]`` → ``x``
"""

from __future__ import annotations

import re
from typing import Union

from sxact.normalize.ast_parser import Expr, Leaf, Node

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_INDEX_RE = re.compile(r"^(-?)([a-zA-Z][a-zA-Z0-9]*)$")


def _is_index(leaf: Leaf) -> bool:
    """Return True if *leaf* looks like an xAct abstract index (e.g. ``a``, ``-b``, ``mu3``)."""
    return bool(_INDEX_RE.match(leaf.value))


def _structural_key(expr: Expr) -> str:
    """Compute a sort key for *expr* that ignores specific index values.

    Index leaves are replaced with ``_`` so that structurally identical
    tensors with different dummy index names compare as equal for ordering.
    """
    if isinstance(expr, Leaf):
        if _is_index(expr):
            # Preserve - sign (up/down distinction) but erase the letter
            sign = "-" if expr.value.startswith("-") else ""
            return f"{sign}_"
        return expr.value
    else:
        # For Node, use head name + recursive structural keys of args
        head_key = (
            expr.head
            if isinstance(expr.head, str)
            else _structural_key(expr.head)
        )
        args_key = ",".join(_structural_key(a) for a in expr.args)
        return f"{head_key}[{args_key}]"


# ---------------------------------------------------------------------------
# Pass 1: sort commutative operators
# ---------------------------------------------------------------------------

_COMMUTATIVE_HEADS = frozenset({"Plus", "Times"})


def sort_commutative(expr: Expr) -> Expr:
    """Sort children of ``Plus`` and ``Times`` nodes by structural key.

    Recurses into all sub-expressions before sorting so that nested
    commutative nodes are also normalized.
    """
    if isinstance(expr, Leaf):
        return expr

    # Recurse first (bottom-up)
    new_args = [sort_commutative(a) for a in expr.args]
    new_head = (
        expr.head
        if isinstance(expr.head, str)
        else sort_commutative(expr.head)
    )

    if isinstance(expr.head, str) and expr.head in _COMMUTATIVE_HEADS:
        new_args = sorted(new_args, key=_structural_key)

    return Node(head=new_head, args=new_args)


# ---------------------------------------------------------------------------
# Pass 2: canonicalize indices
# ---------------------------------------------------------------------------

def canonicalize_indices(expr: Expr) -> Expr:
    """Rename abstract index leaves to ``$1``, ``$2``, … in DFS order.

    The sign (up ``+`` / down ``-``) is preserved, only the letter is replaced.
    Index names are canonicalized across the whole expression so that two
    expressions with the same structure but different dummy index names
    normalize to the same form.

    Example::

        T[-a, -b] S[-a, -c]  →  T[-$1, -$2] S[-$1, -$3]
    """
    counter: list[int] = [1]
    index_map: dict[str, int] = {}

    def _visit(node: Expr) -> Expr:
        if isinstance(node, Leaf):
            m = _INDEX_RE.match(node.value)
            if m:
                sign, name = m.group(1), m.group(2)
                if name not in index_map:
                    index_map[name] = counter[0]
                    counter[0] += 1
                return Leaf(f"{sign}${index_map[name]}")
            return node
        else:
            new_args = [_visit(a) for a in node.args]
            new_head = (
                node.head
                if isinstance(node.head, str)
                else _visit(node.head)
            )
            return Node(head=new_head, args=new_args)

    return _visit(expr)


# ---------------------------------------------------------------------------
# Pass 3: coefficient flattening
# ---------------------------------------------------------------------------

def flatten_coefficients(expr: Expr) -> Expr:
    """Simplify trivial numeric coefficients in ``Times`` nodes.

    - ``Times[-1, x]`` → ``Node("Times", [Leaf("-1"), x])`` is left as-is
      at the AST level; the serializer handles rendering.
    - ``Times[1, x]`` → ``x`` (multiplicative identity removed)

    This pass only removes explicit ``1`` coefficients.  It does not attempt
    full coefficient collection.
    """
    if isinstance(expr, Leaf):
        return expr

    new_args = [flatten_coefficients(a) for a in expr.args]
    new_head = (
        expr.head
        if isinstance(expr.head, str)
        else flatten_coefficients(expr.head)
    )

    # Times[1, x] → x  (when exactly two args and the first is Leaf("1"))
    if (
        isinstance(new_head, str)
        and new_head == "Times"
        and len(new_args) == 2
        and isinstance(new_args[0], Leaf)
        and new_args[0].value == "1"
    ):
        return new_args[1]

    return Node(head=new_head, args=new_args)
