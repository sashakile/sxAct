"""
    XTensor

Abstract tensor algebra for the xAct/sxAct system.
Implements DefManifold, DefMetric, DefTensor, ToCanonical, and Contract.

Curvature tensors are auto-created by def_metric!.
Condition evaluation (Assert, Evaluate) is handled in the Python adapter layer.

Reference: specs/2026-03-06-xperm-xtensor-design.md
"""
module XTensor

include("XPerm.jl")
using .XPerm

# ============================================================
# Exports
# ============================================================

# Type exports
export ManifoldObj, VBundleObj, TensorObj, MetricObj, IndexSpec, SymmetrySpec

# State management
export reset_state!

# Global registry collections (mutable; exported for MemberQ use in conditions)
export Manifolds, Tensors, VBundles

# Def functions
export def_manifold!, def_tensor!, def_metric!

# Accessor functions
export get_manifold, get_tensor, get_vbundle, get_metric
export list_manifolds, list_tensors, list_vbundles

# Query predicates (Wolfram-named, used by _wl_to_jl translator)
export ManifoldQ, TensorQ, VBundleQ, MetricQ
export Dimension, IndicesOfVBundle, SlotsOfTensor
export MemberQ

# Canonicalization and contraction
export ToCanonical, Contract

# Contract support
export SignDetOfMetric

# ============================================================
# Types
# ============================================================

"""
An abstract index slot: the declared label and its variance.
"""
struct IndexSpec
    label::Symbol    # e.g. :a (without the '-' prefix)
    covariant::Bool  # true ↔ '-a' (covariant/down); false ↔ 'a' (contravariant/up)
end

struct ManifoldObj
    name::Symbol
    dimension::Int
    index_labels::Vector{Symbol}   # declared abstract index names (without '-')
end

struct VBundleObj
    name::Symbol          # e.g. :TangentM
    manifold::Symbol
    index_labels::Vector{Symbol}
end

"""
Describes the permutation symmetry of a tensor's slot group.
type  — one of: :Symmetric, :Antisymmetric, :RiemannSymmetric, :NoSymmetry
slots — 1-indexed positions (within this tensor's slot list) that the symmetry acts on.
For :RiemannSymmetric, exactly 4 elements.
For :NoSymmetry, empty.
"""
struct SymmetrySpec
    type::Symbol
    slots::Vector{Int}
end

"""
A fully defined tensor object.
"""
struct TensorObj
    name::Symbol
    slots::Vector{IndexSpec}   # declared slot list
    manifold::Symbol
    symmetry::SymmetrySpec
end

struct MetricObj
    name::Symbol
    manifold::Symbol
    covd::Symbol     # name of auto-created covariant derivative
    signdet::Int     # +1 (Riemannian) or -1 (Lorentzian)
end

# ============================================================
# Global state
# ============================================================

const _manifolds = Dict{Symbol,ManifoldObj}()
const _vbundles = Dict{Symbol,VBundleObj}()
const _tensors = Dict{Symbol,TensorObj}()
const _metrics = Dict{Symbol,MetricObj}()

const Manifolds = Symbol[]   # ordered list
const Tensors = Symbol[]
const VBundles = Symbol[]

# Contract support: physics rules
# Tensors whose full trace vanishes (e.g. Weyl tensor)
const _traceless_tensors = Set{Symbol}()
# Trace rules: trace_of_tensor → (scalar_tensor_name, Int_coefficient)
# e.g. EinsteinXXX → (:RicciScalarXXX, -1)  meaning tr(G) = -1 * R
const _trace_scalars = Dict{Symbol,Tuple{Symbol,Int}}()

# Einstein expansion rules: EinsteinXXX → (RicciXXX, metricXXX, RicciScalarXXX)
# Allows ToCanonical to substitute G_{ab} = R_{ab} - (1/2) g_{ab} R
const _einstein_expansion = Dict{Symbol,Tuple{Symbol,Symbol,Symbol}}()

# ============================================================
# State management
# ============================================================

function reset_state!()
    empty!(_manifolds);
    empty!(_vbundles);
    empty!(_tensors);
    empty!(_metrics)
    empty!(Manifolds);
    empty!(Tensors);
    empty!(VBundles)
    empty!(_traceless_tensors);
    empty!(_trace_scalars)
    empty!(_einstein_expansion)
end

# ============================================================
# Accessor functions
# ============================================================

get_manifold(name::Symbol) = get(_manifolds, name, nothing)
get_tensor(name::Symbol) = get(_tensors, name, nothing)
get_vbundle(name::Symbol) = get(_vbundles, name, nothing)
get_metric(name::Symbol) = get(_metrics, name, nothing)
list_manifolds() = copy(Manifolds)
list_tensors() = copy(Tensors)
list_vbundles() = copy(VBundles)

get_manifold(name::AbstractString) = get_manifold(Symbol(name))
get_tensor(name::AbstractString) = get_tensor(Symbol(name))
get_vbundle(name::AbstractString) = get_vbundle(Symbol(name))
get_metric(name::AbstractString) = get_metric(Symbol(name))

# ============================================================
# Query predicates
# ============================================================

ManifoldQ(s::Symbol) = haskey(_manifolds, s)
ManifoldQ(s::AbstractString) = ManifoldQ(Symbol(s))
TensorQ(s::Symbol) = haskey(_tensors, s)
TensorQ(s::AbstractString) = TensorQ(Symbol(s))
VBundleQ(s::Symbol) = haskey(_vbundles, s)
VBundleQ(s::AbstractString) = VBundleQ(Symbol(s))
MetricQ(s::Symbol) = haskey(_metrics, s)
MetricQ(s::AbstractString) = MetricQ(Symbol(s))

function Dimension(s::Symbol)
    m = get(_manifolds, s, nothing)
    isnothing(m) && error("Dimension: manifold $s not defined")
    m.dimension
