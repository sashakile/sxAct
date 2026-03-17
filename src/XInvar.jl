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
    XInvar

Invariant permutation representation system for the Invar pipeline.
Implements InvariantCase, RPerm, RInv types, MaxIndex table, and
case enumeration for Riemann tensor invariant classification.

Reference: Martín-García, Yllanes & Portugal (2008) arXiv:0802.1274
Wolfram source: resources/xAct/Invar/Invar.m
"""
module XInvar

# ============================================================
# Exports
# ============================================================

export InvariantCase, RPerm, RInv
export PermDegree, MaxIndex, MaxDualIndex
export InvarCases, InvarDualCases
export RiemannToPerm, PermToRiemann
export PermToInv, InvToPerm
export InvSimplify, RiemannSimplify

# InvarDB submodule — database loading and rule parser
include("InvarDB.jl")

# ============================================================
# Types
# ============================================================

"""
    InvariantCase(deriv_orders, n_epsilon=0)

Classifies a Riemann scalar monomial by the derivative orders on each
Riemann factor and the number of epsilon (Levi-Civita) tensors.

  - `deriv_orders`: sorted non-decreasing list; length = degree (number of Riemanns)
  - `n_epsilon`: 0 = non-dual, 1 = dual (4D only)

The derivative order of an invariant case is `2 * degree + sum(deriv_orders)`.
"""
struct InvariantCase
    deriv_orders::Vector{Int}
    n_epsilon::Int
end

InvariantCase(deriv_orders::Vector{Int}) = InvariantCase(deriv_orders, 0)

"""
    RPerm(metric, case, perm)

A Riemann invariant in permutation representation. The permutation encodes
the contraction pattern of indices across all tensor factors in images notation.
"""
struct RPerm
    metric::Symbol
    case::InvariantCase
    perm::Vector{Int}
end

"""
    RInv(metric, case, index)

A labeled Riemann invariant with a canonical index (1-based) from the Invar database.
"""
struct RInv
    metric::Symbol
    case::InvariantCase
    index::Int
end

# ============================================================
# Equality and Hashing
# ============================================================

function Base.:(==)(a::InvariantCase, b::InvariantCase)
    a.deriv_orders == b.deriv_orders && a.n_epsilon == b.n_epsilon
end
Base.hash(a::InvariantCase, h::UInt) = hash(a.n_epsilon, hash(a.deriv_orders, h))

function Base.:(==)(a::RPerm, b::RPerm)
    a.metric == b.metric && a.case == b.case && a.perm == b.perm
end
Base.hash(a::RPerm, h::UInt) = hash(a.perm, hash(a.case, hash(a.metric, h)))

function Base.:(==)(a::RInv, b::RInv)
    a.metric == b.metric && a.case == b.case && a.index == b.index
end
Base.hash(a::RInv, h::UInt) = hash(a.index, hash(a.case, hash(a.metric, h)))

# ============================================================
# Display
# ============================================================

function Base.show(io::IO, c::InvariantCase)
    print(io, "InvariantCase([", join(c.deriv_orders, ","), "]")
    c.n_epsilon > 0 && print(io, ", ε=", c.n_epsilon)
    print(io, ")")
end

function Base.show(io::IO, r::RPerm)
    print(io, "RPerm(:", r.metric, ", ", r.case, ", ", r.perm, ")")
end

function Base.show(io::IO, r::RInv)
    print(io, "RInv(:", r.metric, ", ", r.case, ", ", r.index, ")")
end

# ============================================================
# PermDegree
# ============================================================

"""
    PermDegree(case::InvariantCase) -> Int

Permutation degree (number of index slots) for an invariant case.

Formula: `4 * n_riemanns + sum(deriv_orders) + 4 * n_epsilon`

Source: Invar.m:696
"""
function PermDegree(c::InvariantCase)
    4 * length(c.deriv_orders) + sum(c.deriv_orders; init=0) + 4 * c.n_epsilon
end

# ============================================================
# MaxIndex Table (Invar.m:389-451)
# ============================================================

const _MAX_INDEX = Dict{Vector{Int},Int}(
    # Order 2
    [0] => 1,
    # Order 4
    [0, 0] => 3,
    [2] => 2,
    # Order 6
    [0, 0, 0] => 9,
    [0, 2] => 12,
    [1, 1] => 12,
    [4] => 12,
    # Order 8
    [0, 0, 0, 0] => 38,
    [0, 0, 2] => 99,
    [0, 1, 1] => 125,
    [0, 4] => 126,
    [1, 3] => 138,
    [2, 2] => 86,
    [6] => 105,
    # Order 10
    [0, 0, 0, 0, 0] => 204,
    [0, 0, 0, 2] => 1020,
    [0, 0, 1, 1] => 1749,
    [0, 0, 4] => 1473,
    [0, 1, 3] => 3099,
    [0, 2, 2] => 1622,
    [1, 1, 2] => 1617,
    [0, 6] => 1665,
    [1, 5] => 1770,
    [2, 4] => 1746,
    [3, 3] => 962,
    [8] => 1155,
    # Order 12
    [0, 0, 0, 0, 0, 0] => 1613,
    [0, 0, 0, 0, 2] => 12722,
    [0, 0, 0, 1, 1] => 27022,
    [0, 0, 0, 4] => 19617,
    [0, 0, 1, 3] => 60984,
    [0, 0, 2, 2] => 30974,
    [0, 1, 1, 2] => 62465,
    [1, 1, 1, 1] => 5606,
    [0, 0, 6] => 25590,
    [0, 1, 5] => 53160,
    [0, 2, 4] => 52764,
    [1, 1, 4] => 27396,
    [0, 3, 3] => 27024,
    [1, 2, 3] => 54654,
    [2, 2, 2] => 9104,
    [0, 8] => 25515,
    [1, 7] => 26670,
    [2, 6] => 26460,
    [3, 5] => 26670,
    [4, 4] => 13607,
    [10] => 15120,
    # Order 14 (algebraic only)
    [0, 0, 0, 0, 0, 0, 0] => 16532,
    # Higher algebraic (not in InvarCases[] but have MaxIndex)
    [0, 0, 0, 0, 0, 0, 0, 0] => 217395,
    [0, 0, 0, 0, 0, 0, 0, 0, 0] => 3406747,
)

"""
    MaxIndex(case) -> Int

Number of independent Riemann invariants for a given case.
Accepts `InvariantCase`, `Vector{Int}` (deriv_orders), or `Int` (pure algebraic degree).

Source: Invar.m:389-451
"""
MaxIndex(c::InvariantCase) = MaxIndex(c.deriv_orders)
MaxIndex(n::Int) = n > 0 ? MaxIndex(fill(0, n)) : 0

function MaxIndex(deriv_orders::Vector{Int})
    haskey(_MAX_INDEX, deriv_orders) ||
        throw(ArgumentError("Case $deriv_orders not in MaxIndex table"))
    return _MAX_INDEX[deriv_orders]
end

# ============================================================
# MaxDualIndex Table (Invar.m:455-483)
# ============================================================

const _MAX_DUAL_INDEX = Dict{Vector{Int},Int}(
    # Order 2
    [0] => 1,
    # Order 4
    [0, 0] => 4,
    [2] => 3,
    # Order 6
    [0, 0, 0] => 27,
    [0, 2] => 58,
    [1, 1] => 36,
    [4] => 32,
    # Order 8
    [0, 0, 0, 0] => 232,
    [0, 0, 2] => 967,
    [0, 1, 1] => 1047,
    [0, 4] => 876,
    [1, 3] => 920,
    [2, 2] => 478,
    [6] => 435,
    # Order 10 (algebraic only)
    [0, 0, 0, 0, 0] => 2582,
    # Higher algebraic
    [0, 0, 0, 0, 0, 0] => 35090,
    [0, 0, 0, 0, 0, 0, 0] => 558323,
)

"""
    MaxDualIndex(case) -> Int

