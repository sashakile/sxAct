# TExprLayer — Typed expression layer for xAct.
# Provides Idx, DnIdx, TensorHead, CovDHead, TTensor, TProd, TSum, TScalar,
# TCovD, the @indices macro, tensor() / covd() lookups, _to_string()
# serialisation, and TExpr overloads for all engine functions.
module TExprLayer

using ..XTensor: _manifolds, _tensors, _metrics
import ..XTensor:
    ToCanonical,
    Contract,
    Simplify,
    perturb,
    CommuteCovDs,
    SortCovDs,
    IBP,
    TotalDerivativeQ,
    VarD

export Idx, DnIdx, SlotIdx
export TExpr, TScalar, TensorHead, TTensor, TProd, TSum, CovDHead, TCovD
export @indices, tensor, covd
export _to_string, _to_string_factor

# ---------------------------------------------------------------------------
# Index types
# ---------------------------------------------------------------------------

"""
Abstract index label bound to a manifold (contravariant / up).
"""
struct Idx
    label::Symbol
    manifold::Symbol

    function Idx(label::Symbol, manifold::Symbol)
        haskey(_manifolds, manifold) || error("Manifold $manifold is not defined")
        mobj = _manifolds[manifold]
        label in mobj.index_labels ||
            error("Index $label is not registered for manifold $manifold")
        new(label, manifold)
    end
end

"""
Covariant (down) index — wraps an `Idx`.
"""
struct DnIdx
    parent::Idx
end

Base.:-(i::Idx) = DnIdx(i)
Base.:-(i::DnIdx) = i.parent

"""
Union of `Idx` and `DnIdx` — anything that goes in a tensor slot.
"""
const SlotIdx = Union{Idx,DnIdx}

# ---------------------------------------------------------------------------
# @indices macro
# ---------------------------------------------------------------------------

"""
    @indices M a b c d ...

Declare index variables bound to manifold `M`.  Generates runtime `Idx`
constructor calls (with validation) that assign each name in the current
scope.

Example:

```julia
def_manifold!(:M, 4, [:a, :b, :c, :d])
@indices M a b c d
# a = Idx(:a, :M), b = Idx(:b, :M), ...
```
"""
macro indices(manifold, names...)
    exprs = [
        :($(esc(name)) = Idx($(QuoteNode(name)), $(QuoteNode(manifold)))) for name in names
    ]
    quote
        $(exprs...)
        nothing
    end
end

# ---------------------------------------------------------------------------
# Abstract expression base type
# ---------------------------------------------------------------------------

abstract type TExpr end

# ---------------------------------------------------------------------------
# Expression node types
# ---------------------------------------------------------------------------

"""
Numeric scalar coefficient.
"""
struct TScalar <: TExpr
    value::Rational{Int}
    TScalar(value::Rational{Int}) = new(value)
end

"""
Lightweight handle for a registered tensor.  Not a TExpr itself; must
apply indices via `getindex` to produce a `TTensor`.
"""
struct TensorHead
    name::Symbol
end

"""
A tensor with indices applied, e.g. `T[-a, -b]`.
"""
struct TTensor <: TExpr
    head::TensorHead
    indices::Vector{SlotIdx}
end

"""
Product of tensor expressions with a rational coefficient.
"""
struct TProd <: TExpr
    coeff::Rational{Int}
    factors::Vector{TExpr}  # TTensor, TCovD, or TScalar elements
    TProd(coeff::Rational{Int}, factors::Vector{TExpr}) = new(coeff, factors)
end

"""
Sum of tensor expressions.
"""
struct TSum <: TExpr
    terms::Vector{TExpr}  # TTensor, TProd, TCovD, or TScalar elements
    TSum(terms::Vector{TExpr}) = new(terms)
end

"""
Covariant derivative applied to an expression: `CD[-a](T[-b,-c])`.
"""
struct TCovD <: TExpr
    covd::Symbol
    index::SlotIdx
    operand::TExpr
end

"""
Lightweight handle for a registered covariant derivative.  Not a TExpr.
"""
struct CovDHead
    name::Symbol
end

"""
Intermediate callable produced by `CD[-a]`; call it on a TExpr to
produce a `TCovD` node.
"""
struct _CovDApplicator
    covd::Symbol
    index::SlotIdx
end

(app::_CovDApplicator)(operand::TExpr) = TCovD(app.covd, app.index, operand)

# ---------------------------------------------------------------------------
# Lookup functions
# ---------------------------------------------------------------------------

"""
    tensor(name::Symbol) -> TensorHead

Look up a registered tensor and return a `TensorHead` handle.
Throws if the tensor is not defined (e.g. after `reset_state!()`).
"""
function tensor(name::Symbol)
    haskey(_tensors, name) ||
        error("Tensor $name is not defined (was reset_state!() called?)")
    TensorHead(name)
end
tensor(name::String) = tensor(Symbol(name))

"""
    covd(name::Symbol) -> CovDHead

Look up a registered covariant derivative and return a `CovDHead` handle.
Throws if `name` is not a defined CovD (metric key in `_metrics`).
"""
function covd(name::Symbol)
    haskey(_metrics, name) || error("Covariant derivative $name is not defined")
    CovDHead(name)
end
covd(name::String) = covd(Symbol(name))

# ---------------------------------------------------------------------------
# TensorHead getindex (builds TTensor with validation)
# ---------------------------------------------------------------------------

function _validate_tensor_indices(name::Symbol, indices)
    haskey(_tensors, name) ||
        error("Tensor $name is not defined (was reset_state!() called?)")
    tobj = _tensors[name]

    length(indices) == length(tobj.slots) ||
        error("$name has $(length(tobj.slots)) slots, got $(length(indices))")

    for (i, idx) in enumerate(indices)
        bare = idx isa DnIdx ? idx.parent : idx
        bare.manifold == tobj.manifold || error(
            "Index $(bare.label) is from manifold $(bare.manifold), " *
            "but slot $i of $name expects $(tobj.manifold)",
        )
    end