end
Dimension(s::AbstractString) = Dimension(Symbol(s))

function IndicesOfVBundle(s::Symbol)
    vb = get(_vbundles, s, nothing)
    isnothing(vb) && error("IndicesOfVBundle: VBundle $s not defined")
    vb.index_labels
end
IndicesOfVBundle(s::AbstractString) = IndicesOfVBundle(Symbol(s))

function SlotsOfTensor(s::Symbol)
    t = get(_tensors, s, nothing)
    isnothing(t) && error("SlotsOfTensor: tensor $s not defined")
    t.slots
end
SlotsOfTensor(s::AbstractString) = SlotsOfTensor(Symbol(s))

function MemberQ(collection::Symbol, s::Symbol)
    if collection == :Manifolds
        s in Manifolds
    elseif collection == :Tensors
        s in Tensors
    elseif collection == :VBundles
        s in VBundles
    else
        false
    end
end
# Also accept a live collection (e.g. when `Manifolds` resolves to the actual Vector)
MemberQ(collection::AbstractVector, s::Symbol) = s in collection
MemberQ(collection::AbstractVector, s::AbstractString) = Symbol(s) in collection
MemberQ(collection::Symbol, s::AbstractString) = MemberQ(collection, Symbol(s))
MemberQ(collection::AbstractString, s) = MemberQ(Symbol(collection), s)

"""
    SignDetOfMetric(metric_name) → Int

Return the sign of the determinant (+1 Riemannian, -1 Lorentzian) for a registered metric.
"""
function SignDetOfMetric(metric_name::Symbol)::Int
    # _metrics is keyed by covd name; search by metric tensor name
    for (covd, m) in _metrics
        if m.name == metric_name
            return m.signdet
        end
    end
    error("SignDetOfMetric: metric $metric_name not found")
end
SignDetOfMetric(s::AbstractString) = SignDetOfMetric(Symbol(s))

# ============================================================
# Symmetry string parser
# ============================================================

"""
    _parse_symmetry(sym_str, slot_specs) → SymmetrySpec

Parse a Wolfram symmetry string like "Symmetric[{-bta,-btb}]" into a SymmetrySpec.
`slot_specs` is the tensor's slot list for mapping labels → slot positions.
"""
function _parse_symmetry(
    sym_str::Union{String,Nothing}, slot_specs::Vector{IndexSpec}
)::SymmetrySpec
    (isnothing(sym_str) || isempty(sym_str)) && return SymmetrySpec(:NoSymmetry, Int[])

    m = match(r"^(Symmetric|Antisymmetric|RiemannSymmetric)\[\{([^}]*)\}\]$", sym_str)
    isnothing(m) && error("Cannot parse symmetry string: $sym_str")

    type_str = m.captures[1]
    labels_str = m.captures[2]

    sym_type = Symbol(type_str)

    if isempty(strip(labels_str))
        return SymmetrySpec(:NoSymmetry, Int[])
    end

    raw_labels = split(labels_str, ",")
    label_names = String[strip(lstrip(strip(l), '-')) for l in raw_labels]

    # Map label names to 1-based slot positions
    slot_positions = Int[]
    for lbl in label_names
        lbl_sym = Symbol(lbl)
        pos = findfirst(s -> s.label == lbl_sym, slot_specs)
        isnothing(pos) && error("Symmetry label '$lbl' not found in tensor slots")
        push!(slot_positions, pos)
    end

    if sym_type == :RiemannSymmetric && length(slot_positions) != 4
        error("RiemannSymmetric requires exactly 4 slots, got $(length(slot_positions))")
    end

    SymmetrySpec(sym_type, slot_positions)
end

# ============================================================
# Def functions
# ============================================================

"""
    def_manifold!(name, dim, index_labels) → ManifoldObj

Define a new abstract manifold.
"""
function def_manifold!(name::Symbol, dim::Int, index_labels::Vector{Symbol})::ManifoldObj
    haskey(_manifolds, name) && error("Manifold $name already defined")

    m = ManifoldObj(name, dim, index_labels)
    tb = VBundleObj(Symbol("Tangent" * string(name)), name, index_labels)

    _manifolds[name] = m
    _vbundles[tb.name] = tb
    push!(Manifolds, name)
    push!(VBundles, tb.name)

    m
end

# Convenience overloads for string input
function def_manifold!(name::AbstractString, dim::Int, index_labels::Vector)::ManifoldObj
    sym_name = Symbol(name)
    sym_labels = [Symbol(string(l)) for l in index_labels]
    def_manifold!(sym_name, dim, sym_labels)
end

"""
    def_tensor!(name, index_specs, manifold; symmetry_str=nothing) → TensorObj

Define a new abstract tensor.
index_specs: vector of strings like ["-bta","-btb"] or ["bta"].
"""
function def_tensor!(
    name::Symbol,
    index_specs::Vector{String},
    manifold::Symbol;
    symmetry_str::Union{String,Nothing}=nothing,
)::TensorObj
    m = get(_manifolds, manifold, nothing)
    isnothing(m) && error("def_tensor!: manifold $manifold not defined")

    # Parse index specs into IndexSpec
    slots = IndexSpec[]
    for spec in index_specs
        if startswith(spec, "-")
            push!(slots, IndexSpec(Symbol(spec[2:end]), true))
        else
            push!(slots, IndexSpec(Symbol(spec), false))
        end
    end

    # Validate labels belong to manifold's index set
    allowed = Set(m.index_labels)
    for s in slots
        s.label in allowed ||
            error("Index label $(s.label) not in manifold $manifold indices")
    end

    sym = _parse_symmetry(symmetry_str, slots)
    t = TensorObj(name, slots, manifold, sym)
    _tensors[name] = t
    push!(Tensors, name)
    t
end

