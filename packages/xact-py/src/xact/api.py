"""Public Python API for xAct tensor algebra.

Provides a Pythonic interface to the Julia xAct.jl engine. All Julia
internals (juliacall, Symbol conversion, Vector wrapping) are hidden.

Example::

    import xact

    M = xact.Manifold("M", 4, ["a", "b", "c", "d", "e", "f"])
    g = xact.Metric(M, "g", signature=-1, covd="CD")
    T = xact.Tensor("T", ["-a", "-b"], M, symmetry="Symmetric[{-a,-b}]")

    xact.canonicalize("T[-b,-a] - T[-a,-b]")  # "0"
"""

from __future__ import annotations

import threading
from typing import Any

from xact._bridge import jl_call, jl_int, jl_str, jl_sym, jl_sym_list

# ---------------------------------------------------------------------------
# Lazy Julia bridge — initialized on first use
# ---------------------------------------------------------------------------

_lock = threading.Lock()
_xAct: Any = None
_jl: Any = None


def _ensure_init() -> tuple[Any, Any]:
    """Return (jl_Main, xAct_module), initializing Julia once."""
    global _xAct, _jl
    if _xAct is not None:
        return _jl, _xAct
    with _lock:
        if _xAct is None:
            from xact.xcore._runtime import get_julia

            _jl = get_julia()
            _xAct = _jl.xAct
    return _jl, _xAct


def _to_jl_vec(lst: list[str]) -> Any:
    """Convert a Python list of strings to a Julia Vector{String}."""
    jl, _ = _ensure_init()
    if not lst:
        return jl.seval("String[]")
    return jl.seval("collect")(lst)


# ---------------------------------------------------------------------------
# Handle types — lightweight Python representations of Julia objects
# ---------------------------------------------------------------------------


class Manifold:
    """A differentiable manifold.

    Parameters
    ----------
    name : str
        Manifold identifier (e.g. ``"M"``).
    dim : int
        Dimension of the manifold.
    indices : list[str]
        Abstract index labels (e.g. ``["a", "b", "c", "d"]``).

    Example
    -------
    >>> M = xact.Manifold("M", 4, ["a", "b", "c", "d", "e", "f"])
    """

    def __init__(self, name: str, dim: int, indices: list[str]) -> None:
        if not name or not name.isidentifier():
            raise ValueError(f"Manifold name must be a valid identifier, got {name!r}")
        if dim < 1:
            raise ValueError(f"Manifold dimension must be >= 1, got {dim}")
        if not indices:
            raise ValueError("Manifold requires at least one index label")
        if len(indices) < 2:
            raise ValueError(
                f"Manifold requires at least 2 index labels (for metric definition), "
                f"got {len(indices)}"
            )
        _, mod = _ensure_init()
        mod.def_manifold_b(name, dim, _to_jl_vec(indices))
        self.name = name
        self.dim = dim
        self.indices = indices

    def __repr__(self) -> str:
        return f"Manifold({self.name!r}, {self.dim})"


