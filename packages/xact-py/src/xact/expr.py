"""Typed expression layer for xact.

Provides index types (Idx, DnIdx), tensor handles (TensorHead, CovDHead), and
expression nodes (AppliedTensor, SumExpr, ProdExpr, CovDExpr, TScalar, TSymbol)
that support Python operator overloading and serialise to the string format
expected by the xAct engine.

Engine functions in api.py are overloaded to accept these typed expressions
transparently — they convert via str() before calling the Julia engine.
Stage 2: when the input is a typed expression, engine functions also return
a typed expression (via _parse_to_texpr).
"""

from __future__ import annotations

from fractions import Fraction
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from xact.api import Manifold

# ---------------------------------------------------------------------------
# Index types
# ---------------------------------------------------------------------------


class Idx:
    """Abstract (contravariant / up) index bound to a manifold."""

    __slots__ = ("label", "manifold")

    def __init__(self, label: str, manifold: str) -> None:
        self.label = label
        self.manifold = manifold

    def __neg__(self) -> DnIdx:
        return DnIdx(self)

    def __repr__(self) -> str:
        return self.label

    def __str__(self) -> str:
        return self.label


class DnIdx:
    """Covariant (down) index — wraps an Idx."""

    __slots__ = ("parent",)

    def __init__(self, parent: Idx) -> None:
        self.parent = parent

    def __neg__(self) -> Idx:
        """Double negation returns the bare Idx (identity)."""
        return self.parent

    def __repr__(self) -> str:
        return f"-{self.parent.label}"

    def __str__(self) -> str:
        return f"-{self.parent.label}"


SlotIdx = Idx | DnIdx


# ---------------------------------------------------------------------------
# Expression base class
# ---------------------------------------------------------------------------


class TExpr:
    """Base class for all typed tensor expressions."""

    def __add__(self, other: TExpr) -> SumExpr:
        return SumExpr(_flatten_sum([self, other]))

    def __radd__(self, other: TExpr) -> SumExpr:
        return SumExpr(_flatten_sum([other, self]))

    def __sub__(self, other: TExpr) -> SumExpr:
        return SumExpr(_flatten_sum([self, _make_prod(-1, [other])]))

    def __rsub__(self, other: TExpr) -> SumExpr:
        return SumExpr(_flatten_sum([other, _make_prod(-1, [self])]))

    def __mul__(self, other: object) -> ProdExpr:
        if isinstance(other, (int, Fraction)):
            return _make_prod(other, [self])
        if isinstance(other, TExpr):
            return _make_prod(1, [self, other])
        return NotImplemented

    def __rmul__(self, other: object) -> ProdExpr:
        if isinstance(other, (int, Fraction)):
            return _make_prod(other, [self])
        return NotImplemented

    def __neg__(self) -> ProdExpr:
        return _make_prod(-1, [self])

    def __eq__(self, other: object) -> bool:
        if isinstance(other, str):
            return str(self) == other
        if isinstance(other, TExpr):
            return str(self) == str(other)
        return NotImplemented

    def __hash__(self) -> int:
        return hash(str(self))


# ---------------------------------------------------------------------------
# Expression node types
# ---------------------------------------------------------------------------


class TScalar(TExpr):
    """Numeric scalar coefficient (e.g., 0, 2, 1/2)."""

    def __init__(self, value: Fraction) -> None:
        self.value = value

    def __str__(self) -> str:
        if self.value.denominator == 1:
            return str(self.value.numerator)
        return f"({self.value.numerator}/{self.value.denominator})"

    def __repr__(self) -> str:
        return str(self)


class TSymbol(TExpr):
    """Bare symbol returned by the engine (no index slots)."""

    def __init__(self, name: str) -> None:
        self.name = name

    def __str__(self) -> str:
        return self.name

    def __repr__(self) -> str:
        return str(self)


class AppliedTensor(TExpr):
    """A tensor with indices applied, e.g. T[-a, -b]."""

    def __init__(self, head: TensorHead, indices: list[SlotIdx]) -> None:
        self.head = head
        self.indices = indices

    def __str__(self) -> str:
        idx = ",".join(str(i) for i in self.indices)
        return f"{self.head.name}[{idx}]"

    def __repr__(self) -> str:
        return str(self)