Number of independent dual Riemann invariants for a given case.

Source: Invar.m:455-483
"""
MaxDualIndex(c::InvariantCase) = MaxDualIndex(c.deriv_orders)
MaxDualIndex(n::Int) = n > 0 ? MaxDualIndex(fill(0, n)) : 0

function MaxDualIndex(deriv_orders::Vector{Int})
    haskey(_MAX_DUAL_INDEX, deriv_orders) ||
        throw(ArgumentError("Dual case $deriv_orders not in MaxDualIndex table"))
    return _MAX_DUAL_INDEX[deriv_orders]
end

# ============================================================
# Partition Enumeration (internal)
# ============================================================

"""
All partitions of `n` into `k` non-negative parts in non-decreasing order.
"""
function _sorted_partitions(n::Int, k::Int)
    result = Vector{Vector{Int}}()
    if k == 0
        n == 0 && push!(result, Int[])
        return result
    end
    _partition_helper!(result, Int[], n, k, 0)
    return result
end

function _partition_helper!(
    result::Vector{Vector{Int}},
    current::Vector{Int},
    remaining::Int,
    slots::Int,
    min_val::Int,
)
    if slots == 1
        remaining >= min_val && push!(result, [current; remaining])
        return nothing
    end
    for v in min_val:remaining
        push!(current, v)
        _partition_helper!(result, current, remaining - v, slots - 1, v)
        pop!(current)
    end
end

# ============================================================
# InvarCases — Non-Dual Case Enumeration
# ============================================================

"""
    InvarCases() -> Vector{InvariantCase}

All non-dual invariant cases through order 14 (48 cases).
Matches Wolfram `InvarCases[]`.
"""
function InvarCases()
    cases = InvariantCase[]
    for order in 2:2:14
        append!(cases, InvarCases(order))
    end
    return cases
end

"""
    InvarCases(order) -> Vector{InvariantCase}

Non-dual cases for a given even derivative order (2 ≤ order ≤ 14).
Degrees enumerate from highest to lowest.
"""
function InvarCases(order::Int)
    order % 2 != 0 && throw(ArgumentError("Order must be even, got $order"))
    order < 2 && throw(ArgumentError("Order must be >= 2, got $order"))
    order > 14 && throw(ArgumentError("Order > 14 not supported"))

    if order == 14
        return [InvariantCase(fill(0, 7))]
    end

    cases = InvariantCase[]
    for degree in (order ÷ 2):-1:1
        for p in _sorted_partitions(order - 2 * degree, degree)
            push!(cases, InvariantCase(p))
        end
    end
    return cases
end

"""
    InvarCases(order, degree) -> Vector{InvariantCase}

Non-dual cases for a given order and degree (number of Riemann tensors).
"""
function InvarCases(order::Int, degree::Int)
    remainder = order - 2 * degree
    remainder < 0 && return InvariantCase[]
    return [InvariantCase(p) for p in _sorted_partitions(remainder, degree)]
end

# ============================================================
# InvarDualCases — Dual Case Enumeration
# ============================================================

"""
    InvarDualCases() -> Vector{InvariantCase}

All dual invariant cases through order 10.
Matches Wolfram `InvarDualCases[]`.
"""
function InvarDualCases()
    cases = InvariantCase[]
    for order in 2:2:10
        append!(cases, InvarDualCases(order))
    end
    return cases
end

"""
    InvarDualCases(order) -> Vector{InvariantCase}

Dual cases for a given even derivative order (2 ≤ order ≤ 10).
"""
function InvarDualCases(order::Int)
    order % 2 != 0 && throw(ArgumentError("Order must be even, got $order"))
    order < 2 && throw(ArgumentError("Order must be >= 2, got $order"))
    order > 10 && throw(ArgumentError("Dual order > 10 not supported"))

    if order == 10
        return [InvariantCase(fill(0, 5), 1)]
    end

    cases = InvariantCase[]
    for degree in (order ÷ 2):-1:1
        for p in _sorted_partitions(order - 2 * degree, degree)
            push!(cases, InvariantCase(p, 1))
        end
    end
    return cases
end

# ============================================================
# Phase 3: Riemann-to-Permutation Conversion
# ============================================================

# Index pool for generating fresh dummy indices.
# Uses double-letter names to avoid collision with user indices.
const _FRESH_INDEX_POOL = [
    "xa",
    "xb",
    "xc",
    "xd",
    "xe",
    "xf",
    "xg",
    "xh",
    "xi",
    "xj",
    "xk",
    "xl",
    "xm",
    "xn",
    "xo",
    "xp",
    "xq",
    "xr",
    "xs",
    "xt",
    "xu",
    "xv",
    "xw",
    "xx",
    "xy",
    "xz",
    "ya",
    "yb",
    "yc",
    "yd",
    "ye",
    "yf",
    "yg",
    "yh",
    "yi",
    "yj",
    "yk",
    "yl",
    "ym",
    "yn",
    "yo",
    "yp",
    "yq",
    "yr",
    "ys",
    "yt",
]

"""
    _bare_index(idx::String) -> String

Strip the leading '-' from a covariant index. E.g., "-a" → "a", "a" → "a".
"""
_bare_index(idx::AbstractString) = startswith(idx, "-") ? String(idx[2:end]) : String(idx)

"""
    _is_covariant_idx(idx::String) -> Bool

True if the index is covariant (starts with '-').
"""
_is_covariant_idx(idx::AbstractString) = startswith(idx, "-")

"""
    _collect_used_indices(expr::String) -> Set{String}

Collect all bare index names used in the expression.
"""
function _collect_used_indices(expr::AbstractString)::Set{String}
    used = Set{String}()
    for m in eachmatch(r"[\[,]\s*(-?[a-zA-Z]\w*)", expr)
        # JET: m.captures[1] can be Nothing if the group didn't match.
        # But our regex always matches the group if the match succeeds.
        cap = m.captures[1]
        if !isnothing(cap)
            push!(used, _bare_index(strip(cap)))
        end
    end
    used
end

"""
    _fresh_indices(n::Int, used::Set{String}) -> Vector{String}

Generate `n` fresh index names not in `used`. Mutates `used` by adding the new names.
"""
function _fresh_indices(n::Int, used::Set{String})::Vector{String}
    result = String[]
    for idx in _FRESH_INDEX_POOL
        idx in used && continue
        push!(result, idx)
        push!(used, idx)
        length(result) >= n && return result
    end
    i = 1
    while length(result) < n
        idx = "zz$i"
        if idx ∉ used
            push!(result, idx)
            push!(used, idx)
        end
        i += 1
    end
    result
end

# ============================================================
# String Parsing Utilities for Tensor Expressions
# ============================================================

"""
A parsed tensor factor from a monomial string.
"""
struct _InvarFactor
    tensor_name::String
    indices::Vector{String}
    covd_indices::Vector{String}  # CovD indices applied to this factor (outermost first)
end

"""
    _parse_invar_monomial(mono::String) -> (Rational{Int}, Vector{_InvarFactor})