class Metric:
    """A metric tensor with associated covariant derivative.

    Automatically registers Riemann, Ricci, RicciScalar, Weyl, Einstein,
    and Christoffel tensors.

    Parameters
    ----------
    manifold : Manifold
        The manifold this metric lives on (used for documentation only;
        the Julia side infers the manifold from the index slots).
    name : str
        Metric tensor name (e.g. ``"g"``).
    signature : int
        Sign of the metric determinant (``-1`` for Lorentzian, ``1`` for
        Euclidean).
    covd : str
        Name of the associated covariant derivative (e.g. ``"CD"``).
    indices : tuple[str, str]
        Index slot specification. Defaults to ``("-a", "-b")`` using the
        first two indices of the manifold.

    Example
    -------
    >>> g = xact.Metric(M, "g", signature=-1, covd="CD")
    """

    def __init__(
        self,
        manifold: Manifold,
        name: str,
        *,
        signature: int = -1,
        covd: str = "CD",
        indices: tuple[str, str] | None = None,
    ) -> None:
        if not isinstance(manifold, Manifold):
            raise TypeError(f"manifold must be a Manifold instance, got {type(manifold).__name__}")
        if not name or not name.isidentifier():
            raise ValueError(f"Metric name must be a valid identifier, got {name!r}")
        if signature not in (-1, 1):
            raise ValueError(
                f"signature must be -1 (Lorentzian) or 1 (Euclidean), got {signature}"
            )
        _, mod = _ensure_init()
        if indices is None:
            a, b = manifold.indices[0], manifold.indices[1]
            idx_str = f"{name}[-{a},-{b}]"
        else:
            idx_str = f"{name}[{indices[0]},{indices[1]}]"
        mod.def_metric_b(signature, idx_str, covd)
        self.name = name
        self.manifold = manifold
        self.covd = covd

    def __repr__(self) -> str:
        return f"Metric({self.name!r}, covd={self.covd!r})"

    def __getitem__(self, indices: object) -> Any:
        from xact.expr import AppliedTensor, TensorHead

        if not isinstance(indices, tuple):
            indices = (indices,)
        return AppliedTensor(TensorHead(self.name), list(indices))


class Tensor:
    """An abstract tensor.

    Parameters
    ----------
    name : str
        Tensor identifier (e.g. ``"T"``).
    indices : list[str]
        Index slot specification (e.g. ``["-a", "-b"]`` for covariant).
    manifold : Manifold
        The manifold the tensor is defined on.
    symmetry : str, optional
        Symmetry specification in xAct syntax (e.g.
        ``"Symmetric[{-a,-b}]"``).

    Example
    -------
    >>> T = xact.Tensor("T", ["-a", "-b"], M, symmetry="Symmetric[{-a,-b}]")
    """

    def __init__(
        self,
        name: str,
        indices: list[str],
        manifold: Manifold,
        *,
        symmetry: str | None = None,
    ) -> None:
        if not name or not name.isidentifier():
            raise ValueError(f"Tensor name must be a valid identifier, got {name!r}")
        if not isinstance(manifold, Manifold):
            raise TypeError(f"manifold must be a Manifold instance, got {type(manifold).__name__}")
        _, mod = _ensure_init()
        kwargs: dict[str, str] = {}
        if symmetry is not None:
            kwargs["symmetry_str"] = symmetry
        mod.def_tensor_b(name, _to_jl_vec(indices), manifold.name, **kwargs)
        self.name = name
        self.indices = indices
        self.manifold = manifold

    def __getitem__(self, indices: object) -> Any:
        from xact.expr import AppliedTensor, TensorHead

        if not isinstance(indices, tuple):
            indices = (indices,)
        nslots = len(self.indices)
        if len(indices) != nslots:
            raise IndexError(f"{self.name} has {nslots} slots, got {len(indices)}")
        return AppliedTensor(TensorHead(self.name), list(indices))

    def __repr__(self) -> str:
        return f"Tensor({self.name!r}, {self.indices})"


class Perturbation:
    """A perturbation of a background tensor.

    The perturbation tensor must be defined first via :class:`Tensor`.

    Parameters
    ----------
    tensor : Tensor
        The perturbation tensor (e.g. ``h``).
    background : Metric | Tensor
        The background tensor being perturbed (e.g. ``g``).
    order : int
        Perturbation order (>= 1).

    Example
    -------
    >>> h = xact.Tensor("h", ["-a", "-b"], M, symmetry="Symmetric[{-a,-b}]")
    >>> xact.Perturbation(h, g, order=1)
    """

    def __init__(
        self,
        tensor: Tensor,
        background: Metric | Tensor,
        *,
        order: int = 1,
    ) -> None:
        if not isinstance(tensor, Tensor):
            raise TypeError(f"tensor must be a Tensor instance, got {type(tensor).__name__}")
        if not isinstance(background, (Metric, Tensor)):
            raise TypeError(
                f"background must be a Metric or Tensor instance, got {type(background).__name__}"
            )
        if order < 1:
            raise ValueError(f"Perturbation order must be >= 1, got {order}")
        _, mod = _ensure_init()
        mod.def_perturbation_b(tensor.name, background.name, order)
        self.tensor = tensor
        self.background = background
        self.order = order

    def __repr__(self) -> str:
        return f"Perturbation({self.tensor.name!r}, {self.background.name!r}, order={self.order})"