function def_tensor!(
    name::AbstractString,
    index_specs::Vector,
    manifold::AbstractString;
    symmetry_str::Union{String,Nothing}=nothing,
)::TensorObj
    sym_name = Symbol(name)
    sym_manifold = Symbol(manifold)
    str_specs = [string(s) for s in index_specs]
    def_tensor!(sym_name, str_specs, sym_manifold; symmetry_str=symmetry_str)
end

"""
    def_metric!(signdet, metric_expr, covd_name) → MetricObj

Define a metric tensor and auto-create curvature tensors.
metric_expr: e.g. "Cng[-cna,-cnb]"
covd_name: e.g. "Cnd" (used as suffix for auto-created curvature tensors)
"""
function def_metric!(
    signdet::Int, metric_expr::AbstractString, covd_name::Symbol
)::MetricObj
    # Parse metric_expr: extract name and slots
    m = match(r"^(\w+)\[([^\]]*)\]$", metric_expr)
    isnothing(m) && error("Cannot parse metric expression: $metric_expr")

    metric_name = Symbol(m.captures[1])
    slot_strs = String[strip(s) for s in split(m.captures[2], ",")]

    # Determine manifold: find which manifold has these index labels
    manifold_sym = _find_manifold_for_indices(slot_strs)
    isnothing(manifold_sym) &&
        error("Cannot determine manifold for metric indices: $slot_strs")

    # Register the metric tensor (symmetric rank-2 covariant)
    sym_str = "Symmetric[{$(join(slot_strs, ","))}]"
    def_tensor!(metric_name, slot_strs, manifold_sym; symmetry_str=sym_str)

    metric = MetricObj(metric_name, manifold_sym, covd_name, signdet)
    _metrics[covd_name] = metric

    # Auto-create curvature tensors
    _auto_create_curvature!(manifold_sym, covd_name)

    metric
end

function def_metric!(
    signdet::Int, metric_expr::AbstractString, covd_name::AbstractString
)::MetricObj
    def_metric!(signdet, metric_expr, Symbol(covd_name))
end

"""
Find which manifold has all of the given index labels (stripping '-').
"""
function _find_manifold_for_indices(slot_strs)::Union{Symbol,Nothing}
    # Strip '-' from each label
    bare = Set([Symbol(startswith(s, "-") ? s[2:end] : string(s)) for s in slot_strs])
    for (name, m) in _manifolds
        if bare ⊆ Set(m.index_labels)
            return name
        end
    end
    nothing
end

"""
Auto-create Riemann, Ricci, RicciScalar, Einstein tensors for a metric.
"""
function _auto_create_curvature!(manifold::Symbol, covd::Symbol)
    m = _manifolds[manifold]
    idxs = m.index_labels
    n = length(idxs)
    covd_str = string(covd)

    # Ricci scalar: always created (scalar, no indices)
    ricci_scalar_name = Symbol("RicciScalar" * covd_str)
    if !haskey(_tensors, ricci_scalar_name)
        t = TensorObj(
            ricci_scalar_name, IndexSpec[], manifold, SymmetrySpec(:NoSymmetry, Int[])
        )
        _tensors[ricci_scalar_name] = t
        push!(Tensors, ricci_scalar_name)
    end

    # Need at least 2 indices for Ricci and Einstein
    n >= 2 || return nothing

    i1, i2 = "-" * string(idxs[1]), "-" * string(idxs[2])

    ricci_name = Symbol("Ricci" * covd_str)
    if !haskey(_tensors, ricci_name)
        slots2 = String[i1, i2]
        sym2 = "Symmetric[{$i1,$i2}]"
        def_tensor!(ricci_name, slots2, manifold; symmetry_str=sym2)
    end

    einstein_name = Symbol("Einstein" * covd_str)
    if !haskey(_tensors, einstein_name)
        slots2 = String[i1, i2]
        sym2 = "Symmetric[{$i1,$i2}]"
        def_tensor!(einstein_name, slots2, manifold; symmetry_str=sym2)
    end

    # Need at least 4 indices for Riemann
    n >= 4 || return nothing

    i3, i4 = "-" * string(idxs[3]), "-" * string(idxs[4])

    riemann_name = Symbol("Riemann" * covd_str)
    if !haskey(_tensors, riemann_name)
        slots4 = String[i1, i2, i3, i4]
        sym4 = "RiemannSymmetric[{$i1,$i2,$i3,$i4}]"
        def_tensor!(riemann_name, slots4, manifold; symmetry_str=sym4)
    end

    # Also register Weyl tensor (curvature_invariants.toml uses WeylCID)
    weyl_name = Symbol("Weyl" * covd_str)
    if !haskey(_tensors, weyl_name)
        slots4 = String[i1, i2, i3, i4]
        sym4 = "RiemannSymmetric[{$i1,$i2,$i3,$i4}]"
        def_tensor!(weyl_name, slots4, manifold; symmetry_str=sym4)
    end
    # Mark Weyl as traceless (any trace over any pair of its indices = 0)
    push!(_traceless_tensors, weyl_name)

    # Register Einstein tensor trace rule: tr(G_{ab}) = g^{ab} G_{ab} = -R
    # In n dimensions: g^{ab} G_{ab} = R - (n/2)*R = (1 - n/2)*R
    # For a general manifold we encode the 4D rule (coefficient -1) since
    # the curvature invariant tests use 4D manifolds.
    # The coefficient is (1 - dim/2).  For dim=4: coeff = -1.
    n = m.dimension
    coeff_int = 1 - div(n, 2)  # integer only for even dimensions
    if !haskey(_trace_scalars, einstein_name)
        _trace_scalars[einstein_name] = (ricci_scalar_name, coeff_int)
    end

    # Register Einstein expansion rule: G_{ab} = R_{ab} - (1/2) g_{ab} R
    # Used by ToCanonical to verify the Einstein definition identity
    metric_obj = get(_metrics, covd, nothing)
    if !isnothing(metric_obj) && !haskey(_einstein_expansion, einstein_name)
        _einstein_expansion[einstein_name] = (
            ricci_name, metric_obj.name, ricci_scalar_name
        )
    end