class SumExpr(TExpr):
    """Sum of tensor expressions."""

    def __init__(self, terms: list[TExpr]) -> None:
        self.terms = terms

    def __str__(self) -> str:
        if not self.terms:
            return "0"
        buf = []
        for i, term in enumerate(self.terms):
            s = str(term)
            if i == 0:
                buf.append(s)
            elif s.startswith("-"):
                buf.append(" - ")
                buf.append(s[1:])
            else:
                buf.append(" + ")
                buf.append(s)
        return "".join(buf)

    def __repr__(self) -> str:
        return str(self)


class ProdExpr(TExpr):
    """Product of tensor expressions with a rational coefficient.

    Serialises with space-separated factors (matching the Julia engine's
    ``_to_string`` format) so that the string is accepted by the engine's
    expression parser.
    """

    def __init__(self, coeff: Fraction, factors: list[TExpr]) -> None:
        self.coeff = coeff
        self.factors = factors

    def __str__(self) -> str:
        parts = [_str_factor(f) for f in self.factors]
        body = " ".join(parts)
        if self.coeff == 1:
            return body
        elif self.coeff == -1:
            return "-" + body
        elif self.coeff.denominator == 1:
            return f"{self.coeff.numerator} {body}"
        else:
            return f"({self.coeff.numerator}/{self.coeff.denominator}) {body}"

    def __repr__(self) -> str:
        return str(self)


class CovDExpr(TExpr):
    """Covariant derivative applied to an expression: CD[-a](T[-b,-c])."""

    def __init__(self, covd: str, index: SlotIdx, operand: TExpr) -> None:
        self.covd = covd
        self.index = index
        self.operand = operand

    def __str__(self) -> str:
        return f"{self.covd}[{self.index}][{self.operand}]"

    def __repr__(self) -> str:
        return str(self)


class _CovDApplicator:
    """Intermediate callable: ``CD[-a](expr)`` -> :class:`CovDExpr`."""

    __slots__ = ("covd", "index")

    def __init__(self, covd: str, index: SlotIdx) -> None:
        self.covd = covd
        self.index = index

    def __call__(self, operand: TExpr) -> CovDExpr:
        return CovDExpr(self.covd, self.index, operand)


# ---------------------------------------------------------------------------
# TensorHead and CovDHead
# ---------------------------------------------------------------------------


class TensorHead:
    """Lightweight handle for a registered tensor.  Supports T[-a, -b] syntax.

    Instances are created by :func:`tensor`.  The ``_nslots`` attribute stores
    the expected arity for fast Python-side validation.
    """

    def __init__(self, name: str, nslots: int = -1) -> None:
        self.name = name
        self._nslots = nslots

    def __getitem__(self, indices: object) -> AppliedTensor:
        if indices is None:
            idx_list: list[SlotIdx] = []
        elif isinstance(indices, tuple):
            idx_list = list(indices)
        else:
            idx_list = [indices]  # type: ignore[list-item]
        if self._nslots >= 0 and len(idx_list) != self._nslots:
            raise IndexError(f"{self.name} has {self._nslots} slots, got {len(idx_list)}")
        return AppliedTensor(self, idx_list)

    def __repr__(self) -> str:
        return f"TensorHead({self.name!r})"


class CovDHead:
    """Lightweight handle for a registered covariant derivative.

    Created by :func:`covd`.  Supports ``CD[-a](expr)`` syntax via
    ``__getitem__`` (returns a :class:`_CovDApplicator`) followed by a call.
    """

    __slots__ = ("name",)

    def __init__(self, name: str) -> None:
        self.name = name

    def __getitem__(self, idx: SlotIdx) -> _CovDApplicator:
        return _CovDApplicator(self.name, idx)

    def __repr__(self) -> str:
        return f"CovDHead({self.name!r})"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _make_prod(coeff: int | Fraction, nodes: list[TExpr]) -> ProdExpr:
    """Flatten nested ProdExpr and merge coefficients."""
    c = Fraction(coeff)
    flat: list[TExpr] = []
    for node in nodes:
        if isinstance(node, ProdExpr):
            c *= node.coeff
            flat.extend(node.factors)
        else:
            flat.append(node)
    return ProdExpr(c, flat)