# ---------------------------------------------------------------------------
# Expression operations
# ---------------------------------------------------------------------------


def canonicalize(expr: str | Any) -> str | Any:
    """Bring a tensor expression into canonical form.

    Uses the Butler-Portugal algorithm to find the lexicographically
    smallest representative under index permutation symmetries.

    Accepts either a string expression or a typed expression object
    (from :mod:`xact.expr`).  When the input is a typed expression,
    the result is also returned as a typed expression.

    Example
    -------
    >>> xact.canonicalize("T[-b,-a] - T[-a,-b]")
    '0'
    """
    from xact.expr import TExpr, _parse_to_texpr

    is_typed = isinstance(expr, TExpr)
    if is_typed:
        expr = str(expr)
    _, mod = _ensure_init()
    result = str(mod.ToCanonical(expr))
    return _parse_to_texpr(result) if is_typed else result


def contract(expr: str | Any) -> str | Any:
    """Evaluate metric contractions in a tensor expression.

    Accepts either a string expression or a typed expression object.
    When the input is typed, the result is also a typed expression.

    Example
    -------
    >>> xact.contract("V[a] * g[-a,-b]")
    'V[-b]'
    """
    from xact.expr import TExpr, _parse_to_texpr

    is_typed = isinstance(expr, TExpr)
    if is_typed:
        expr = str(expr)
    _, mod = _ensure_init()
    result = str(mod.Contract(expr))
    return _parse_to_texpr(result) if is_typed else result


def simplify(expr: str | Any) -> str | Any:
    """Iteratively contract and canonicalize until stable.

    Accepts either a string expression or a typed expression object.
    When the input is typed, the result is also a typed expression.

    Example
    -------
    >>> xact.simplify("T[-a,-b] * g[a,b]")
    """
    from xact.expr import TExpr, _parse_to_texpr

    is_typed = isinstance(expr, TExpr)
    if is_typed:
        expr = str(expr)
    _, mod = _ensure_init()
    result = str(mod.Simplify(expr))
    return _parse_to_texpr(result) if is_typed else result


def perturb(expr: str | Any, order: int = 1) -> str | Any:
    """Perturb a tensor expression to the given order.

    Applies the multinomial Leibniz expansion.
    Accepts either a string expression or a typed expression object.
    When the input is typed, the result is also a typed expression.

    Example
    -------
    >>> xact.perturb("g[-a,-b]", order=1)
    'h[-a,-b]'
    """
    from xact.expr import TExpr, _parse_to_texpr

    is_typed = isinstance(expr, TExpr)
    if is_typed:
        expr = str(expr)
    _, mod = _ensure_init()
    result = str(mod.perturb(expr, order))
    return _parse_to_texpr(result) if is_typed else result


def commute_covds(expr: str | Any, covd: str, index1: str, index2: str) -> str | Any:
    """Commute two covariant derivative indices, producing curvature terms.

    Parameters
    ----------
    expr : str or TExpr
        Expression containing covariant derivatives.
    covd : str
        Name of the covariant derivative (e.g. ``"CD"``).
    index1, index2 : str
        The two derivative indices to commute.
    """
    from xact.expr import TExpr, _parse_to_texpr

    is_typed = isinstance(expr, TExpr)
    if is_typed:
        expr = str(expr)
    jl, _ = _ensure_init()
    result = str(
        jl_call(
            jl,
            "XTensor.CommuteCovDs",
            jl_str(expr),
            jl_sym(covd, "covariant derivative"),
            jl_str(index1),
            jl_str(index2),
        )
    )
    return _parse_to_texpr(result) if is_typed else result