Parse a monomial string into its numeric coefficient and tensor factors.
Handles CovD notation: `CD[-e][RiemannCD[-a,-b,-c,-d]]` is parsed as a single
factor with covd_indices=["-e"] and tensor RiemannCD with indices ["-a","-b","-c","-d"].
"""
function _parse_invar_monomial(mono::AbstractString)
    s = String(strip(mono))
    isempty(s) && return (0 // 1, _InvarFactor[])

    # Extract leading coefficient
    coeff = 1 // 1

    # Try rational coefficient: (N/M)
    m_rat = match(r"^\((-?\d+)/(\d+)\)\s*\*?\s*", s)
    if !isnothing(m_rat)
        # JET: check captures are not nothing
        c1 = m_rat.captures[1]
        c2 = m_rat.captures[2]
        if !isnothing(c1) && !isnothing(c2)
            num = parse(Int, c1)
            den = parse(Int, c2)
            coeff = num // den
            s = String(strip(s[(length(m_rat.match) + 1):end]))
        end
    else
        # Try integer coefficient: only if followed by whitespace or *
        m_int = match(r"^(-?\d+)\s*(\*\s*|\s+)", s)
        if !isnothing(m_int)
            c1 = m_int.captures[1]
            if !isnothing(c1)
                rest = String(strip(s[(length(m_int.match) + 1):end]))
                if !isempty(rest) && (isletter(rest[1]) || rest[1] == '(')
                    coeff = parse(Int, c1) // 1
                    s = rest
                end
            end
        end
    end

    factors = _InvarFactor[]
    pos = 1
    n = length(s)

    while pos <= n
        while pos <= n && isspace(s[pos])
            pos += 1
        end
        pos > n && break

        factor, pos = _parse_one_factor(s, pos)
        !isnothing(factor) && push!(factors, factor)
    end

    (coeff, factors)
end

"""
    _parse_one_factor(s, pos) -> (_InvarFactor or nothing, new_pos)

Parse one tensor factor starting at position `pos`. Handles both plain
`TensorName[indices]` and CovD-wrapped `CovD[-i][...CovD[-j][Tensor[indices]]...]`.
"""
function _parse_one_factor(s::AbstractString, pos::Int)
    n = length(s)

    # Read the name
    name_start = pos
    while pos <= n && (isletter(s[pos]) || isdigit(s[pos]) || s[pos] == '_')
        pos += 1
    end
    name = String(s[name_start:(pos - 1)])
    isempty(name) && return (nothing, pos)

    # Skip whitespace
    while pos <= n && isspace(s[pos])
        pos += 1
    end

    # Must be followed by '['
    (pos > n || s[pos] != '[') &&
        error("Expected '[' after '$name' at position $pos in: $s")
    pos += 1  # consume '['

    # Read until matching ']'
    idx_start = pos
    depth = 1
    while pos <= n && depth > 0
        s[pos] == '[' && (depth += 1)
        s[pos] == ']' && (depth -= 1)
        depth > 0 && (pos += 1)
    end
    content = String(s[idx_start:(pos - 1)])
    pos += 1  # consume ']'

    # Check for CovD two-bracket pattern: Name[idx][operand]
    # After consuming Name[content], if the next char is '[', this is a CovD application.
    if pos <= n && s[pos] == '['
        # CovD pattern: name[covd_idx][inner_expr]
        covd_idx = String(strip(content))

        # Read the second bracket: [inner_expr]
        pos += 1  # consume '['
        inner_start = pos
        depth = 1
        while pos <= n && depth > 0
            s[pos] == '[' && (depth += 1)
            s[pos] == ']' && (depth -= 1)
            depth > 0 && (pos += 1)
        end
        inner_str = String(s[inner_start:(pos - 1)])
        pos += 1  # consume ']'

        inner_factor, _ = _parse_one_factor(inner_str, 1)
        isnothing(inner_factor) && error("Failed to parse inner CovD factor in: $inner_str")

        return (
            _InvarFactor(
                inner_factor.tensor_name,
                inner_factor.indices,
                [covd_idx; inner_factor.covd_indices],
            ),
            pos,
        )
    end

    # Check if content itself contains a '][' split indicating CovD wrapping
    # (alternative syntax where the split is inside the brackets)
    bracket_pos = _find_covd_split(content)

    if !isnothing(bracket_pos)
        covd_idx = String(strip(content[1:(bracket_pos - 1)]))
        inner_str = String(content[(bracket_pos + 2):end])

        inner_factor, _ = _parse_one_factor(inner_str, 1)
        isnothing(inner_factor) && error("Failed to parse inner CovD factor in: $content")

        return (
            _InvarFactor(
                inner_factor.tensor_name,
                inner_factor.indices,
                [covd_idx; inner_factor.covd_indices],
            ),
            pos,
        )
    else
        indices = _parse_idx_list(content)
        return (_InvarFactor(name, indices, String[]), pos)
    end
end

"""
    _find_covd_split(content::String) -> Union{Int, Nothing}

Find the position of '][' in content that indicates a CovD split.
Returns the position of the ']' or nothing.
"""
function _find_covd_split(content::AbstractString)
    depth = 0
    n = length(content)
    for i in 1:n
        c = content[i]
        if c == '['
            depth += 1
        elseif c == ']'
            if depth == 0
                if i + 1 <= n && content[i + 1] == '['
                    return i
                end
            else
                depth -= 1
            end
        end
    end
    nothing
end

"""
    _parse_idx_list(s::String) -> Vector{String}

Parse a comma-separated index list like "-a,-b,c,d" into ["-a", "-b", "c", "d"].
"""
function _parse_idx_list(s::AbstractString)::Vector{String}
    s = strip(s)
    isempty(s) && return String[]
    [String(strip(idx)) for idx in split(s, ",")]
end

# ============================================================
# Sum Parsing
# ============================================================

"""
    _parse_invar_sum(expr::String) -> Vector{Tuple{Int, String}}

Split an expression on top-level + and - (not inside brackets) into
signed monomial strings. Returns (sign, monomial_string) pairs.
"""
function _parse_invar_sum(expr::AbstractString)::Vector{Tuple{Int,String}}
    s = String(strip(expr))
    isempty(s) && return Tuple{Int,String}[]

    result = Tuple{Int,String}[]
    pos = 1
    n = length(s)
    current_start = 1
    current_sign = 1
    depth = 0

    # Handle leading sign
    if pos <= n && (s[pos] == '+' || s[pos] == '-')
        current_sign = s[pos] == '-' ? -1 : 1
        pos += 1
        current_start = pos
    end

    while pos <= n
        c = s[pos]
        if c == '[' || c == '('
            depth += 1
            pos += 1
        elseif c == ']' || c == ')'
            depth -= 1
            pos += 1
        elseif (c == '+' || c == '-') && depth == 0 && pos > 1
            chunk = String(strip(s[current_start:(pos - 1)]))
            !isempty(chunk) && push!(result, (current_sign, chunk))
            current_sign = c == '-' ? -1 : 1
            pos += 1
            current_start = pos
        else
            pos += 1
        end
    end

    chunk = String(strip(s[current_start:end]))
    !isempty(chunk) && push!(result, (current_sign, chunk))
    result
end

# ============================================================
# _ricci_to_riemann
# ============================================================

"""
    _ricci_to_riemann(expr::String, covd::Symbol) -> String

Replace Ricci and RicciScalar tensors with their contracted Riemann equivalents.

  - `RicciCD[-a,-b]` → `RiemannCD[xa,-a,-xa,-b]` (contracted Riemann)
  - `RicciScalarCD[]` → `RiemannCD[xa,xb,-xa,-xb]` (double-contracted Riemann)

The covd name determines the tensor prefix (e.g., covd=:CD → RiemannCD, RicciCD, etc.).
"""
function _ricci_to_riemann(expr::AbstractString, covd::Symbol)::String
    prefix = string(covd)
    riemann_name = "Riemann" * prefix
    ricci_name = "Ricci" * prefix
    ricci_scalar_name = "RicciScalar" * prefix

    used = _collect_used_indices(expr)
    result = expr

    # Replace RicciScalar first (longer name avoids partial Ricci match)
    while true
        m = match(
            Regex(
                replace(ricci_scalar_name, r"([.*+?^${}()|\\])" => s"\\\1") * "\\[\\s*\\]"
            ),
            result,
        )
        isnothing(m) && break
        fresh = _fresh_indices(2, used)
        replacement = "$(riemann_name)[$(fresh[1]),$(fresh[2]),-$(fresh[1]),-$(fresh[2])]"
        result = replace(result, m.match => replacement; count=1)
    end

    # Replace Ricci tensors
    while true
        m = match(
            Regex(replace(ricci_name, r"([.*+?^${}()|\\])" => s"\\\1") * "\\[([^\\]]*)\\]"),
            result,
        )
        isnothing(m) && break
        cap = m.captures[1]
        isnothing(cap) && break
        indices = _parse_idx_list(cap)
        length(indices) == 2 || error("Ricci tensor must have 2 indices, got: $(m.match)")
        fresh = _fresh_indices(1, used)
        # Ricci_{ab} = R^c{}_{acb}: contract slots 1&3 of Riemann
        replacement = "$(riemann_name)[$(fresh[1]),$(indices[1]),-$(fresh[1]),$(indices[2])]"
        result = replace(result, m.match => replacement; count=1)
    end

    result
end

# ============================================================
# _classify_case
# ============================================================

"""
    _classify_case(expr::String, metric::Symbol) -> InvariantCase

