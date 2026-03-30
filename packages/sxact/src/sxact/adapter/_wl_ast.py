"""Wolfram symbolic expression data model.

Pure data types for the Python-native Wolfram mini-interpreter:
Sym (atom), WExpr (compound), and well-known symbol singletons.

Extracted from python_stub.py for modularity (sxAct-ckzw).
"""

from __future__ import annotations

from typing import Any


class Sym:
    """A Wolfram Symbol (atomic)."""

    __slots__ = ("name",)

    def __init__(self, name: str) -> None:
        self.name = name

    def __repr__(self) -> str:
        return self.name

    def __eq__(self, other: object) -> bool:
        return isinstance(other, Sym) and self.name == other.name

    def __hash__(self) -> int:
        return hash(("Sym", self.name))


class WExpr:
    """A Wolfram compound expression: Head[arg1, arg2, ...]."""

    __slots__ = ("args", "head")

    def __init__(self, head: Any, args: list[Any]) -> None:
        self.head = head
        self.args = args

    def __repr__(self) -> str:
        args_str = ", ".join(wl_repr(a) for a in self.args)
        return f"{wl_repr(self.head)}[{args_str}]"

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, WExpr):
            return False
        return self.head == other.head and self.args == other.args

    def __hash__(self) -> int:
        return hash(("WExpr", self.head, tuple(self.args)))


# Well-known symbol singletons
SYM_TRUE = Sym("True")
SYM_FALSE = Sym("False")
SYM_NULL = Sym("Null")
SYM_PLUS = Sym("Plus")
SYM_LIST = Sym("List")
SYM_PI = Sym("Pi")


def wl_repr(val: Any) -> str:
    """Convert a Python value back to a Wolfram-like string representation."""
    if val is None or (isinstance(val, Sym) and val == SYM_NULL):
        return "Null"
    if val is True or (isinstance(val, Sym) and val == SYM_TRUE):
        return "True"
    if val is False or (isinstance(val, Sym) and val == SYM_FALSE):
        return "False"
    if isinstance(val, bool):
        return "True" if val else "False"
    if isinstance(val, Sym):
        return val.name
    if isinstance(val, WExpr):
        return repr(val)
    if isinstance(val, str):
        return repr(val)  # quoted string
    if isinstance(val, list):
        return "{" + ", ".join(wl_repr(x) for x in val) + "}"
    if isinstance(val, tuple):
        # Rule tuple (lhs, rhs)
        return f"{wl_repr(val[0])} -> {wl_repr(val[1])}"
    return str(val)