def sort_covds(expr: str | Any, covd: str) -> str | Any:
    """Sort all covariant derivatives into canonical order."""
    from xact.expr import TExpr, _parse_to_texpr

    is_typed = isinstance(expr, TExpr)
    if is_typed:
        expr = str(expr)
    jl, _ = _ensure_init()
    result = str(
        jl_call(jl, "XTensor.SortCovDs", jl_str(expr), jl_sym(covd, "covariant derivative"))
    )
    return _parse_to_texpr(result) if is_typed else result


def ibp(expr: str | Any, covd: str) -> str | Any:
    """Integration by parts — move a covariant derivative off a field.

    When the input is a typed expression, the result is also a typed expression.
    """
    from xact.expr import TExpr, _parse_to_texpr

    is_typed = isinstance(expr, TExpr)
    if is_typed:
        expr = str(expr)
    _, mod = _ensure_init()
    result = str(mod.IBP(expr, covd))
    return _parse_to_texpr(result) if is_typed else result


def total_derivative_q(expr: str, covd: str) -> bool:
    """Check whether an expression is a total covariant derivative."""
    _, mod = _ensure_init()
    return bool(mod.TotalDerivativeQ(expr, covd))


def var_d(expr: str | Any, field: str, covd: str) -> str | Any:
    """Euler-Lagrange variational derivative.

    When the input is a typed expression, the result is also a typed expression.
    """
    from xact.expr import TExpr, _parse_to_texpr

    is_typed = isinstance(expr, TExpr)
    if is_typed:
        expr = str(expr)
    _, mod = _ensure_init()
    result = str(mod.VarD(expr, field, covd))
    return _parse_to_texpr(result) if is_typed else result


def riemann_simplify(expr: str | Any, covd: str, *, level: int = 6) -> str | Any:
    """Simplify scalar Riemann polynomial expressions.

    Uses the Invar database to reduce expressions modulo
    algebraic and differential identities.

    Parameters
    ----------
    expr : str or TExpr
        A scalar polynomial in Riemann, Ricci, etc.
    covd : str
        Covariant derivative name.
    level : int
        Simplification level (1-6). Default 6 (all identities).
    """
    from xact.expr import TExpr, _parse_to_texpr

    is_typed = isinstance(expr, TExpr)
    if is_typed:
        expr = str(expr)
    _, mod = _ensure_init()
    result = str(mod.RiemannSimplify(expr, covd, level=level))
    return _parse_to_texpr(result) if is_typed else result


# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------


def reset() -> None:
    """Reset all global tensor algebra state.

    Clears all manifold, metric, tensor, and perturbation definitions.
    """
    _, mod = _ensure_init()
    mod.reset_state_b()


def dimension(manifold: Manifold | str) -> int:
    """Return the dimension of a manifold."""
    _, mod = _ensure_init()
    name = manifold.name if isinstance(manifold, Manifold) else manifold
    return int(mod.Dimension(name))


# ---------------------------------------------------------------------------
# Private seval helpers (for ops that need Julia array literals)
# ---------------------------------------------------------------------------


# _jl_escape removed — use jl_escape from xact._bridge instead


def _nested_list_to_julia(data: object) -> str:
    """Convert a nested Python list to a Julia array literal string for seval."""
    if not isinstance(data, list):
        return f"fill({data})"
    if not data:
        return "Any[]"
    if not isinstance(data[0], list):
        return "Any[" + ", ".join(str(x) for x in data) + "]"
    if not isinstance(data[0][0], list):
        rows = [" ".join(str(x) for x in row) for row in data]
        return "Any[" + "; ".join(rows) + "]"

    def _flatten(lst: object) -> list[object]:
        if not isinstance(lst, list):
            return [lst]
        result: list[object] = []
        for item in lst:
            result.extend(_flatten(item))
        return result

    def _shape(lst: object) -> list[int]:
        dims: list[int] = []
        cur: object = lst
        while isinstance(cur, list):
            dims.append(len(cur))
            cur = cur[0]
        return dims

    flat = _flatten(data)
    dims = _shape(data)
    flat_jl = "Any[" + ", ".join(str(x) for x in flat) + "]"
    dims_jl = ", ".join(str(d) for d in reversed(dims))
    return f"permutedims(reshape({flat_jl}, {dims_jl}), {len(dims)}:-1:1)"