end

function Base.getindex(t::TensorHead, indices::SlotIdx...)
    _validate_tensor_indices(t.name, indices)
    TTensor(t, collect(SlotIdx, indices))
end

# Rank-0 tensors: RS[]
function Base.getindex(t::TensorHead)
    _validate_tensor_indices(t.name, ())
    TTensor(t, SlotIdx[])
end

# ---------------------------------------------------------------------------
# CovDHead getindex (returns _CovDApplicator)
# ---------------------------------------------------------------------------

function Base.getindex(c::CovDHead, idx::SlotIdx)
    _CovDApplicator(c.name, idx)
end

# ---------------------------------------------------------------------------
# Arithmetic operators
# ---------------------------------------------------------------------------

# Helper: flatten nested TProd and merge coefficients.
# Returns (merged_coeff, flat_factors).
function _make_prod(coeff::Rational{Int}, nodes::Vector{<:TExpr})
    flat = TExpr[]
    c = coeff
    for node in nodes
        if node isa TProd
            c *= node.coeff
            append!(flat, node.factors)
        elseif node isa TScalar
            c *= node.value
        else
            push!(flat, node)
        end
    end
    isempty(flat) ? TScalar(c) : TProd(c, flat)
end

# Helper: flatten nested TSum.
function _flatten_sum(nodes::Vector{<:TExpr})
    terms = TExpr[]
    for node in nodes
        if node isa TSum
            append!(terms, node.terms)
        else
            push!(terms, node)
        end
    end
    terms
end

Base.:*(a::TExpr, b::TExpr) = _make_prod(1//1, TExpr[a, b])
Base.:+(a::TExpr, b::TExpr) = TSum(_flatten_sum(TExpr[a, b]))
Base.:-(a::TExpr, b::TExpr) = TSum(_flatten_sum(TExpr[a, _make_prod(-1//1, TExpr[b])]))
Base.:-(a::TExpr) = _make_prod(-1//1, TExpr[a])

Base.:*(c::Union{Integer,Rational}, a::TExpr) = _make_prod(Rational{Int}(c), TExpr[a])
Base.:*(a::TExpr, c::Union{Integer,Rational}) = c * a

# ---------------------------------------------------------------------------
# String serialisation
# ---------------------------------------------------------------------------

function _to_string(i::Idx)::String
    string(i.label)
end

function _to_string(i::DnIdx)::String
    "-" * string(i.parent.label)
end

function _to_string(t::TTensor)::String
    if isempty(t.indices)
        "$(t.head.name)[]"
    else
        idx_str = join([_to_string(i) for i in t.indices], ",")
        "$(t.head.name)[$idx_str]"
    end
end

function _to_string(s::TScalar)::String
    if s.value.den == 1
        string(s.value.num)
    else
        "($(s.value.num)/$(s.value.den))"
    end
end

"""
Serialise a factor inside a product, parenthesising sums.
"""
function _to_string_factor(f::TExpr)::String
    f isa TSum ? "(" * _to_string(f) * ")" : _to_string(f)
end

function _to_string(p::TProd)::String
    parts = [_to_string_factor(f) for f in p.factors]
    body = join(parts, " * ")
    if p.coeff == 1//1
        body
    elseif p.coeff == -1//1
        "-" * body
    elseif p.coeff.den == 1
        "$(p.coeff.num) * $body"
    else
        "($(p.coeff.num)/$(p.coeff.den)) * $body"
    end
end

function _to_string(s::TSum)::String
    isempty(s.terms) && return "0"
    buf = IOBuffer()
    for (i, term) in enumerate(s.terms)
        if i == 1
            print(buf, _to_string(term))
        else
            str = _to_string(term)
            if startswith(str, "-")
                print(buf, " - ", str[2:end])
            else
                print(buf, " + ", str)
            end
        end
    end
    String(take!(buf))
end

function _to_string(c::TCovD)::String
    idx_str = _to_string(c.index)
    op_str = _to_string(c.operand)
    "$(c.covd)[$idx_str][$op_str]"
end

# ---------------------------------------------------------------------------
# Display (show)
# ---------------------------------------------------------------------------

Base.show(io::IO, e::TExpr) = print(io, _to_string(e))
Base.show(io::IO, i::Idx) = print(io, i.label)
Base.show(io::IO, i::DnIdx) = print(io, "-", i.parent.label)
Base.show(io::IO, t::TensorHead) = print(io, "TensorHead(:", t.name, ")")

# ---------------------------------------------------------------------------
# Engine function overloads (TExpr -> String -> engine)
# ---------------------------------------------------------------------------

# Engine function overloads: TExpr -> _to_string -> String method
ToCanonical(expr::TExpr) = ToCanonical(_to_string(expr))
Contract(expr::TExpr) = Contract(_to_string(expr))
Simplify(expr::TExpr) = Simplify(_to_string(expr))
perturb(expr::TExpr, order::Int) = perturb(_to_string(expr), order)
CommuteCovDs(expr::TExpr, cd, i1, i2) = CommuteCovDs(_to_string(expr), cd, i1, i2)
SortCovDs(expr::TExpr, cd) = SortCovDs(_to_string(expr), cd)
IBP(expr::TExpr, cd) = IBP(_to_string(expr), cd)
TotalDerivativeQ(expr::TExpr, cd) = TotalDerivativeQ(_to_string(expr), cd)
VarD(expr::TExpr, field, cd) = VarD(_to_string(expr), field, cd)

end # module TExprLayer