Classify a single monomial (product of Riemann tensors, possibly with CovD derivatives)
into an InvariantCase. Ricci/RicciScalar should already be replaced with Riemann.
"""
function _classify_case(expr::AbstractString, metric::Symbol)::InvariantCase
    _, factors = _parse_invar_monomial(expr)
    isempty(factors) && throw(ArgumentError("Empty expression cannot be classified"))

    deriv_orders = Int[]
    for f in factors
        if startswith(f.tensor_name, "Riemann")
            push!(deriv_orders, length(f.covd_indices))
        elseif startswith(f.tensor_name, "Ricci")
            error(
                "_classify_case: Ricci/RicciScalar must be replaced before classification"
            )
        end
    end

    isempty(deriv_orders) && throw(ArgumentError("No Riemann factors found in expression"))
    sort!(deriv_orders)
    InvariantCase(deriv_orders)
end

# ============================================================
# _extract_contraction_perm
# ============================================================

"""
    _extract_contraction_perm(expr::String, case::InvariantCase) -> Vector{Int}

Extract the contraction permutation from a monomial string.

Slot assignment: for each Riemann factor (left to right), CovD indices come before
the 4 Riemann indices. The result is an involution: perm[i] = j and perm[j] = i
for each contracted pair (i, j).
"""
function _extract_contraction_perm(expr::AbstractString, case::InvariantCase)::Vector{Int}
    _, factors = _parse_invar_monomial(expr)
    expected_degree = PermDegree(case)

    slot = 0
    index_slots = Dict{String,Vector{Tuple{Int,Bool}}}()

    for f in factors
        startswith(f.tensor_name, "Riemann") || continue

        # CovD indices first
        for cidx in f.covd_indices
            slot += 1
            bare = _bare_index(cidx)
            cov = _is_covariant_idx(cidx)
            push!(get!(Vector{Tuple{Int,Bool}}, index_slots, bare), (slot, cov))
        end

        # Then Riemann indices
        for idx in f.indices
            slot += 1
            bare = _bare_index(idx)
            cov = _is_covariant_idx(idx)
            push!(get!(Vector{Tuple{Int,Bool}}, index_slots, bare), (slot, cov))
        end
    end

    slot == expected_degree ||
        error("Slot count $slot != expected PermDegree $expected_degree for case $case")

    perm = zeros(Int, expected_degree)

    for (bare, occurrences) in index_slots
        length(occurrences) == 2 || throw(
            ArgumentError(
                "Index '$bare' appears $(length(occurrences)) times; " *
                "expected exactly 2 for a contracted pair",
            ),
        )

        s1, cov1 = occurrences[1]
        s2, cov2 = occurrences[2]
        cov1 != cov2 ||
            throw(ArgumentError("Index '$bare' has same variance in both occurrences"))

        perm[s1] = s2
        perm[s2] = s1
    end

    any(==(0), perm) && throw(
        ArgumentError(
            "Incomplete contraction: free indices not allowed in Riemann invariants"
        ),
    )

    perm
end

# ============================================================
# Permutation Canonicalization for Riemann Products
# ============================================================

"""
    _swap_slots!(perm::Vector{Int}, a::Int, b::Int)

Conjugate the contraction permutation by the transposition (a b).
This swaps slots a and b: perm → (a b) ∘ perm ∘ (a b).
"""
function _swap_slots!(perm::Vector{Int}, a::Int, b::Int)
    # Step 1: swap values a↔b throughout
    for i in eachindex(perm)
        if perm[i] == a
            perm[i] = b
        elseif perm[i] == b
            perm[i] = a
        end
    end
    # Step 2: swap entries at positions a and b
    perm[a], perm[b] = perm[b], perm[a]
end

"""
    _perm_sign_of(arr::Vector{Int}) -> Int

Compute the sign (parity) of the permutation arr relative to its sorted order.
"""
function _perm_sign_of(arr::Vector{Int})::Int
    n = length(arr)
    n <= 1 && return 1
    sorted = sort(arr)
    pos = Dict(v => i for (i, v) in enumerate(sorted))
    perm_indices = [pos[v] for v in arr]

    visited = falses(n)
    sign = 1
    for i in 1:n
        visited[i] && continue
        cycle_len = 0
        j = i
        while !visited[j]
            visited[j] = true
            j = perm_indices[j]
            cycle_len += 1
        end
        iseven(cycle_len) && (sign = -sign)
    end
    sign
end

"""
    _all_permutations_of(indices::Vector{Int}) -> Vector{Tuple{Vector{Int}, Int}}

Generate all permutations of `indices` as (permuted_list, sign_relative_to_sorted) pairs.
"""
function _all_permutations_of(indices::Vector{Int})::Vector{Tuple{Vector{Int},Int}}
    n = length(indices)
    n == 0 && return [(Int[], 1)]
    n == 1 && return [(copy(indices), 1)]

    result = Tuple{Vector{Int},Int}[]
    arr = copy(indices)
    _heap_permute!(result, arr, n)
    result
end

function _heap_permute!(result::Vector{Tuple{Vector{Int},Int}}, arr::Vector{Int}, k::Int)
    if k == 1
        push!(result, (copy(arr), _perm_sign_of(arr)))
        return nothing
    end
    for i in 1:k
        _heap_permute!(result, arr, k - 1)
        if iseven(k)
            arr[i], arr[k] = arr[k], arr[i]
        else
            arr[1], arr[k] = arr[k], arr[1]
        end
    end
end

"""
    _apply_block_perm_to_contraction(perm, block_perm, slot_ranges, degree) -> Vector{Int}

Apply a block (factor) permutation to a contraction permutation.
block_perm[i] = j means factor i moves to position j.
"""
function _apply_block_perm_to_contraction(
    perm::Vector{Int},
    block_perm::Vector{Int},
    slot_ranges::Vector{UnitRange{Int}},
    degree::Int,
)::Vector{Int}
    n = length(slot_ranges)
    slot_map = zeros(Int, degree)
    for i in 1:n
        j = block_perm[i]
        old_range = slot_ranges[i]
        new_range = slot_ranges[j]
        for (k, old_s) in enumerate(old_range)
            slot_map[old_s] = new_range[k]
        end
    end

    new_perm = zeros(Int, degree)
    for i in 1:degree
        new_perm[slot_map[i]] = slot_map[perm[i]]
    end
    new_perm
end

"""
    _all_block_permutations(groups, n, slot_ranges) -> Vector{Tuple{Vector{Int}, Int}}

Generate all block permutations respecting same-derivative-order groups.
Returns (block_perm, sign) pairs where block_perm[i] = position that factor i maps to.
"""
function _all_block_permutations(
    groups::Dict{Int,Vector{Int}}, n::Int, slot_ranges::Vector{UnitRange{Int}}
)::Vector{Tuple{Vector{Int},Int}}
    result = [(collect(1:n), 1)]

    for (_, group_indices) in groups
        length(group_indices) <= 1 && continue

        # All permutations of this group
        group_perms = _all_permutations_of(group_indices)

        new_result = Tuple{Vector{Int},Int}[]
        for (base_perm, base_sign) in result
            for (gp, gp_sign) in group_perms
                combined = copy(base_perm)
                for (k, idx) in enumerate(group_indices)
                    combined[idx] = base_perm[gp[k]]
                end
                push!(new_result, (combined, base_sign * gp_sign))
            end
        end
        result = new_result
    end

    result
end

"""
    _backtrack_riemann_syms!(perm, sign, factor, ...)

