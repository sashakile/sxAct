"""
    TExprLayer

Typed expression layer for xAct.
Provides Idx, DnIdx, TensorHead, CovDHead, TTensor, TProd, TSum, TScalar,
TSymbol, TCovD, the @indices macro, tensor() / covd() lookups, _to_string()
serialisation, and TExpr overloads for all engine functions.
"""
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
    VarD,
    CollectTensors,
    AllContractions,
    MakeTraceFree,
    ToBasis,
    FromBasis,
    TraceBasisDummy
import ..XInvar: RiemannSimplify

export Idx, DnIdx, SlotIdx
export TExpr, TScalar, TSymbol, TensorHead, TTensor, TProd, TSum, CovDHead, TCovD
export @indices, tensor, covd
export _to_string, _to_string_factor, _parse_to_texpr

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
Bare symbol returned by the engine (e.g. a perturbation tensor name without
indices).  Serialises back to the bare name string.
"""
struct TSymbol <: TExpr
    name::Symbol
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
    body = join(parts, " ")
    if p.coeff == 1//1
        body
    elseif p.coeff == -1//1
        "-" * body
    elseif p.coeff.den == 1
        "$(p.coeff.num) $body"
    else
        "($(p.coeff.num)/$(p.coeff.den)) $body"
    end
end

function _to_string(s::TSymbol)::String
    string(s.name)
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
# Rich Display (Unicode and LaTeX)
# ---------------------------------------------------------------------------

const _GREEK_MAP = Dict(
    :alpha => ("α", "\\alpha"),
    :beta => ("β", "\\beta"),
    :gamma => ("γ", "\\gamma"),
    :delta => ("δ", "\\delta"),
    :epsilon => ("ϵ", "\\epsilon"),
    :zeta => ("ζ", "\\zeta"),
    :eta => ("η", "\\eta"),
    :theta => ("θ", "\\theta"),
    :iota => ("ι", "\\iota"),
    :kappa => ("κ", "\\kappa"),
    :lambda => ("λ", "\\lambda"),
    :mu => ("μ", "\\mu"),
    :nu => ("ν", "\\nu"),
    :xi => ("ξ", "\\xi"),
    :pi => ("π", "\\pi"),
    :rho => ("ρ", "\\rho"),
    :sigma => ("σ", "\\sigma"),
    :tau => ("τ", "\\tau"),
    :phi => ("ϕ", "\\phi"),
    :chi => ("χ", "\\chi"),
    :psi => ("ψ", "\\psi"),
    :omega => ("ω", "\\omega"),
    # Uppercase
    :Gamma => ("Γ", "\\Gamma"),
    :Delta => ("Δ", "\\Delta"),
    :Theta => ("Θ", "\\Theta"),
    :Lambda => ("Λ", "\\Lambda"),
    :Xi => ("Ξ", "\\Xi"),
    :Pi => ("Π", "\\Pi"),
    :Sigma => ("Σ", "\\Sigma"),
    :Phi => ("Φ", "\\Phi"),
    :Psi => ("Ψ", "\\Psi"),
    :Omega => ("Ω", "\\Omega"),
    # Curvature / Physics
    :Riemann => ("R", "R"),
    :Ricci => ("R", "R"),
    :RicciScalar => ("R", "R"),
    :Weyl => ("C", "C"),
    :Einstein => ("G", "G"),
    :eta => ("η", "\\eta"),
    :delta => ("δ", "\\delta"),
)

const _SUPERSCRIPTS = Dict(
    'a' => 'ᵃ',
    'b' => 'ᵇ',
    'c' => 'ᶜ',
    'd' => 'ᵈ',
    'e' => 'ᵉ',
    'f' => 'ᶠ',
    'g' => 'ᵍ',
    'h' => 'ʰ',
    'i' => 'ⁱ',
    'j' => 'ʲ',
    'k' => 'ᵏ',
    'l' => 'ˡ',
    'm' => 'ᵐ',
    'n' => 'ⁿ',
    'o' => 'ᵒ',
    'p' => 'ᵖ',
    'r' => 'ʳ',
    's' => 'ˢ',
    't' => 'ᵗ',
    'u' => 'ᵘ',
    'v' => 'ᵛ',
    'w' => 'ʷ',
    'x' => 'ˣ',
    'y' => 'ʸ',
    'z' => 'ᶻ',
    'α' => 'ᵅ',
    'β' => 'ᵝ',
    'γ' => 'ᵞ',
    'δ' => 'ᵟ',
    'ϵ' => 'ᵋ',
    'θ' => 'ᶿ',
    'ι' => 'ᶥ',
    'λ' => 'ᶝ',
    'μ' => 'ᵝ',
    'ν' => 'ᵛ',
    'ρ' => 'ᵨ',
    'σ' => 'ᵟ',
    'τ' => 'ᵜ',
    'ϕ' => 'ᵠ',
    'χ' => 'ᵡ',
    'ψ' => 'ᵝ',
    'ω' => 'ᵜ',
)

const _SUBSCRIPTS = Dict(
    'a' => 'ₐ',
    'e' => 'ₑ',
    'h' => 'ₕ',
    'i' => 'ᵢ',
    'j' => 'ⱼ',
    'k' => 'ₖ',
    'l' => 'ₗ',
    'm' => 'ₘ',
    'n' => 'ₙ',
    'o' => 'ₒ',
    'p' => 'ₚ',
    'r' => 'ᵣ',
    's' => 'ₛ',
    't' => 'ₜ',
    'u' => 'ᵤ',
    'v' => 'ᵥ',
    'x' => 'ₓ',
    'α' => 'ₐ',
    'β' => 'ᵦ',
    'γ' => 'ᵧ',
    'ρ' => 'ᵨ',
    'σ' => 'ₛ',
    'χ' => 'ᵪ',
    'ψ' => 'ᵦ',
)

function _label_to_unicode(s::Symbol)::String
    name = string(s)
    # Try exact match
    haskey(_GREEK_MAP, s) && return _GREEK_MAP[s][1]
    # Try stripping CD/PD prefixes
    for prefix in ["Riemann", "RicciScalar", "Ricci", "Weyl", "Einstein", "Christoffel"]
        if startswith(name, prefix)
            psym = Symbol(prefix)
            haskey(_GREEK_MAP, psym) && return _GREEK_MAP[psym][1]
        end
    end
    get(_GREEK_MAP, s, (name, ""))[1]
end

function _label_to_latex(s::Symbol)::String
    name = string(s)
    # Try exact match
    haskey(_GREEK_MAP, s) && return _GREEK_MAP[s][2]
    # Try stripping CD/PD prefixes
    for prefix in ["Riemann", "RicciScalar", "Ricci", "Weyl", "Einstein", "Christoffel"]
        if startswith(name, prefix)
            psym = Symbol(prefix)
            haskey(_GREEK_MAP, psym) && return _GREEK_MAP[psym][2]
        end
    end
    get(_GREEK_MAP, s, ("", "\\" * name))[2]
end

function _to_unicode(i::Idx)::String
    lbl = _label_to_unicode(i.label)
    # If lbl has multiple chars or no superscript mapping, use ^(...)
    if length(lbl) > 1 || any(c -> !haskey(_SUPERSCRIPTS, c), lbl)
        return "^" * lbl
    end
    join([_SUPERSCRIPTS[c] for c in lbl])
end

function _to_unicode(i::DnIdx)::String
    lbl = _label_to_unicode(i.parent.label)
    # If lbl has multiple chars or no subscript mapping, use _(...)
    if length(lbl) > 1 || any(c -> !haskey(_SUBSCRIPTS, c), lbl)
        return "_" * lbl
    end
    join([_SUBSCRIPTS[c] for c in lbl])
end

function _to_latex(i::Idx)::String
    "^{" * _label_to_latex(i.label) * "}"
end

function _to_latex(i::DnIdx)::String
    "_{" * _label_to_latex(i.parent.label) * "}"
end

function _to_unicode(t::TTensor)::String
    name = _label_to_unicode(t.head.name)
    if isempty(t.indices)
        name
    else
        name * join([_to_unicode(i) for i in t.indices])
    end
end

function _to_latex(t::TTensor)::String
    name = _label_to_latex(t.head.name)
    if isempty(t.indices)
        name
    else
        name * join([_to_latex(i) for i in t.indices])
    end
end

function _to_unicode(s::TScalar)::String
    s.value.den == 1 ? string(s.value.num) : "($(s.value.num)/$(s.value.den))"
end

function _to_latex(s::TScalar)::String
    if s.value.den == 1
        string(s.value.num)
    else
        "\\frac{$(s.value.num)}{$(s.value.den)}"
    end
end

function _to_unicode(p::TProd)::String
    parts = [f isa TSum ? "(" * _to_unicode(f) * ")" : _to_unicode(f) for f in p.factors]
    body = join(parts, " ")
    if p.coeff == 1//1
        body
    elseif p.coeff == -1//1
        "-" * body
    elseif p.coeff.den == 1
        "$(p.coeff.num) $body"
    else
        "($(p.coeff.num)/$(p.coeff.den)) $body"
    end
end

function _to_latex(p::TProd)::String
    parts = [f isa TSum ? "(" * _to_latex(f) * ")" : _to_latex(f) for f in p.factors]
    body = join(parts, " ")
    if p.coeff == 1//1
        body
    elseif p.coeff == -1//1
        "-" * body
    elseif p.coeff.den == 1
        "$(p.coeff.num) " * body
    else
        "\\frac{$(p.coeff.num)}{$(p.coeff.den)} " * body
    end
end

function _to_unicode(s::TSum)::String
    isempty(s.terms) && return "0"
    buf = IOBuffer()
    for (i, term) in enumerate(s.terms)
        str = _to_unicode(term)
        if i == 1
            print(buf, str)
        else
            if startswith(str, "-")
                print(buf, " - ", str[2:end])
            else
                print(buf, " + ", str)
            end
        end
    end
    String(take!(buf))
end

function _to_latex(s::TSum)::String
    isempty(s.terms) && return "0"
    buf = IOBuffer()
    for (i, term) in enumerate(s.terms)
        str = _to_latex(term)
        if i == 1
            print(buf, str)
        else
            if startswith(str, "-")
                print(buf, " - ", str[2:end])
            else
                print(buf, " + ", str)
            end
        end
    end
    String(take!(buf))
end

function _to_unicode(c::TCovD)::String
    idx = _to_unicode(c.index)
    op = c.operand isa TSum ? "(" * _to_unicode(c.operand) * ")" : _to_unicode(c.operand)
    "∇" * idx * op
end

function _to_latex(c::TCovD)::String
    idx = _to_latex(c.index)
    op = c.operand isa TSum ? "(" * _to_latex(c.operand) * ")" : _to_latex(c.operand)
    "\\nabla" * idx * op
end

function _to_unicode(s::TSymbol)::String
    _label_to_unicode(s.name)
end

function _to_latex(s::TSymbol)::String
    _label_to_latex(s.name)
end

# ---------------------------------------------------------------------------
# Display (show)
# ---------------------------------------------------------------------------

# REPL / text/plain
function Base.show(io::IO, ::MIME"text/plain", e::TExpr)
    print(io, _to_unicode(e))
end

# Default fallback (serialization)
Base.show(io::IO, e::TExpr) = print(io, _to_string(e))

# LaTeX for Jupyter / Documenter
function Base.show(io::IO, ::MIME"text/latex", e::TExpr)
    print(io, "\$", _to_latex(e), "\$")
end

# HTML for notebooks
function Base.show(io::IO, ::MIME"text/html", e::TExpr)
    print(io, "<span class=\"tex\">\\(", _to_latex(e), "\\)</span>")
end

# REPL / text/plain for index objects
function Base.show(io::IO, ::MIME"text/plain", i::Idx)
    print(io, _to_unicode(i))
end
function Base.show(io::IO, ::MIME"text/plain", i::DnIdx)
    print(io, _to_unicode(i))
end

# LaTeX for index objects
function Base.show(io::IO, ::MIME"text/latex", i::Idx)
    print(io, "\$", _to_latex(i), "\$")
end
function Base.show(io::IO, ::MIME"text/latex", i::DnIdx)
    print(io, "\$", _to_latex(i), "\$")
end

Base.show(io::IO, i::Idx) = print(io, i.label)
Base.show(io::IO, i::DnIdx) = print(io, "-", i.parent.label)
Base.show(io::IO, t::TensorHead) = print(io, "TensorHead(:", t.name, ")")
Base.show(io::IO, s::TSymbol) = print(io, s.name)

# ---------------------------------------------------------------------------
# TExpr / String equality — compare by canonical string representation
# ---------------------------------------------------------------------------

Base.:(==)(t::TExpr, s::AbstractString) = _to_string(t) == s
Base.:(==)(s::AbstractString, t::TExpr) = _to_string(t) == s

# ---------------------------------------------------------------------------
# Parser: String → TExpr  (Stage 2)
# ---------------------------------------------------------------------------

"""
    _parse_to_texpr(s::AbstractString) -> TExpr