# ---------------------------------------------------------------------------
# xCoba — coordinate basis and component operations
# ---------------------------------------------------------------------------


class Basis:
    """A coordinate basis on a vector bundle.

    Parameters
    ----------
    name : str
        Basis identifier (e.g. ``"Bcart"``).
    vbundle : str
        Vector bundle the basis is defined on (e.g. ``"TangentM"``).
    cnumbers : list[int]
        Coordinate numbers identifying the basis slots.

    Example
    -------
    >>> B = xact.Basis("Bcart", "TangentM", [1, 2, 3, 4])
    """

    def __init__(self, name: str, vbundle: str, cnumbers: list[int]) -> None:
        def_basis(name, vbundle, cnumbers)
        self.name = name
        self.vbundle = vbundle
        self.cnumbers = cnumbers

    def __repr__(self) -> str:
        return f"Basis({self.name!r}, {self.vbundle!r})"


class Chart:
    """A coordinate chart on a manifold.

    Internally creates a coordinate basis and registers the coordinate
    scalar fields as tensors.

    Parameters
    ----------
    name : str
        Chart identifier (e.g. ``"SchC"``).
    manifold : Manifold | str
        The manifold this chart covers.
    cnumbers : list[int]
        Coordinate numbers identifying the chart slots.
    scalars : list[str]
        Coordinate scalar field names (e.g. ``["t", "r", "th", "ph"]``).

    Example
    -------
    >>> C = xact.Chart("SchC", M, [1, 2, 3, 4], ["t", "r", "th", "ph"])
    """

    def __init__(
        self,
        name: str,
        manifold: Manifold | str,
        cnumbers: list[int],
        scalars: list[str],
    ) -> None:
        manifold_name = manifold.name if isinstance(manifold, Manifold) else manifold
        def_chart(name, manifold_name, cnumbers, scalars)
        self.name = name
        self.manifold = manifold
        self.cnumbers = cnumbers
        self.scalars = scalars

    def __repr__(self) -> str:
        mname = self.manifold.name if isinstance(self.manifold, Manifold) else self.manifold
        return f"Chart({self.name!r}, {mname!r})"


def def_basis(name: str, vbundle: str, cnumbers: list[int]) -> None:
    """Define a coordinate basis."""
    jl, _ = _ensure_init()
    cn_jl = "[" + ", ".join(jl_int(c) for c in cnumbers) + "]"
    jl_call(
        jl,
        "XTensor.def_basis!",
        jl_sym(name, "basis name"),
        jl_sym(vbundle, "vector bundle"),
        cn_jl,
    )


def def_chart(name: str, manifold: str, cnumbers: list[int], scalars: list[str]) -> None:
    """Define a coordinate chart with scalar coordinate symbols."""
    jl, _ = _ensure_init()
    cn_jl = "[" + ", ".join(jl_int(c) for c in cnumbers) + "]"
    sc_jl = jl_sym_list(scalars, "chart scalars")
    jl_call(
        jl,
        "XTensor.def_chart!",
        jl_sym(name, "chart name"),
        jl_sym(manifold, "manifold"),
        cn_jl,
        sc_jl,
    )


def set_basis_change(from_basis: str, to_basis: str, matrix: list[list[object]]) -> None:
    """Register the Jacobian matrix between two bases."""
    jl, _ = _ensure_init()
    mat_jl = _nested_list_to_julia(matrix)
    jl_call(
        jl,
        "XTensor.set_basis_change!",
        jl_sym(from_basis, "from basis"),
        jl_sym(to_basis, "to basis"),
        mat_jl,
    )


