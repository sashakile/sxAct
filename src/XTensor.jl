# sxAct — xAct Migration & Implementation
# Copyright (C) 2026 sxAct Contributors
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

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

using LinearAlgebra: det, inv

# ============================================================
# Exports
# ============================================================

# Type exports
export ManifoldObj, VBundleObj, TensorObj, MetricObj, IndexSpec, SymmetrySpec
export BasisObj, ChartObj

# State management
export reset_state!

# Global registry collections (mutable; exported for MemberQ use in conditions)
export Manifolds, Tensors, VBundles, Perturbations, Bases, Charts

# Def functions
export def_manifold!, def_tensor!, def_metric!, def_perturbation!
export def_basis!, def_chart!

# Accessor functions
export get_manifold, get_tensor, get_vbundle, get_metric, get_basis, get_chart
export list_manifolds, list_tensors, list_vbundles, list_bases, list_charts

# Query predicates (Wolfram-named, used by _wl_to_jl translator)
export ManifoldQ, TensorQ, VBundleQ, MetricQ, CovDQ, PerturbationQ, FermionicQ
export BasisQ, ChartQ
export Dimension, IndicesOfVBundle, SlotsOfTensor
export VBundleOfBasis, BasesOfVBundle, CNumbersOf, PDOfBasis
export ManifoldOfChart, ScalarsOfChart
export MemberQ

# Symbol validation
export ValidateSymbolInSession, set_symbol_hooks!

# Canonicalization and contraction
export ToCanonical, Contract, CommuteCovDs, Simplify

# Contract support
export SignDetOfMetric

# xPert background metric consistency
export check_metric_consistency, check_perturbation_order

# xPert perturbation order queries
export PerturbationOrder, PerturbationAtOrder
export perturb

# IBP and VarD
export IBP, TotalDerivativeQ, VarD

# xCoba coordinate transformations
export BasisChangeObj
export set_basis_change!, change_basis, Jacobian
export BasisChangeQ, BasisChangeMatrix, InverseBasisChangeMatrix

# xCoba component tensors (CTensor)
export CTensorObj
export set_components!, get_components, ComponentArray
export CTensorQ, component_value, ctensor_contract

# xCoba Christoffel symbols
export christoffel!

# xCoba ToBasis / FromBasis / TraceBasisDummy
export ToBasis, FromBasis, TraceBasisDummy

# Multi-term identity framework
export MultiTermIdentity, RegisterIdentity!