Parse an engine output string into a typed expression tree.

Supported formats (same as `_to_string` output):

  - `"0"` → `TScalar(0//1)`
  - `"Name[i1,i2]"` → `TTensor`
  - `"Name[-i][operand]"` → `TCovD`
  - `"2 * Name[...]"`, `"(1/2) * Name[...]"`, `"-Name[...]"` → `TProd`
  - `"A + B"`, `"A - B"` → `TSum`
"""
function _parse_to_texpr(s::AbstractString)::TExpr
    _parse_texpr_sum(strip(s), _build_index_map())
end

# Build label→manifold map from all currently-defined manifolds.
function _build_index_map()::Dict{Symbol,Symbol}
    d = Dict{Symbol,Symbol}()
    for (mname, mobj) in _manifolds
        for lbl in mobj.index_labels
            d[lbl] = mname
        end
    end
    d
end

# Find the matching closing bracket starting at `open_pos` in `s`.
function _texpr_find_close(s::AbstractString, open_pos::Int)::Int
    depth = 0
    i = open_pos
    while i <= ncodeunits(s)
        c = s[i]
        if c == '[' || c == '('
            depth += 1
        elseif c == ']' || c == ')'
            depth -= 1
            depth == 0 && return i
        end
        i = nextind(s, i)
    end
    error("Unmatched bracket in TExpr string: $(repr(s))")
end

# Split `s` at depth-0 occurrences of `sep` (a literal string).
# All strings here are ASCII so byte indices equal character indices.
function _texpr_depth0_split(s::AbstractString, sep::String)::Vector{String}
    parts = String[]
    depth = 0
    current_start = 1
    n = ncodeunits(s)
    seplen = ncodeunits(sep)
    i = 1
    while i <= n
        c = s[i]
        if c == '(' || c == '['
            depth += 1
            i += 1
        elseif c == ')' || c == ']'
            depth -= 1
            i += 1
        elseif depth == 0 && i + seplen - 1 <= n && s[i:(i + seplen - 1)] == sep
            push!(parts, s[current_start:(i - 1)])
            i += seplen
            current_start = i
        else
            i += 1
        end
    end
    push!(parts, s[current_start:n])
    parts
end

# Parse sum: "A + B - C" → TSum([A, B, TProd(-1,[C])])
function _parse_texpr_sum(s::AbstractString, imap::Dict{Symbol,Symbol})::TExpr
    # Collect (sign, term_string) by scanning for depth-0 " + " and " - "
    signs = Int[1]
    term_strs = String[]
    depth = 0
    n = ncodeunits(s)
    i = 1
    seg_start = 1
    while i <= n
        c = s[i]
        if c == '(' || c == '['
            depth += 1;
            i += 1
        elseif c == ')' || c == ']'
            depth -= 1;
            i += 1
        elseif depth == 0 &&
            c == ' ' &&
            i + 2 <= n &&
            (s[i + 1] == '+' || s[i + 1] == '-') &&
            s[i + 2] == ' '
            push!(term_strs, strip(s[seg_start:(i - 1)]))
            push!(signs, s[i + 1] == '+' ? 1 : -1)
            i += 3
            seg_start = i
        else
            i += 1
        end
    end
    push!(term_strs, strip(s[seg_start:n]))

    terms = TExpr[
        let t = _parse_texpr_term(ts, imap)
            signs[k] < 0 ? _make_prod(-1//1, TExpr[t]) : t
        end for (k, ts) in enumerate(term_strs)
    ]
    length(terms) == 1 ? terms[1] : TSum(terms)
end

# Parse a single term: "coeff factor ..." or "-factor" or "-(n/d)" (pure scalar).
# Engine output uses space for multiplication; _to_string uses " * ". Handle both.
function _parse_texpr_term(s::AbstractString, imap::Dict{Symbol,Symbol})::TExpr
    s = strip(s)
    s == "0" && return TScalar(0//1)

    # Try " * " split first (from _to_string format). Fall back to space split.
    factors = _texpr_depth0_split(s, " * ")
    if length(factors) == 1
        factors = filter!(!isempty, _texpr_depth0_split(s, " "))
    end
    isempty(factors) && return TScalar(0//1)

    first = factors[1]
    coeff = 1//1
    atom_start = 1

    if _texpr_is_coeff(first)
        coeff = _texpr_parse_rational(first)
        atom_start = 2
    elseif startswith(first, "-") && length(first) > 1 && !_texpr_is_coeff(first)
        # Leading minus on a non-coefficient: "-T[-a,-b]" → coeff=-1, atom="T[-a,-b]"
        coeff = -1//1
        factors[1] = first[2:end]
    end

    # Pure scalar with no tensor factors
    atom_start > length(factors) && return TScalar(coeff)

    atoms = TExpr[
        _parse_texpr_atom(strip(factors[k]), imap) for k in atom_start:length(factors)
    ]
    length(atoms) == 1 && coeff == 1//1 ? atoms[1] : _make_prod(coeff, atoms)
end

# Return true if s is a coefficient: integer, "(n/d)", "(-n/d)", or "-(n/d)".
function _texpr_is_coeff(s::AbstractString)::Bool
    isempty(s) && return false
    # Integer: optional leading - then all digits
    all(c -> isdigit(c) || c == '-', s) && s != "-" && return true
    # Rational with optional outer negation: "(n/d)", "(-n/d)", "-(n/d)"
    s_inner = startswith(s, "-") ? s[2:end] : s
    startswith(s_inner, "(") &&
        endswith(s_inner, ")") &&
        occursin("/", s_inner) &&
        return true
    return false
end

function _texpr_parse_rational(s::AbstractString)::Rational{Int}
    s = strip(s)
    neg = startswith(s, "-(")
    s_inner = neg ? s[2:end] : s
    if startswith(s_inner, "(") && endswith(s_inner, ")")
        inner = s_inner[2:(end - 1)]
        slash = findfirst('/', inner)
        slash === nothing && error("Bad rational: $(repr(s))")
        r =
            parse(Int, strip(inner[1:(slash - 1)])) //
            parse(Int, strip(inner[(slash + 1):end]))
        return neg ? -r : r
    else
        return parse(Int, s) // 1
    end
end

# Parse a single atom: TTensor, TCovD, or TSymbol (bare name without brackets).
function _parse_texpr_atom(s::AbstractString, imap::Dict{Symbol,Symbol})::TExpr
    s = strip(s)
    bracket1 = findfirst('[', s)
    # Bare name (no brackets): e.g. perturb can return "TEh" without index spec
    bracket1 === nothing && return TSymbol(Symbol(s))

    name = Symbol(s[1:(bracket1 - 1)])
    close1 = _texpr_find_close(s, bracket1)

    # CovD: Name[-idx][operand]
    if close1 < ncodeunits(s) && s[close1 + 1] == '['
        idx_str = s[(bracket1 + 1):(close1 - 1)]
        open2 = close1 + 1
        close2 = _texpr_find_close(s, open2)
        op_str = s[(open2 + 1):(close2 - 1)]
        idx = _parse_texpr_idx(idx_str, imap)
        operand = _parse_texpr_sum(op_str, imap)
        return TCovD(name, idx, operand)
    end

    # Tensor: Name[i1,i2,...]
    indices_str = s[(bracket1 + 1):(close1 - 1)]
    indices = if isempty(strip(indices_str))
        SlotIdx[]
    else
        SlotIdx[_parse_texpr_idx(strip(p), imap) for p in split(indices_str, ",")]
    end
    TTensor(TensorHead(name), indices)
end

function _parse_texpr_idx(s::AbstractString, imap::Dict{Symbol,Symbol})::SlotIdx
    s = strip(s)
    if startswith(s, "-")
        lbl = Symbol(s[2:end])
        mname = get(imap, lbl, nothing)
        mname === nothing && error("Unknown index label in parser: $lbl")
        return DnIdx(Idx(lbl, mname))
    else
        lbl = Symbol(s)
        mname = get(imap, lbl, nothing)
        mname === nothing && error("Unknown index label in parser: $lbl")
        return Idx(lbl, mname)
    end
end

# ---------------------------------------------------------------------------
# Engine function overloads (TExpr -> String -> engine -> TExpr)
# ---------------------------------------------------------------------------

# Parse engine String output back to TExpr; return TScalar(0) for "0".
_engine_out(s::String)::TExpr = _parse_to_texpr(s)
_engine_out(e::TExpr)::TExpr = e

ToCanonical(expr::TExpr) = _engine_out(ToCanonical(_to_string(expr)))
Contract(expr::TExpr) = _engine_out(Contract(_to_string(expr)))
Simplify(expr::TExpr) = _engine_out(Simplify(_to_string(expr)))
perturb(expr::TExpr, order::Int) = _engine_out(perturb(_to_string(expr), order))
function CommuteCovDs(expr::TExpr, cd, i1, i2)
    _engine_out(CommuteCovDs(_to_string(expr), cd, i1, i2))
end
SortCovDs(expr::TExpr, cd) = _engine_out(SortCovDs(_to_string(expr), cd))
IBP(expr::TExpr, cd) = _engine_out(IBP(_to_string(expr), cd))
TotalDerivativeQ(expr::TExpr, cd) = TotalDerivativeQ(_to_string(expr), cd)  # returns Bool
VarD(expr::TExpr, field, cd) = _engine_out(VarD(_to_string(expr), field, cd))
function RiemannSimplify(expr::TExpr, metric; kwargs...)
    _engine_out(RiemannSimplify(_to_string(expr), metric; kwargs...))
end

# xTras overloads
CollectTensors(expr::TExpr) = _engine_out(CollectTensors(_to_string(expr)))
function AllContractions(expr::TExpr, metric::Symbol)
    TExpr[_engine_out(r) for r in AllContractions(_to_string(expr), metric)]
end
function MakeTraceFree(expr::TExpr, metric::Symbol)
    _engine_out(MakeTraceFree(_to_string(expr), metric))
end

# xCoba overloads
ToBasis(expr::TExpr, basis::Symbol) = ToBasis(_to_string(expr), basis)
function FromBasis(tensor::TensorHead, bases::Vector{Symbol})
    _engine_out(FromBasis(tensor.name, bases))
end
function TraceBasisDummy(tensor::TensorHead, bases::Vector{Symbol})
    TraceBasisDummy(tensor.name, bases)
end

end # module TExprLayer