def _flatten_sum(nodes: list[TExpr]) -> list[TExpr]:
    """Flatten nested SumExpr into a single flat term list."""
    terms: list[TExpr] = []
    for node in nodes:
        if isinstance(node, SumExpr):
            terms.extend(node.terms)
        else:
            terms.append(node)
    return terms


def _str_factor(f: TExpr) -> str:
    """Serialise a factor, parenthesising sums inside products."""
    return f"({f})" if isinstance(f, SumExpr) else str(f)


# ---------------------------------------------------------------------------
# Public factory functions (need Julia bridge -- imported lazily from api)
# ---------------------------------------------------------------------------


def indices(manifold: Manifold) -> tuple[Idx, ...]:
    """Return Idx objects for all abstract index labels of *manifold*.

    Example::

        a, b, c, d, e, f = xact.indices(M)
    """
    return tuple(Idx(label, manifold.name) for label in manifold.indices)


def tensor(name: str) -> TensorHead:
    """Look up a registered tensor and return a :class:`TensorHead`.

    Parameters
    ----------
    name:
        The tensor name as registered via :class:`~xact.Tensor` or
        auto-created by :class:`~xact.Metric` (e.g. ``"RiemannCD"``).

    Raises
    ------
    ValueError
        If the tensor is not registered in the current Julia session.
    """
    # Lazy import to avoid circular dependency
    from xact.api import _ensure_init

    _, mod = _ensure_init()
    if not bool(mod.TensorQ(name)):
        raise ValueError(f"Tensor {name!r} is not defined")
    nslots = len(mod.SlotsOfTensor(name))
    return TensorHead(name, nslots=nslots)


def covd(name: str) -> CovDHead:
    """Look up a registered covariant derivative and return a :class:`CovDHead`.

    Parameters
    ----------
    name:
        The covariant derivative name as registered via :class:`~xact.Metric`
        (e.g. ``"CD"``).

    Raises
    ------
    ValueError
        If the covariant derivative is not registered in the current Julia session.
    """
    from xact.api import _ensure_init

    _, mod = _ensure_init()
    if not bool(mod.CovDQ(name)):
        raise ValueError(f"Covariant derivative {name!r} is not defined")
    return CovDHead(name)


# ---------------------------------------------------------------------------
# Parser: engine string output -> TExpr  (Stage 2)
# ---------------------------------------------------------------------------


def _parse_to_texpr(s: str) -> TExpr:
    """Parse an engine output string into a typed expression tree.

    Supported formats (same as ``str(TExpr)`` output):

    - ``"0"`` -> :class:`TScalar` (zero)
    - ``"Name[i1,i2]"`` -> :class:`AppliedTensor`
    - ``"Name[-i][operand]"`` -> :class:`CovDExpr`
    - ``"2 Name[...]"`` / ``"(1/2) Name[...]"`` / ``"-Name[...]"`` -> :class:`ProdExpr`
    - ``"A + B"`` / ``"A - B"`` -> :class:`SumExpr`
    - bare name (no brackets) -> :class:`TSymbol`
    """
    return _texpr_parse_sum(s.strip())


def _texpr_find_close(s: str, open_pos: int) -> int:
    """Return index of the matching close bracket starting at ``open_pos``."""
    depth = 0
    i = open_pos
    n = len(s)
    while i < n:
        c = s[i]
        if c in ("[", "("):
            depth += 1
        elif c in ("]", ")"):
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise ValueError(f"Unmatched bracket in TExpr string: {s!r}")


def _texpr_depth0_split(s: str, sep: str) -> list[str]:
    """Split *s* at depth-0 occurrences of *sep*."""
    parts: list[str] = []
    depth = 0
    start = 0
    i = 0
    n = len(s)
    seplen = len(sep)
    while i < n:
        c = s[i]
        if c in ("(", "["):
            depth += 1
            i += 1
        elif c in (")", "]"):
            depth -= 1
            i += 1
        elif depth == 0 and s[i : i + seplen] == sep:
            parts.append(s[start:i])
            i += seplen
            start = i
        else:
            i += 1
    parts.append(s[start:])
    return parts