Recursively apply Riemann symmetries to factors `factor..n_factors`, pruning
branches where frozen positions are already worse than `best_perm`.

A position j is "frozen" after processing factor k when both
`slot_to_factor[j] ≤ k` and `slot_to_factor[perm[j]] ≤ k` — future
factor symmetries cannot change frozen values.
"""
function _backtrack_riemann_syms!(
    perm::Vector{Int},
    sign::Int,
    factor::Int,
    n_factors::Int,
    degree::Int,
    riemann_starts::Vector{Int},
    slot_to_factor::Vector{Int},
    best_perm::Vector{Int},
    best_sign::Ref{Int},
)
    if factor > n_factors
        if perm < best_perm
            copyto!(best_perm, perm)
            best_sign[] = sign
        end
        return nothing
    end

    saved = copy(perm)
    for bits in 0:7
        copyto!(perm, saved)
        current_sign = sign

        rs = riemann_starts[factor]
        a, b, c, d = rs, rs + 1, rs + 2, rs + 3

        if bits & 1 != 0
            _swap_slots!(perm, a, b)
            current_sign = -current_sign
        end
        if bits & 2 != 0
            _swap_slots!(perm, c, d)
            current_sign = -current_sign
        end
        if bits & 4 != 0
            _swap_slots!(perm, a, c)
            _swap_slots!(perm, b, d)
        end

        # Frozen-position pruning: check positions whose factor and value are both ≤ current
        pruned = false
        for j in 1:degree
            (slot_to_factor[j] > factor || slot_to_factor[perm[j]] > factor) && continue
            if perm[j] > best_perm[j]
                pruned = true
                break
            elseif perm[j] < best_perm[j]
                break
            end
        end

        if !pruned
            _backtrack_riemann_syms!(
                perm,
                current_sign,
                factor + 1,
                n_factors,
                degree,
                riemann_starts,
                slot_to_factor,
                best_perm,
                best_sign,
            )
        end
    end

    copyto!(perm, saved)
    return nothing
end

"""
    _canonicalize_contraction_perm(perm, case) -> (canonical_perm, sign)

Canonicalize a contraction permutation under the symmetry group of a product
of Riemann tensors. The symmetry group combines:

 1. Riemann pair symmetries (8 elements per factor): swap (a,b) sign=-1,
    swap (c,d) sign=-1, exchange pairs (a,b)↔(c,d) sign=+1.
 2. Block permutations of factors with the same derivative order (sign = parity).

Returns the lexicographically minimal permutation and its sign.
"""
function _canonicalize_contraction_perm(
    perm::Vector{Int}, case::InvariantCase
)::Tuple{Vector{Int},Int}
    n = length(case.deriv_orders)
    n == 0 && return (copy(perm), 1)

    degree = PermDegree(case)
    length(perm) == degree || error("Perm length $(length(perm)) != PermDegree $degree")

    # Compute slot ranges
    slot_ranges = Vector{UnitRange{Int}}(undef, n)
    riemann_offsets = Vector{Int}(undef, n)  # start of 4 Riemann slots in each factor
    offset = 0
    for i in 1:n
        nd = case.deriv_orders[i]
        total = nd + 4
        slot_ranges[i] = (offset + 1):(offset + total)
        riemann_offsets[i] = offset + nd
        offset += total
    end

    # Group factors by derivative order
    groups = Dict{Int,Vector{Int}}()
    for i in 1:n
        d = case.deriv_orders[i]
        push!(get!(Vector{Int}, groups, d), i)
    end

    block_perms = _all_block_permutations(groups, n, slot_ranges)

    # Precompute slot-to-factor mapping and Riemann start positions
    slot_to_factor = zeros(Int, degree)
    for i in 1:n
        for j in slot_ranges[i]
            slot_to_factor[j] = i
        end
    end

    riemann_starts = Vector{Int}(undef, n)
    for i in 1:n
        riemann_starts[i] = first(slot_ranges[i]) + case.deriv_orders[i]
    end

    best_perm = copy(perm)
    best_sign = 1

    if n <= 4
        # Brute-force: enumerate all 8^n Riemann symmetry combinations
        for (block_perm_map, block_sign) in block_perms
            bp = _apply_block_perm_to_contraction(perm, block_perm_map, slot_ranges, degree)

            total_configs = 8^n
            for config in 0:(total_configs - 1)
                current_perm = copy(bp)
                current_sign = block_sign

                cfg = config
                for i in 1:n
                    bits = cfg & 7
                    cfg >>= 3

                    rs = riemann_starts[i]
                    a, b, c, d = rs, rs + 1, rs + 2, rs + 3

                    if bits & 1 != 0  # swap first pair (a,b)
                        _swap_slots!(current_perm, a, b)
                        current_sign = -current_sign
                    end
                    if bits & 2 != 0  # swap second pair (c,d)
                        _swap_slots!(current_perm, c, d)
                        current_sign = -current_sign
                    end
                    if bits & 4 != 0  # exchange pairs (a,b) ↔ (c,d)
                        _swap_slots!(current_perm, a, c)
                        _swap_slots!(current_perm, b, d)
                    end
                end

                if current_perm < best_perm
                    best_perm = current_perm
                    best_sign = current_sign
                end
            end
        end
    else
        # Backtracking with frozen-position pruning for n ≥ 5
        best_sign_ref = Ref(best_sign)

        # Precompute block-permuted perms and seed best_perm for tighter pruning
        block_results = Vector{Tuple{Vector{Int},Int}}(undef, length(block_perms))
        for (k, (bmap, bsign)) in enumerate(block_perms)
            bp = _apply_block_perm_to_contraction(perm, bmap, slot_ranges, degree)
            block_results[k] = (bp, bsign)
            if bp < best_perm
                copyto!(best_perm, bp)
                best_sign_ref[] = bsign
            end
        end

        # Explore best-looking block perms first to maximize pruning
        sort!(block_results; by=first)

        for (bp, block_sign) in block_results
            _backtrack_riemann_syms!(
                bp,
                block_sign,
                1,
                n,
                degree,
                riemann_starts,
                slot_to_factor,
                best_perm,
                best_sign_ref,
            )
        end
        best_sign = best_sign_ref[]
    end

    (best_perm, best_sign)
end

# ============================================================
# RiemannToPerm
# ============================================================

"""
    RiemannToPerm(expr::String, metric::Symbol; covd::Symbol=metric)

Convert a Riemann scalar expression into canonical RPerm permutation form.

For a single monomial, returns an RPerm. For a sum, returns
`Vector{Tuple{Rational{Int}, RPerm}}`.

The expression should use pre-canonicalized index ordering. The `covd` keyword
determines the tensor name prefix (default: same as metric).

# Examples