def change_basis(expr: str, slot: int, from_basis: str, to_basis: str) -> str:
    """Change the basis of one index slot in an expression."""
    jl, _ = _ensure_init()
    # expr is a Julia expression that evaluates to an array — pass through raw
    result = jl_call(
        jl,
        "XTensor.change_basis",
        expr,
        "Symbol[]",
        jl_int(slot),
        jl_sym(from_basis, "from basis"),
        jl_sym(to_basis, "to basis"),
    )
    return str(result)


def get_jacobian(basis1: str, basis2: str) -> str:
    """Return the Jacobian scalar between two bases."""
    jl, _ = _ensure_init()
    result = jl_call(jl, "XTensor.Jacobian", jl_sym(basis1, "basis1"), jl_sym(basis2, "basis2"))
    return str(result)


def basis_change_q(from_basis: str, to_basis: str) -> bool:
    """Return True if a basis change between two bases is registered."""
    jl, _ = _ensure_init()
    result = jl_call(
        jl,
        "XTensor.BasisChangeQ",
        jl_sym(from_basis, "from basis"),
        jl_sym(to_basis, "to basis"),
    )
    return result is True or str(result).lower() == "true"


class CTensor:
    """A coordinate component tensor — array of component values in a given basis.

    Returned by :func:`get_components`, :func:`to_basis`,
    :func:`trace_basis_dummy`, and :func:`christoffel`.

    Attributes
    ----------
    tensor : str
        Name of the abstract tensor (e.g. ``"g"``).
    array : list
        Component values as a (nested) Python list.
    bases : list[str]
        Basis names for each slot.
    weight : int
        Tensor density weight (usually 0).
    """

    def __init__(
        self,
        tensor: str,
        array: list[object],
        bases: list[str],
        weight: int = 0,
        julia_str: str | None = None,
    ) -> None:
        self.tensor = tensor
        self.array = array
        self.bases = bases
        self.weight = weight
        self._julia_str = julia_str

    def __repr__(self) -> str:
        return f"CTensor({self.tensor!r}, bases={self.bases!r})"


def _jl_to_scalar(v: Any) -> int | float:
    """Convert a Julia scalar to Python int or float."""
    f = float(v)
    return int(f) if f == int(f) else f


def _jl_to_list(obj: Any) -> Any:
    """Convert a Julia array to nested Python lists, preserving shape.

    Uses numpy if available (fast path), otherwise reshapes manually from
    the flat column-major iteration order using .shape.
    """
    ndim = getattr(obj, "ndim", None)
    if ndim is None:
        return _jl_to_scalar(obj)
    if ndim == 0:
        # 0-dimensional array: extract the single element
        flat = [_jl_to_scalar(x) for x in obj]
        return flat[0] if flat else _jl_to_scalar(obj)

    # Fast path: use numpy if available
    try:
        return obj.to_numpy().tolist()
    except (ImportError, ModuleNotFoundError):
        pass

    # Pure-Python fallback: flat column-major → nested row-major lists
    shape = obj.shape
    flat = [_jl_to_scalar(x) for x in obj]
    if len(shape) == 1:
        return flat
    return _reshape_colmajor(flat, shape)


def _reshape_colmajor(flat: list[int | float], shape: tuple[int, ...]) -> list[Any]:
    """Reshape a flat column-major list into nested row-major Python lists."""
    if len(shape) == 1:
        return flat
    # Julia arrays are column-major: first index varies fastest
    # For 2D (rows, cols): flat[i + j*rows] = arr[i, j]
    rows, cols = shape[0], shape[1]
    if len(shape) == 2:
        return [[flat[i + j * rows] for j in range(cols)] for i in range(rows)]
    # For 3D+: recurse on slices
    stride = 1
    for d in shape[:-1]:
        stride *= d
    slices = [flat[i * stride : (i + 1) * stride] for i in range(shape[-1])]
    inner_shape = shape[:-1]
    result_slices = [_reshape_colmajor(s, inner_shape) for s in slices]
    # Transpose outermost: Julia stores last index slowest
    n_first = shape[0]
    return [[result_slices[k][i] for k in range(shape[-1])] for i in range(n_first)]


