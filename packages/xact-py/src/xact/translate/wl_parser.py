"""Recursive-descent parser for Wolfram Language surface syntax (xAct subset).

Parses standard WL expressions like ``DefManifold[M, 4, {a, b, c, d}]`` into
a tree of :class:`WLNode` and :class:`WLLeaf` objects.  Handles:

- Function calls: ``Head[arg1, arg2]``
- Chained application: ``f[x][y]``
- Curly-brace lists: ``{a, b, c}``
- Infix arithmetic: ``+``, ``-``, ``*``, ``/``
- Signed indices inside brackets: ``T[-a, -b]``
- Multi-line bracket continuation
- Postfix pipe: ``expr // F``
- Comments: ``(* ... *)``
- String literals: ``"hello"``
- Semicolon-separated statements
- Assignments: ``result = expr``
- Comparisons: ``==``, ``===``

Two expression sub-grammars resolve the ``-index`` ambiguity: at the top level
``-`` is subtraction/negation; inside ``[...]`` argument lists ``-identifier``
(no whitespace) is a signed index.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

# ---------------------------------------------------------------------------
# AST node types
# ---------------------------------------------------------------------------


@dataclass
class WLLeaf:
    """Atomic value: symbol, number, string, or signed index like ``-a``."""

    value: str
    pos: int = 0  # character offset in source

    def __repr__(self) -> str:
        return f"WLLeaf({self.value!r})"

    def __eq__(self, other: object) -> bool:
        if isinstance(other, WLLeaf):
            return self.value == other.value
        return NotImplemented

    def __hash__(self) -> int:
        return hash(self.value)


@dataclass
class WLNode:
    """Compound expression: ``head[arg1, arg2, ...]`` or ``List[...]``."""

    head: str | WLNode
    args: list[WLExpr] = field(default_factory=list)
    pos: int = 0

    def __repr__(self) -> str:
        head_r = self.head if isinstance(self.head, str) else repr(self.head)
        args_r = ", ".join(repr(a) for a in self.args)
        return f"WLNode({head_r!r}, [{args_r}])"

    def __eq__(self, other: object) -> bool:
        if isinstance(other, WLNode):
            return self.head == other.head and self.args == other.args
        return NotImplemented

    def __hash__(self) -> int:
        return hash((self.head, tuple(self.args)))


WLExpr = WLNode | WLLeaf


# ---------------------------------------------------------------------------
# Token types
# ---------------------------------------------------------------------------

# Order matters: longer patterns first, then shorter.
_TOKEN_PATTERNS = [
    ("COMMENT", r"\(\*[\s\S]*?\*\)"),
    ("STRING", r'"[^"]*"'),
    ("NUMBER", r"[0-9]+(?:\.[0-9]+)?"),
    ("ARROW", r"->"),
    ("MAPTO", r"/@"),  # unsupported but must tokenize
    ("APPLYAT", r"@@"),  # unsupported but must tokenize
    ("REPLACEALL", r"/\."),  # unsupported but must tokenize
    ("PIPE", r"//"),
    ("EQEQEQ", r"==="),
    ("EQEQ", r"=="),
    ("EQ", r"="),
    ("GT", r">"),
    ("LT", r"<"),
    ("LBRACKET", r"\["),
    ("RBRACKET", r"\]"),
    ("LBRACE", r"\{"),
    ("RBRACE", r"\}"),
    ("LPAREN", r"\("),
    ("RPAREN", r"\)"),
    ("COMMA", r","),
    ("SEMI", r";"),
    ("NEWLINE", r"\n"),
    ("PLUS", r"\+"),
    ("MINUS", r"-"),
    ("STAR", r"\*"),
    ("SLASH", r"/"),
    ("CARET", r"\^"),
    ("AT", r"@"),
    ("PERCENT", r"%"),
    ("IDENT", r"[a-zA-Z_$\u00C0-\uFFFF][a-zA-Z0-9_$`\u00C0-\uFFFF]*"),
    ("WS", r"[ \t\r]+"),
]

_TOKEN_RE = re.compile("|".join(f"(?P<{n}>{p})" for n, p in _TOKEN_PATTERNS))


@dataclass
class _Token:
    type: str
    value: str
    pos: int


_UNSUPPORTED_TOKENS: dict[str, str] = {
    "MAPTO": "/@ (Map) is a Wolfram programming construct. Use explicit function calls.",
    "APPLYAT": "@@ (Apply) is a Wolfram programming construct. Use explicit function calls.",
    "REPLACEALL": "/. (ReplaceAll) is not supported. Apply operations directly.",
    "PERCENT": "% (last output) is not supported. Assign results explicitly: result = ...",
}


def _tokenize(source: str) -> list[_Token]:
    tokens: list[_Token] = []
    bracket_depth = 0
    for m in _TOKEN_RE.finditer(source):
        kind = m.lastgroup
        assert kind is not None
        if kind in ("WS", "COMMENT"):
            continue

        # Check unsupported idioms at token level
        if kind in _UNSUPPORTED_TOKENS:
            raise WLParseError(
                f"Unsupported: {_UNSUPPORTED_TOKENS[kind]}",
                pos=m.start(),
                source=source,
            )

        # Track bracket depth for newline handling
        if kind in ("LBRACKET", "LBRACE", "LPAREN"):
            bracket_depth += 1
        elif kind in ("RBRACKET", "RBRACE", "RPAREN"):
            bracket_depth = max(0, bracket_depth - 1)

        # Newlines inside balanced brackets are whitespace; otherwise line separator
        if kind == "NEWLINE":
            if bracket_depth == 0:
                tokens.append(_Token(type="SEMI", value="\n", pos=m.start()))
            continue

        tokens.append(_Token(type=kind, value=m.group(), pos=m.start()))
    return tokens


# ---------------------------------------------------------------------------
# Parse error
# ---------------------------------------------------------------------------


class WLParseError(Exception):
    """Error raised when parsing fails, with position information."""

    def __init__(self, message: str, pos: int = 0, source: str = "") -> None:
        self.pos = pos
        self.source = source
        if source and pos < len(source):
            # Find the line containing pos
            line_start = source.rfind("\n", 0, pos) + 1
            line_end = source.find("\n", pos)
            if line_end == -1:
                line_end = len(source)
            line = source[line_start:line_end]
            col = pos - line_start
            message = f"{message}\n  {line}\n  {' ' * col}^"
        super().__init__(message)


# ---------------------------------------------------------------------------
# Parser
# ---------------------------------------------------------------------------


class _Parser:
    """Recursive-descent parser for WL surface syntax."""

    def __init__(self, source: str) -> None:
        self._source = source
        self._tokens = _tokenize(source)
        self._pos = 0

    def _peek(self) -> _Token | None:
        if self._pos < len(self._tokens):
            return self._tokens[self._pos]
        return None

    def _peek_type(self) -> str | None:
        tok = self._peek()
        return tok.type if tok else None

    def _consume(self) -> _Token:
        tok = self._tokens[self._pos]
        self._pos += 1
        return tok

    def _expect(self, ttype: str) -> _Token:
        tok = self._peek()
        if tok is None:
            raise WLParseError(
                f"Expected {ttype}, got end of input",
                pos=len(self._source),
                source=self._source,
            )
        if tok.type != ttype:
            raise WLParseError(
                f"Expected {ttype}, got {tok.type} ({tok.value!r})",
                pos=tok.pos,
                source=self._source,
            )
        return self._consume()

    def _error(self, msg: str) -> WLParseError:
        tok = self._peek()
        pos = tok.pos if tok else len(self._source)
        return WLParseError(msg, pos=pos, source=self._source)

    # ---------------------------------------------------------------
    # Top-level: Session = (Line (';' Line)* ';'?)*
    # ---------------------------------------------------------------

    def parse_session(self) -> list[WLExpr]:
        """Parse a full session (multiple statements)."""
        stmts: list[WLExpr] = []
        while self._peek() is not None:
            if self._peek_type() == "SEMI":
                self._consume()
                continue
            stmt = self._parse_assignment()
            stmts.append(stmt)
            # Consume optional trailing semicolon
            if self._peek_type() == "SEMI":
                self._consume()
        return stmts

    def parse_one(self) -> WLExpr:
        """Parse a single expression (may include assignment/comparison)."""
        result = self._parse_assignment()
        if self._peek() is not None:
            tok = self._peek()
            assert tok is not None
            raise self._error(f"Unexpected token after expression: {tok.value!r}")
        return result

    # ---------------------------------------------------------------
    # Assignment: ident '=' expr | expr ('==' | '===') expr | expr
    # ---------------------------------------------------------------

    def _parse_assignment(self) -> WLExpr:
        left = self._parse_pipe()

        # Assignment: result = expr
        if self._peek_type() == "EQ":
            eq_tok = self._consume()
            right = self._parse_pipe()
            return WLNode(head="Set", args=[left, right], pos=eq_tok.pos)

        # Comparison: expr == expr, expr === expr
        if self._peek_type() == "EQEQ":
            op_tok = self._consume()
            right = self._parse_pipe()
            return WLNode(head="Equal", args=[left, right], pos=op_tok.pos)

        if self._peek_type() == "EQEQEQ":
            op_tok = self._consume()
            right = self._parse_pipe()
            return WLNode(head="SameQ", args=[left, right], pos=op_tok.pos)

        # Rule: key -> value
        if self._peek_type() == "ARROW":
            op_tok = self._consume()
            right = self._parse_pipe()
            return WLNode(head="Rule", args=[left, right], pos=op_tok.pos)

        # Comparison: >, <
        if self._peek_type() == "GT":
            op_tok = self._consume()
            right = self._parse_pipe()
            return WLNode(head="Greater", args=[left, right], pos=op_tok.pos)

        if self._peek_type() == "LT":
            op_tok = self._consume()
            right = self._parse_pipe()
            return WLNode(head="Less", args=[left, right], pos=op_tok.pos)

        return left

    # ---------------------------------------------------------------
    # Postfix pipe: expr // F  →  F[expr]
    # ---------------------------------------------------------------

    def _parse_pipe(self) -> WLExpr:
        expr = self._parse_sum()
        while self._peek_type() == "PIPE":
            self._consume()
            func = self._parse_primary()
            # Rewrite: expr // F  →  F[expr]
            if isinstance(func, WLLeaf):
                expr = WLNode(head=func.value, args=[expr], pos=func.pos)
            else:
                expr = WLNode(head=func, args=[expr], pos=func.pos)
        return expr

    # ---------------------------------------------------------------
    # Top-level arithmetic (- is subtraction/negation)
    # ---------------------------------------------------------------

    def _parse_sum(self) -> WLExpr:
        left = self._parse_product()
        while self._peek_type() in ("PLUS", "MINUS"):
            op = self._consume()
            right = self._parse_product()
            if op.type == "MINUS":
                right = WLNode(head="Times", args=[WLLeaf("-1", op.pos), right], pos=op.pos)
            if isinstance(left, WLNode) and isinstance(left.head, str) and left.head == "Plus":
                left.args.append(right)
            else:
                left = WLNode(head="Plus", args=[left, right], pos=op.pos)
        return left

    def _parse_product(self) -> WLExpr:
        left = self._parse_power()
        while True:
            pt = self._peek_type()
            if pt == "STAR":
                self._consume()
                right = self._parse_power()
            elif pt == "SLASH":
                op = self._consume()
                right = self._parse_power()
                right = WLNode(head="Power", args=[right, WLLeaf("-1", op.pos)], pos=op.pos)
            elif pt == "NUMBER" or pt == "IDENT" or pt == "LPAREN" or pt == "LBRACE":
                # Implicit multiplication: 2 T[-a,-b] or T S
                right = self._parse_power()
            else:
                break
            if isinstance(left, WLNode) and isinstance(left.head, str) and left.head == "Times":
                left.args.append(right)
            else:
                left = WLNode(head="Times", args=[left, right], pos=right.pos)
        return left

    def _parse_power(self) -> WLExpr:
        base = self._parse_unary()
        if self._peek_type() == "CARET":
            self._consume()
            exp = self._parse_unary()
            return WLNode(head="Power", args=[base, exp], pos=base.pos)
        return base

    def _parse_unary(self) -> WLExpr:
        if self._peek_type() == "MINUS":
            op = self._consume()
            operand = self._parse_unary()
            return WLNode(head="Times", args=[WLLeaf("-1", op.pos), operand], pos=op.pos)
        return self._parse_postfix()

    # ---------------------------------------------------------------
    # Postfix application: primary ('[' arglist ']')*
    # ---------------------------------------------------------------

    def _parse_postfix(self) -> WLExpr:
        node = self._parse_primary()
        while self._peek_type() == "LBRACKET":
            self._consume()
            args = self._parse_bracket_arglist()
            self._expect("RBRACKET")
            if isinstance(node, WLLeaf):
                node = WLNode(head=node.value, args=args, pos=node.pos)
            else:
                node = WLNode(head=node, args=args, pos=node.pos)
        return node

    # ---------------------------------------------------------------
    # Primary: number | string | ident | '(' expr ')' | '{' ... '}'
    # ---------------------------------------------------------------

    def _parse_primary(self) -> WLExpr:
        tok = self._peek()
        if tok is None:
            raise self._error("Unexpected end of input")

        if tok.type == "NUMBER":
            self._consume()
            return WLLeaf(tok.value, tok.pos)

        if tok.type == "STRING":
            self._consume()
            return WLLeaf(tok.value, tok.pos)

        if tok.type == "IDENT":
            self._consume()
            return WLLeaf(tok.value, tok.pos)

        if tok.type == "LPAREN":
            self._consume()
            expr = self._parse_pipe()
            self._expect("RPAREN")
            return expr

        if tok.type == "LBRACE":
            return self._parse_list()

        raise self._error(f"Unexpected token: {tok.value!r}")

    def _parse_list(self) -> WLNode:
        tok = self._expect("LBRACE")
        items: list[WLExpr] = []
        if self._peek_type() != "RBRACE":
            items.append(self._parse_bracket_expr())
            while self._peek_type() == "COMMA":
                self._consume()
                items.append(self._parse_bracket_expr())
        self._expect("RBRACE")
        return WLNode(head="List", args=items, pos=tok.pos)

    # ---------------------------------------------------------------
    # Bracket-level expressions (inside [...] or {...})
    # -a is a signed index, not negation
    # ---------------------------------------------------------------

    def _parse_bracket_arglist(self) -> list[WLExpr]:
        args: list[WLExpr] = []
        if self._peek_type() == "RBRACKET":
            return args
        args.append(self._parse_bracket_expr())
        while self._peek_type() == "COMMA":
            self._consume()
            args.append(self._parse_bracket_expr())
        return args

    def _parse_bracket_expr(self) -> WLExpr:
        """Parse expression inside brackets — signed index aware."""
        left = self._parse_bracket_sum()
        # Arrow (->): rule
        if self._peek_type() == "ARROW":
            op = self._consume()
            right = self._parse_bracket_sum()
            return WLNode(head="Rule", args=[left, right], pos=op.pos)
        # Comparison operators inside brackets
        if self._peek_type() == "GT":
            op = self._consume()
            right = self._parse_bracket_sum()
            return WLNode(head="Greater", args=[left, right], pos=op.pos)
        if self._peek_type() == "LT":
            op = self._consume()
            right = self._parse_bracket_sum()
            return WLNode(head="Less", args=[left, right], pos=op.pos)
        return left

    def _parse_bracket_sum(self) -> WLExpr:
        left = self._parse_bracket_product()
        while self._peek_type() in ("PLUS", "MINUS"):
            op = self._consume()
            right = self._parse_bracket_product()
            if op.type == "MINUS":
                right = WLNode(head="Times", args=[WLLeaf("-1", op.pos), right], pos=op.pos)
            if isinstance(left, WLNode) and isinstance(left.head, str) and left.head == "Plus":
                left.args.append(right)
            else:
                left = WLNode(head="Plus", args=[left, right], pos=op.pos)
        return left

    def _parse_bracket_product(self) -> WLExpr:
        left = self._parse_bracket_power()
        while True:
            pt = self._peek_type()
            if pt == "STAR":
                self._consume()
                right = self._parse_bracket_power()
            elif pt == "SLASH":
                op = self._consume()
                right = self._parse_bracket_power()
                right = WLNode(head="Power", args=[right, WLLeaf("-1", op.pos)], pos=op.pos)
            elif pt == "NUMBER" or pt == "LPAREN":
                # Implicit multiplication inside brackets
                right = self._parse_bracket_power()
            elif pt == "IDENT":
                # Implicit multiplication: only if not followed by context
                # that would make this ambiguous
                right = self._parse_bracket_power()
            else:
                break
            if isinstance(left, WLNode) and isinstance(left.head, str) and left.head == "Times":
                left.args.append(right)
            else:
                left = WLNode(head="Times", args=[left, right], pos=right.pos)
        return left

    def _parse_bracket_power(self) -> WLExpr:
        base = self._parse_bracket_unary()
        if self._peek_type() == "CARET":
            self._consume()
            exp = self._parse_bracket_unary()
            return WLNode(head="Power", args=[base, exp], pos=base.pos)
        return base

    def _parse_bracket_unary(self) -> WLExpr:
        """Inside brackets: -ident is SignedIndex, -number or -(expr) is negation."""
        if self._peek_type() == "MINUS":
            minus_tok = self._tokens[self._pos]
            # Look ahead: if next token is IDENT with no whitespace gap → signed index
            if self._pos + 1 < len(self._tokens):
                next_tok = self._tokens[self._pos + 1]
                # Signed index: minus immediately before identifier (no space)
                if next_tok.type == "IDENT" and next_tok.pos == minus_tok.pos + 1:
                    self._consume()  # consume MINUS
                    ident = self._consume()  # consume IDENT
                    return WLLeaf(f"-{ident.value}", minus_tok.pos)
            # Fall through to regular negation
            self._consume()
            operand = self._parse_bracket_unary()
            return WLNode(
                head="Times",
                args=[WLLeaf("-1", minus_tok.pos), operand],
                pos=minus_tok.pos,
            )
        return self._parse_bracket_postfix()

    def _parse_bracket_postfix(self) -> WLExpr:
        node = self._parse_bracket_primary()
        while self._peek_type() == "LBRACKET":
            self._consume()
            args = self._parse_bracket_arglist()
            self._expect("RBRACKET")
            if isinstance(node, WLLeaf):
                node = WLNode(head=node.value, args=args, pos=node.pos)
            else:
                node = WLNode(head=node, args=args, pos=node.pos)
        return node

    def _parse_bracket_primary(self) -> WLExpr:
        tok = self._peek()
        if tok is None:
            raise self._error("Unexpected end of input")

        if tok.type == "NUMBER":
            self._consume()
            return WLLeaf(tok.value, tok.pos)

        if tok.type == "STRING":
            self._consume()
            return WLLeaf(tok.value, tok.pos)

        if tok.type == "IDENT":
            self._consume()
            return WLLeaf(tok.value, tok.pos)

        if tok.type == "LPAREN":
            self._consume()
            expr = self._parse_bracket_expr()
            self._expect("RPAREN")
            return expr

        if tok.type == "LBRACE":
            return self._parse_list()

        raise self._error(f"Unexpected token in bracket context: {tok.value!r}")


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def parse(source: str) -> WLExpr:
    """Parse a single WL expression.

    >>> parse("DefManifold[M, 4, {a, b, c, d}]")
    WLNode('DefManifold', [WLLeaf('M'), WLLeaf('4'), WLNode('List', [...])])
    """
    return _Parser(source.strip()).parse_one()


def parse_session(source: str) -> list[WLExpr]:
    """Parse a multi-statement WL session (semicolons, newlines, comments).

    >>> parse_session("DefManifold[M, 4, {a,b}]; DefMetric[-1, g[-a,-b], CD]")
    [WLNode('DefManifold', ...), WLNode('DefMetric', ...)]
    """
    return _Parser(source).parse_session()