end

# ============================================================
# Tensor expression parser
# ============================================================

struct FactorAST
    tensor_name::Symbol
    indices::Vector{String}
end

struct TermAST
    coeff::Rational{Int}
    factors::Vector{FactorAST}
end

"""
    _parse_expression(expr_str) → Vector{TermAST}

Parse a tensor expression string into a list of terms.
"""
function _parse_expression(expr_str::AbstractString)::Vector{TermAST}
    s = strip(expr_str)

    # Special case: bare "0" or empty string
    (s == "0" || isempty(s)) && return TermAST[]

    terms = TermAST[]
    # Tokenise into sign-separated chunks
    # Split on '+' and '-' that are not inside brackets
    _parse_sum!(terms, s)
    terms
end

function _parse_sum!(terms::Vector{TermAST}, s::AbstractString)
    # Walk through the string, splitting on top-level + and -
    # Tracks both [] and () depth to avoid splitting inside grouped sub-expressions.
    pos = 1
    n = length(s)
    current_start = 1
    current_sign = 1
    paren_depth = 0  # tracks ( ) nesting

    # Handle leading sign
    if pos <= n && (s[pos] == '+' || s[pos] == '-')
        current_sign = s[pos] == '-' ? -1 : 1
        pos += 1
        current_start = pos
    end

    while pos <= n
        c = s[pos]
        if c == '['
            # Skip to matching ']'
            depth = 1
            pos += 1
            while pos <= n && depth > 0
                s[pos] == '[' && (depth += 1)
                s[pos] == ']' && (depth -= 1)
                pos += 1
            end
        elseif c == '('
            paren_depth += 1
            pos += 1
        elseif c == ')'
            paren_depth -= 1
            pos += 1
        elseif (c == '+' || c == '-') && pos > 1 && paren_depth == 0
            # Top-level +/-: end current term
            chunk = strip(s[current_start:(pos - 1)])
            if !isempty(chunk)
                _push_chunk!(terms, chunk, current_sign)
            end
            current_sign = c == '-' ? -1 : 1
            pos += 1
            current_start = pos
        else
            pos += 1
        end
    end

    # Last chunk
    chunk = strip(s[current_start:end])
    if !isempty(chunk)
        _push_chunk!(terms, chunk, current_sign)
    end
end

"""
Push a parsed chunk into `terms`, handling parenthesized sub-expressions and
scalar-times-subexpression patterns.
"""
function _push_chunk!(terms::Vector{TermAST}, chunk::AbstractString, sign::Int)
    s = strip(chunk)

    # Case 1: Entire chunk is a parenthesized sub-expression: (A + B + ...)
    if startswith(s, "(") && endswith(s, ")")
        inner = strip(s[2:(end - 1)])
        sub_terms = TermAST[]
        _parse_sum!(sub_terms, inner)
        for t in sub_terms
            push!(terms, TermAST(t.coeff * sign, t.factors))
        end
        return nothing
    end

    # Case 2: Integer * (sub-expression): N * (A + B)
    m = match(r"^(-?\d+)\s*\*\s*\((.+)\)$"s, s)
    if !isnothing(m)
        n_coeff = parse(Int, m.captures[1])
        inner = strip(m.captures[2])
        sub_terms = TermAST[]
        _parse_sum!(sub_terms, inner)
        for t in sub_terms
            push!(terms, TermAST(t.coeff * sign * n_coeff, t.factors))
        end
        return nothing
    end

    # Default: parse as a regular term
    push!(terms, _parse_term(s, sign))
end