# xTras utilities
export CollectTensors, AllContractions, SymmetryOf, MakeTraceFree

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
type  — one of: :Symmetric, :Antisymmetric, :GradedSymmetric, :RiemannSymmetric, :YoungSymmetry, :NoSymmetry
slots — 1-indexed positions (within this tensor's slot list) that the symmetry acts on.
For :RiemannSymmetric, exactly 4 elements.
For :NoSymmetry, empty.
"""
struct SymmetrySpec
    type::Symbol
    slots::Vector{Int}
    partition::Vector{Int}  # non-empty for :YoungSymmetry only
end
SymmetrySpec(type::Symbol, slots::Vector{Int}) = SymmetrySpec(type, slots, Int[])

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

"""
A perturbation of a tensor: records the perturbed tensor name, its background
tensor name, and the perturbation order (1 = first order, 2 = second order, ...).
"""
struct PerturbationObj
    name::Symbol        # e.g. :Pertg1 (the perturbed tensor)
    background::Symbol  # e.g. :g (the background tensor)
    order::Int          # perturbation order ≥ 1
end

"""
A basis of vector fields on a vector bundle (non-coordinate frame).
Created by `def_basis!` or internally by `def_chart!`.
"""
struct BasisObj
    name::Symbol            # e.g. :tetrad
    vbundle::Symbol         # e.g. :TangentM
    cnumbers::Vector{Int}   # integer labels for basis elements, length == dim
    parallel_deriv::Symbol  # auto-created parallel derivative
    is_chart::Bool          # true if created by def_chart!
end

"""
A coordinate chart on a manifold. Internally creates a BasisObj.
"""
struct ChartObj
    name::Symbol            # e.g. :Schw (also the basis name)
    manifold::Symbol        # e.g. :M
    cnumbers::Vector{Int}   # coordinate integer labels
    scalars::Vector{Symbol} # coordinate scalar fields, e.g. [:t, :r, :theta, :phi]
end

"""
A coordinate transformation between two bases (stored as matrix + inverse + jacobian).
"""
struct BasisChangeObj
    from_basis::Symbol      # source basis name
    to_basis::Symbol        # target basis name
    matrix::Matrix{Any}     # transformation matrix (n×n)
    inverse::Matrix{Any}    # inverse matrix
    jacobian::Any           # determinant of matrix (cached)
end

"""
A component tensor: stores explicit numerical values of a tensor in a given basis.
"""
struct CTensorObj
    tensor::Symbol          # which abstract tensor this represents (e.g. :g)
    array::Array            # N-dimensional array of component values
    bases::Vector{Symbol}   # basis for each slot (length == ndims(array))
    weight::Int             # density weight (usually 0)
end

"""
    MultiTermIdentity

A multi-term identity relating N canonical tensor terms by a linear relation.

The identity asserts: Σᵢ coefficients[i] * T[slot_perms[i](free_indices)] = 0

Fields:

  - `name`: identity label (e.g. :FirstBianchi)
  - `tensor`: which tensor this applies to (e.g. :RiemannCD)
  - `n_slots`: total tensor rank (4 for Riemann)
  - `fixed_slots`: slot positions held constant across terms
  - `cycled_slots`: slot positions permuted across terms
  - `slot_perms`: for each term, the rank-permutation of cycled_slot values
  - `coefficients`: coefficient of each term in the identity (Σ coefficients[i] * X_i = 0)
  - `eliminate`: which term index to eliminate (reduce away)

Example — First Bianchi identity R_{a[bcd]} = 0:
Three canonical forms for 4 distinct indices p < q < r < s:
X₁ = R[p,q,r,s]  →  cycled ranks [1,2,3]
X₂ = R[p,r,q,s]  →  cycled ranks [2,1,3]
X₃ = R[p,s,q,r]  →  cycled ranks [3,1,2]
Identity: X₁ - X₂ + X₃ = 0;  eliminate X₃.
"""
struct MultiTermIdentity
    name::Symbol
    tensor::Symbol
    n_slots::Int
    fixed_slots::Vector{Int}
    cycled_slots::Vector{Int}
    slot_perms::Vector{Vector{Int}}
    coefficients::Vector{Rational{Int}}
    eliminate::Int
end

# ============================================================
# Global state
# ============================================================

const _manifolds = Dict{Symbol,ManifoldObj}()
const _vbundles = Dict{Symbol,VBundleObj}()
const _tensors = Dict{Symbol,TensorObj}()
const _metrics = Dict{Symbol,MetricObj}()
const _perturbations = Dict{Symbol,PerturbationObj}()
const _bases = Dict{Symbol,BasisObj}()
const _charts = Dict{Symbol,ChartObj}()
const _basis_changes = Dict{Tuple{Symbol,Symbol},BasisChangeObj}()
const _ctensors = Dict{Tuple{Symbol,Vararg{Symbol}},CTensorObj}()

const Manifolds = Symbol[]   # ordered list
const Tensors = Symbol[]
const VBundles = Symbol[]
const Perturbations = Symbol[]   # perturbation tensor names (ordered)
const Bases = Symbol[]
const Charts = Symbol[]

# Contract support: physics rules
# Tensors whose full trace vanishes (e.g. Weyl tensor)
const _traceless_tensors = Set{Symbol}()
# Trace rules: trace_of_tensor → (scalar_tensor_name, Int_coefficient)
# e.g. EinsteinXXX → (:RicciScalarXXX, -1)  meaning tr(G) = -1 * R
const _trace_scalars = Dict{Symbol,Tuple{Symbol,Int}}()

# Einstein expansion rules: EinsteinXXX → (RicciXXX, metricXXX, RicciScalarXXX)
# Allows ToCanonical to substitute G_{ab} = R_{ab} - (1/2) g_{ab} R
const _einstein_expansion = Dict{Symbol,Tuple{Symbol,Symbol,Symbol}}()

# Multi-term identity registry: tensor name → list of identities
# Auto-populated by def_tensor! for RiemannSymmetric tensors (first Bianchi).
const _identity_registry = Dict{Symbol,Vector{MultiTermIdentity}}()

# ============================================================
# Symbol validation hooks
# ============================================================
#
# XTensor runs standalone (no XCore dependency at module level).
# When loaded via xAct.jl, set_symbol_hooks! wires in XCore.ValidateSymbol
# and XCore.register_symbol so that every def_*! call validates names against
# the global xAct symbol registry.  In standalone mode, the hooks are no-ops
# and validation is limited to XTensor's own session-level checks.

const _validate_symbol_hook = Ref{Function}((_) -> nothing)
const _register_symbol_hook = Ref{Function}((_, _) -> nothing)

"""
    set_symbol_hooks!(validate, register)

Install XCore symbol-validation and registration hooks.

Called by xAct.jl after loading both XCore and XTensor:

    XTensor.set_symbol_hooks!(XCore.ValidateSymbol, XCore.register_symbol)
"""
function set_symbol_hooks!(validate::Function, register::Function)
    _validate_symbol_hook[] = validate
    _register_symbol_hook[] = register
    nothing
end

"""
    ValidateSymbolInSession(name::Symbol)

Check that `name` is not already used as a manifold, tensor, metric, vbundle,
covariant derivative, or perturbation in the current session.  Throws on
collision.  Analogous to Wolfram `ValidateSymbolInSession`.
"""
function ValidateSymbolInSession(name::Symbol)
    sname = string(name)
    ManifoldQ(name) &&
        error("ValidateSymbolInSession: \"$sname\" already used as a manifold")
    VBundleQ(name) &&
        error("ValidateSymbolInSession: \"$sname\" already used as a vector bundle")
    MetricQ(name) && error("ValidateSymbolInSession: \"$sname\" already used as a metric")
    TensorQ(name) && error("ValidateSymbolInSession: \"$sname\" already used as a tensor")
    CovDQ(name) &&
        error("ValidateSymbolInSession: \"$sname\" already used as a covariant derivative")
    PerturbationQ(name) &&
        error("ValidateSymbolInSession: \"$sname\" already used as a perturbation")
    BasisQ(name) && error("ValidateSymbolInSession: \"$sname\" already used as a basis")
    ChartQ(name) && error("ValidateSymbolInSession: \"$sname\" already used as a chart")
    nothing
end
ValidateSymbolInSession(name::AbstractString) = ValidateSymbolInSession(Symbol(name))

# ============================================================
# State management
# ============================================================

function reset_state!()
    empty!(_manifolds);
    empty!(_vbundles);
    empty!(_tensors);
    empty!(_metrics);
    empty!(_perturbations)
    empty!(_bases);
    empty!(_charts)
    empty!(_basis_changes)
    empty!(_ctensors)
    empty!(Manifolds);
    empty!(Tensors);
    empty!(VBundles);
    empty!(Perturbations)
    empty!(Bases);
    empty!(Charts)
    empty!(_traceless_tensors);
    empty!(_trace_scalars)
    empty!(_einstein_expansion)
    empty!(_identity_registry)
end

# ============================================================
# Multi-term identity framework
# ============================================================

"""
    RegisterIdentity!(tensor_name, identity)

Register a multi-term identity for a tensor. Identities are applied during
canonicalization by `_apply_identities!`.
"""
function RegisterIdentity!(tensor_name::Symbol, identity::MultiTermIdentity)
    if !haskey(_identity_registry, tensor_name)
        _identity_registry[tensor_name] = MultiTermIdentity[]
    end
    push!(_identity_registry[tensor_name], identity)
    nothing
end

"""
    _make_bianchi_identity(tensor_name)

Construct the first Bianchi identity R_{a[bcd]} = 0 for a 4-slot tensor
with RiemannSymmetric symmetry.

Canonical forms for indices p < q < r < s:
X₁ = R[p,q,r,s]  →  cycled ranks [1,2,3]
X₂ = R[p,r,q,s]  →  cycled ranks [2,1,3]
X₃ = R[p,s,q,r]  →  cycled ranks [3,1,2]
Identity: X₁ - X₂ + X₃ = 0;  eliminate X₃.
"""
function _make_bianchi_identity(tensor_name::Symbol)
    MultiTermIdentity(
        :FirstBianchi,
        tensor_name,
        4,
        [1],
        [2, 3, 4],
        [[1, 2, 3], [2, 1, 3], [3, 1, 2]],
        [1 // 1, -1 // 1, 1 // 1],
        3,
    )
end

"""
    _apply_identities!(coeff_map, key_order)

Apply all registered multi-term identities to the canonical term map.
Replaces the hardcoded `_bianchi_reduce!` with a general framework.
"""
function _apply_identities!(
    coeff_map::Dict{Vector{Tuple{Symbol,Vector{String}}},Rational{Int}},
    key_order::Vector{Vector{Tuple{Symbol,Vector{String}}}},
)
    isempty(_identity_registry) && return nothing
    for (_, identities) in _identity_registry
        for identity in identities
            _apply_single_identity!(coeff_map, key_order, identity)
        end
    end
    nothing
end

"""
    _apply_single_identity!(coeff_map, key_order, id)

Apply one multi-term identity to the canonical term map.

Groups single-factor terms by sector (values at fixed_slots + sorted values at cycled_slots),
then for each complete sector eliminates the designated term.
"""
function _apply_single_identity!(
    coeff_map::Dict{Vector{Tuple{Symbol,Vector{String}}},Rational{Int}},
    key_order::Vector{Vector{Tuple{Symbol,Vector{String}}}},
    id::MultiTermIdentity,
)
    # Map: sector_key → (rank_perm → key)
    # sector_key = (fixed_values, sorted_cycled_values)
    SectorKey = Tuple{Vector{String},Vector{String}}
    KeyType = Vector{Tuple{Symbol,Vector{String}}}
    sectors = Dict{SectorKey,Dict{Vector{Int},KeyType}}()

    for key in key_order
        get(coeff_map, key, 0 // 1) == 0 && continue
        length(key) != 1 && continue
        tname, indices = key[1]
        tname != id.tensor && continue
        length(indices) != id.n_slots && continue

        bare = [_bare(idx) for idx in indices]
        fixed_vals = [bare[s] for s in id.fixed_slots]
        cycled_vals = [bare[s] for s in id.cycled_slots]
        sorted_cycled = sort(cycled_vals)

        sector_key = (fixed_vals, sorted_cycled)
        if !haskey(sectors, sector_key)
            sectors[sector_key] = Dict{Vector{Int},KeyType}()
        end

        # Compute rank permutation: map each cycled value to its rank in sorted order
        rank_map = Dict{String,Int}()
        for (i, v) in enumerate(sorted_cycled)
            rank_map[v] = i
        end
        perm = [rank_map[v] for v in cycled_vals]

        sectors[sector_key][perm] = key
    end

    # Apply identity to each complete sector
    n_terms = length(id.coefficients)
    for (_, perm_to_key) in sectors
        length(perm_to_key) < n_terms && continue

        # Check all identity terms are present
        all_present = true
        for sp in id.slot_perms
            if !haskey(perm_to_key, sp)
                all_present = false
                break
            end
        end
        all_present || continue

        elim_key = perm_to_key[id.slot_perms[id.eliminate]]
        c_e = get(coeff_map, elim_key, 0 // 1)
        iszero(c_e) && continue

        # Eliminate: X_e = -(1/c_id_e) Σ_{i≠e} c_id_i * X_i
        c_id_e = id.coefficients[id.eliminate]
        for (i, sp) in enumerate(id.slot_perms)
            i == id.eliminate && continue
            other_key = perm_to_key[sp]
            coeff_map[other_key] =
                get(coeff_map, other_key, 0 // 1) + c_e * (-id.coefficients[i] / c_id_e)
        end
        coeff_map[elim_key] = 0 // 1
    end
    nothing
end

# ============================================================
# Accessor functions
# ============================================================

get_manifold(name::Symbol) = get(_manifolds, name, nothing)
get_tensor(name::Symbol) = get(_tensors, name, nothing)
get_vbundle(name::Symbol) = get(_vbundles, name, nothing)
get_metric(name::Symbol) = get(_metrics, name, nothing)
get_basis(name::Symbol) = get(_bases, name, nothing)
get_chart(name::Symbol) = get(_charts, name, nothing)
list_manifolds() = copy(Manifolds)
list_tensors() = copy(Tensors)
list_vbundles() = copy(VBundles)
list_bases() = copy(Bases)
list_charts() = copy(Charts)

get_manifold(name::AbstractString) = get_manifold(Symbol(name))
get_tensor(name::AbstractString) = get_tensor(Symbol(name))
get_vbundle(name::AbstractString) = get_vbundle(Symbol(name))
get_metric(name::AbstractString) = get_metric(Symbol(name))
get_basis(name::AbstractString) = get_basis(Symbol(name))
get_chart(name::AbstractString) = get_chart(Symbol(name))

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
BasisQ(s::Symbol) = haskey(_bases, s)
BasisQ(s::AbstractString) = BasisQ(Symbol(s))
ChartQ(s::Symbol) = haskey(_charts, s)
ChartQ(s::AbstractString) = ChartQ(Symbol(s))
CovDQ(s::Symbol) = haskey(_metrics, s) || any(b -> b.parallel_deriv == s, values(_bases))
CovDQ(s::AbstractString) = CovDQ(Symbol(s))
PerturbationQ(s::Symbol) = haskey(_perturbations, s)
PerturbationQ(s::AbstractString) = PerturbationQ(Symbol(s))
FermionicQ(s::Symbol) = begin
    t = get(_tensors, s, nothing)
    !isnothing(t) && t.symmetry.type == :GradedSymmetric
end
FermionicQ(s::AbstractString) = FermionicQ(Symbol(s))

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

function VBundleOfBasis(s::Symbol)
    b = get(_bases, s, nothing)
    isnothing(b) && error("VBundleOfBasis: basis $s not defined")
    b.vbundle
end
VBundleOfBasis(s::AbstractString) = VBundleOfBasis(Symbol(s))

function BasesOfVBundle(vb::Symbol)
    [b.name for b in values(_bases) if b.vbundle == vb]
end
BasesOfVBundle(vb::AbstractString) = BasesOfVBundle(Symbol(vb))

function CNumbersOf(s::Symbol)
    b = get(_bases, s, nothing)
    isnothing(b) && error("CNumbersOf: basis $s not defined")
    copy(b.cnumbers)
end
CNumbersOf(s::AbstractString) = CNumbersOf(Symbol(s))

function PDOfBasis(s::Symbol)
    b = get(_bases, s, nothing)
    isnothing(b) && error("PDOfBasis: basis $s not defined")
    b.parallel_deriv
end
PDOfBasis(s::AbstractString) = PDOfBasis(Symbol(s))

function ManifoldOfChart(s::Symbol)
    c = get(_charts, s, nothing)
    isnothing(c) && error("ManifoldOfChart: chart $s not defined")
    c.manifold
end
ManifoldOfChart(s::AbstractString) = ManifoldOfChart(Symbol(s))

function ScalarsOfChart(s::Symbol)
    c = get(_charts, s, nothing)
    isnothing(c) && error("ScalarsOfChart: chart $s not defined")
    copy(c.scalars)
end
ScalarsOfChart(s::AbstractString) = ScalarsOfChart(Symbol(s))

function MemberQ(collection::Symbol, s::Symbol)
    if collection == :Manifolds
        s in Manifolds
    elseif collection == :Tensors
        s in Tensors
    elseif collection == :VBundles
        s in VBundles
    elseif collection == :Perturbations
        s in Perturbations
    elseif collection == :Bases
        s in Bases
    elseif collection == :Charts
        s in Charts
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

    # Young[{k1,k2,...}] — applies to all tensor slots in order
    m_young = match(r"^Young\[\{([^}]*)\}\]$", sym_str)
    if !isnothing(m_young)
        partition = [
            parse(Int, strip(s)) for s in split(something(m_young.captures[1]), ",")
        ]
        all_slots = collect(1:length(slot_specs))
        sum(partition) == length(all_slots) || error(
            "Young partition sum $(sum(partition)) ≠ tensor arity $(length(all_slots))"
        )
        return SymmetrySpec(:YoungSymmetry, all_slots, partition)
    end

    m = match(
        r"^(Symmetric|Antisymmetric|GradedSymmetric|RiemannSymmetric)\[\{([^}]*)\}\]$",
        sym_str,
    )
    isnothing(m) && error("Cannot parse symmetry string: $sym_str")

    type_str = something(m.captures[1])
    labels_str = something(m.captures[2])

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
    _validate_symbol_hook[](name)
    ValidateSymbolInSession(name)

    tb_name = Symbol("Tangent" * string(name))

    m = ManifoldObj(name, dim, index_labels)
    tb = VBundleObj(tb_name, name, index_labels)

    _manifolds[name] = m
    _vbundles[tb.name] = tb
    push!(Manifolds, name)
    push!(VBundles, tb.name)

    _register_symbol_hook[](name, "XTensor")
    _register_symbol_hook[](tb_name, "XTensor")

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
    _skip_validation::Bool=false,
)::TensorObj
    if !_skip_validation
        _validate_symbol_hook[](name)
        ValidateSymbolInSession(name)
    end

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

    _register_symbol_hook[](name, "XTensor")

    # Auto-register first Bianchi identity for RiemannSymmetric tensors
    if sym.type == :RiemannSymmetric && length(slots) == 4
        RegisterIdentity!(name, _make_bianchi_identity(name))
    end

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
    def_tensor!(name, index_specs, manifolds::Vector{Symbol}; symmetry_str=nothing) → TensorObj

Multi-index-set variant: each index label must belong to one of the given manifolds.
The first manifold in the list is used as the primary manifold stored in TensorObj.manifold.
This enables tensors that mix indices from e.g. spacetime and internal gauge manifolds.
"""
function def_tensor!(
    name::Symbol,
    index_specs::Vector{String},
    manifolds::Vector{Symbol};
    symmetry_str::Union{String,Nothing}=nothing,
    _skip_validation::Bool=false,
)::TensorObj
    isempty(manifolds) && error("def_tensor!: manifolds list is empty")

    if !_skip_validation
        _validate_symbol_hook[](name)
        ValidateSymbolInSession(name)
    end

    # Validate all listed manifolds exist and build union of allowed labels
    allowed = Set{Symbol}()
    for mname in manifolds
        m = get(_manifolds, mname, nothing)
        isnothing(m) && error("def_tensor!: manifold $mname not defined")
        union!(allowed, m.index_labels)
    end

    # Parse index specs into IndexSpec
    slots = IndexSpec[]
    for spec in index_specs
        if startswith(spec, "-")
            push!(slots, IndexSpec(Symbol(spec[2:end]), true))
        else
            push!(slots, IndexSpec(Symbol(spec), false))
        end
    end

    # Validate each label belongs to one of the manifolds
    for s in slots
        s.label in allowed ||
            error("Index label $(s.label) not found in any of manifolds $manifolds")
    end

    # Primary manifold = first in list (used by CommuteCovDs for fresh index selection)
    primary_manifold = manifolds[1]
    sym = _parse_symmetry(symmetry_str, slots)
    t = TensorObj(name, slots, primary_manifold, sym)
    _tensors[name] = t
    push!(Tensors, name)

    _register_symbol_hook[](name, "XTensor")

    # Auto-register first Bianchi identity for RiemannSymmetric tensors
    if sym.type == :RiemannSymmetric && length(slots) == 4
        RegisterIdentity!(name, _make_bianchi_identity(name))
    end

    t
end

# Convenience overload: Vector of manifold name strings
function def_tensor!(
    name::AbstractString,
    index_specs::Vector,
    manifolds::Vector;
    symmetry_str::Union{String,Nothing}=nothing,
)::TensorObj
    sym_name = Symbol(name)
    sym_manifolds = Symbol[Symbol(string(m)) for m in manifolds]
    str_specs = [string(s) for s in index_specs]
    def_tensor!(sym_name, str_specs, sym_manifolds; symmetry_str=symmetry_str)
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
    # Validate covd name against xAct registry and session
    _validate_symbol_hook[](covd_name)
    ValidateSymbolInSession(covd_name)

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
    # (metric tensor name validated inside def_tensor!)
    sym_str = "Symmetric[{$(join(slot_strs, ","))}]"
    def_tensor!(metric_name, slot_strs, manifold_sym; symmetry_str=sym_str)

    metric = MetricObj(metric_name, manifold_sym, covd_name, signdet)
    _metrics[covd_name] = metric

    _register_symbol_hook[](covd_name, "XTensor")

    # Auto-create curvature tensors
    _auto_create_curvature!(manifold_sym, covd_name)

    metric
end

function def_metric!(
    signdet::Int, metric_expr::AbstractString, covd_name::AbstractString
)::MetricObj
    def_metric!(signdet, metric_expr, Symbol(covd_name))
end

# ============================================================
# Basis and Chart definitions
# ============================================================

"""
    def_basis!(name, vbundle, cnumbers) → BasisObj

Define a basis of vector fields on a vector bundle.
`cnumbers` are integer labels for the basis elements (length must equal dim of vbundle).
Auto-creates a parallel derivative symbol `PD<name>`.
"""
function def_basis!(
    name::Symbol, vbundle::Symbol, cnumbers::Vector{Int}; _skip_validation::Bool=false
)::BasisObj
    if !_skip_validation
        _validate_symbol_hook[](name)
        ValidateSymbolInSession(name)
    end

    # Validate vbundle exists
    vb = get(_vbundles, vbundle, nothing)
    isnothing(vb) && error("def_basis!: vector bundle $vbundle not defined")

    # Validate cnumbers length matches dimension
    manifold = _manifolds[vb.manifold]
    dim = manifold.dimension
    length(cnumbers) == dim || error(
        "def_basis!: cnumbers length $(length(cnumbers)) != dimension $dim of $vbundle"
    )

    # Validate cnumbers are distinct integers
    length(unique(cnumbers)) == length(cnumbers) ||
        error("def_basis!: cnumbers must be distinct")

    # Auto-create parallel derivative name
    pd_name = Symbol("PD" * string(name))

    b = BasisObj(name, vbundle, sort(cnumbers), pd_name, false)
    _bases[name] = b
    push!(Bases, name)

    _register_symbol_hook[](name, "XTensor")
    _register_symbol_hook[](pd_name, "XTensor")

    b
end

function def_basis!(
    name::AbstractString, vbundle::AbstractString, cnumbers::Vector{Int}
)::BasisObj
    def_basis!(Symbol(name), Symbol(vbundle), cnumbers)
end

function def_basis!(
    name::AbstractString, vbundle::AbstractString, cnumbers::Vector
)::BasisObj
    def_basis!(Symbol(name), Symbol(vbundle), Int[Int(c) for c in cnumbers])
end

"""
    def_chart!(name, manifold, cnumbers, scalars) → ChartObj

Define a coordinate chart on a manifold. Internally creates a BasisObj (coordinate basis)
and registers the coordinate scalar fields as tensors.
`scalars` are the coordinate field names, e.g. [:t, :r, :theta, :phi].
"""
function def_chart!(
    name::Symbol, manifold::Symbol, cnumbers::Vector{Int}, scalars::Vector{Symbol}
)::ChartObj
    _validate_symbol_hook[](name)
    ValidateSymbolInSession(name)

    # Validate manifold exists
    m = get(_manifolds, manifold, nothing)
    isnothing(m) && error("def_chart!: manifold $manifold not defined")

    dim = m.dimension
    length(cnumbers) == dim ||
        error("def_chart!: cnumbers length $(length(cnumbers)) != dimension $dim")
    length(scalars) == dim ||
        error("def_chart!: scalars length $(length(scalars)) != dimension $dim")
    length(unique(cnumbers)) == length(cnumbers) ||
        error("def_chart!: cnumbers must be distinct")

    # Create the coordinate basis on the tangent bundle
    tb_name = Symbol("Tangent" * string(manifold))
    def_basis!(name, tb_name, cnumbers; _skip_validation=true)
    # Mark it as a chart basis
    _bases[name] = BasisObj(
        name, tb_name, sort(cnumbers), _bases[name].parallel_deriv, true
    )

    # Register coordinate scalars as rank-0 tensors on this manifold
    for sc in scalars
        if !TensorQ(sc)
            t = TensorObj(sc, IndexSpec[], manifold, SymmetrySpec(:NoSymmetry, Int[]))
            _tensors[sc] = t
            push!(Tensors, sc)
            _register_symbol_hook[](sc, "XTensor")
        end
    end

    chart = ChartObj(name, manifold, sort(cnumbers), scalars)
    _charts[name] = chart
    push!(Charts, name)

    _register_symbol_hook[](name, "XTensor")

    chart
end

function def_chart!(
    name::AbstractString, manifold::AbstractString, cnumbers::Vector, scalars::Vector
)::ChartObj
    def_chart!(
        Symbol(name),
        Symbol(manifold),
        Int[Int(c) for c in cnumbers],
        Symbol[Symbol(s) for s in scalars],
    )
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
        _register_symbol_hook[](ricci_scalar_name, "XTensor")
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

    # Christoffel (second kind): Γ^a_{bc}, symmetric in last two covariant slots
    # Use 3 distinct labels to avoid symmetry slot lookup ambiguity
    if n >= 3
        i3 = "-" * string(idxs[3])
        christoffel_name = Symbol("Christoffel" * covd_str)
        if !haskey(_tensors, christoffel_name)
            # Slot 1 = contravariant (up), Slots 2,3 = covariant (down)
            slots3 = String[string(idxs[1]), i2, i3]
            sym3 = "Symmetric[{$i2,$i3}]"
            def_tensor!(christoffel_name, slots3, manifold; symmetry_str=sym3)
        end
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
        n_coeff = parse(Int, something(m.captures[1]))
        inner = strip(something(m.captures[2]))
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
        num = parse(Int, something(m_rat.captures[1]))
        den = parse(Int, something(m_rat.captures[2]))
        coeff = coeff * (num // den)
        s = strip(s[(length(m_rat.match) + 1):end])
    else
        # Match leading integer (possibly with optional * and surrounding spaces)
        # Handles "7*T", "7 *T", "7* T", "7 * T"
        m_int = match(r"^(-?\d+)\s*\*?\s*", s)
        if !isnothing(m_int)
            coeff = coeff * (parse(Int, something(m_int.captures[1])) // 1)
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
    _bianchi_reduce!(coeff_map, key_order)

Legacy wrapper: delegates to `_apply_identities!`.
Kept for backward compatibility; new code should call `_apply_identities!` directly.
"""
function _bianchi_reduce!(
    coeff_map::Dict{Vector{Tuple{Symbol,Vector{String}}},Rational{Int}},
    key_order::Vector{Vector{Tuple{Symbol,Vector{String}}}},
)
    _apply_identities!(coeff_map, key_order)
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

# ============================================================
# CommuteCovDs
# ============================================================

"""
    CommuteCovDs(expr, covd_name, idx1, idx2) → String

Apply the commutation identity for two covariant derivatives:
∇_{idx1} ∇_{idx2} T = ∇_{idx2} ∇_{idx1} T + curvature correction terms

where correction terms are given by the Riemann curvature:

  - For each covariant slot -aᵢ: correction `- RiemannCD[-aᵢ, e, idx1, idx2] T[..., -e, ...]`
  - For each contravariant slot aᵢ: correction `+ RiemannCD[aᵢ, -e, idx1, idx2] T[..., e, ...]`

Here `e` is a fresh dummy index (contravariant/covariant in Riemann, covariant/contravariant in T).

Args:
expr      : String expression containing `covd[idx1][covd[idx2][tensor[slots]]]`
covd_name : Symbol — e.g. :CVD
idx1      : String — first derivative index, e.g. "-cva"
idx2      : String — second derivative index, e.g. "-cvb"

Returns a String expression suitable for ToCanonical.
"""
function CommuteCovDs(
    expr::AbstractString, covd_name::Symbol, idx1::AbstractString, idx2::AbstractString
)::String
    covd_str = string(covd_name)

    # Escape special regex chars in idx1, idx2 (e.g. the leading '-')
    re_esc(s)::String = replace(s, r"([-\[\].\^$*+?{}|()])" => s"\\\1")

    # Pattern: covd[idx1][covd[idx2][TENSOR_NAME[SLOTS]]]
    pat = Regex(
        covd_str *
        raw"\[" *
        re_esc(idx1) *
        raw"\]\[" *
        covd_str *
        raw"\[" *
        re_esc(idx2) *
        raw"\]\[" *
        raw"(\w+)\[(.*?)\]" *
        raw"\]\]",
    )
    m = match(pat, expr)
    if isnothing(m)
        error("CommuteCovDs: pattern not found in expression: $expr")
    end

    tensor_name = m[1]
    slots_str = m[2]   # e.g. "-cvc" or "-cvc,-cvd,cve"

    # Parse slot strings
    slots = strip.(split(slots_str, ","))

    # Lookup tensor to find its manifold
    tensor_sym = Symbol(tensor_name)
    haskey(_tensors, tensor_sym) ||
        error("CommuteCovDs: tensor $tensor_name not registered")
    manifold_sym = _tensors[tensor_sym].manifold
    haskey(_manifolds, manifold_sym) ||
        error("CommuteCovDs: manifold $manifold_sym not found")
    manifold_indices = _manifolds[manifold_sym].index_labels

    # Riemann tensor name for this CovD
    riemann_name = "Riemann" * covd_str

    # Collect all index names already used in the expression
    used_idx = Set{String}(m2.match for m2 in eachmatch(r"\b([a-z][a-z0-9]*)\b", expr))
    push!(used_idx, lstrip(idx1, '-'), lstrip(idx2, '-'))
    for s in slots
        push!(used_idx, lstrip(s, '-'))
    end

    # Pick fresh dummy indices from the manifold's index list
    dummies = String[]
    for idx_sym in manifold_indices
        name = string(idx_sym)
        if name ∉ used_idx
            push!(dummies, name)
            push!(used_idx, name)
            length(dummies) >= length(slots) && break
        end
    end
    length(dummies) < length(slots) &&
        error("CommuteCovDs: not enough fresh indices in manifold $manifold_sym")

    # Build commuted double-derivative: covd[idx2][covd[idx1][tensor[slots]]]
    commuted = string(
        covd_str,
        "[",
        idx2,
        "][",
        covd_str,
        "[",
        idx1,
        "][",
        tensor_name,
        "[",
        join(slots, ","),
        "]]]",
    )

    # Build correction terms (one per slot of the inner tensor)
    parts = [commuted]
    for (i, slot) in enumerate(slots)
        covariant = startswith(slot, "-")
        index_name = lstrip(slot, '-')
        dummy = dummies[i]

        new_slots = copy(slots)
        if covariant
            # Covariant slot -aᵢ:  correction = - Riemann[-aᵢ, e, idx1, idx2] T[..., -e, ...]
            # dummy 'e' is contravariant in Riemann (slot 2), covariant in T (-e)
            new_slots[i] = "-" * dummy
            riemann_args = "-" * index_name * "," * dummy * "," * idx1 * "," * idx2
            correction =
                "- " *
                riemann_name *
                "[" *
                riemann_args *
                "] " *
                tensor_name *
                "[" *
                join(new_slots, ",") *
                "]"
        else
            # Contravariant slot aᵢ: correction = + Riemann[aᵢ, -e, idx1, idx2] T[..., e, ...]
            # dummy 'e' is covariant in Riemann (-e slot 2), contravariant in T (e)
            new_slots[i] = dummy
            riemann_args = index_name * ",-" * dummy * "," * idx1 * "," * idx2
            correction =
                "+ " *
                riemann_name *
                "[" *
                riemann_args *
                "] " *
                tensor_name *
                "[" *
                join(new_slots, ",") *
                "]"
        end
        push!(parts, correction)
    end

    join(parts, " ")
end

# Convenience: accept index list as a Vector of strings
function CommuteCovDs(
    expr::AbstractString, covd_name::Symbol, indices::Vector{<:AbstractString}
)::String
    length(indices) == 2 ||
        error("CommuteCovDs: expected exactly 2 indices, got $(length(indices))")
    CommuteCovDs(expr, covd_name, indices[1], indices[2])
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
    _apply_identities!(coeff_map, key_order)

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

        (canon_indices, factor_sign) = canonicalize_slots(
            current, sym.type, sym.slots, sym.partition
        )

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
        # mono is empty for pure-scalar terms (no tensor factors)
        mono_part = isempty(mono) ? abs_str : (abs_c == 1 ? mono : abs_str * " " * mono)
        if first
            print(result, sign_c > 0 ? mono_part : "-" * mono_part)
            first = false
        else
            print(result, sign_c > 0 ? " + " * mono_part : " - " * mono_part)
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
                # Fire trace rule only when no free indices remain outside the contracted pair
                if isempty(remaining_free)
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
            # Special case: metric contracted with itself → dimension (trace = g^ab g_ab = n)
            if has_1 && has_2
                other_as_metric = _factor_as_metric(other)
                if !isnothing(other_as_metric)
                    # Get the manifold dimension for this metric
                    (_, other_metric_obj, _) = other_as_metric
                    manifold = get(_manifolds, other_metric_obj.manifold, nothing)
                    if !isnothing(manifold) && other_metric_obj.name == metric_obj.name
                        dim = manifold.dimension
                        # Return a pure scalar term with no factors, coefficient = dim
                        remaining = [
                            ff for
                            (k, ff) in enumerate(factors) if k != metric_pos && k != j
                        ]
                        new_coeff = term.coeff * dim
                        return TermAST(new_coeff, remaining)
                    end
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
    parts = Tuple{Rational{Int},String}[]
    for term in terms
        mono = join(
            ["$(f.tensor_name)[$(join(f.indices, ","))]" for f in term.factors], " "
        )
        push!(parts, (term.coeff, mono))
    end

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
        mono_part = isempty(mono) ? abs_str : (abs_c == 1 ? mono : abs_str * " " * mono)
        if first
            print(result, sign_c > 0 ? mono_part : "-" * mono_part)
            first = false
        else
            print(result, sign_c > 0 ? " + " * mono_part : " - " * mono_part)
        end
    end
    String(take!(result))
end

# ============================================================
# xPert: Background metric consistency and perturbation order
# ============================================================

"""
    def_perturbation!(tensor, background, order) → PerturbationObj

Register a perturbation tensor.

  - `tensor`     — name of the perturbed tensor (e.g. `:Pertg1`)
  - `background` — name of the background tensor it perturbs (e.g. `:g`)
  - `order`      — perturbation order (≥ 1)

The perturbed tensor must already be registered (via `def_tensor!`).
The background tensor must already be registered (via `def_tensor!` or `def_metric!`).
Raises an error if either tensor is unknown, `order < 1`, or the perturbation
is already defined.
"""
function def_perturbation!(tensor::Symbol, background::Symbol, order::Int)::PerturbationObj
    order < 1 && error("def_perturbation!: order must be ≥ 1, got $order")
    PerturbationQ(tensor) &&
        error("def_perturbation!: perturbation $tensor already defined")
    haskey(_tensors, tensor) ||
        error("def_perturbation!: tensor $tensor not registered — call def_tensor! first")
    haskey(_tensors, background) ||
        error("def_perturbation!: background tensor $background not registered")
    for (existing_name, existing_p) in _perturbations
        if existing_p.background == background && existing_p.order == order
            error(
                "def_perturbation!: order-$order perturbation for $background already registered as $existing_name",
            )
        end
    end

    p = PerturbationObj(tensor, background, order)
    _perturbations[tensor] = p
    push!(Perturbations, tensor)
    p
end

function def_perturbation!(tensor::AbstractString, background::AbstractString, order::Int)
    def_perturbation!(Symbol(tensor), Symbol(background), order)
end

"""
    check_metric_consistency(metric_name) → Bool

Verify that a registered metric is internally consistent: its metric tensor
is symmetric and its inverse (raised-index version) is registered as its own
symmetric tensor.  Currently validates:

 1. The metric tensor exists in the tensor registry.
 2. The metric is recorded in the metric registry (via `def_metric!`).
 3. The metric tensor is symmetric (rank-2 with Symmetric symmetry).

Returns `true` if all checks pass, `false` otherwise (never throws).
"""
function check_metric_consistency(metric_name::Symbol)::Bool
    # Check metric tensor is defined
    t = get(_tensors, metric_name, nothing)
    isnothing(t) && return false

    # Check metric is registered in the metric registry
    found = false
    for (_, m) in _metrics
        if m.name == metric_name
            found = true
            break
        end
    end
    found || return false

    # Check rank-2 symmetric
    length(t.slots) == 2 || return false
    t.symmetry.type == :Symmetric || return false

    true
end

function check_metric_consistency(metric_name::AbstractString)::Bool
    check_metric_consistency(Symbol(metric_name))
end

"""
    check_perturbation_order(tensor_name, order) → Bool

Verify that a perturbation tensor is registered with the given perturbation order.
Returns `true` if `tensor_name` is a registered perturbation of exactly `order`,
`false` otherwise.
"""
function check_perturbation_order(tensor_name::Symbol, order::Int)::Bool
    p = get(_perturbations, tensor_name, nothing)
    isnothing(p) && return false
    p.order == order
end

function check_perturbation_order(tensor_name::AbstractString, order::Int)::Bool
    check_perturbation_order(Symbol(tensor_name), order)
end

"""
    PerturbationOrder(tensor_name) → Int

Return the perturbation order of a registered perturbation tensor.
Throws an error if `tensor_name` is not a registered perturbation.

# Examples

```julia
PerturbationOrder(:Pertg1)   # → 1
PerturbationOrder(:Pertg2)   # → 2
```
"""
function PerturbationOrder(tensor_name::Symbol)::Int
    p = get(_perturbations, tensor_name, nothing)
    isnothing(p) &&
        error("PerturbationOrder: $tensor_name is not a registered perturbation")
    p.order
end

function PerturbationOrder(tensor_name::AbstractString)::Int
    PerturbationOrder(Symbol(tensor_name))
end

"""
    PerturbationAtOrder(background, order) → Symbol

Return the name of the perturbation tensor registered for `background` at
perturbation `order`.  Throws an error if no such perturbation is registered.

# Examples

```julia
PerturbationAtOrder(:g, 1)   # → :Pertg1
PerturbationAtOrder(:g, 2)   # → :Pertg2
```
"""
function PerturbationAtOrder(background::Symbol, order::Int)::Symbol
    for (pname, p) in _perturbations
        if p.background == background && p.order == order
            return pname
        end
    end
    error("PerturbationAtOrder: no order-$order perturbation registered for $background")
end

function PerturbationAtOrder(background::AbstractString, order::Int)::Symbol
    PerturbationAtOrder(Symbol(background), order)
end

# ============================================================
# perturb() — Leibniz expansion of perturbations
# ============================================================

"""
    perturb(tensor_name::Symbol, order::Int) → String

Look up the registered perturbation tensor for `tensor_name` at the given
perturbation order.  Returns the perturbation tensor name as a String, or
throws an error if no such perturbation is registered.
"""
function perturb(tensor_name::Symbol, order::Int)::String
    for (pname, p) in _perturbations
        if p.background == tensor_name && p.order == order
            return String(pname)
        end
    end
    error("perturb: no order-$order perturbation registered for $tensor_name")
end

"""
    perturb(expr::AbstractString, order::Int) → String

Apply the Leibniz rule to expand perturbations of a tensor expression at
the given order.

## Supported forms

  - Single tensor name  — looks up registered perturbation for that background.
    Index decorations (e.g. `Cng[-a,-b]`) are stripped before lookup.
  - Sum  `A + B`        — `perturb(A,n) + perturb(B,n)`.
  - Difference `A - B`  — `perturb(A,n) - perturb(B,n)`.
  - Product `A B` or `A * B` — general Leibniz (multinomial) rule:
    ``δⁿ(A₁⋯Aₖ) = Σ C(n;i₁,…,iₖ) δⁱ¹(A₁)⋯δⁱᵏ(Aₖ)``
    where the sum runs over all non-negative integer compositions
    ``i₁+⋯+iₖ = n`` and ``C`` is the multinomial coefficient.
  - Numeric coefficient `c A` — coefficient passes through unchanged.
  - Factor with no registered perturbation — treated as background (variation = 0).
"""
function perturb(expr::AbstractString, order::Int)::String
    s = strip(expr)

    # ── 1. Sum / difference (split on " + " and " - ") ──────────────────────
    plus_parts = split(s, " + ")
    if length(plus_parts) > 1
        perturbed = [perturb(strip(p), order) for p in plus_parts]
        return join(perturbed, " + ")
    end

    minus_parts = split(s, " - ")
    if length(minus_parts) > 1
        result_parts = String[]
        push!(result_parts, perturb(strip(minus_parts[1]), order))
        for p in minus_parts[2:end]
            push!(result_parts, perturb(strip(p), order))
        end
        return join(result_parts, " - ")
    end

    # ── 2. Product (space-separated or "*"-separated factors) ────────────────
    s_norm = replace(s, " * " => " ")
    factors = split(s_norm)

    # Separate leading numeric coefficient (first factor only)
    coeff = ""
    tensor_factors = String[]
    for (i, f) in enumerate(factors)
        fs = String(f)
        if i == 1 && (tryparse(Float64, fs) !== nothing || tryparse(Int, fs) !== nothing)
            coeff = fs
        else
            push!(tensor_factors, fs)
        end
    end

    if isempty(tensor_factors)
        return "0"   # pure numeric — no variation
    end

    if length(tensor_factors) == 1
        # Strip index decorations before registry lookup (e.g. "Cng[-a,-b]" → "Cng")
        raw = tensor_factors[1]
        bare = replace(raw, r"\[.*\]$" => "")
        tname = Symbol(bare)
        # If the factor is itself a registered perturbation, return it at its own
        # order and 0 at any other order.
        if haskey(_perturbations, tname)
            p = _perturbations[tname]
            result = p.order == order ? String(tname) : "0"
            return coeff == "" ? result : "$coeff $result"
        end
        # Look up registered perturbation by background + order; return "0" if none
        try
            perturbed_name = perturb(tname, order)
            return coeff == "" ? perturbed_name : "$coeff $perturbed_name"
        catch e
            e isa ErrorException || rethrow(e)
            return "0"
        end
    end

    # Multiple tensor factors — general multinomial Leibniz rule
    k = length(tensor_factors)
    comps = _compositions(order, k)

    # Parse numeric coefficient once (already validated as parseable above)
    coeff_num = if coeff == ""
        1
    else
        c = tryparse(Int, coeff)
        c !== nothing ? c : parse(Float64, coeff)
    end

    terms = String[]
    for comp in comps
        mc = _multinomial(order, comp)
        valid = true
        perturbed_factors = String[]
        for (idx, ord) in enumerate(comp)
            if ord == 0
                push!(perturbed_factors, tensor_factors[idx])
            else
                try
                    pi = perturb(tensor_factors[idx], ord)
                    if pi == "0"
                        valid = false
                        break
                    end
                    push!(perturbed_factors, pi)
                catch e
                    e isa ErrorException || rethrow(e)
                    valid = false
                    break
                end
            end
        end
        valid || continue

        total = coeff_num * mc
        term_expr = join(perturbed_factors, " ")
        if total == 1
            push!(terms, term_expr)
        elseif total == floor(total)
            push!(terms, "$(Int(total)) $term_expr")
        else
            push!(terms, "$total $term_expr")
        end
    end
    isempty(terms) ? "0" : join(terms, " + ")
end

"""
Generate all compositions of `n` into `k` non-negative integer parts.

Returns compositions in descending order of the first element, so that
for order=1 the term with the first factor perturbed comes first (matching
the natural Leibniz convention).
"""
function _compositions(n::Int, k::Int)::Vector{Vector{Int}}
    result = Vector{Vector{Int}}()
    if k == 1
        push!(result, [n])
        return result
    end
    for first in n:-1:0
        for rest in _compositions(n - first, k - 1)
            push!(result, vcat([first], rest))
        end
    end
    return result
end

"""
Multinomial coefficient: ``n! / (k₁! k₂! ⋯ kₘ!)``.
"""
function _multinomial(n::Int, parts::Vector{Int})::Int
    return factorial(n) ÷ prod(factorial(ki) for ki in parts)
end

"""
    Simplify(expression::AbstractString) → String

Algebraic simplification of a tensor expression.

Iterates `Contract` followed by `ToCanonical` until the expression stops
changing (convergence), providing:

  - Metric contraction (index raising/lowering, self-trace → dimension)
  - Weyl-tracelessness and Einstein-trace physics rules
  - Index canonicalization and sign normalization
  - Like-term collection (sum simplification)
  - Bianchi identity reduction
  - Einstein tensor expansion

For example, `g^{ab}g_{ab}` is reduced to `n` (the manifold dimension) in
a single pass without requiring a prior `Contract` call.
"""
function Simplify(expression::AbstractString)::String
    current = strip(expression)
    max_iters = 20
    for _ in 1:max_iters
        contracted = Contract(current)
        canonical = ToCanonical(contracted)
        canonical == current && return canonical  # full pass produced no change → converged
        current = canonical
    end
    current
end

# ============================================================
# PerturbCurvature — first-order curvature perturbation formulas
# ============================================================

"""
    perturb_curvature(covd_name, metric_pert_name; order=1) → Dict{String,String}

Return the first-order perturbation formulas for the Riemann tensor, Ricci tensor,
Ricci scalar, and Christoffel symbol perturbation for the metric associated with
`covd_name`, using `metric_pert_name` as the first-order metric perturbation h_{ab}.

The formulas are returned in the system's CovD string notation using the manifold's
first four abstract index labels.  Index positions:
a = idxs[1], b = idxs[2], c = idxs[3], d = idxs[4]

## Standard GR perturbation theory (xPert conventions)

First-order Christoffel perturbation:
δΓ^a_{bc} = (1/2) g^{ad} (∇_b h_{cd} + ∇_c h_{bd} - ∇_d h_{bc})

First-order Riemann perturbation (fully covariant):
δR_{abcd} = ∇_c δΓ_{abd} - ∇_d δΓ_{abc}
(with all indices lowered using the background metric)

First-order Ricci perturbation:
δR_{ab} = ∇_c δΓ^c_{ab} - ∇_b δΓ^c_{ac}
= (1/2)(∇_c ∇_a h^c_b + ∇_c ∇_b h^c_a - □h_{ab} - ∇_a ∇_b h)

First-order Ricci scalar perturbation:
δR = g^{ab} δR_{ab} - R_{ab} h^{ab}

The returned dict has keys:
"Christoffel1" — δΓ expressed in CovD notation (mixed index)
"Riemann1"     — δR_{abcd} in CovD notation
"Ricci1"       — δR_{ab} in CovD notation
"RicciScalar1" — δR string formula (contracted Ricci)

All expressions use abstract index labels from the metric's manifold.
"""
function perturb_curvature(
    covd_name::Symbol, metric_pert_name::Symbol; order::Int=1
)::Dict{String,String}
    order == 1 || error("perturb_curvature: only order=1 is implemented")

    # Look up the metric
    metric_obj = get(_metrics, covd_name, nothing)
    isnothing(metric_obj) &&
        error("perturb_curvature: no metric registered for covd $covd_name")

    # Look up the perturbation tensor — it must be registered
    haskey(_tensors, metric_pert_name) ||
        error("perturb_curvature: perturbation tensor $metric_pert_name not registered")

    # Fetch manifold and its index labels
    manifold_sym = metric_obj.manifold
    manifold_obj = get(_manifolds, manifold_sym, nothing)
    isnothing(manifold_obj) && error("perturb_curvature: manifold $manifold_sym not found")

    idxs = manifold_obj.index_labels
    length(idxs) >= 4 ||
        error("perturb_curvature: manifold needs ≥ 4 index labels, got $(length(idxs))")

    # Short aliases for the abstract index labels (as strings).
    # Free indices: a(1), b(2), c(3), d(4).
    # Contraction dummy e: use 5th index if available, otherwise use the 4th
    # (since d is only free in Riemann but not in Ricci/Christoffel, reusing it
    # as a contraction dummy in those sub-expressions is valid).
    a = string(idxs[1])
    b = string(idxs[2])
    c = string(idxs[3])
    d = string(idxs[4])
    # Dummy index for index contractions (e.g. in Christoffel, Ricci trace slot)
    # Must not collide with free indices; use 5th label if available, else 4th.
    e = length(idxs) >= 5 ? string(idxs[5]) : d

    g = string(metric_obj.name)   # e.g. "Cng"
    h = string(metric_pert_name)  # e.g. "Pertg1"
    cd = string(covd_name)         # e.g. "Cnd"
    ricci = "Ricci" * cd         # e.g. "RicciCnd"
    rscalar = "RicciScalar" * cd

    # ── Christoffel perturbation δΓ^a_{bc} ────────────────────────────────
    # δΓ^a_{bc} = (1/2) g^{ae}(∇_b h_{ce} + ∇_c h_{be} - ∇_e h_{bc})
    # Free indices: a (up), b (down), c (down); dummy: e.
    christoffel1 = string(
        "(1/2)*",
        g,
        "[",
        a,
        ",",
        e,
        "](",
        cd,
        "[-",
        b,
        "][",
        h,
        "[-",
        c,
        ",-",
        e,
        "]]",
        " + ",
        cd,
        "[-",
        c,
        "][",
        h,
        "[-",
        b,
        ",-",
        e,
        "]]",
        " - ",
        cd,
        "[-",
        e,
        "][",
        h,
        "[-",
        b,
        ",-",
        c,
        "]]",
        ")",
    )

    # ── Riemann perturbation δR_{abcd} ────────────────────────────────────
    # Palatini (linearized Riemann) formula — second-derivative form:
    #   δR_{abcd} = (1/2)(∇_c ∇_a h_{bd} - ∇_c ∇_b h_{ad}
    #                     - ∇_d ∇_a h_{bc} + ∇_d ∇_b h_{ac})
    # Free indices: a,b (first pair), c,d (second pair) — all covariant.
    # No dummy needed here.
    riemann1 = string(
        "(1/2)(",
        cd,
        "[-",
        c,
        "][",
        cd,
        "[-",
        a,
        "][",
        h,
        "[-",
        b,
        ",-",
        d,
        "]]]",
        " - ",
        cd,
        "[-",
        c,
        "][",
        cd,
        "[-",
        b,
        "][",
        h,
        "[-",
        a,
        ",-",
        d,
        "]]]",
        " - ",
        cd,
        "[-",
        d,
        "][",
        cd,
        "[-",
        a,
        "][",
        h,
        "[-",
        b,
        ",-",
        c,
        "]]]",
        " + ",
        cd,
        "[-",
        d,
        "][",
        cd,
        "[-",
        b,
        "][",
        h,
        "[-",
        a,
        ",-",
        c,
        "]]]",
        ")",
    )

    # ── Ricci perturbation δR_{ab} ────────────────────────────────────────
    # de Donder / Lichnerowicz form (valid on any background):
    #   δR_{ab} = (1/2)(∇^c ∇_a h_{bc} + ∇^c ∇_b h_{ac} - □h_{ab} - ∇_a ∇_b h)
    # where h = g^{cd} h_{cd} and □ = g^{cd}∇_c∇_d.
    # Written with explicit metric raising:
    #   = (1/2)(g[c,e] cd[-e][cd[-a][h[-b,-c]]]
    #         + g[c,e] cd[-e][cd[-b][h[-a,-c]]]
    #         - g[c,e] cd[-c][cd[-e][h[-a,-b]]]
    #         - cd[-a][cd[-b][g[c,e] h[-c,-e]]])
    # Free indices: a,b. Dummies: c,e (c is free-slot dummy, e is raise dummy).
    # For the box term and trace term we need two summation dummies.
    # Use c and e where e = 5th index (or d if only 4 available).
    ricci1 = string(
        "(1/2)(",
        g,
        "[",
        c,
        ",",
        e,
        "] ",
        cd,
        "[-",
        e,
        "][",
        cd,
        "[-",
        a,
        "][",
        h,
        "[-",
        b,
        ",-",
        c,
        "]]]",
        " + ",
        g,
        "[",
        c,
        ",",
        e,
        "] ",
        cd,
        "[-",
        e,
        "][",
        cd,
        "[-",
        b,
        "][",
        h,
        "[-",
        a,
        ",-",
        c,
        "]]]",
        " - ",
        g,
        "[",
        c,
        ",",
        e,
        "] ",
        cd,
        "[-",
        c,
        "][",
        cd,
        "[-",
        e,
        "][",
        h,
        "[-",
        a,
        ",-",
        b,
        "]]]",
        " - ",
        cd,
        "[-",
        a,
        "][",
        cd,
        "[-",
        b,
        "][",
        g,
        "[",
        c,
        ",",
        e,
        "] ",
        h,
        "[-",
        c,
        ",-",
        e,
        "]",
        "]]",
        ")",
    )

    # ── Ricci scalar perturbation δR ──────────────────────────────────────
    # δR = g^{ab} δR_{ab} - R^{ab} h_{ab}
    # g[a,b] * ricci1 gives g^{ab}δR_{ab} (ricci1 already carries the 1/2 factor).
    # Background Ricci correction: R_{ac}g^{ab}h_b^c = R^{ab}h_{ab} (symmetric R,h).
    # Free indices: none (scalar). Dummies: a,b,c.
    ricci_scalar1 = string(
        g,
        "[",
        a,
        ",",
        b,
        "] ",
        ricci1,
        " - ",
        ricci,
        "[-",
        a,
        ",-",
        c,
        "] ",
        g,
        "[",
        a,
        ",",
        b,
        "] ",
        h,
        "[-",
        b,
        ",",
        c,
        "]",
    )

    Dict{String,String}(
        "Christoffel1" => christoffel1,
        "Riemann1" => riemann1,
        "Ricci1" => ricci1,
        "RicciScalar1" => ricci_scalar1,
    )
end

function perturb_curvature(
    covd_name::AbstractString, metric_pert_name::AbstractString; order::Int=1
)::Dict{String,String}
    perturb_curvature(Symbol(covd_name), Symbol(metric_pert_name); order=order)
end

export perturb_curvature

# ============================================================
# IBP — Integration By Parts
# ============================================================

"""
Simplify `expr` only if it contains no CovD-applied factors (patterns like
`CovD[-a][inner]`).  `_parse_monomial` truncates such factors at the first
bracket group, so `Simplify` would corrupt them.  A quick regex scan over
registered CovD names is sufficient; full factor parsing is not needed.
"""
function _safe_simplify(expr::AbstractString)::String
    for (covd_sym, _) in _metrics
        occursin(Regex(string(covd_sym) * raw"\[-\w+\]\["), expr) && return String(expr)
    end
    Simplify(expr)
end

"""
Split a multiplicative term body into individual factor strings.
Each factor is `Name[...]` or `CovD[-a][inner_expr]` (CovD has two bracket groups).
"""
function _split_factor_strings(term_body::AbstractString)::Vector{String}
    body = strip(term_body)
    factors = String[]
    i = firstindex(body)
    n = lastindex(body)
    while i <= n
        # skip whitespace between factors
        while i <= n && isspace(body[i])
            i = nextind(body, i)
        end
        i > n && break
        # Read identifier (name token)
        j = i
        while j <= n && (isletter(body[j]) || isdigit(body[j]) || body[j] == '_')
            j = nextind(body, j)
        end
        if j == i
            # Not an identifier character — skip
            i = nextind(body, i)
            continue
        end
        name_end = j  # exclusive end of name
        # Now consume all consecutive bracket groups
        groups = String[]
        k = name_end
        while k <= n
            # skip whitespace
            while k <= n && isspace(body[k])
                k = nextind(body, k)
            end
            k > n && break
            body[k] != '[' && break
            # consume matching bracket group
            depth = 0
            start_k = k
            while k <= n
                c = body[k]
                if c == '['
                    depth += 1
                elseif c == ']'
                    depth -= 1
                    if depth == 0
                        k = nextind(body, k)
                        break
                    end
                end
                k = nextind(body, k)
            end
            push!(groups, body[start_k:prevind(body, k)])
        end
        factor_str = body[i:prevind(body, name_end)] * join(groups)
        push!(factors, factor_str)
        i = k
    end
    factors
end

"""
Parse `covd_name[-der_idx][inner_expr]` from a factor string.
Returns a named tuple `(der_idx, inner)` or `nothing`.
"""
function _parse_covd_application(factor::AbstractString, covd::AbstractString)
    prefix = covd * "["
    startswith(factor, prefix) || return nothing
    fstr = factor
    # Find the end of the first bracket group (der_idx group)
    depth = 0
    i = firstindex(fstr) + length(prefix) - 1  # points to '['
    j = i
    while j <= lastindex(fstr)
        c = fstr[j]
        if c == '['
            depth += 1
        elseif c == ']'
            depth -= 1
            if depth == 0
                j = nextind(fstr, j)
                break
            end
        end
        j = nextind(fstr, j)
    end
    # fstr[i:prevind(fstr,j)] is the der_idx bracket group e.g. "[-ia]"
    der_bracket = fstr[i:prevind(fstr, j)]  # "[-ia]"
    # Strip outer brackets to get "-ia"
    der_idx_raw = strip(
        der_bracket[nextind(der_bracket, firstindex(der_bracket)):prevind(
            der_bracket, lastindex(der_bracket)
        )],
    )
    # Now consume inner bracket group
    k = j
    while k <= lastindex(fstr) && isspace(fstr[k])
        k = nextind(fstr, k)
    end
    k > lastindex(fstr) && return nothing
    fstr[k] != '[' && return nothing
    depth2 = 0
    start_inner = k
    while k <= lastindex(fstr)
        c = fstr[k]
        if c == '['
            depth2 += 1
        elseif c == ']'
            depth2 -= 1
            if depth2 == 0
                k = nextind(fstr, k)
                break
            end
        end
        k = nextind(fstr, k)
    end
    # Must have consumed entire string
    k <= lastindex(fstr) && return nothing
    inner_bracket = fstr[start_inner:prevind(fstr, k)]  # "[expr]"
    # Strip outer brackets
    inner = strip(
        inner_bracket[nextind(inner_bracket, firstindex(inner_bracket)):prevind(
            inner_bracket, lastindex(inner_bracket)
        )],
    )
    # Strip the leading '-' from der_idx to get the bare index label
    bare_idx = if startswith(der_idx_raw, "-")
        der_idx_raw[nextind(der_idx_raw, firstindex(der_idx_raw)):end]
    else
        der_idx_raw
    end
    return (der_idx=der_idx_raw, bare_idx=bare_idx, inner=String(inner))
end

"""
Check if bare index `idx` (e.g. "a") appears as a contracted (dummy) index inside `expr`.
"""
function _index_appears_in(expr::AbstractString, idx::AbstractString)::Bool
    any(
        p -> occursin(p, expr),
        ["[" * idx * ",", "[" * idx * "]", "," * idx * ",", "," * idx * "]"],
    )
end

"""
Extract leading coefficient from term body string.
Returns `(coeff::Rational{Int}, remaining_str)`.
Matches `(N/D) rest` or `N rest` (integer followed by whitespace). Otherwise coeff=1//1.
"""
function _extract_leading_coeff(body::AbstractString)
    s = String(strip(body))
    # Try rational: "(N/D) rest"
    m = match(r"^\((-?\d+)/(\d+)\)\s*(.*)"s, s)
    if m !== nothing
        num = parse(Int, something(m.captures[1]))
        den = parse(Int, something(m.captures[2]))
        return (num // den, String(strip(something(m.captures[3]))))
    end
    # Try integer followed by space: "N rest"
    m2 = match(r"^(-?\d+)\s+(.*)"s, s)
    if m2 !== nothing
        num = parse(Int, something(m2.captures[1]))
        return (num // 1, String(strip(something(m2.captures[2]))))
    end
    return (1 // 1, s)
end

"""
Format rational coefficient for positive printing.
"""
function _fmt_pos_coeff(c::Rational{Int})::String
    c == 1 // 1 && return ""
    denominator(c) == 1 && return "$(numerator(c)) "
    return "($(numerator(c))/$(denominator(c))) "
end

"""
Format (coeff, body) as a signed term string suitable for joining.
"""
function _term_string(c::Rational{Int}, body::AbstractString)::String
    body_s = String(body)::String
    if c == 1 // 1
        return body_s
    elseif c == -1 // 1
        return "-" * body_s
    elseif c > 0
        return _fmt_pos_coeff(c) * body_s
    else
        return "-" * _fmt_pos_coeff(-c) * body_s
    end
end

"""
Split expression into signed string terms. Returns `Vector{Tuple{Int, String}}` = [(sign, body), ...].
Splits on top-level `+` and `-`, tracking bracket depth.
"""
function _split_string_terms(expr::AbstractString)::Vector{Tuple{Int,String}}
    s = String(strip(expr))
    isempty(s) && return [(1, "0")]
    terms = Tuple{Int,String}[]
    depth = 0
    current = IOBuffer()
    current_sign = 1
    i = firstindex(s)
    n = lastindex(s)
    # Handle leading sign
    if i <= n && s[i] == '-'
        current_sign = -1
        i = nextind(s, i)
    elseif i <= n && s[i] == '+'
        current_sign = 1
        i = nextind(s, i)
    end
    while i <= n
        c = s[i]
        if c == '[' || c == '('
            depth += 1
            write(current, c)
        elseif c == ']' || c == ')'
            depth -= 1
            write(current, c)
        elseif depth == 0 && (c == '+' || c == '-')
            chunk = strip(String(take!(current)))
            if !isempty(chunk)
                push!(terms, (current_sign, chunk))
            end
            current_sign = c == '-' ? -1 : 1
            current = IOBuffer()
        else
            write(current, c)
        end
        i = nextind(s, i)
    end
    chunk = strip(String(take!(current)))
    if !isempty(chunk)
        push!(terms, (current_sign, chunk))
    end
    isempty(terms) && return [(1, "0")]
    terms
end

"""
Apply one IBP step to factors of a single term.
Returns `(new_coeff, new_body)` or `nothing` (no CovD found).
Returns `(0//1, "0")` for a pure total divergence.
"""
function _ibp_term_factors(
    factors::Vector{String}, coeff::Rational{Int}, covd::AbstractString
)
    # Find the first CovD factor
    covd_idx = findfirst(f -> startswith(f, covd * "["), factors)
    covd_idx === nothing && return nothing
    covd_factor = factors[covd_idx]
    parsed = _parse_covd_application(covd_factor, covd)
    parsed === nothing && return nothing
    der_idx = parsed.der_idx    # e.g. "-ia"
    bare_idx = parsed.bare_idx  # e.g. "ia"
    inner = parsed.inner        # inner expression

    # Remaining factors (all except this CovD)
    other_factors = [factors[k] for k in eachindex(factors) if k != covd_idx]

    if isempty(other_factors)
        # Pure divergence: covd[-a][expr_with_a_contracted]?
        if _index_appears_in(inner, bare_idx)
            return (0 // 1, "0")
        else
            # Not contracted — can't simplify (unusual), return unchanged as nothing
            return nothing
        end
    end

    # IBP: A * ∇_a B → -(∇_a A) * B, picking A = first non-CovD factor
    partner_idx = findfirst(f -> !startswith(f, covd * "["), other_factors)
    if partner_idx === nothing
        # All remaining are CovDs — take the first one
        partner_idx = 1
    end
    partner = other_factors[partner_idx]
    rest_others = [other_factors[k] for k in eachindex(other_factors) if k != partner_idx]

    # New CovD applied to the partner
    new_covd_factor = covd * "[" * der_idx * "][" * partner * "]"
    # New body = new_covd_factor * inner * rest_others
    new_factors_strs = String[]
    push!(new_factors_strs, new_covd_factor)
    push!(new_factors_strs, inner)
    append!(new_factors_strs, rest_others)
    new_body = join(filter(!isempty, new_factors_strs), " ")
    new_coeff = -coeff
    return (new_coeff, new_body)
end

"""
Join a vector of signed term strings into a sum expression.
Each element may start with `"-"` (negative) or not (positive).
Adjacent terms are separated by `" - "` or `" + "` as appropriate.
"""
function _join_term_strings(parts::Vector{String})::String
    isempty(parts) && return "0"
    out = IOBuffer()
    for (k, p) in enumerate(parts)
        if k == 1
            write(out, p)
        elseif startswith(p, "-")
            write(out, " - ", p[nextind(p, firstindex(p)):end])
        else
            write(out, " + ", p)
        end
    end
    String(take!(out))
end

"""
    IBP(expr, covd_name) → String

Integrate `expr` by parts with respect to `covd_name`. For each term:

  - Pure divergence `covd[-a][V[a]]`: dropped (→ 0)
  - Product `A * covd[-a][B]`: → `-(covd[-a][A]) * B` (mod total derivative)
  - Otherwise: unchanged
    Result is passed through Simplify.
"""
function IBP(expr::AbstractString, covd_name::AbstractString)::String
    terms = _split_string_terms(expr)
    result_terms = Tuple{Rational{Int},String}[]
    for (sign, body) in terms
        (coeff0, remaining) = _extract_leading_coeff(body)
        coeff = sign * coeff0
        factors = _split_factor_strings(remaining)
        ibp_result = _ibp_term_factors(factors, coeff, covd_name)
        if ibp_result === nothing
            # No CovD found — keep term unchanged
            push!(result_terms, (coeff, remaining))
        else
            (new_coeff, new_body) = ibp_result
            if new_coeff != 0 // 1
                push!(result_terms, (new_coeff, new_body))
            end
            # new_coeff == 0 means total divergence, drop the term
        end
    end
    isempty(result_terms) && return "0"
    raw = _join_term_strings([_term_string(c, b) for (c, b) in result_terms])
    _safe_simplify(raw)
end

function IBP(expr::AbstractString, covd::Symbol)::String
    IBP(expr, String(covd))
end

"""
    TotalDerivativeQ(expr, covd_name) → Bool

Return `true` iff `expr` is a total divergence (IBP drops it entirely).
"""
function TotalDerivativeQ(expr::AbstractString, covd_name::AbstractString)::Bool
    IBP(expr, covd_name) == "0"
end

function TotalDerivativeQ(expr::AbstractString, covd::Symbol)::Bool
    TotalDerivativeQ(expr, String(covd))
end

# ============================================================
# VarD — Variational (Euler-Lagrange) Derivative
# ============================================================

"""
Expand `covd[der_idx][f1 f2 ... fn]` via Leibniz product rule.
Returns a Vector of term strings, each with CovD applied to one factor.
"""
function _leibniz_covd(
    covd::AbstractString, der_idx::AbstractString, factors::Vector{String}
)::Vector{String}
    result = String[]
    for (i, f) in enumerate(factors)
        rest = [factors[k] for k in eachindex(factors) if k != i]
        new_covd = covd * "[" * der_idx * "][" * f * "]"
        parts = String[new_covd]
        append!(parts, rest)
        push!(result, join(filter(!isempty, parts), " "))
    end
    result
end

"""
Compute all EL contributions from a single term for variational derivative w.r.t. `field`.
Returns `Vector{Tuple{Rational{Int}, String}}` of `(coeff, body)` contributions.
"""
function _vard_term_contributions(
    factors::Vector{String},
    coeff::Rational{Int},
    field::AbstractString,
    covd::AbstractString,
)::Vector{Tuple{Rational{Int},String}}
    contributions = Tuple{Rational{Int},String}[]
    for (i, factor) in enumerate(factors)
        rest = [factors[k] for k in eachindex(factors) if k != i]
        rest_str = join(filter(!isempty, rest), " ")

        # Case 1: Direct field occurrence — factor starts with "field["
        if startswith(factor, field * "[")
            # Contribution: (+coeff, rest_str) or (+coeff, "1") if no rest
            body = isempty(rest_str) ? "1" : rest_str
            push!(contributions, (coeff, body))
            continue
        end

        # Case 2: covd[-a][field[...]] — first-order derivative
        parsed1 = _parse_covd_application(factor, covd)
        if parsed1 !== nothing && startswith(parsed1.inner, field * "[")
            # IBP: contribution is (-coeff, leibniz expansion applied to rest)
            # The EL term is -∇_a (rest) when field is ∇_a φ
            # i.e. we integrate by parts: -(∇_a rest)  → for each factor in rest
            der_bracket = covd * "[" * parsed1.der_idx * "]"
            if isempty(rest_str)
                # No other factors: contribution is trivially 0 (total div) — skip
                continue
            end
            rest_factors = _split_factor_strings(rest_str)
            leibniz_terms = _leibniz_covd(covd, parsed1.der_idx, rest_factors)
            for lt in leibniz_terms
                push!(contributions, (-coeff, lt))
            end
            continue
        end

        # Case 3: covd[-a][covd[-b][field[...]]] — second-order derivative
        if parsed1 !== nothing
            inner1 = parsed1.inner
            parsed2 = _parse_covd_application(inner1, covd)
            if parsed2 !== nothing && startswith(parsed2.inner, field * "[")
                # Two IBP steps → sign is +coeff
                # Apply outer Leibniz on rest, then wrap inner derivative
                der_outer = parsed1.der_idx
                der_inner = parsed2.der_idx
                inner_covd = covd * "[" * der_inner * "]"
                if isempty(rest_str)
                    # Only factor: ∇_a ∇_b φ — contribution is ∇_a ∇_b(1) = 0
                    continue
                end
                rest_factors = _split_factor_strings(rest_str)
                # Leibniz on rest with the outer derivative
                leibniz_terms = _leibniz_covd(covd, der_outer, rest_factors)
                for lt in leibniz_terms
                    # Wrap each leibniz term in the inner derivative
                    inner_lt_covd = covd * "[" * der_inner * "][" * lt * "]"
                    push!(contributions, (coeff, inner_lt_covd))
                end
                continue
            end
        end
    end
    contributions
end

"""
    VarD(expr, field_name, covd_name) → String

Euler-Lagrange derivative of Lagrangian `expr` w.r.t. field `field_name`.
Uses IBP to move derivatives off the field variation.
Result is simplified.
"""
function VarD(
    expr::AbstractString, field_name::AbstractString, covd_name::AbstractString
)::String
    terms = _split_string_terms(expr)
    all_contributions = Tuple{Rational{Int},String}[]
    for (sign, body) in terms
        (coeff0, remaining) = _extract_leading_coeff(body)
        coeff = sign * coeff0
        factors = _split_factor_strings(remaining)
        contribs = _vard_term_contributions(factors, coeff, field_name, covd_name)
        append!(all_contributions, contribs)
    end
    isempty(all_contributions) && return "0"
    raw = _join_term_strings([_term_string(c, b) for (c, b) in all_contributions])
    _safe_simplify(raw)
end

function VarD(expr::AbstractString, field::Symbol, covd::Symbol)::String
    VarD(expr, String(field), String(covd))
end

function VarD(expr::AbstractString, field::AbstractString, covd::Symbol)::String
    VarD(expr, field, String(covd))
end

function VarD(expr::AbstractString, field::Symbol, covd::AbstractString)::String
    VarD(expr, String(field), covd)
end

# ============================================================
# xCoba: Coordinate transformations (basis changes)
# ============================================================

"""
    set_basis_change!(from_basis, to_basis, matrix) → BasisChangeObj

Register a coordinate transformation between two bases.
The matrix transforms components from `from_basis` to `to_basis`.
Both the forward (from→to) and inverse (to→from) directions are stored.

Validates:

  - Both bases exist (via BasisQ)
  - Both bases belong to the same vector bundle
  - Matrix is square with size matching the basis dimension
  - Matrix is invertible (non-singular)
"""
function set_basis_change!(
    from_basis::Symbol, to_basis::Symbol, matrix::AbstractMatrix
)::BasisChangeObj
    BasisQ(from_basis) || error("set_basis_change!: basis $from_basis not defined")
    BasisQ(to_basis) || error("set_basis_change!: basis $to_basis not defined")

    vb_from = VBundleOfBasis(from_basis)
    vb_to = VBundleOfBasis(to_basis)
    vb_from == vb_to || error(
        "set_basis_change!: bases $from_basis ($vb_from) and $to_basis ($vb_to) belong to different vector bundles",
    )

    dim = length(CNumbersOf(from_basis))
    n, m = size(matrix)
    (n == m == dim) ||
        error("set_basis_change!: matrix size ($n×$m) does not match basis dimension $dim")

    # Convert to Matrix{Any} for storage
    mat = Matrix{Any}(matrix)
    jac = det(Float64.(matrix))
    abs(jac) < 1e-15 && error("set_basis_change!: matrix is singular (det ≈ 0)")
    inv_mat = Matrix{Any}(inv(Float64.(matrix)))

    bc = BasisChangeObj(from_basis, to_basis, mat, inv_mat, jac)
    _basis_changes[(from_basis, to_basis)] = bc

    # Store inverse direction
    bc_inv = BasisChangeObj(to_basis, from_basis, inv_mat, mat, 1.0 / jac)
    _basis_changes[(to_basis, from_basis)] = bc_inv

    bc
end

function set_basis_change!(
    from_basis::AbstractString, to_basis::AbstractString, matrix::AbstractMatrix
)::BasisChangeObj
    set_basis_change!(Symbol(from_basis), Symbol(to_basis), matrix)
end

"""
    BasisChangeQ(from, to) → Bool

Check if a basis change from `from` to `to` is registered.
"""
BasisChangeQ(from::Symbol, to::Symbol) = haskey(_basis_changes, (from, to))
function BasisChangeQ(from::AbstractString, to::AbstractString)
    BasisChangeQ(Symbol(from), Symbol(to))
end

"""
    BasisChangeMatrix(from, to) → Matrix

Return the transformation matrix from `from` basis to `to` basis.
"""
function BasisChangeMatrix(from::Symbol, to::Symbol)::Matrix{Any}
    haskey(_basis_changes, (from, to)) ||
        error("BasisChangeMatrix: no basis change registered from $from to $to")
    _basis_changes[(from, to)].matrix
end
function BasisChangeMatrix(from::AbstractString, to::AbstractString)
    BasisChangeMatrix(Symbol(from), Symbol(to))
end

"""
    InverseBasisChangeMatrix(from, to) → Matrix

Return the inverse transformation matrix (i.e. the matrix that goes from `to` back to `from`).
"""
function InverseBasisChangeMatrix(from::Symbol, to::Symbol)::Matrix{Any}
    haskey(_basis_changes, (from, to)) ||
        error("InverseBasisChangeMatrix: no basis change registered from $from to $to")
    _basis_changes[(from, to)].inverse
end
function InverseBasisChangeMatrix(from::AbstractString, to::AbstractString)
    InverseBasisChangeMatrix(Symbol(from), Symbol(to))
end

"""
    Jacobian(basis1, basis2) → Any

Return the Jacobian determinant of the transformation from `basis1` to `basis2`.
"""
function Jacobian(basis1::Symbol, basis2::Symbol)
    haskey(_basis_changes, (basis1, basis2)) ||
        error("Jacobian: no basis change registered from $basis1 to $basis2")
    _basis_changes[(basis1, basis2)].jacobian
end
function Jacobian(basis1::AbstractString, basis2::AbstractString)
    Jacobian(Symbol(basis1), Symbol(basis2))
end

"""
    change_basis(array, bases, slot, from_basis, to_basis) → Array

Apply a basis change to a specific slot of a component array.

  - `array`      — the component array (Vector for rank-1, Matrix for rank-2, etc.)
  - `bases`      — vector of basis symbols for each slot (unused, reserved for future)
  - `slot`       — 1-indexed slot to transform
  - `from_basis` — current basis of that slot
  - `to_basis`   — target basis

For rank-1 (vector): result = M * v
For rank-2 (matrix): transforms the specified slot using the transformation matrix.
"""
function change_basis(
    array::AbstractArray,
    bases::Vector{Symbol},
    slot::Int,
    from_basis::Symbol,
    to_basis::Symbol,
)::AbstractArray
    haskey(_basis_changes, (from_basis, to_basis)) ||
        error("change_basis: no basis change registered from $from_basis to $to_basis")
    M = Float64.(_basis_changes[(from_basis, to_basis)].matrix)
    ndims(array) == 0 && return array

    # Contract M along the `slot`-th dimension of the array
    # TensorContraction: result_{...i'...} = M_{i',i} * array_{...i...}
    # with i in position `slot`
    _contract_slot(M, array, slot)
end

function change_basis(
    array::AbstractArray,
    bases::Vector,
    slot::Int,
    from_basis::AbstractString,
    to_basis::AbstractString,
)::AbstractArray
    change_basis(
        array, Symbol[Symbol(b) for b in bases], slot, Symbol(from_basis), Symbol(to_basis)
    )
end

"""
Contract matrix M into array along the given slot dimension.
"""
function _contract_slot(M::AbstractMatrix, A::AbstractVector, slot::Int)
    slot == 1 || error("change_basis: slot $slot out of range for rank-1 array")
    M * A
end

function _contract_slot(M::AbstractMatrix, A::AbstractMatrix, slot::Int)
    if slot == 1
        # Transform first index: result[i',j] = sum_i M[i',i] * A[i,j]
        M * A
    elseif slot == 2
        # Transform second index: result[i,j'] = sum_j A[i,j] * M'[j,j']
        # = (M * A')'
        (M * A')'
    else
        error("change_basis: slot $slot out of range for rank-2 array")
    end
end

function _contract_slot(M::AbstractMatrix, A::AbstractArray, slot::Int)
    nd = ndims(A)
    (1 <= slot <= nd) || error("change_basis: slot $slot out of range for rank-$nd array")
    # General case: permute slot dimension to front, reshape, multiply, reshape back, permute back
    perm = vcat(slot, setdiff(1:nd, slot))
    iperm = invperm(perm)
    sz = size(A)
    Ap = permutedims(A, perm)
    n = sz[slot]
    Ar = reshape(Ap, n, :)
    Br = M * Ar
    Bp = reshape(Br, size(Ap))
    permutedims(Bp, iperm)
end

# ============================================================
# xCoba: Component tensors (CTensor)
# ============================================================

"""
    set_components!(tensor, array, bases; weight=0) → CTensorObj

Store component values for a tensor in the given bases.

Validates:

  - Tensor exists (via TensorQ or MetricQ)
  - Each basis exists (via BasisQ)
  - Array rank matches number of bases
  - Each array dimension matches the basis dimension (length of CNumbersOf)
"""
function set_components!(
    tensor::Symbol, array::AbstractArray, bases::Vector{Symbol}; weight::Int=0
)::CTensorObj
    # Validate tensor exists
    TensorQ(tensor) || error("set_components!: tensor $tensor not defined")

    # Validate each basis exists
    for b in bases
        BasisQ(b) || error("set_components!: basis $b not defined")
    end

    # Validate array rank matches number of bases
    # Special case: rank-0 (scalar) tensor with 0 bases and a 0-dim array
    if isempty(bases)
        ndims(array) == 0 || error(
            "set_components!: expected rank-0 array for 0 bases, got rank-$(ndims(array))",
        )
    else
        ndims(array) == length(bases) || error(
            "set_components!: array rank $(ndims(array)) does not match number of bases $(length(bases))",
        )
    end

    # Validate each array dimension matches the basis dimension
    for (i, b) in enumerate(bases)
        dim = length(CNumbersOf(b))
        if size(array, i) != dim
            error(
                "set_components!: array dimension $i is $(size(array, i)), expected $dim (basis $b)",
            )
        end
    end

    key = (tensor, bases...)
    ct = CTensorObj(tensor, Array(array), collect(bases), weight)
    _ctensors[key] = ct
    ct
end

function set_components!(
    tensor::AbstractString, array::AbstractArray, bases::Vector; weight::Int=0
)::CTensorObj
    set_components!(Symbol(tensor), array, Symbol[Symbol(b) for b in bases]; weight=weight)
end

"""
    get_components(tensor, bases) → CTensorObj

Retrieve stored component values for a tensor in the given bases.
If not directly stored, attempts to transform from a stored basis configuration
using registered basis changes.
"""
function get_components(tensor::Symbol, bases::Vector{Symbol})::CTensorObj
    key = (tensor, bases...)
    haskey(_ctensors, key) && return _ctensors[key]

    # Try to find stored components in a different basis configuration and transform
    for (stored_key, ct) in _ctensors
        stored_key[1] == tensor || continue
        stored_bases = Symbol[stored_key[i] for i in 2:length(stored_key)]
        length(stored_bases) == length(bases) || continue

        # Check if we can transform each slot
        can_transform = true
        for (i, (from_b, to_b)) in enumerate(zip(stored_bases, bases))
            if from_b != to_b && !BasisChangeQ(from_b, to_b)
                can_transform = false
                break
            end
        end
        can_transform || continue

        # Transform slot by slot
        result_array = ct.array
        current_bases = copy(stored_bases)
        for (i, (from_b, to_b)) in enumerate(zip(stored_bases, bases))
            if from_b != to_b
                result_array = change_basis(result_array, current_bases, i, from_b, to_b)
                current_bases[i] = to_b
            end
        end
        return CTensorObj(tensor, Array(result_array), collect(bases), ct.weight)
    end

    error(
        "get_components: no components stored for $tensor in bases $(bases), and no transform path available",
    )
end

function get_components(tensor::AbstractString, bases::Vector)::CTensorObj
    get_components(Symbol(tensor), Symbol[Symbol(b) for b in bases])
end

"""
    ComponentArray(tensor, bases) → Array

Return just the array of component values for a tensor in the given bases.
"""
function ComponentArray(tensor::Symbol, bases::Vector{Symbol})::Array
    get_components(tensor, bases).array
end

function ComponentArray(tensor::AbstractString, bases::Vector)::Array
    ComponentArray(Symbol(tensor), Symbol[Symbol(b) for b in bases])
end

"""
    CTensorQ(tensor, bases...) → Bool

Return true if component values are stored for the given tensor and bases.
"""
function CTensorQ(tensor::Symbol, bases::Symbol...)::Bool
    haskey(_ctensors, (tensor, bases...))
end

function CTensorQ(tensor::AbstractString, bases::AbstractString...)::Bool
    CTensorQ(Symbol(tensor), (Symbol(b) for b in bases)...)
end

"""
    component_value(tensor, indices, bases) → Any

Return a single component value from a stored CTensor.
`indices` are 1-based integer indices into the array.
"""
function component_value(tensor::Symbol, indices::Vector{Int}, bases::Vector{Symbol})::Any
    ct = get_components(tensor, bases)
    arr = ct.array
    for (i, idx) in enumerate(indices)
        if idx < 1 || idx > size(arr, i)
            error(
                "component_value: index $idx out of range [1, $(size(arr, i))] for dimension $i",
            )
        end
    end
    arr[indices...]
end

function component_value(tensor::AbstractString, indices::Vector, bases::Vector)::Any
    component_value(
        Symbol(tensor), Int[Int(i) for i in indices], Symbol[Symbol(b) for b in bases]
    )
end

"""
    ctensor_contract(tensor, bases, slot1, slot2) → CTensorObj

Contract (trace) two indices of a CTensor.
Both slots must be in the same basis. The result has rank reduced by 2.
For rank-2, this is the matrix trace.
"""
function ctensor_contract(
    tensor::Symbol, bases::Vector{Symbol}, slot1::Int, slot2::Int
)::CTensorObj
    ct = get_components(tensor, bases)
    arr = ct.array
    nd = ndims(arr)
    (1 <= slot1 <= nd) || error("ctensor_contract: slot1=$slot1 out of range [1, $nd]")
    (1 <= slot2 <= nd) || error("ctensor_contract: slot2=$slot2 out of range [1, $nd]")
    slot1 != slot2 || error("ctensor_contract: slot1 and slot2 must be different")
    bases[slot1] == bases[slot2] || error(
        "ctensor_contract: slots $slot1 and $slot2 have different bases ($(bases[slot1]) vs $(bases[slot2]))",
    )

    s1, s2 = minmax(slot1, slot2)  # s1 < s2

    if nd == 2
        # Simple matrix trace
        result_val = sum(arr[i, i] for i in 1:size(arr, 1))
        result_array = fill(result_val)  # 0-dim array
        remaining_bases = Symbol[]
    else
        # General contraction: sum over matching indices
        remaining_dims = [i for i in 1:nd if i != s1 && i != s2]
        remaining_sizes = [size(arr, d) for d in remaining_dims]
        remaining_bases = [bases[d] for d in remaining_dims]
        trace_dim = size(arr, s1)  # == size(arr, s2)

        T = eltype(arr) === Any ? Float64 : eltype(arr)
        result_array = zeros(T, remaining_sizes...)
        for idx in CartesianIndices(Tuple(remaining_sizes))
            val = zero(T)
            for k in 1:trace_dim
                # Build full index tuple
                full_idx = Vector{Int}(undef, nd)
                rem_pos = 1
                for d in 1:nd
                    if d == s1
                        full_idx[d] = k
                    elseif d == s2
                        full_idx[d] = k
                    else
                        full_idx[d] = idx[rem_pos]
                        rem_pos += 1
                    end
                end
                val += arr[full_idx...]
            end
            result_array[idx] = val
        end
    end

    CTensorObj(tensor, result_array, remaining_bases, ct.weight)
end

function ctensor_contract(
    tensor::AbstractString, bases::Vector, slot1::Int, slot2::Int
)::CTensorObj
    ctensor_contract(Symbol(tensor), Symbol[Symbol(b) for b in bases], slot1, slot2)
end

# ============================================================
# xCoba: Christoffel symbols from metric components
# ============================================================

"""
    christoffel!(metric, basis; metric_derivs=nothing) → CTensorObj

Compute and store Christoffel symbols (second kind) from metric CTensor components.

The Christoffel symbol is:

    Γ^a_{bc} = (1/2) g^{ad} (∂_b g_{dc} + ∂_c g_{bd} - ∂_d g_{bc})

Arguments:

  - `metric`: the metric tensor symbol (must have stored components in `basis`)
  - `basis`: the coordinate basis (chart) in which to compute
  - `metric_derivs`: optional rank-3 array where `dg[c,a,b] = ∂_c g_{ab}`.
    If omitted, assumes constant metric (all derivatives zero → all Christoffels zero).

Returns the CTensorObj stored under the auto-created Christoffel tensor name.
"""
function christoffel!(
    metric::Symbol, basis::Symbol; metric_derivs::Union{Nothing,AbstractArray}=nothing
)::CTensorObj
    # Find the covariant derivative associated with this metric
    covd = nothing
    for (cd, mobj) in _metrics
        if mobj.name == metric
            covd = cd
            break
        end
    end
    isnothing(covd) && error("christoffel!: no metric named $metric found")

    christoffel_name = Symbol("Christoffel" * string(covd))
    TensorQ(christoffel_name) ||
        error("christoffel!: Christoffel tensor $christoffel_name not registered")

    # Get metric components g_{ab}
    g_ct = get_components(metric, [basis, basis])
    g_arr = g_ct.array
    dim = size(g_arr, 1)

    # Compute inverse metric g^{ab}
    g_inv = inv(convert(Matrix{Float64}, g_arr))

    # Metric derivatives: dg[c, a, b] = ∂_c g_{ab}
    if metric_derivs === nothing
        dg = zeros(Float64, dim, dim, dim)
    else
        dg = metric_derivs
        size(dg) == (dim, dim, dim) ||
            error("christoffel!: metric_derivs must be ($dim,$dim,$dim), got $(size(dg))")
    end

    # Γ^a_{bc} = (1/2) Σ_d g^{ad} (∂_b g_{dc} + ∂_c g_{bd} - ∂_d g_{bc})
    gamma = zeros(Float64, dim, dim, dim)
    for a in 1:dim, b in 1:dim, c in 1:dim
        val = 0.0
        for d in 1:dim
            val += g_inv[a, d] * (dg[b, d, c] + dg[c, b, d] - dg[d, b, c])
        end
        gamma[a, b, c] = 0.5 * val
    end

    set_components!(christoffel_name, gamma, [basis, basis, basis])
end

function christoffel!(
    metric::AbstractString, basis::AbstractString; metric_derivs=nothing
)::CTensorObj
    christoffel!(Symbol(metric), Symbol(basis); metric_derivs=metric_derivs)
end

# ============================================================
# xCoba: ToBasis / FromBasis / TraceBasisDummy
# ============================================================

"""
    _index_label(idx_str) → Symbol

Extract the bare label from an index string (strip leading '-').
"""
function _index_label(idx_str::AbstractString)::Symbol
    s = strip(idx_str)
    startswith(s, "-") ? Symbol(s[2:end]) : Symbol(s)
end

"""
    _contract_array_axes(arr, ax1, ax2) → Array

Contract (trace over) two axes of an N-dimensional array.
"""
function _contract_array_axes(arr::AbstractArray, ax1::Int, ax2::Int)
    nd = ndims(arr)
    s1, s2 = minmax(ax1, ax2)
    dim = size(arr, s1)

    remaining_dims = [i for i in 1:nd if i != s1 && i != s2]

    if isempty(remaining_dims)
        # Scalar result
        total = zero(Float64)
        for k in 1:dim
            total += Float64(arr[ntuple(d -> k, nd)...])
        end
        return fill(total)
    end

    remaining_sizes = [size(arr, d) for d in remaining_dims]
    result = zeros(Float64, remaining_sizes...)

    for idx in CartesianIndices(Tuple(remaining_sizes))
        val = 0.0
        for k in 1:dim
            full_idx = Vector{Int}(undef, nd)
            rem_pos = 1
            for d in 1:nd
                if d == s1 || d == s2
                    full_idx[d] = k
                else
                    full_idx[d] = idx[rem_pos]
                    rem_pos += 1
                end
            end
            val += Float64(arr[full_idx...])
        end
        result[idx] = val
    end
    result
end

"""
    _tobasis_term(term, basis, dim) → (Array, Vector{Symbol})

Evaluate a single parsed term to component form.
Returns (array, free_index_labels).
Uses einsum-style evaluation: for each assignment of free index values,
sums over all dummy index values the product of factor components.
"""
function _tobasis_term(term::TermAST, basis::Symbol, dim::Int)
    factors = term.factors

    if isempty(factors)
        # Pure scalar coefficient
        return (fill(Float64(term.coeff)), Symbol[])
    end

    # Parse index labels per factor and count label occurrences
    factor_labels = Vector{Vector{Symbol}}()
    label_count = Dict{Symbol,Int}()
    for f in factors
        labels = Symbol[]
        for idx_str in f.indices
            lbl = _index_label(idx_str)
            push!(labels, lbl)
            label_count[lbl] = get(label_count, lbl, 0) + 1
        end
        push!(factor_labels, labels)
    end

    # Classify labels as free (appears once) or dummy (appears twice)
    dummy_labels = Symbol[]
    free_labels = Symbol[]
    seen = Set{Symbol}()
    for labels in factor_labels
        for lbl in labels
            if lbl ∉ seen
                if label_count[lbl] == 1
                    push!(free_labels, lbl)
                elseif label_count[lbl] == 2
                    push!(dummy_labels, lbl)
                else
                    error("ToBasis: index $lbl appears $(label_count[lbl]) times")
                end
                push!(seen, lbl)
            end
        end
    end

    # Get component arrays for each factor
    factor_arrays = AbstractArray[]
    for f in factors
        n_slots = length(f.indices)
        if n_slots == 0
            # Scalar tensor — retrieve its value
            ct = get_components(f.tensor_name, Symbol[])
            push!(factor_arrays, ct.array)
        else
            ct = get_components(f.tensor_name, fill(basis, n_slots))
            push!(factor_arrays, ct.array)
        end
    end

    coeff = Float64(term.coeff)
    n_free = length(free_labels)

    # Scalar result (no free indices)
    if n_free == 0
        total = _einsum_eval(
            factor_arrays, factor_labels, dummy_labels, Dict{Symbol,Int}(), dim
        )
        return (fill(coeff * total), free_labels)
    end

    # Tensor result
    result_shape = ntuple(_ -> dim, n_free)
    result = zeros(Float64, result_shape...)

    for free_idx in CartesianIndices(result_shape)
        assignment = Dict{Symbol,Int}()
        for (i, lbl) in enumerate(free_labels)
            assignment[lbl] = free_idx[i]
        end
        val = _einsum_eval(factor_arrays, factor_labels, dummy_labels, assignment, dim)
        result[free_idx] = coeff * val
    end

    (result, free_labels)
end

"""
    _einsum_eval(factor_arrays, factor_labels, dummy_labels, assignment, dim) → Float64

Recursively sum over dummy indices, then evaluate the product of all factors.
"""
function _einsum_eval(
    factor_arrays::Vector{<:AbstractArray},
    factor_labels::Vector{Vector{Symbol}},
    dummy_labels::Vector{Symbol},
    assignment::Dict{Symbol,Int},
    dim::Int,
    dummy_idx::Int=1,
)::Float64
    if dummy_idx > length(dummy_labels)
        # All indices assigned — evaluate the product
        prod_val = 1.0
        for (fi, arr) in enumerate(factor_arrays)
            labels = factor_labels[fi]
            if isempty(labels)
                # Scalar tensor
                prod_val *= Float64(arr[])
            else
                indices = Int[assignment[l] for l in labels]
                prod_val *= Float64(arr[indices...])
            end
        end
        return prod_val
    end

    # Sum over current dummy label
    lbl = dummy_labels[dummy_idx]
    total = 0.0
    for v in 1:dim
        assignment[lbl] = v
        total += _einsum_eval(
            factor_arrays, factor_labels, dummy_labels, assignment, dim, dummy_idx + 1
        )
    end
    total
end

"""
    ToBasis(expr_str, basis) → CTensorObj

Convert an abstract-index tensor expression to component form in the given basis.

Handles single tensors, products, sums, and automatically contracts dummy
(repeated) indices via einsum.

# Examples

```julia
ToBasis("g[-a,-b]", :Polar)           # metric components
ToBasis("g[-a,-b] * v[a]", :Polar)    # contraction g_{ab} v^a
ToBasis("T[-a,-b] + S[-a,-b]", :Polar) # sum of tensors
```
"""
function ToBasis(expr_str::AbstractString, basis::Symbol)::CTensorObj
    BasisQ(basis) || error("ToBasis: basis $basis not defined")
    terms = _parse_expression(expr_str)
    isempty(terms) && error("ToBasis: cannot convert empty expression")

    dim = length(CNumbersOf(basis))

    # Evaluate each term
    term_results = [_tobasis_term(t, basis, dim) for t in terms]

    # All terms must have same number of free indices
    n_free = length(term_results[1][2])
    for (i, (_, free)) in enumerate(term_results)
        length(free) == n_free ||
            error("ToBasis: term $i has $(length(free)) free indices, expected $n_free")
    end

    # Sum all term arrays
    result = term_results[1][1]
    for i in 2:length(term_results)
        result = result .+ term_results[i][1]
    end

    bases = fill(basis, n_free)

    # Derive tensor name: use original name for single-factor single-term
    tname = :_ToBasis
    if length(terms) == 1 && length(terms[1].factors) == 1
        tname = terms[1].factors[1].tensor_name
    end

    CTensorObj(tname, Array(result), collect(bases), 0)
end

function ToBasis(expr_str::AbstractString, basis::AbstractString)::CTensorObj
    ToBasis(expr_str, Symbol(basis))
end

"""
    FromBasis(tensor, bases) → String

Return the abstract-index expression string for a tensor whose components
are stored in the given bases. Verifies components exist, then reconstructs
the symbolic form using the tensor's declared index slots.
"""
function FromBasis(tensor::Symbol, bases::Vector{Symbol})::String
    # Verify components exist (will error if not)
    get_components(tensor, bases)

    # Reconstruct abstract expression from tensor's declared slots
    if haskey(_metrics, tensor)
        m = _metrics[tensor]
        man = _manifolds[m.manifold]
        labels = man.index_labels
        return string(tensor) * "[-" * string(labels[1]) * ",-" * string(labels[2]) * "]"
    end

    haskey(_tensors, tensor) || error("FromBasis: tensor $tensor not found in registry")

    t_obj = _tensors[tensor]
    if isempty(t_obj.slots)
        return string(tensor) * "[]"
    end

    idx_strs = String[]
    for slot in t_obj.slots
        prefix = slot.covariant ? "-" : ""
        push!(idx_strs, prefix * string(slot.label))
    end
    string(tensor) * "[" * join(idx_strs, ",") * "]"
end

function FromBasis(tensor::AbstractString, bases::Vector)::String
    FromBasis(Symbol(tensor), Symbol[Symbol(b) for b in bases])
end

"""
    TraceBasisDummy(tensor, bases) → CTensorObj

Automatically find and contract all pairs of basis indices where one slot is
covariant and the other is contravariant (with the same basis), mirroring
Wolfram's TraceBasisDummy. Returns the contracted CTensorObj.

For a rank-2 mixed tensor like T^a_{b} with both slots in the same basis,
this computes the trace.
"""
function TraceBasisDummy(tensor::Symbol, bases::Vector{Symbol})::CTensorObj
    ct = get_components(tensor, bases)

    # Get slot variance from tensor definition
    slots = if haskey(_tensors, tensor)
        _tensors[tensor].slots
    elseif haskey(_metrics, tensor)
        m = _metrics[tensor]
        man = _manifolds[m.manifold]
        labels = man.index_labels
        [IndexSpec(labels[1], true), IndexSpec(labels[2], true)]
    else
        error("TraceBasisDummy: tensor $tensor not found in registry")
    end

    length(slots) == length(bases) || error(
        "TraceBasisDummy: number of bases ($(length(bases))) ≠ number of slots ($(length(slots)))",
    )

    # Find pairs of same-basis slots with opposite variance
    contracted = Set{Int}()
    pairs = Tuple{Int,Int}[]
    for i in 1:length(bases)
        i in contracted && continue
        for j in (i + 1):length(bases)
            j in contracted && continue
            if bases[i] == bases[j] && slots[i].covariant != slots[j].covariant
                push!(pairs, (i, j))
                push!(contracted, i)
                push!(contracted, j)
                break
            end
        end
    end

    isempty(pairs) && error(
        "TraceBasisDummy: no dummy basis index pairs found (need same basis, opposite variance)",
    )

    # Contract pairs iteratively
    result_array = ct.array
    result_bases = collect(bases)
    offset = 0
    for (orig_i, orig_j) in pairs
        cur_i = orig_i - offset
        cur_j = orig_j - offset
        result_array = _contract_array_axes(result_array, cur_i, cur_j)
        # Remove the two contracted bases entries
        s1, s2 = minmax(cur_i, cur_j)
        deleteat!(result_bases, s2)
        deleteat!(result_bases, s1)
        offset += 2
    end

    CTensorObj(tensor, Array(result_array), result_bases, ct.weight)
end

function TraceBasisDummy(tensor::AbstractString, bases::Vector)::CTensorObj
    TraceBasisDummy(Symbol(tensor), Symbol[Symbol(b) for b in bases])
end

# ============================================================
# xTras: CollectTensors, AllContractions, SymmetryOf, MakeTraceFree
# ============================================================

"""
    CollectTensors(expression) → String

Collect like terms in a tensor expression by canonicalizing each term
and combining terms with identical canonical monomials.
"""
function CollectTensors(expression::AbstractString)::String
    s = strip(expression)
    (s == "0" || isempty(s)) && return "0"
    # ToCanonical already canonicalizes and collects like terms
    ToCanonical(s)
end

"""
    AllContractions(expression, metric_name) → Vector{String}

Find all independent scalar contractions of an expression with a metric.
For a rank-2 tensor T_{ab}, this contracts g^{ab} T_{ab} → scalar.
Returns a vector of simplified scalar expressions (one per contraction pattern).
"""
function AllContractions(expression::AbstractString, metric_name::Symbol)::Vector{String}
    s = strip(expression)
    (s == "0" || isempty(s)) && return ["0"]

    # Find the metric
    metric_obj = nothing
    for (_, m) in _metrics
        if m.name == metric_name
            metric_obj = m
            break
        end
    end
    isnothing(metric_obj) && error("AllContractions: metric $metric_name not found")

    # Parse and canonicalize the expression
    canon = ToCanonical(s)
    canon == "0" && return ["0"]

    terms = _parse_expression(canon)
    isempty(terms) && return ["0"]

    # Collect all free indices (appear exactly once across all factors in first term)
    idx_counts = Dict{String,Int}()
    for f in terms[1].factors
        for idx in f.indices
            label = startswith(idx, "-") ? idx[2:end] : idx
            key = label  # use raw label for counting
            idx_counts[key] = get(idx_counts, key, 0) + 1
        end
    end
    free_labels = [k for (k, v) in idx_counts if v == 1]

    # Need an even number of free indices for full contraction
    length(free_labels) % 2 != 0 && error(
        "AllContractions: expression has odd number of free indices, cannot fully contract",
    )

    isempty(free_labels) && return [Simplify(canon)]

    # Generate all perfect matchings of free indices
    matchings = _perfect_matchings(free_labels)

    results = String[]
    seen = Set{String}()
    for matching in matchings
        # Build the contraction: insert metric factors g^{a,b} for each pair
        metric_factors = join(["$metric_name[$(p[1]),$(p[2])]" for p in matching], " ")
        contracted_expr = "$metric_factors $canon"
        simplified = Simplify(contracted_expr)
        if !(simplified in seen)
            push!(seen, simplified)
            push!(results, simplified)
        end
    end

    isempty(results) && return ["0"]
    results
end

"""
    _perfect_matchings(items) → Vector{Vector{Tuple{String,String}}}

Recursively compute all perfect pair matchings of a list of items.
"""
function _perfect_matchings(items::Vector{String})::Vector{Vector{Tuple{String,String}}}
    length(items) == 0 && return [Tuple{String,String}[]]
    length(items) == 2 && return [[(items[1], items[2])]]

    result = Vector{Tuple{String,String}}[]
    first = items[1]
    rest = items[2:end]
    for i in eachindex(rest)
        partner = rest[i]
        remaining = [rest[j] for j in eachindex(rest) if j != i]
        for sub_matching in _perfect_matchings(remaining)
            push!(result, [(first, partner); sub_matching])
        end
    end
    result
end

"""
    SymmetryOf(expression) → String

Determine the symmetry type of an expression by examining its behavior
under index permutations. Returns "Symmetric", "Antisymmetric", or "NoSymmetry".
For expressions with 0 or 1 free indices, returns "Symmetric".
"""
function SymmetryOf(expression::AbstractString)::String
    s = strip(expression)
    (s == "0" || isempty(s)) && return "Symmetric"

    canon = ToCanonical(s)
    canon == "0" && return "Symmetric"

    terms = _parse_expression(canon)
    isempty(terms) && return "Symmetric"

    # Collect free indices
    idx_counts = Dict{String,Int}()
    idx_variance = Dict{String,String}()  # label → full index string
    for f in terms[1].factors
        for idx in f.indices
            label = startswith(idx, "-") ? idx[2:end] : idx
            idx_counts[label] = get(idx_counts, label, 0) + 1
            if !haskey(idx_variance, label)
                idx_variance[label] = idx
            end
        end
    end
    free_labels = sort([k for (k, v) in idx_counts if v == 1])

    # 0 or 1 free indices: trivially symmetric
    length(free_labels) <= 1 && return "Symmetric"

    # For rank-2: check single transposition
    if length(free_labels) == 2
        a, b = free_labels
        swapped = _swap_indices(canon, a, b)
        swapped_canon = ToCanonical(swapped)
        swapped_canon == canon && return "Symmetric"
        # Check antisymmetric: swapped == -original
        neg_check = ToCanonical("$canon + $swapped_canon")
        neg_check == "0" && return "Antisymmetric"
        return "NoSymmetry"
    end

    # For higher rank: check all transpositions
    is_sym = true
    is_antisym = true
    for i in 1:(length(free_labels) - 1)
        for j in (i + 1):length(free_labels)
            a, b = free_labels[i], free_labels[j]
            swapped = _swap_indices(canon, a, b)
            swapped_canon = ToCanonical(swapped)
            if swapped_canon != canon
                is_sym = false
            end
            sum_check = ToCanonical("$canon + $swapped_canon")
            if sum_check != "0"
                is_antisym = false
            end
            (!is_sym && !is_antisym) && return "NoSymmetry"
        end
    end

    is_sym && return "Symmetric"
    is_antisym && return "Antisymmetric"
    "NoSymmetry"
end

"""
    _swap_indices(expr, label_a, label_b) → String

Swap two index labels in an expression string, handling both covariant
(-label) and contravariant (label) forms.
"""
function _swap_indices(
    expr::AbstractString, label_a::AbstractString, label_b::AbstractString
)::String
    placeholder = "__SWAP_TMP__"
    # Swap using a temporary placeholder to avoid collision
    result = replace(expr, label_a => placeholder)
    result = replace(result, label_b => label_a)
    result = replace(result, placeholder => label_b)
    result
end

"""
    MakeTraceFree(expression, metric_name) → String

Compute the trace-free part of a rank-2 tensor expression with respect
to the given metric. For T_{ab}:

T_{ab}^TF = T_{ab} - (1/dim) g_{ab} g^{cd} T_{cd}

where dim is the manifold dimension.
"""
function MakeTraceFree(expression::AbstractString, metric_name::Symbol)::String
    s = strip(expression)
    (s == "0" || isempty(s)) && return "0"

    # Find the metric
    metric_obj = nothing
    for (_, m) in _metrics
        if m.name == metric_name
            metric_obj = m
            break
        end
    end
    isnothing(metric_obj) && error("MakeTraceFree: metric $metric_name not found")

    canon = ToCanonical(s)
    canon == "0" && return "0"

    terms = _parse_expression(canon)
    isempty(terms) && return "0"

    # Collect free indices from first term
    idx_counts = Dict{String,Int}()
    for f in terms[1].factors
        for idx in f.indices
            label = startswith(idx, "-") ? idx[2:end] : idx
            idx_counts[label] = get(idx_counts, label, 0) + 1
        end
    end
    free_labels = sort([k for (k, v) in idx_counts if v == 1])
    length(free_labels) != 2 && error(
        "MakeTraceFree: expression must have exactly 2 free indices, got $(length(free_labels))",
    )

    # Special case: single metric factor → trace-free part is zero
    if length(terms) == 1 && length(terms[1].factors) == 1
        f = terms[1].factors[1]
        if f.tensor_name == metric_name
            return "0"
        end
    end

    # Get manifold dimension
    manifold = get(_manifolds, metric_obj.manifold, nothing)
    isnothing(manifold) && error("MakeTraceFree: manifold $(metric_obj.manifold) not found")
    dim = manifold.dimension

    # Free index labels (as they appear: with - prefix for covariant)
    a_label, b_label = free_labels

    # Find covariant forms of the free indices from the expression
    free_idx_forms = Dict{String,String}()
    for f in terms[1].factors
        for idx in f.indices
            label = startswith(idx, "-") ? idx[2:end] : idx
            if label in free_labels
                free_idx_forms[label] = idx
            end
        end
    end

    g_a = free_idx_forms[a_label]
    g_b = free_idx_forms[b_label]

    # Pick dummy index labels not used in the expression
    # Use manifold's index labels as candidates
    used_labels = Set(keys(idx_counts))
    dummy_candidates = [
        string(l) for l in manifold.index_labels if !(string(l) in used_labels)
    ]
    length(dummy_candidates) < 2 &&
        error("MakeTraceFree: not enough free index labels for dummy indices")
    d1, d2 = dummy_candidates[1], dummy_candidates[2]

    # Build trace-free expression at AST level
    # TF = T_{ab} - (1/dim) * g_{ab} * g^{cd} * T_{cd}
    # where T_{cd} has free indices replaced by dummies
    sub_terms = TermAST[]
    for term in terms
        new_factors = FactorAST[]
        # Add g_{ab} (same variance as free indices)
        push!(new_factors, FactorAST(metric_name, [g_a, g_b]))
        # Add g^{cd} (opposite variance for contraction)
        m_da = startswith(g_a, "-") ? d1 : "-$d1"
        m_db = startswith(g_b, "-") ? d2 : "-$d2"
        contra_d1 = startswith(g_a, "-") ? d1 : "-$d1"
        contra_d2 = startswith(g_b, "-") ? d2 : "-$d2"
        push!(new_factors, FactorAST(metric_name, [contra_d1, contra_d2]))
        # Add original factors with free indices replaced by dummies
        for f in term.factors
            new_idxs = String[]
            for idx in f.indices
                label = startswith(idx, "-") ? idx[2:end] : idx
                if label == a_label
                    # Same variance as original
                    push!(new_idxs, startswith(idx, "-") ? "-$d1" : d1)
                elseif label == b_label
                    push!(new_idxs, startswith(idx, "-") ? "-$d2" : d2)
                else
                    push!(new_idxs, idx)
                end
            end
            push!(new_factors, FactorAST(f.tensor_name, new_idxs))
        end
        push!(sub_terms, TermAST(-term.coeff * (1 // dim), new_factors))
    end

    # Serialize the subtraction terms
    sub_str = _serialize_terms(sub_terms)

    # Combine: original + subtraction, then simplify
    combined = "$canon + $sub_str"
    Simplify(combined)
end

end  # module XTensor
