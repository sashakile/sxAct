"""Recursive-descent S-expression parser for Wolfram FullForm output.

Converts FullForm strings like ``Plus[Times[2, a], b]`` into a tree of
:class:`Node` and :class:`Leaf` objects.  Handles:

- Simple atoms: symbols, numbers, negative numbers, index names (``-a``)
- Application: ``Head[arg1, arg2, ...]``
- Nested application: ``f[x][y]`` (``f[x]`` applied to ``y``)

Usage::

    tree = parse("Plus[Times[2, a], b]")
    # Node(head='Plus', args=[Node('Times', [Leaf('2'), Leaf('a')]), Leaf('b')])
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Union


# ---------------------------------------------------------------------------
# AST node types
# ---------------------------------------------------------------------------


@dataclass
class Leaf:
    """An atomic value: a symbol name, number, or index literal like ``-a``."""

    value: str

    def __repr__(self) -> str:
        return f"Leaf({self.value!r})"


@dataclass
class Node:
    """A compound expression: ``head[arg1, arg2, ...]``.

    ``head`` is either a plain name string or itself a :class:`Node` (for
    chained application like ``f[x][y]``).
    """

    head: Union[str, "Node"]
    args: list[Union["Node", Leaf]] = field(default_factory=list)

    def __repr__(self) -> str:
        head_repr = self.head if isinstance(self.head, str) else repr(self.head)
        args_repr = ", ".join(repr(a) for a in self.args)
        return f"Node({head_repr!r}, [{args_repr}])"


Expr = Union[Node, Leaf]


# ---------------------------------------------------------------------------
# Parser
# ---------------------------------------------------------------------------


class _Parser:
    """Tokenise and parse a FullForm WL string."""

    _TOKEN_RE = re.compile(
        r"""
        \s*                          # skip whitespace
        (
          "[^"]*"                    # string literal (e.g. "hello")
        | -?[0-9]+(?:\.[0-9]+)?      # number (integer or real, optional negative)
        | [a-zA-Z$][a-zA-Z0-9$`]*   # symbol name (including context paths and I)
        | -[a-zA-Z][a-zA-Z0-9]*     # negative index like -a, -bcd
        | [\[\],]                    # structural characters
        )
        """,
        re.VERBOSE,
    )

    def __init__(self, text: str) -> None:
        self._tokens: list[str] = [m.group(1) for m in self._TOKEN_RE.finditer(text)]
        self._pos: int = 0

    def _peek(self) -> str | None:
        if self._pos < len(self._tokens):
            return self._tokens[self._pos]
        return None

    def _consume(self) -> str:
        tok = self._tokens[self._pos]
        self._pos += 1
        return tok

    def _expect(self, tok: str) -> None:
        got = self._consume()
        if got != tok:
            raise ValueError(f"Expected {tok!r}, got {got!r} at position {self._pos}")

    def parse(self) -> Expr:
        result = self._parse_expr()
        if self._peek() is not None:
            raise ValueError(f"Unexpected token after expression: {self._peek()!r}")
        return result

    def _parse_expr(self) -> Expr:
        """Parse a primary expression, then consume any ``[args]`` suffixes."""
        tok = self._peek()
        if tok is None:
            raise ValueError("Unexpected end of input")

        # --- atom ---
        if tok not in ("[", "]", ","):
            self._consume()
            atom: Expr = Leaf(tok)
        else:
            raise ValueError(f"Unexpected token: {tok!r}")

        # --- optional application suffixes: atom[args][more_args]... ---
        while self._peek() == "[":
            self._consume()  # consume '['
            args: list[Expr] = []
            if self._peek() != "]":
                args.append(self._parse_expr())
                while self._peek() == ",":
                    self._consume()  # consume ','
                    args.append(self._parse_expr())
            self._expect("]")

            # If the base was a Leaf with a plain symbol name, upgrade to Node.
            # Otherwise nest: new_head = current atom, args = new args.
            if isinstance(atom, Leaf) and not atom.value.startswith("-"):
                atom = Node(head=atom.value, args=args)
            else:
                head: str | Node = atom.value if isinstance(atom, Leaf) else atom
                atom = Node(head=head, args=args)

        return atom


def parse(expr: str) -> Expr:
    """Parse a Wolfram FullForm string into a tree of :class:`Node`/:class:`Leaf`.

    Args:
        expr: A FullForm Wolfram expression such as ``"Plus[Times[2, a], b]"``
              or a simple atom like ``"a"``.

    Returns:
        The root :class:`Node` or :class:`Leaf` of the parsed tree.

    Raises:
        ValueError: If the string is not valid FullForm syntax.
    """
    return _Parser(expr.strip()).parse()