function _parse_term(chunk::AbstractString, outer_sign::Int)::TermAST
    s = strip(chunk)

    # Extract leading coefficient (rational or integer)
    coeff = outer_sign // 1
    # Match leading rational (N/M) — must try before integer to avoid partial match
    m_rat = match(r"^\((-?\d+)/(\d+)\)\*?\s*", s)
    if !isnothing(m_rat)
        num = parse(Int, m_rat.captures[1])
        den = parse(Int, m_rat.captures[2])
        coeff = coeff * (num // den)
        s = strip(s[(length(m_rat.match) + 1):end])
    else
        # Match leading integer (possibly with optional * and surrounding spaces)
        # Handles "7*T", "7 *T", "7* T", "7 * T"
        m_int = match(r"^(-?\d+)\s*\*?\s*", s)
        if !isnothing(m_int)
            coeff = coeff * (parse(Int, m_int.captures[1]) // 1)
            s = strip(s[(length(m_int.match) + 1):end])
        end
    end

    # Parse monomial: one or more factor calls (Name[...])
    factors = _parse_monomial(s)
    TermAST(coeff, factors)
end

function _parse_monomial(s::AbstractString)::Vector{FactorAST}
    factors = FactorAST[]
    pos = 1
    n = length(s)

    while pos <= n
        # Skip whitespace
        while pos <= n && isspace(s[pos])
            pos += 1
        end
        pos > n && break

        # Match tensor name: alphanumeric + underscore
        name_start = pos
        while pos <= n && (isletter(s[pos]) || isdigit(s[pos]) || s[pos] == '_')
            pos += 1
        end
        name_end = pos - 1
        name_start > name_end && break

        tensor_name = Symbol(s[name_start:name_end])

        # Skip whitespace
        while pos <= n && isspace(s[pos])
            pos += 1
        end

        # Must be followed by '['
        pos > n ||
            s[pos] != '[' &&
            error("Expected '[' after tensor name $tensor_name at position $pos in: $s")
        pos += 1  # consume '['

        # Collect index list up to matching ']'
        idx_start = pos
        depth = 1
        while pos <= n && depth > 0
            s[pos] == '[' && (depth += 1)
            s[pos] == ']' && (depth -= 1)
            depth > 0 && (pos += 1)
        end
        idx_str = s[idx_start:(pos - 1)]
        pos += 1  # consume ']'

        indices = _parse_index_list(idx_str)
        push!(factors, FactorAST(tensor_name, indices))
    end

    factors
end

function _parse_index_list(s::AbstractString)::Vector{String}
    isempty(strip(s)) && return String[]
    [strip(idx) for idx in split(s, ",")]
end

# ============================================================
# Canonicalization pipeline
# ============================================================

"""
Expand any EinsteinXXX factors using G_{ab} = R_{ab} - (1/2) g_{ab} R.
"""
function _expand_einstein_terms(terms::Vector{TermAST})::Vector{TermAST}
    isempty(_einstein_expansion) && return terms
    expanded = TermAST[]
    for term in terms
        # Find an Einstein factor in this term (if any)
        ei_idx = findfirst(f -> haskey(_einstein_expansion, f.tensor_name), term.factors)
        if isnothing(ei_idx)
            push!(expanded, term)
            continue
        end
        ef = term.factors[ei_idx]
        other_factors = [term.factors[i] for i in eachindex(term.factors) if i != ei_idx]
        ricci_name, metric_name, scalar_name = _einstein_expansion[ef.tensor_name]
        # Ricci term: same coefficient, replace Einstein factor with Ricci
        push!(
            expanded,
            TermAST(
                term.coeff, [other_factors..., FactorAST(ricci_name, copy(ef.indices))]
            ),
        )
        # -1/2 metric * RicciScalar term
        push!(
            expanded,
            TermAST(
                term.coeff * (-1 // 2),
                [
                    other_factors...,
                    FactorAST(metric_name, copy(ef.indices)),
                    FactorAST(scalar_name, String[]),
                ],
            ),
        )
    end
    expanded
end

"""
Apply first Bianchi identity R_{a[bcd]} = 0 to reduce canonical Riemann terms.

For 4 distinct abstract indices p < q < r < s, the canonical Bianchi identity is:
X₁ - X₂ + X₃ = 0  where:
X₁ = R[p,q,r,s]  (second index = q, smallest remaining)
X₂ = R[p,r,q,s]  (second index = r, middle remaining)
X₃ = R[p,s,q,r]  (second index = s, largest remaining)

Replaces X₃ with X₂ - X₁ when all three are present.
"""
function _bianchi_reduce!(
    coeff_map::Dict{Vector{Tuple{Symbol,Vector{String}}},Rational{Int}},
    key_order::Vector{Vector{Tuple{Symbol,Vector{String}}}},
)
    # Find all single-factor Riemann canonical terms and group by sector
    # sector = (tensor_name, first_bare_index, Set{second/third/fourth bare indices})
    sectors = Dict{
        Tuple{Symbol,String,Set{String}},Dict{String,Vector{Tuple{Symbol,Vector{String}}}}
    }()

    for key in key_order
        get(coeff_map, key, 0 // 1) == 0 && continue
        length(key) != 1 && continue
        tensor_name, indices = key[1]
        t = get(_tensors, tensor_name, nothing)
        isnothing(t) && continue
        t.symmetry.type != :RiemannSymmetric && continue
        length(indices) != 4 && continue

        bare = [_bare(idx) for idx in indices]
        p = bare[1]  # first index (lex-min after canonical form)
        rem = Set(bare[2:4])
        sector = (tensor_name, p, rem)

        if !haskey(sectors, sector)
            sectors[sector] = Dict{String,Vector{Tuple{Symbol,Vector{String}}}}()
        end
        # Second bare index identifies X₁/X₂/X₃
        sectors[sector][bare[2]] = key
    end

    # For each sector with all three Bianchi representatives, reduce X₃ = X₂ - X₁
    for (sector, idx_to_key) in sectors
        length(idx_to_key) < 3 && continue
        _, p, rem = sector
        sorted_rem = sort(collect(rem))  # q < r < s
        length(sorted_rem) != 3 && continue
        q, r, s = sorted_rem[1], sorted_rem[2], sorted_rem[3]

        haskey(idx_to_key, q) || continue
        haskey(idx_to_key, r) || continue
        haskey(idx_to_key, s) || continue

        key1 = idx_to_key[q]  # X₁
        key2 = idx_to_key[r]  # X₂
        key3 = idx_to_key[s]  # X₃

        c3 = get(coeff_map, key3, 0 // 1)
        iszero(c3) && continue

        # X₃ = X₂ - X₁  →  c₃*X₃ adds -c₃ to X₁ and +c₃ to X₂
        coeff_map[key1] = get(coeff_map, key1, 0 // 1) - c3
        coeff_map[key2] = get(coeff_map, key2, 0 // 1) + c3
        coeff_map[key3] = 0 // 1
    end
end

# ============================================================
# CovD reduction preprocessing
# ============================================================

"""
Apply metric compatibility: CovD[-x][g[-a,-b]] → 0 for any registered metric.
"""
function _reduce_metric_compatibility(s::AbstractString)::AbstractString
    for (covd_sym, metric_obj) in _metrics
        covd = string(covd_sym)
        mname = string(metric_obj.name)
        pat = Regex(covd * raw"\[-\w+\]\[" * mname * raw"\[-\w+,-\w+\]\]")
        s = replace(s, pat => "0")
    end
    s
end

"""
Apply second Bianchi identity: detect cyclic sum
∇_e R_{abcd} + ∇_c R_{abde} + ∇_d R_{abec} = 0 and replace all three terms with 0.
"""
function _reduce_second_bianchi(s::AbstractString)::AbstractString
    isempty(_metrics) && return s

    # Find all CovD[-x][Riemann[-a,-b,-c,-d]] patterns
    pat = r"(\w+)\[(-\w+)\]\[(\w+)\[(-\w+),(-\w+),(-\w+),(-\w+)\]\]"
    matches = collect(eachmatch(pat, s))
    isempty(matches) && return s

    # Group by (cd_name, riem_name, r1, r2)
    groups = Dict{NTuple{4,String},Vector{Tuple{String,String,String,String}}}()
    for m in matches
        cd_name, cd_idx, riem_name = m[1], m[2], m[3]
        r1, r2, r3, r4 = m[4], m[5], m[6], m[7]
        # Only process registered CovD / matching Riemann pairs
        cd_sym = Symbol(cd_name)
        haskey(_metrics, cd_sym) || continue
        Symbol(riem_name) == Symbol("Riemann" * cd_name) || continue
        key = (cd_name, riem_name, r1, r2)
        v = get!(groups, key, Tuple{String,String,String,String}[])
        push!(v, (m.match, cd_idx, r3, r4))
    end

    to_remove = String[]
    for (_, terms) in groups
        length(terms) < 3 && continue
        n = length(terms)
        used = falses(n)
        for i in 1:n
            used[i] && continue
            (full_i, ei, ci, di) = terms[i]
            # Cyclic: (cd=ei,r3=ci,r4=di) → (cd=ci,r3=di,r4=ei) → (cd=di,r3=ei,r4=ci)
            j_idx = findfirst(
                jj ->
                    !used[jj] &&
                    jj != i &&
                    terms[jj][2] == ci &&
                    terms[jj][3] == di &&
                    terms[jj][4] == ei,
                1:n,
            )
            isnothing(j_idx) && continue
            k_idx = findfirst(
                kk ->
                    !used[kk] &&
                    kk != i &&
                    kk != j_idx &&
                    terms[kk][2] == di &&
                    terms[kk][3] == ei &&
                    terms[kk][4] == ci,
                1:n,
            )
            isnothing(k_idx) && continue
            push!(to_remove, full_i, terms[j_idx][1], terms[k_idx][1])
            used[i] = used[j_idx] = used[k_idx] = true
        end
    end

    for full_pat in to_remove
        s = replace(s, full_pat => "0"; count=1)
    end
    s
end

"""
Apply CovD reductions before canonical parsing.
"""
function _preprocess_covd_reductions(s::AbstractString)::AbstractString
    s = _reduce_metric_compatibility(s)
    s = _reduce_second_bianchi(s)
    s
end

"""
    ToCanonical(expression::String) → String

Canonicalize a tensor expression. Returns "0" if all terms cancel.
"""
function ToCanonical(expression::AbstractString)::String
    s = strip(expression)
    (s == "0" || isempty(s)) && return "0"

    # Preprocess covariant derivative applications
    s = _preprocess_covd_reductions(s)

    terms = _parse_expression(s)
    isempty(terms) && return "0"

    # Expand Einstein tensors: EinsteinXXX[a,b] → RicciXXX[a,b] - (1/2) gXXX[a,b] RicciScalarXXX[]
    terms = _expand_einstein_terms(terms)

    # Canonicalize each term
    canon_terms = TermAST[]
    for term in terms
        result = _canonicalize_term(term)
        isnothing(result) || push!(canon_terms, result)
    end

    isempty(canon_terms) && return "0"

    # Collect like terms: key = tuple of (name, frozen_indices)
    coeff_map = Dict{Vector{Tuple{Symbol,Vector{String}}},Rational{Int}}()
    key_order = Vector{Tuple{Symbol,Vector{String}}}[]

    for term in canon_terms
        key = [(f.tensor_name, copy(f.indices)) for f in term.factors]
        if !haskey(coeff_map, key)
            coeff_map[key] = 0 // 1
            push!(key_order, key)
        end
        coeff_map[key] += term.coeff
    end

    # Apply Bianchi identity reduction: R_{a[bcd]} = 0
    _bianchi_reduce!(coeff_map, key_order)

    # Drop zero-coefficient terms
    keys_nonzero = filter(k -> coeff_map[k] != 0, key_order)
    isempty(keys_nonzero) && return "0"

    # Sort keys for deterministic output
    sort!(keys_nonzero; by=k -> [(string(n), idxs) for (n, idxs) in k])

    # Serialize
    _serialize(keys_nonzero, coeff_map)
end

"""
Canonicalize a single term; returns nothing if the term is zero.
"""
function _canonicalize_term(term::TermAST)::Union{TermAST,Nothing}
    running_sign = term.coeff
    new_factors = FactorAST[]

    for f in term.factors
        t = get(_tensors, f.tensor_name, nothing)
        if isnothing(t)
            # Unknown tensor: treat as NoSymmetry, pass through unchanged
            push!(new_factors, FactorAST(f.tensor_name, copy(f.indices)))
            continue
        end

        current = copy(f.indices)
        sym = t.symmetry

        if isempty(sym.slots) || sym.type == :NoSymmetry
            push!(new_factors, FactorAST(f.tensor_name, current))
            continue
        end

        (canon_indices, factor_sign) = canonicalize_slots(current, sym.type, sym.slots)

        if factor_sign == 0
            return nothing  # term is zero
        end

        running_sign *= (factor_sign // 1)
        push!(new_factors, FactorAST(f.tensor_name, canon_indices))
    end

    # Sort factors within the term for canonical factor ordering.
    # In abstract index notation, tensor factors commute (tensor product is symmetric),
    # so we canonicalize factor order by tensor name then index list.
    sort!(new_factors; by=f -> (string(f.tensor_name), f.indices))

    TermAST(running_sign, new_factors)
end

"""
Serialize the canonical map to a Wolfram-style string.
"""
function _serialize(
    keys::Vector{Vector{Tuple{Symbol,Vector{String}}}},
    coeff_map::Dict{Vector{Tuple{Symbol,Vector{String}}},Rational{Int}},
)::String
    parts = Tuple{Rational{Int},String}[]

    for key in keys
        c = coeff_map[key]
        c == 0 && continue

        mono = join(["$(n)[$(join(idxs,","))]" for (n, idxs) in key], " ")
        push!(parts, (c, mono))
    end

    isempty(parts) && return "0"

    result = IOBuffer()
    first = true
    for (c, mono) in parts
        abs_c = abs(c)
        sign_c = c > 0 ? 1 : -1
        abs_str = if denominator(abs_c) == 1
            string(numerator(abs_c))
        else
            "($(numerator(abs_c))/$(denominator(abs_c)))"
        end
        if first
            if c == 1
                print(result, mono)
            elseif c == -1
                print(result, "-", mono)
            elseif sign_c > 0
                print(result, abs_str, " ", mono)
            else
                print(result, "-", abs_str, " ", mono)
            end
            first = false
        else
            if c == 1
                print(result, " + ", mono)
            elseif c == -1
                print(result, " - ", mono)
            elseif sign_c > 0
                print(result, " + ", abs_str, " ", mono)
            else
                print(result, " - ", abs_str, " ", mono)
            end
        end
    end

    String(take!(result))
end

# ============================================================
# Contract (ContractMetric)
# ============================================================

"""
    Contract(expression::String) → String

Perform metric contraction (ContractMetric) on a tensor expression.

For each metric factor in the expression, contracts its indices with matching
indices in other factors (raises/lowers indices, removes the metric).

Physics rules applied:

  - Weyl-type tensors (traceless): any self-trace → term is 0
  - Einstein tensor trace: tr(G_{ab}) → (1 - dim/2) * RicciScalar
"""
function Contract(expression::AbstractString)::String
    s = strip(expression)
    (s == "0" || isempty(s)) && return "0"

    terms = _parse_expression(s)
    isempty(terms) && return "0"

    result_terms = TermAST[]
    for term in terms
        contracted = _contract_term(term)
        isnothing(contracted) && continue
        push!(result_terms, contracted)
    end

    isempty(result_terms) && return "0"

    # Run ToCanonical on the contracted result
    ToCanonical(_serialize_terms(result_terms))
end

"""
Return the bare index label (strip leading '-').
"""
_bare(s::AbstractString) = startswith(s, "-") ? s[2:end] : string(s)

"""
True if index is covariant (has leading '-').
"""
_is_covariant(s::AbstractString) = startswith(s, "-")

"""
Find which registered metric a tensor factor corresponds to, and its variance.
Returns (covd_key, MetricObj, :contravariant | :covariant) or nothing.
:contravariant — g^{ab}: both indices up (no '-' prefix) → raises indices
:covariant     — g_{ab}: both indices down ('-' prefix)   → lowers indices
"""
function _factor_as_metric(f::FactorAST)::Union{Tuple{Symbol,MetricObj,Symbol},Nothing}
    t = get(_tensors, f.tensor_name, nothing)
    isnothing(t) && return nothing
    length(f.indices) == 2 || return nothing
    for (covd, metric) in _metrics
        if metric.name == f.tensor_name
            i1_cov = _is_covariant(f.indices[1])
            i2_cov = _is_covariant(f.indices[2])
            if !i1_cov && !i2_cov
                return (covd, metric, :contravariant)  # g^{ab}
            elseif i1_cov && i2_cov
                return (covd, metric, :covariant)       # g_{ab}
            end
        end
    end
    nothing
end

"""
Apply ContractMetric to a single term.
Returns the contracted TermAST, or nothing if the term is zero.
"""
function _contract_term(term::TermAST)::Union{TermAST,Nothing}
    # Iteratively contract metrics until none remain
    current = term
    max_iters = 20
    for _ in 1:max_iters
        result = _contract_one_metric(current)
        if isnothing(result)
            return nothing  # term is zero
        end
        if result === current
            # No metric found / no further contraction possible
            break
        end
        current = result
    end
    current
end

"""
Find one metric factor and contract it with another factor (or apply a trace rule).
Returns:

  - The updated TermAST if a contraction was performed
  - the same TermAST object if no metric found (signal: no more contractions)
  - nothing if the term is zero (traceless tensor trace)
"""
function _contract_one_metric(term::TermAST)::Union{TermAST,Nothing}
    factors = term.factors

    # Find a metric factor (contravariant or covariant)
    metric_pos = 0
    metric_covd = nothing
    metric_obj = nothing
    metric_var = :contravariant  # :contravariant (g^{ab}) or :covariant (g_{ab})
    for (i, f) in enumerate(factors)
        r = _factor_as_metric(f)
        if !isnothing(r)
            metric_pos = i
            metric_covd, metric_obj, metric_var = r
            break
        end
    end

    metric_pos == 0 && return term  # no metric found, signal no-op

    metric_factor = factors[metric_pos]

    # For g^{ab} (contravariant): metric indices are UP, we look for DOWN (covariant) matches
    # For g_{ab} (covariant):     metric indices are DOWN, we look for UP (contravariant) matches
    if metric_var == :contravariant
        # g^{ab}: indices stored without '-', bare labels are the contracted names
        idx_1 = metric_factor.indices[1]   # e.g. "cia" (up)
        idx_2 = metric_factor.indices[2]   # e.g. "cib" (up)
        bare_1 = _bare(idx_1)
        bare_2 = _bare(idx_2)
    else
        # g_{ab}: indices stored with '-', bare labels are the contracted names
        idx_1 = metric_factor.indices[1]   # e.g. "-cia" (down)
        idx_2 = metric_factor.indices[2]   # e.g. "-cib" (down)
        bare_1 = _bare(idx_1)
        bare_2 = _bare(idx_2)
    end

    # Find another factor that has matching index(es) of the opposite variance
    for (j, other) in enumerate(factors)
        j == metric_pos && continue

        if metric_var == :contravariant
            # g^{ab} contracts with down (-) indices in other factors
            has_1 = any(idx -> _bare(idx) == bare_1 && _is_covariant(idx), other.indices)
            has_2 = any(idx -> _bare(idx) == bare_2 && _is_covariant(idx), other.indices)
        else
            # g_{ab} contracts with up (no -) indices in other factors
            has_1 = any(idx -> _bare(idx) == bare_1 && !_is_covariant(idx), other.indices)
            has_2 = any(idx -> _bare(idx) == bare_2 && !_is_covariant(idx), other.indices)
        end

        (has_1 || has_2) || continue

        # Perform the contraction: replace matched indices with the OTHER metric index
        # For g^{ab} contracting with T_{a...}: replace -a in T with b (up) → raises index
        # For g_{ab} contracting with T^{a...}: replace a in T with -b (down) → lowers index
        new_indices = copy(other.indices)

        function replace_idx!(new_idxs, bare_match, replacement, is_contra)
            for k in eachindex(new_idxs)
                b = _bare(new_idxs[k])
                cov = _is_covariant(new_idxs[k])
                # Match: correct bare label AND opposite variance to the metric
                if b == bare_match && (is_contra ? cov : !cov)
                    new_idxs[k] = replacement
                end
            end
        end

        if metric_var == :contravariant
            # g^{ab}: raise -a to b (up), and/or raise -b to a (up)
            if has_1 && has_2
                replace_idx!(new_indices, bare_1, idx_2, true)   # -a → b (up)
                replace_idx!(new_indices, bare_2, idx_1, true)   # -b → a (up)
            elseif has_1
                replace_idx!(new_indices, bare_1, idx_2, true)   # -a → b (up)
            else
                replace_idx!(new_indices, bare_2, idx_1, true)   # -b → a (up)
            end
        else
            # g_{ab}: lower a to -b (down), and/or lower b to -a (down)
            if has_1 && has_2
                replace_idx!(new_indices, bare_1, "-" * bare_2, false)  # a → -b (down)
                replace_idx!(new_indices, bare_2, "-" * bare_1, false)  # b → -a (down)
            elseif has_1
                replace_idx!(new_indices, bare_1, "-" * bare_2, false)  # a → -b (down)
            else
                replace_idx!(new_indices, bare_2, "-" * bare_1, false)  # b → -a (down)
            end
        end

        # Build the new factor with updated indices
        new_other = FactorAST(other.tensor_name, new_indices)

        # Detect traces:
        # 1. Double contraction (has_1 && has_2 against the same factor) is always a trace.
        #    For a rank-2 tensor: full trace (scalar).  For rank-4: trace on 2 slots.
        # 2. Self-trace after substitution: same bare label appears twice in new_indices.
        bare_new = [_bare(idx) for idx in new_indices]
        self_trace_from_subst = length(unique(bare_new)) < length(bare_new)
        is_trace = (has_1 && has_2) || self_trace_from_subst

        if is_trace
            # Apply physics rules for the trace case
            # First: is this tensor traceless?
            if other.tensor_name in _traceless_tensors
                return nothing  # term is zero
            end
            # Second: do we have a trace rule for this tensor?
            if has_1 && has_2 && haskey(_trace_scalars, other.tensor_name)
                # Check this is truly a full trace (all slots of the tensor contracted by metric)
                # For a rank-2 tensor this is always the case when has_1 && has_2
                # For rank-4 we only apply if the tensor has no remaining free indices after contraction
                # Count how many distinct bare labels remain in new_other after removing contracted ones
                remaining_free = [
                    idx for idx in new_other.indices if
                    !(_bare(idx) == bare_1 || _bare(idx) == bare_2)
                ]
                # If all original contracted slots are consumed, check trace rule
                if isempty(remaining_free) || all(b -> b == bare_1 || b == bare_2, bare_new)
                    (scalar_name, coeff_int) = _trace_scalars[other.tensor_name]
                    new_factors = FactorAST[]
                    scalar_factor = FactorAST(scalar_name, String[])
                    for (k, ff) in enumerate(factors)
                        k == metric_pos && continue
                        k == j && continue
                        push!(new_factors, ff)
                    end
                    push!(new_factors, scalar_factor)
                    new_coeff = term.coeff * coeff_int
                    return TermAST(new_coeff, new_factors)
                end
            end
            # No special rule: keep the self-trace factor (ToCanonical handles)
        end

        # Remove the metric factor, replace `other` with `new_other`
        new_factors = FactorAST[]
        for (k, ff) in enumerate(factors)
            k == metric_pos && continue
            if k == j
                push!(new_factors, new_other)
            else
                push!(new_factors, ff)
            end
        end
        return TermAST(term.coeff, new_factors)
    end

    # Metric found but no matching factor for either index — return as-is
    term
end

"""
Serialize a list of TermAST back to a string (without collecting like terms).
"""
function _serialize_terms(terms::Vector{TermAST})::String
    isempty(terms) && return "0"
    parts = Tuple{Int,String}[]
    for term in terms
        mono = join(
            ["$(f.tensor_name)[$(join(f.indices, ","))]" for f in term.factors], " "
        )
        push!(parts, (term.coeff, mono))
    end

    result = IOBuffer()
    first = true
    for (c, mono) in parts
        if first
            if c == 1
                print(result, mono)
            elseif c == -1
                print(result, "-", mono)
            else
                print(result, c, " ", mono)
            end
            first = false
        else
            if c == 1
                print(result, " + ", mono)
            elseif c == -1
                print(result, " - ", mono)
            elseif c > 0
                print(result, " + ", c, " ", mono)
            else
                print(result, " - ", abs(c), " ", mono)
            end
        end
    end
    String(take!(result))
end

end  # module XTensor