```julia
RiemannToPerm("RiemannCD[-a,-b,-c,-d] RiemannCD[a,b,c,d]", :g; covd=:CD)
RiemannToPerm("RicciScalarCD[]", :g; covd=:CD)
```
"""
function RiemannToPerm(expr::AbstractString, metric::Symbol; covd::Symbol=metric)
    terms = _parse_invar_sum(expr)
    isempty(terms) && throw(ArgumentError("Empty expression"))

    results = Tuple{Rational{Int},RPerm}[]

    for (sign, mono_str) in terms
        coeff, rperm = _monomial_to_rperm(mono_str, metric, covd)
        push!(results, (sign * coeff, rperm))
    end

    if length(results) == 1 && results[1][1] == 1
        return results[1][2]
    end

    results
end

"""
Process a single monomial into (coefficient, RPerm).
"""
function _monomial_to_rperm(
    mono::AbstractString, metric::Symbol, covd::Symbol
)::Tuple{Rational{Int},RPerm}
    # Step 1: Replace Ricci/RicciScalar → Riemann
    expanded = _ricci_to_riemann(mono, covd)

    # Step 2: Parse
    coeff, factors = _parse_invar_monomial(expanded)

    for f in factors
        startswith(f.tensor_name, "Riemann") || throw(
            ArgumentError(
                "Non-Riemann factor '$(f.tensor_name)' cannot be converted to RPerm"
            ),
        )
    end

    # Step 3: Classify
    case = _classify_case(expanded, metric)

    # Step 4: Extract contraction permutation
    raw_perm = _extract_contraction_perm(expanded, case)

    # Step 5: Canonicalize
    canon_perm, canon_sign = _canonicalize_contraction_perm(raw_perm, case)

    (coeff * canon_sign, RPerm(metric, case, canon_perm))
end

# ============================================================
# PermToRiemann
# ============================================================

const _INDEX_ALPHABET = [
    "a",
    "b",
    "c",
    "d",
    "e",
    "f",
    "g",
    "h",
    "i",
    "j",
    "k",
    "l",
    "m",
    "n",
    "o",
    "p",
    "q",
    "r",
    "s",
    "t",
    "u",
    "v",
    "w",
]

"""
    PermToRiemann(rperm::RPerm; covd::Symbol=rperm.metric, curvature_relations::Bool=false) -> String

Convert an RPerm back to a tensor expression string.

The contraction permutation is an involution: perm[i]=j means slot i contracts with
slot j. Each pair gets a unique index name. The lower-numbered slot gets the covariant
(down) index, the higher slot gets the contravariant (up) index.

If `curvature_relations=true`, contracted Riemann tensors are replaced with Ricci
or RicciScalar where applicable.
"""
function PermToRiemann(
    rperm::RPerm; covd::Symbol=rperm.metric, curvature_relations::Bool=false
)::String
    case = rperm.case
    perm = rperm.perm
    degree = PermDegree(case)
    n = length(case.deriv_orders)
    prefix = string(covd)
    riemann_name = "Riemann" * prefix

    n == 0 && return "1"

    # Assign index names to contracted pairs
    pair_count = 0
    slot_index = Vector{String}(undef, degree)

    for i in 1:degree
        j = perm[i]
        j > i || continue
        pair_count += 1
        pair_count <= length(_INDEX_ALPHABET) ||
            error("Too many contracted pairs — index alphabet exhausted")
        idx_name = _INDEX_ALPHABET[pair_count]
        slot_index[i] = "-" * idx_name  # lower slot → covariant
        slot_index[j] = idx_name         # higher slot → contravariant
    end

    # Build the tensor expression
    parts = String[]
    offset = 0
    for i in 1:n
        nd = case.deriv_orders[i]
        total_slots = nd + 4

        covd_indices = [slot_index[offset + k] for k in 1:nd]
        riemann_indices = [slot_index[offset + nd + k] for k in 1:4]

        if nd == 0
            push!(parts, "$(riemann_name)[$(join(riemann_indices, ","))]")
        else
            inner = "$(riemann_name)[$(join(riemann_indices, ","))]"
            for k in nd:-1:1
                inner = "$(prefix)[$(covd_indices[k])][$(inner)]"
            end
            push!(parts, inner)
        end

        offset += total_slots
    end

    result = join(parts, " ")

    curvature_relations && (result = _riemann_to_ricci(result, covd))

    result
end

"""
    _riemann_to_ricci(expr::String, covd::Symbol) -> String

Replace contracted Riemann patterns with Ricci/RicciScalar where applicable.
A Riemann factor with indices that self-contract can be simplified.
"""
function _riemann_to_ricci(expr::AbstractString, covd::Symbol)::String
    prefix = string(covd)
    riemann_name = "Riemann" * prefix
    ricci_name = "Ricci" * prefix
    ricci_scalar_name = "RicciScalar" * prefix

    _, factors = _parse_invar_monomial(expr)

    parts = String[]
    for f in factors
        if f.tensor_name == riemann_name && isempty(f.covd_indices)
            self_pairs = _find_self_contractions(f.indices)

            if length(self_pairs) == 2
                push!(parts, "$(ricci_scalar_name)[]")
            elseif length(self_pairs) == 1
                contracted_slots = Set([self_pairs[1]...])
                remaining = [f.indices[k] for k in 1:4 if k ∉ contracted_slots]
                push!(parts, "$(ricci_name)[$(join(remaining, ","))]")
            else
                push!(parts, "$(riemann_name)[$(join(f.indices, ","))]")
            end
        else
            if isempty(f.covd_indices)
                push!(parts, "$(f.tensor_name)[$(join(f.indices, ","))]")
            else
                inner = "$(f.tensor_name)[$(join(f.indices, ","))]"
                for k in length(f.covd_indices):-1:1
                    inner = "$(prefix)[$(f.covd_indices[k])][$(inner)]"
                end
                push!(parts, inner)
            end
        end
    end

    join(parts, " ")
end

"""
Find pairs of indices within a single factor that contract with each other.
Returns list of (slot1, slot2) tuples.
"""
function _find_self_contractions(indices::Vector{String})::Vector{Tuple{Int,Int}}
    pairs = Tuple{Int,Int}[]
    n = length(indices)
    used = falses(n)
    for i in 1:n
        used[i] && continue
        for j in (i + 1):n
            used[j] && continue
            if _bare_index(indices[i]) == _bare_index(indices[j]) &&
                _is_covariant_idx(indices[i]) != _is_covariant_idx(indices[j])
                push!(pairs, (i, j))
                used[i] = true
                used[j] = true
                break
            end
        end
    end
    pairs
end

# ============================================================
# Phase 4: Permutation-to-Invariant Lookup (PermToInv)
# ============================================================

"""
    _invar_perm_to_involution(σ::Vector{Int}) -> Vector{Int}

Convert a Wolfram Invar "canonical labeling" permutation to a contraction
involution. In the Invar convention, σ(i) gives the position of slot i in a
canonical paired arrangement where pairs occupy consecutive positions (1,2),
(3,4), etc. The returned involution maps each slot to the slot it contracts
with: invol[i] = j means slot i and slot j share the same dummy index.
"""
function _invar_perm_to_involution(σ::Vector{Int})::Vector{Int}
    d = length(σ)
    invol = zeros(Int, d)
    # Group slots by which pair they belong to (pair k = positions 2k-1, 2k)
    pairs = Dict{Int,Vector{Int}}()
    for i in 1:d
        pair_idx = (σ[i] + 1) ÷ 2
        slots = get!(pairs, pair_idx, Int[])
        push!(slots, i)
    end
    for (_, slots) in pairs
        length(slots) == 2 ||
            error("Invalid Invar permutation: pair has $(length(slots)) slots (expected 2)")
        invol[slots[1]] = slots[2]
        invol[slots[2]] = slots[1]
    end
    invol
end

"""
    _involution_to_invar_perm(invol::Vector{Int}) -> Vector{Int}

Convert a contraction involution back to the Wolfram Invar "canonical labeling"
convention. Contracted pairs are assigned consecutive positions (1,2), (3,4), etc.
in the order they appear (scanning slots left to right).
"""
function _involution_to_invar_perm(invol::Vector{Int})::Vector{Int}
    d = length(invol)
    σ = zeros(Int, d)
    pair_idx = 0
    assigned = falses(d)
    for i in 1:d
        assigned[i] && continue
        j = invol[i]
        pair_idx += 1
        σ[i] = 2 * pair_idx - 1
        σ[j] = 2 * pair_idx
        assigned[i] = true
        assigned[j] = true
    end
    σ
end

"""
    _build_case_dispatch(index_to_perm, case) -> Dict{Vector{Int}, Int}