def _texpr_is_coeff(s: str) -> bool:
    if not s or s == "-":
        return False
    if s != "-" and all(c.isdigit() or c == "-" for c in s):
        return True
    s_inner = s[1:] if s.startswith("-") else s
    return s_inner.startswith("(") and s_inner.endswith(")") and "/" in s_inner


def _texpr_parse_rational(s: str) -> Fraction:
    s = s.strip()
    neg = s.startswith("-(")
    s_inner = s[1:] if neg else s
    if s_inner.startswith("(") and s_inner.endswith(")"):
        inner = s_inner[1:-1]
        slash = inner.index("/")
        r = Fraction(int(inner[:slash].strip()), int(inner[slash + 1 :].strip()))
        return -r if neg else r
    return Fraction(int(s))


def _texpr_parse_idx(s: str) -> SlotIdx:
    s = s.strip()
    if s.startswith("-"):
        return DnIdx(Idx(s[1:], ""))
    return Idx(s, "")


def _texpr_parse_atom(s: str) -> TExpr:
    s = s.strip()
    bracket1 = s.find("[")
    if bracket1 == -1:
        return TSymbol(s)
    name = s[:bracket1]
    close1 = _texpr_find_close(s, bracket1)
    # CovD: Name[-idx][operand]
    if close1 + 1 < len(s) and s[close1 + 1] == "[":
        idx_str = s[bracket1 + 1 : close1]
        open2 = close1 + 1
        close2 = _texpr_find_close(s, open2)
        op_str = s[open2 + 1 : close2]
        idx = _texpr_parse_idx(idx_str)
        operand = _texpr_parse_sum(op_str)
        return CovDExpr(name, idx, operand)
    # Tensor: Name[i1,i2,...]
    indices_str = s[bracket1 + 1 : close1]
    if not indices_str.strip():
        idx_list: list[SlotIdx] = []
    else:
        idx_list = [_texpr_parse_idx(p) for p in indices_str.split(",")]
    return AppliedTensor(TensorHead(name), idx_list)


def _texpr_parse_term(s: str) -> TExpr:
    s = s.strip()
    if s == "0":
        return TScalar(Fraction(0))
    # Try " * " split first (round-trip format). Fall back to space split (engine format).
    factors = _texpr_depth0_split(s, " * ")
    if len(factors) == 1:
        factors = [f for f in _texpr_depth0_split(s, " ") if f]
    if not factors:
        return TScalar(Fraction(0))

    first = factors[0]
    coeff = Fraction(1)
    atom_start = 0

    if _texpr_is_coeff(first):
        coeff = _texpr_parse_rational(first)
        atom_start = 1
    elif first.startswith("-") and len(first) > 1:
        coeff = Fraction(-1)
        factors[0] = first[1:]

    if atom_start >= len(factors):
        return TScalar(coeff)

    atoms = [_texpr_parse_atom(factors[k].strip()) for k in range(atom_start, len(factors))]
    if len(atoms) == 1 and coeff == 1:
        return atoms[0]
    return _make_prod(int(coeff) if coeff.denominator == 1 else coeff, atoms)


def _texpr_parse_sum(s: str) -> TExpr:
    """Parse ``"A + B - C"`` -> :class:`SumExpr`."""
    signs: list[int] = [1]
    term_strs: list[str] = []
    depth = 0
    i = 0
    seg_start = 0
    n = len(s)
    while i < n:
        c = s[i]
        if c in ("(", "["):
            depth += 1
            i += 1
        elif c in (")", "]"):
            depth -= 1
            i += 1
        elif depth == 0 and c == " " and i + 2 < n and s[i + 1] in ("+", "-") and s[i + 2] == " ":
            term_strs.append(s[seg_start:i].strip())
            signs.append(1 if s[i + 1] == "+" else -1)
            i += 3
            seg_start = i
        else:
            i += 1
    term_strs.append(s[seg_start:].strip())

    terms: list[TExpr] = []
    for k, ts in enumerate(term_strs):
        t = _texpr_parse_term(ts)
        if signs[k] < 0:
            t = _make_prod(-1, [t])
        terms.append(t)

    return terms[0] if len(terms) == 1 else SumExpr(terms)