def _ct_from_julia(ct_jl: Any) -> CTensor:
    """Convert a Julia CTensorObj to a Python CTensor."""
    tensor_name = str(ct_jl.tensor).lstrip(":")
    array = _jl_to_list(ct_jl.array)
    bases = [str(b).lstrip(":") for b in ct_jl.bases]
    weight = int(ct_jl.weight)
    julia_str = str(ct_jl.array)
    return CTensor(tensor_name, array, bases, weight, julia_str=julia_str)


def set_components(
    tensor: str, array: list[object], bases: list[str], *, weight: int = 0
) -> CTensor:
    """Set coordinate components of a tensor.

    Returns the resulting :class:`CTensor`.
    """
    jl, _ = _ensure_init()
    arr_jl = _nested_list_to_julia(array)
    bases_jl = jl_sym_list(bases, "component bases")
    t_jl = jl_sym(tensor, "tensor")
    w_jl = jl_int(weight)
    ct_jl = jl.seval(f"XTensor.set_components!({t_jl}, {arr_jl}, {bases_jl}; weight={w_jl})")
    return _ct_from_julia(ct_jl)


def get_components(tensor: str, bases: list[str]) -> CTensor:
    """Return the component array of a tensor as a :class:`CTensor`."""
    jl, _ = _ensure_init()
    ct_jl = jl_call(
        jl,
        "XTensor.get_components",
        jl_sym(tensor, "tensor"),
        jl_sym_list(bases, "component bases"),
    )
    return _ct_from_julia(ct_jl)


def component_value(tensor: str, indices: list[int], bases: list[str]) -> Any:
    """Return a single component value of a tensor."""
    jl, _ = _ensure_init()
    idx_jl = "[" + ", ".join(jl_int(i) for i in indices) + "]"
    result = jl_call(
        jl,
        "XTensor.component_value",
        jl_sym(tensor, "tensor"),
        idx_jl,
        jl_sym_list(bases, "component bases"),
    )
    # Preserve the Julia type: juliacall maps Int64→int, Float64→float
    if isinstance(result, (int, float)):
        return result
    try:
        return float(result)
    except (TypeError, ValueError):
        return str(result)


def ctensor_q(tensor: str, *bases: str) -> bool:
    """Return True if tensor has components registered for the given bases."""
    jl, _ = _ensure_init()
    bases_args = [jl_sym(b, "basis") for b in bases]
    result = jl_call(jl, "XTensor.CTensorQ", jl_sym(tensor, "tensor"), *bases_args)
    return result is True or str(result).lower() == "true"


def to_basis(expr: str | Any, basis: str) -> CTensor:
    """Project an abstract expression into a coordinate basis.

    Accepts a string expression or a typed :class:`~xact.expr.TExpr`.
    Returns a :class:`CTensor` with the component array.
    """
    from xact.expr import TExpr

    if isinstance(expr, TExpr):
        expr = str(expr)
    jl, _ = _ensure_init()
    ct_jl = jl_call(jl, "XTensor.ToBasis", jl_str(expr), jl_sym(basis, "basis"))
    return _ct_from_julia(ct_jl)


def from_basis(tensor: str, bases: list[str]) -> str:
    """Convert component tensor back to abstract index notation.

    Returns the abstract tensor expression as a string.
    """
    jl, _ = _ensure_init()
    result = jl_call(
        jl,
        "XTensor.FromBasis",
        jl_sym(tensor, "tensor"),
        jl_sym_list(bases, "component bases"),
    )
    return str(result)