Build a reverse lookup for a single case: canonical involution → invariant index.
DB permutations are converted from Invar labeling convention to contraction
involutions and canonicalized to match the output of `_canonicalize_contraction_perm`.
"""
function _build_case_dispatch(
    index_to_perm::Dict{Int,Vector{Int}}, case::InvariantCase
)::Dict{Vector{Int},Int}
    perm_to_index = Dict{Vector{Int},Int}()
    for (idx, db_perm) in index_to_perm
        invol = _invar_perm_to_involution(db_perm)
        canon, _ = _canonicalize_contraction_perm(invol, case)
        perm_to_index[canon] = idx
    end
    perm_to_index
end

"""
Global cached dispatch tables. Built lazily per case on first `PermToInv` call.
"""
_perm_dispatch::Dict{Vector{Int},Dict{Vector{Int},Int}} = Dict{
    Vector{Int},Dict{Vector{Int},Int}
}()
_dual_perm_dispatch::Dict{Vector{Int},Dict{Vector{Int},Int}} = Dict{
    Vector{Int},Dict{Vector{Int},Int}
}()

"""
    _build_case_dispatch_raw(index_to_perm) -> Dict{Vector{Int}, Int}

Build a reverse lookup for a single case using raw DB permutations (no conversion).
Used for dual cases where the epsilon tensor slots complicate canonicalization.
"""
function _build_case_dispatch_raw(
    index_to_perm::Dict{Int,Vector{Int}}
)::Dict{Vector{Int},Int}
    perm_to_index = Dict{Vector{Int},Int}()
    for (idx, perm) in index_to_perm
        perm_to_index[perm] = idx
    end
    perm_to_index
end

"""
    _ensure_case_dispatch(db::InvarDB, case_key::Vector{Int}, is_dual::Bool) -> Dict{Vector{Int}, Int}

Return the cached dispatch table for a specific case, building it lazily if needed.
Non-dual cases convert from Invar labeling to canonical involutions.
Dual cases use raw DB perms (looked up via `_involution_to_invar_perm` conversion).
"""
function _ensure_case_dispatch(
    db::InvarDB, case_key::Vector{Int}, is_dual::Bool
)::Dict{Vector{Int},Int}
    dispatch = is_dual ? _dual_perm_dispatch : _perm_dispatch
    perm_table = is_dual ? db.dual_perms : db.perms

    if !haskey(dispatch, case_key)
        if !haskey(perm_table, case_key)
            return Dict{Vector{Int},Int}()
        end
        if is_dual
            dispatch[case_key] = _build_case_dispatch_raw(perm_table[case_key])
        else
            case = InvariantCase(case_key)
            dispatch[case_key] = _build_case_dispatch(perm_table[case_key], case)
        end
    end
    dispatch[case_key]
end

"""
    PermToInv(rperm::RPerm; db::InvarDB) -> RInv

Look up the invariant label for a canonical RPerm from the loaded database.

The RPerm's permutation must already be in canonical form (as produced by
`RiemannToPerm`). Returns the corresponding `RInv` with the database index.

For dual invariants (`rperm.case.n_epsilon == 1`), looks up in the dual
permutation tables.

Throws `ArgumentError` if the permutation is not found in the database.
"""
function PermToInv(rperm::RPerm; db::InvarDB)::RInv
    case_key = rperm.case.deriv_orders
    is_dual = rperm.case.n_epsilon == 1
    label = is_dual ? "dual database" : "database"

    perm_to_index = _ensure_case_dispatch(db, case_key, is_dual)

    if isempty(perm_to_index)
        throw(
            ArgumentError(
                "Case $case_key not found in $label. " *
                "Load the database with LoadInvarDB first.",
            ),
        )
    end

    # For non-dual: dispatch contains canonical involutions, input is already canonical
    # For dual: dispatch contains raw perms from DB, input used directly
    lookup_key = rperm.perm

    if !haskey(perm_to_index, lookup_key)
        throw(
            ArgumentError(
                "Permutation $(rperm.perm) not found in $label for case $case_key. " *
                "The permutation may not be in canonical form, or the database may be incomplete.",
            ),
        )
    end

    RInv(rperm.metric, rperm.case, perm_to_index[lookup_key])
end

"""
    InvToPerm(rinv::RInv; db::InvarDB) -> RPerm

Reverse lookup: given an RInv, return the canonical RPerm from the database.

For dual invariants (`rinv.case.n_epsilon == 1`), looks up in the dual
permutation tables.

Throws `ArgumentError` if the invariant index is not found.
"""
function InvToPerm(rinv::RInv; db::InvarDB)::RPerm
    case_key = rinv.case.deriv_orders
    is_dual = rinv.case.n_epsilon == 1

    perm_table = is_dual ? db.dual_perms : db.perms
    label = is_dual ? "dual database" : "database"

    if !haskey(perm_table, case_key)
        throw(
            ArgumentError(
                "Case $case_key not found in $label. " *
                "Load the database with LoadInvarDB first.",
            ),
        )
    end

    index_to_perm = perm_table[case_key]
    if !haskey(index_to_perm, rinv.index)
        throw(
            ArgumentError(
                "Invariant index $(rinv.index) not found in $label for case $case_key. " *
                "Valid range: 1..$(length(index_to_perm)).",
            ),
        )
    end

    db_perm = index_to_perm[rinv.index]
    if is_dual
        # Dual perms stored as-is (involutions); return directly
        RPerm(rinv.metric, rinv.case, db_perm)
    else
        # Non-dual: convert from Invar labeling to involution and canonicalize
        invol = _invar_perm_to_involution(db_perm)
        canon, _ = _canonicalize_contraction_perm(invol, rinv.case)
        RPerm(rinv.metric, rinv.case, canon)
    end
end

# ============================================================
# Phase 6: InvSimplify — Multi-Level Simplification
# ============================================================

"""
A linear combination of RInv terms: [(coefficient, RInv), ...].
"""
const InvExpr = Vector{Tuple{Rational{Int},RInv}}

"""
    InvSimplify(rinv::RInv, level::Int=6; db::InvarDB, dim=nothing) -> InvExpr

Simplify a single Riemann invariant using pre-computed database rules.
Returns a linear combination of independent invariants.

Levels:

  - 1: identity (no simplification)
  - 2: cyclic identity rules
  - 3: + Bianchi identity rules
  - 4: + CovD commutation rules
  - 5: + dimension-dependent rules (requires integer `dim`)
  - 6: + dual reduction rules (requires `dim == 4`)

Source: Invar.m:628-678
"""
function InvSimplify(
    rinv::RInv,
    level::Int=6;
    db::Union{InvarDB,Nothing}=nothing,
    dim::Union{Int,Nothing}=nothing,
)
    _db = (db === nothing ? _ensure_invar_db() : db)::InvarDB
    return InvSimplify(Tuple{Rational{Int},RInv}[(1 // 1, rinv)], level; db=_db, dim=dim)
end

"""
    InvSimplify(expr::InvExpr, level::Int=6; db::InvarDB, dim=nothing) -> InvExpr

Simplify a linear combination of Riemann invariants.

Dual invariants (`n_epsilon == 1`) require `dim == 4`. An `ArgumentError` is
raised if any dual term is present and `dim` is not 4.
"""
function InvSimplify(
    expr::InvExpr,
    level::Int=6;
    db::Union{InvarDB,Nothing}=nothing,
    dim::Union{Int,Nothing}=nothing,
)
    isempty(expr) && return expr
    _db = (db === nothing ? _ensure_invar_db() : db)::InvarDB

    # Validate: dual invariants require dim == 4
    for (_, rinv) in expr
        if rinv.case.n_epsilon == 1 && dim != 4
            throw(
                ArgumentError(
                    "Dual invariants (n_epsilon=1) require dim=4, got dim=$dim. " *
                    "Dual Riemann invariants involving the Levi-Civita tensor " *
                    "are only defined in 4 dimensions.",
                ),
            )
        end
    end

    level <= 1 && return _collect_inv_terms(expr)

    result = _apply_step_rules(expr, 2, _db)
    level >= 3 && (result = _apply_step_rules(result, 3, _db))
    level >= 4 && (result = _apply_step_rules(result, 4, _db))
    if level >= 5 && dim isa Int
        result = _apply_step_rules(result, 5, _db; dim=dim)
    end
    if level >= 6 && dim isa Int && dim == 4
        result = _apply_step_rules(result, 6, _db; dim=dim)
    end

    _collect_inv_terms(result)
end

"""
    _apply_step_rules(expr::InvExpr, step::Int, db::InvarDB; dim::Int=4) -> InvExpr

