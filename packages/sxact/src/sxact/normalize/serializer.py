"""Canonical serializer for normalized AST trees.

Converts a :class:`~.ast_parser.Node`/:class:`~.ast_parser.Leaf` tree into a
compact, whitespace-free string suitable for Tier 1 equality comparison.

Infix rendering rules:
- ``Plus[a, b, ...]`` → ``a + b + ...``   (space-padded ``+``)
- ``Times[-1, x]`` → ``-x``              (unary negation shorthand)
- ``Times[c, x]`` → ``c x``             (space-separated scalar product)
- All other nodes → ``Head[arg1,arg2,...]`` (standard application, no spaces)
"""

from __future__ import annotations

from sxact.normalize.ast_parser import Expr, Leaf, Node


def serialize(expr: Expr) -> str:
    """Serialize *expr* to a canonical string.

    The output format matches the existing regex-pipeline output for simple
    expressions, enabling drop-in replacement.

    Args:
        expr: A parsed and normalized AST tree.

    Returns:
        A canonical string representation with minimal whitespace.
    """
    if isinstance(expr, Leaf):
        return expr.value

    head = expr.head
    args = expr.args

    # --- Nested application: (f[x])[y] ---
    if isinstance(head, Node):
        return f"{serialize(head)}[{','.join(serialize(a) for a in args)}]"

    # --- Plus: infix with spaces ---
    if head == "Plus":
        return " + ".join(serialize(a) for a in args)

    # --- Times: special cases for coefficients ---
    if head == "Times":
        if isinstance(args[0], Leaf) and args[0].value == "-1":
            rest = " ".join(serialize(a) for a in args[1:])
            return f"-{rest}"
        # General: space-separated (e.g., "2 x")
        return " ".join(serialize(a) for a in args)

    # --- Standard application: Head[arg1,arg2,...] ---
    # Use ", " after commas to match legacy output convention
    inner = ", ".join(serialize(a) for a in args)
    return f"{head}[{inner}]"