def trace_basis_dummy(tensor: str, bases: list[str]) -> CTensor:
    """Trace dummy indices in component tensor.

    Returns a :class:`CTensor` with the traced component array.
    """
    jl, _ = _ensure_init()
    ct_jl = jl_call(
        jl,
        "XTensor.TraceBasisDummy",
        jl_sym(tensor, "tensor"),
        jl_sym_list(bases, "component bases"),
    )
    return _ct_from_julia(ct_jl)


def christoffel(metric: str, basis: str, *, metric_derivs: list[object] | None = None) -> CTensor:
    """Compute Christoffel symbols from metric components.

    Returns a :class:`CTensor` of shape ``(dim, dim, dim)`` representing
    Γ^a_{bc}.
    """
    jl, _ = _ensure_init()
    m_jl = jl_sym(metric, "metric")
    b_jl = jl_sym(basis, "basis")
    if metric_derivs is not None:
        dg_jl = _nested_list_to_julia(metric_derivs)
        ct_jl = jl.seval(f"XTensor.christoffel!({m_jl}, {b_jl}; metric_derivs={dg_jl})")
    else:
        ct_jl = jl_call(jl, "XTensor.christoffel!", m_jl, b_jl)
    return _ct_from_julia(ct_jl)


# ---------------------------------------------------------------------------
# xTras — extended tensor utilities
# ---------------------------------------------------------------------------


def collect_tensors(expr: str) -> str:
    """Group like tensor terms."""
    _, mod = _ensure_init()
    return str(mod.CollectTensors(expr))


def all_contractions(expr: str, metric: str) -> list[str]:
    """Enumerate all possible contractions of an expression."""
    jl, _ = _ensure_init()
    result = jl_call(jl, "XTensor.AllContractions", jl_str(expr), jl_sym(metric, "metric"))
    return [str(x) for x in result]


def symmetry_of(expr: str) -> str:
    """Return the symmetry type of a tensor expression."""
    _, mod = _ensure_init()
    return str(mod.SymmetryOf(expr))


def make_trace_free(expr: str, metric: str) -> str:
    """Project an expression to its trace-free part."""
    jl, _ = _ensure_init()
    return str(jl_call(jl, "XTensor.MakeTraceFree", jl_str(expr), jl_sym(metric, "metric")))


# ---------------------------------------------------------------------------
# Perturbation utilities
# ---------------------------------------------------------------------------


def check_metric_consistency(metric: str) -> bool:
    """Check that a metric tensor is self-consistent."""
    jl, _ = _ensure_init()
    result = jl_call(jl, "XTensor.check_metric_consistency", jl_sym(metric, "metric"))
    return result is True or str(result).lower() == "true"


def perturb_curvature(covd: str, perturbation: str, *, order: int = 1) -> dict[str, str]:
    """Return first-order perturbations of curvature tensors.

    Returns a dict with keys ``"Christoffel1"``, ``"Riemann1"``,
    ``"Ricci1"``, ``"RicciScalar1"``.
    """
    jl, _ = _ensure_init()
    c_jl = jl_sym(covd, "covariant derivative")
    p_jl = jl_sym(perturbation, "perturbation")
    o_jl = jl_int(order)
    result = jl.seval(f"XTensor.perturb_curvature({c_jl}, {p_jl}; order={o_jl})")
    return {str(k): str(v) for k, v in result.items()}


def perturbation_order(tensor: str) -> int:
    """Return the perturbation order of a tensor."""
    jl, _ = _ensure_init()
    return int(jl_call(jl, "XTensor.PerturbationOrder", jl_sym(tensor, "tensor")))


def perturbation_at_order(background: str, order: int) -> str:
    """Return the name of the perturbation tensor at the given order."""
    jl, _ = _ensure_init()
    result = jl_call(
        jl,
        "XTensor.PerturbationAtOrder",
        jl_sym(background, "background tensor"),
        jl_int(order),
    )
    name = str(result)
    return name[1:] if name.startswith(":") else name
