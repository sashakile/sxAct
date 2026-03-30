"""Recursive descent parser for Wolfram-like expressions.

Parses Wolfram surface syntax into Sym/WExpr/list/str/int Python AST.

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
)


def _parse(source: str) -> Any:
    """Parse a Wolfram expression string into a Python AST (Sym / WExpr / list / str / int).

    Grammar handled:
    - Integer literals: 42
    - String literals: "hello"
    - Symbols: Foo, myVar, x_  (bare identifiers)
    - Compound: f[a, b, ...]
    - List: {a, b, ...}
    - Infix: a === b, a == b, a + b, a * b, a - b, a && b, a || b
    - Postfix: expr // f  (rewritten to f[expr])
    - Rule: a -> b  (rewritten to (a, b) tuple)
    - Assignment: a = b
    - Dollar-ref substitution: $name (already done by runner before parse)
    """
    parser = _Parser(source)
    result = parser.parse_expr()
    parser.skip_ws()
    return result


class _Parser:
    """Recursive descent parser for Wolfram-like expressions."""

    def __init__(self, source: str) -> None:
        self.src = source
        self.pos = 0
        self.n = len(source)

    def skip_ws(self) -> None:
        while self.pos < self.n and self.src[self.pos] in " \t\n\r":
            self.pos += 1

    def peek(self) -> str:
        self.skip_ws()
        if self.pos >= self.n:
            return ""
        return self.src[self.pos]

    def parse_expr(self) -> Any:
        """Top-level: handles =, ==, ===, &&, ||, +, -, *, //, ->"""
        return self._parse_assign()

    def _parse_assign(self) -> Any:
        lhs = self._parse_rule()
        self.skip_ws()
        if (
            self.pos < self.n
            and self.src[self.pos] == "="
            and (self.pos + 1 >= self.n or self.src[self.pos + 1] not in ("=", ">"))
        ):
            self.pos += 1
            rhs = self._parse_assign()
            return WExpr(Sym("Set"), [lhs, rhs])
        return lhs

    def _parse_rule(self) -> Any:
        lhs = self._parse_or()
        self.skip_ws()
        if self.pos + 1 < self.n and self.src[self.pos : self.pos + 2] == "->":
            self.pos += 2
            rhs = self._parse_or()
            return (lhs, rhs)
        return lhs

    def _parse_or(self) -> Any:
        lhs = self._parse_and()
        while True:
            self.skip_ws()
            if self.pos + 1 < self.n and self.src[self.pos : self.pos + 2] == "||":
                self.pos += 2
                rhs = self._parse_and()
                lhs = WExpr(Sym("Or"), [lhs, rhs])
            else:
                break
        return lhs

    def _parse_and(self) -> Any:
        lhs = self._parse_eq()
        while True:
            self.skip_ws()
            if self.pos + 1 < self.n and self.src[self.pos : self.pos + 2] == "&&":
                self.pos += 2
                rhs = self._parse_eq()
                lhs = WExpr(Sym("And"), [lhs, rhs])
            else:
                break
        return lhs

    def _parse_eq(self) -> Any:
        lhs = self._parse_compare()
        self.skip_ws()
        if self.pos + 2 < self.n and self.src[self.pos : self.pos + 3] == "===":
            self.pos += 3
            rhs = self._parse_compare()
            return WExpr(Sym("SameQ"), [lhs, rhs])
        if self.pos + 1 < self.n and self.src[self.pos : self.pos + 2] == "==":
            self.pos += 2
            rhs = self._parse_compare()
            return WExpr(Sym("Equal"), [lhs, rhs])
        return lhs

    def _parse_compare(self) -> Any:
        lhs = self._parse_postfix()
        self.skip_ws()
        if self.pos < self.n and self.src[self.pos] == ">":
            self.pos += 1
            rhs = self._parse_postfix()
            return WExpr(Sym("Greater"), [lhs, rhs])
        return lhs

    def _parse_postfix(self) -> Any:
        lhs = self._parse_add()
        while True:
            self.skip_ws()
            if self.pos + 1 < self.n and self.src[self.pos : self.pos + 2] == "//":
                self.pos += 2
                rhs = self._parse_atom_call()  # function to apply
                # lhs // rhs → rhs[lhs]
                lhs = WExpr(rhs, [lhs])
            else:
                break
        return lhs

    def _parse_add(self) -> Any:
        lhs = self._parse_mul()
        while True:
            self.skip_ws()
            if self.pos < self.n and self.src[self.pos] == "+":
                self.pos += 1
                rhs = self._parse_mul()
                # Symbolic addition
                if isinstance(lhs, WExpr) and lhs.head == SYM_PLUS:
                    lhs = WExpr(SYM_PLUS, [*lhs.args, rhs])
                else:
                    lhs = WExpr(SYM_PLUS, [lhs, rhs])
            elif (
                self.pos < self.n
                and self.src[self.pos] == "-"
                and (self.pos + 1 >= self.n or self.src[self.pos + 1] != ">")
            ):
                self.pos += 1
                rhs = self._parse_mul()
                lhs = WExpr(Sym("Subtract"), [lhs, rhs])
            else:
                break
        return lhs

    def _parse_mul(self) -> Any:
        lhs = self._parse_unary()
        while True:
            self.skip_ws()
            if self.pos < self.n and self.src[self.pos] == "*":
                self.pos += 1
                rhs = self._parse_unary()
                lhs = WExpr(Sym("Times"), [lhs, rhs])
            else:
                break
        return lhs

    def _parse_unary(self) -> Any:
        return self._parse_atom_call()

    def _parse_atom_call(self) -> Any:
        atom = self._parse_atom()
        # Check for f[...] application
        self.skip_ws()
        while self.pos < self.n and self.src[self.pos] == "[":
            self.pos += 1  # consume [
            args = self._parse_arg_list("]")
            atom = WExpr(atom, args)
            self.skip_ws()
        return atom

    def _parse_arg_list(self, close: str) -> list[Any]:
        args: list[Any] = []
        self.skip_ws()
        if self.pos < self.n and self.src[self.pos] == close:
            self.pos += 1
            return args
        while True:
            args.append(self.parse_expr())
            self.skip_ws()
            if self.pos < self.n and self.src[self.pos] == ",":
                self.pos += 1
            elif self.pos < self.n and self.src[self.pos] == close:
                self.pos += 1
                break
            else:
                break
        return args

    def _parse_atom(self) -> Any:
        self.skip_ws()
        if self.pos >= self.n:
            return SYM_NULL

        ch = self.src[self.pos]

        # String literal
        if ch == '"':
            self.pos += 1
            buf = []
            while self.pos < self.n:
                c = self.src[self.pos]
                if c == "\\" and self.pos + 1 < self.n:
                    self.pos += 1
                    nc = self.src[self.pos]
                    if nc == "n":
                        buf.append("\n")
                    elif nc == "t":
                        buf.append("\t")
                    else:
                        buf.append(nc)
                    self.pos += 1
                elif c == '"':
                    self.pos += 1
                    break
                else:
                    buf.append(c)
                    self.pos += 1
            return "".join(buf)

        # List {a, b, ...}
        if ch == "{":
            self.pos += 1
            elems = self._parse_arg_list("}")
            return WExpr(SYM_LIST, elems)

        # Parenthesised expression
        if ch == "(":
            self.pos += 1
            inner = self.parse_expr()
            self.skip_ws()
            if self.pos < self.n and self.src[self.pos] == ")":
                self.pos += 1
            return inner

        # Negative number
        if ch == "-":
            self.pos += 1
            self.skip_ws()
            num = self._parse_number()
            if num is not None:
                return -num
            self.pos -= 1
            return Sym("-")

        # Number
        num = self._parse_number()
        if num is not None:
            return num

        # Symbol / identifier (may contain _ for Wolfram Pattern notation,
        # and Unicode non-ASCII chars like † ⁀ for dagger/link symbols)
        if ch.isalpha() or ch == "_" or (ord(ch) > 127):
            j = self.pos
            while j < self.n and (
                self.src[j].isalnum() or self.src[j] == "_" or ord(self.src[j]) > 127
            ):
                j += 1
            name = self.src[self.pos : j]
            self.pos = j
            # Well-known atoms
            if name == "True":
                return True
            if name == "False":
                return False
            if name == "Null":
                return SYM_NULL
            if name == "Plus":
                return SYM_PLUS
            if name == "List":
                return SYM_LIST
            if name == "Pi":
                return SYM_PI
            return Sym(name)

        # Dollar reference $name (should be pre-substituted, but handle gracefully)
        if ch == "$":
            self.pos += 1
            j = self.pos
            while j < self.n and (self.src[j].isalnum() or self.src[j] == "_"):
                j += 1
            name = self.src[self.pos : j]
            self.pos = j
            return Sym(name)

        # Unknown character — skip and return null
        self.pos += 1
        return SYM_NULL

    def _parse_number(self) -> int | float | None:
        j = self.pos
        if j >= self.n:
            return None
        if not (self.src[j].isdigit()):
            return None
        while j < self.n and self.src[j].isdigit():
            j += 1
        is_float = False
        if j < self.n and self.src[j] == ".":
            is_float = True
            j += 1
            while j < self.n and self.src[j].isdigit():
                j += 1
        text = self.src[self.pos : j]
        self.pos = j
        return float(text) if is_float else int(text)