Apply substitution rules from database step to each term in the expression.
Dependent invariants are replaced with linear combinations of independent ones.

For dual invariants (`n_epsilon == 1`), uses `db.dual_rules` instead of `db.rules`.
"""
function _apply_step_rules(expr::InvExpr, step::Int, db::InvarDB; dim::Int=4)
    result = InvExpr()
    for (coeff, rinv) in expr
        is_dual = rinv.case.n_epsilon == 1
        rule_table = is_dual ? db.dual_rules : db.rules
        step_rules = get(rule_table, step, nothing)

        if isnothing(step_rules)
            push!(result, (coeff, rinv))
            continue
        end

        case_key = rinv.case.deriv_orders
        case_rules = get(step_rules, case_key, nothing)

        if !isnothing(case_rules) && haskey(case_rules, rinv.index)
            # Dependent invariant — substitute using the rule
            for (ind, rule_coeff) in case_rules[rinv.index]
                push!(result, (coeff * rule_coeff, RInv(rinv.metric, rinv.case, ind)))
            end
        else
            # Independent at this step — keep it
            push!(result, (coeff, rinv))
        end
    end

    result
end

"""
    _collect_inv_terms(expr::InvExpr) -> InvExpr

Combine like terms (same RInv) and remove zeros. Returns sorted result.
"""
function _collect_inv_terms(expr::InvExpr)::InvExpr
    combined = Dict{RInv,Rational{Int}}()
    for (coeff, rinv) in expr
        combined[rinv] = get(combined, rinv, 0 // 1) + coeff
    end

    result = InvExpr()
    for (rinv, coeff) in combined
        coeff != 0 && push!(result, (coeff, rinv))
    end

    sort!(result; by=t -> (t[2].case.deriv_orders, t[2].index))
    result
end

# ============================================================
# Phase 7: RiemannSimplify — End-to-End Pipeline
# ============================================================

"""
    RiemannSimplify(expr, metric; covd, level, curvature_relations, db, dim) -> String

Simplify a Riemann scalar expression using the Invar database.

Pipeline: parse → RiemannToPerm → PermToInv → InvSimplify → InvToPerm → PermToRiemann.

# Arguments

  - `expr::String`: tensor expression (fully contracted scalar)
  - `metric::Symbol`: the metric symbol
  - `covd::Symbol=metric`: covariant derivative name (determines tensor prefixes)
  - `level::Int=6`: InvSimplify level (1-6)
  - `curvature_relations::Bool=false`: replace contracted Riemanns with Ricci/RicciScalar
  - `db::InvarDB`: loaded Invar database
  - `dim::Union{Int,Nothing}=nothing`: manifold dimension (needed for levels 5-6)

# Returns

A simplified tensor expression string, or `"0"` if all terms cancel.

Source: Invar.m:834-839
"""
function RiemannSimplify(
    expr::AbstractString,
    metric::Symbol;
    covd::Symbol=metric,
    level::Int=6,
    curvature_relations::Bool=false,
    db::Union{InvarDB,Nothing}=nothing,
    dim::Union{Int,Nothing}=nothing,
)::String
    _db = (db === nothing ? _ensure_invar_db() : db)::InvarDB
    s = String(strip(expr))
    (s == "0" || isempty(s)) && return "0"

    # Convert expression to RPerm terms
    rperm_result = RiemannToPerm(s, metric; covd=covd)

    # Normalize to a list of (coefficient, RPerm)
    rperm_terms = if rperm_result isa RPerm
        Tuple{Rational{Int},RPerm}[(1 // 1, rperm_result)]
    else
        rperm_result::Vector{Tuple{Rational{Int},RPerm}}
    end

    # Convert to InvExpr via PermToInv
    inv_terms = InvExpr()
    for (coeff, rperm) in rperm_terms
        # DB lookup REQUIRES canonical form
        cp, cs = _canonicalize_contraction_perm(rperm.perm, rperm.case)
        _rperm = RPerm(rperm.metric, rperm.case, cp)
        rinv = PermToInv(_rperm; db=_db)
        push!(inv_terms, (coeff * cs, rinv))
    end

    # Simplify
    simplified = InvSimplify(inv_terms, level; db=_db, dim=dim)
    isempty(simplified) && return "0"

    # Convert back to tensor expression
    _inv_expr_to_string(
        simplified; covd=covd, curvature_relations=curvature_relations, db=_db
    )
end

"""
    _inv_expr_to_string(expr::InvExpr; covd, curvature_relations, db) -> String

Convert a simplified InvExpr back to a tensor expression string.
"""
function _inv_expr_to_string(
    expr::InvExpr;
    covd::Symbol,
    curvature_relations::Bool=false,
    db::Union{InvarDB,Nothing}=nothing,
)::String
    isempty(expr) && return "0"
    _db = (db === nothing ? _ensure_invar_db() : db)::InvarDB

    parts = String[]
    for (i, (coeff, rinv)) in enumerate(expr)
        rperm = InvToPerm(rinv; db=_db)
        tensor = PermToRiemann(rperm; covd=covd, curvature_relations=curvature_relations)

        if i == 1
            # First term: include sign in coefficient
            if coeff == 1 // 1
                push!(parts, tensor)
            elseif coeff == -1 // 1
                push!(parts, "-" * tensor)
            else
                push!(parts, _format_rational(coeff) * " " * tensor)
            end
        else
            # Subsequent terms: use + or - separator
            abs_coeff = abs(coeff)
            sign = coeff > 0 ? " + " : " - "
            if abs_coeff == 1 // 1
                push!(parts, sign * tensor)
            else
                push!(parts, sign * _format_rational(abs_coeff) * " " * tensor)
            end
        end
    end

    join(parts)
end

"""
Format a rational coefficient as a string. Integers omit the denominator.
"""
function _format_rational(r::Rational{Int})::String
    if denominator(r) == 1
        string(numerator(r))
    else
        "(" * string(numerator(r)) * "/" * string(denominator(r)) * ")"
    end
end

# ============================================================
# Lazy Database Loading
# ============================================================

"""
Global cached InvarDB instance. Loaded on first access via `_ensure_db_loaded`.
"""
_invar_db::Union{Nothing,InvarDB} = nothing

"""
    _ensure_invar_db(; dbdir::String="", dim::Int=4) -> InvarDB

Load the Invar database if not already cached. Returns the cached instance.
If `dbdir` is empty, searches standard resource paths.
"""
function _ensure_invar_db(dbdir::String=""; dim::Int=4)::InvarDB
    global _invar_db
    if _invar_db === nothing
        path = if isempty(dbdir)
            # Default to resources/xAct/Invar relative to project root
            joinpath(@__DIR__, "..", "resources", "xAct", "Invar")
        else
            dbdir
        end
        _invar_db = LoadInvarDB(path; dim=dim)
    end
    return _invar_db::InvarDB
end

"""
    _reset_invar_db!()

Clear the cached InvarDB instance. Called by `reset_state!` in xAct.jl.
"""
function _reset_invar_db!()
    global _invar_db
    global _perm_dispatch
    global _dual_perm_dispatch
    _invar_db = nothing
    empty!(_perm_dispatch)
    empty!(_dual_perm_dispatch)
end

end # module XInvar
