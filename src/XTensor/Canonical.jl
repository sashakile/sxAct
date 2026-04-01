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
Zero-coefficient sentinel: returned instead of `nothing` to keep TermAST endomorphism.
"""
const ZERO_TERM = TermAST(0 // 1, FactorAST[])
_is_zero_term(t::TermAST) = t.coeff == 0 && isempty(t.factors)

"""
Serialize a structured key to a canonical string for O(1) Dict hashing.
"""
function _term_key_str(factors::_StructKey)::String
    join(["$(n)[$(join(idxs,","))]" for (n, idxs) in factors], " ")
end
_term_key_str(factors::Vector{FactorAST})::String = _term_key_str([
    (f.tensor_name, f.indices) for f in factors
])

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
            paren_depth < 0 &&
                error("_parse_sum!: unbalanced parentheses — extra ')' in expression")
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

    paren_depth != 0 &&
        error("_parse_sum!: unbalanced parentheses — unclosed '(' in expression")

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
        (pos > n || s[pos] != '[') &&
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

        # Detect CovD bracket syntax: Name[idx][operand] — not supported here
        typos = pos
        while typos <= n && isspace(s[typos])
            typos += 1
        end
        if typos <= n && s[typos] == '['
            error(
                "CovD bracket syntax $(tensor_name)[...][...] is not supported by " *
                "ToCanonical/Contract. Use SortCovDs or CommuteCovDs for covariant " *
                "derivative expressions.",
            )
        end
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
    coeff_map::Dict{String,Rational{Int}},
    struct_map::Dict{String,_StructKey},
    key_order::Vector{String},
)
    _apply_identities!(coeff_map, struct_map, key_order)
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
    haskey(_tensors, tensor_sym) || throw(
        ArgumentError(
            "CommuteCovDs: tensor $tensor_name not registered. Register it with def_tensor!(:$tensor_name, indices, manifold).",
        ),
    )
    manifold_sym = _tensors[tensor_sym].manifold
    haskey(_manifolds, manifold_sym) || throw(
        ArgumentError(
            "CommuteCovDs: manifold $manifold_sym not found. Register it with def_manifold!(:$manifold_sym, dim, indices).",
        ),
    )
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

# ============================================================
# SortCovDs — sort covariant derivatives into canonical order
# ============================================================

"""
    _extract_covd_chain(term::AbstractString, covd_str::AbstractString)

Find a CovD chain in a single term string and return:
(covd_indices, inner_tensor_name, inner_slots, prefix, suffix)

where `covd_indices` is the list of CovD indices in outer-to-inner order,
`inner_tensor_name` is the innermost tensor name (e.g. "T"),
`inner_slots` is the list of slot strings (e.g. ["-a","-b"]),
`prefix` is everything before the CovD chain (coefficient etc.), and
`suffix` is everything after the CovD chain.

Returns `nothing` if no CovD chain with ≥ 2 derivatives is found.
"""
function _extract_covd_chain(
    term::AbstractString,
    covd_str::AbstractString;
    cd_start_pat::Union{Regex,Nothing}=nothing,
)
    # Find the start of a CovD chain: COVD[idx][...]
    # Must NOT be preceded by a word character (to avoid matching "RiemannCOVD[")
    if cd_start_pat === nothing
        re_esc(s)::String = replace(s, r"([-\[\].\^$*+?{}|()])" => s"\\\1")
        cd_start_pat = Regex("(?<![A-Za-z0-9_])" * re_esc(covd_str) * raw"\[")
    end
    m = match(cd_start_pat, term)
    isnothing(m) && return nothing

    chain_start = m.offset
    prefix = term[1:(chain_start - 1)]

    # Parse the CovD chain starting at chain_start
    # Format: COVD[-idx][COVD[-idx][...COVD[-idx][TENSOR[slots]]...]]
    covd_indices = String[]
    pos = chain_start
    cd_len = length(covd_str)

    while pos <= length(term)
        remaining = SubString(term, pos)
        if !startswith(remaining, covd_str * "[")
            break
        end

        # Skip past "COVD["
        pos += cd_len + 1

        # Read the index until ']'
        idx_start = pos
        while pos <= length(term) && term[pos] != ']'
            pos += 1
        end
        pos > length(term) && break

        idx = term[idx_start:(pos - 1)]
        push!(covd_indices, idx)
        pos += 1  # skip ']'

        # Now expect '[' for the next level
        pos > length(term) && break
        term[pos] != '[' && break
        pos += 1  # skip '['
    end

    length(covd_indices) < 2 && return nothing

    # pos is at the start of the innermost expression: TENSOR[slots]
    # Parse tensor name
    tensor_start = pos
    while pos <= length(term) && term[pos] != '['
        pos += 1
    end
    pos > length(term) && return nothing
    inner_tensor_name = term[tensor_start:(pos - 1)]

    # Parse slots: everything between the first [ and the matching ]
    pos += 1  # skip '['
    slots_start = pos
    bracket_depth = 1
    while pos <= length(term) && bracket_depth > 0
        if term[pos] == '['
            bracket_depth += 1
        elseif term[pos] == ']'
            bracket_depth -= 1
        end
        bracket_depth > 0 && (pos += 1)
    end
    inner_slots_str = term[slots_start:(pos - 1)]
    inner_slots = [strip(s) for s in split(inner_slots_str, ",")]

    # Skip past the closing ']' for the tensor slots, then the chain closing brackets
    pos += 1  # skip ']' for tensor slots
    # Now there should be length(covd_indices) closing brackets
    for _ in 1:length(covd_indices)
        pos > length(term) && break
        pos += 1  # skip each ']'
    end
    suffix = pos <= length(term) ? term[pos:end] : ""

    (covd_indices, inner_tensor_name, inner_slots, strip(prefix), strip(suffix))
end

"""
    _rebuild_covd_expr(covd_str, covd_indices, tensor_name, slots)

Rebuild a CovD chain expression from parts:
covd[i1][covd[i2][...covd[in][tensor[slots]]...]]
"""
function _rebuild_covd_expr(
    covd_str::AbstractString,
    covd_indices::Vector{<:AbstractString},
    tensor_name::AbstractString,
    slots::Vector{<:AbstractString},
)::String
    result = tensor_name * "[" * join(slots, ",") * "]"
    for i in length(covd_indices):-1:1
        result = covd_str * "[" * covd_indices[i] * "][" * result * "]"
    end
    result
end

"""
    _find_unsorted_pair(covd_indices::Vector{String}) -> Union{Int, Nothing}

Find the first adjacent pair of CovD indices that is out of canonical
(lexicographic) order. Returns the index `i` such that
`covd_indices[i] > covd_indices[i+1]`, or `nothing` if all are sorted.

Comparison is on the bare index name (stripping the leading '-').
"""
function _find_unsorted_pair(covd_indices::Vector{String})::Union{Int,Nothing}
    for i in 1:(length(covd_indices) - 1)
        bare_i = lstrip(covd_indices[i], '-')
        bare_next = lstrip(covd_indices[i + 1], '-')
        if bare_i > bare_next
            return i
        end
    end
    nothing
end

"""
    _split_expression_terms(expr::AbstractString) -> Vector{String}

Split a tensor expression string into additive terms, preserving signs.
Each returned term includes its leading sign ('+' or '-') if not the first term.
Returns individual term strings that can be recombined with ' '.
"""
function _split_expression_terms(expr::AbstractString)::Vector{String}
    s = strip(expr)
    (s == "0" || isempty(s)) && return String[]

    terms = String[]
    pos = 1
    n = length(s)
    current_start = 1
    bracket_depth = 0
    paren_depth = 0

    while pos <= n
        c = s[pos]
        if c == '['
            bracket_depth += 1
            pos += 1
        elseif c == ']'
            bracket_depth -= 1
            pos += 1
        elseif c == '('
            paren_depth += 1
            pos += 1
        elseif c == ')'
            paren_depth -= 1
            pos += 1
        elseif (c == '+' || c == '-') && pos > 1 && bracket_depth == 0 && paren_depth == 0
            chunk = strip(s[current_start:(pos - 1)])
            if !isempty(chunk) && chunk != "+"
                push!(terms, chunk)
            end
            current_start = pos
            pos += 1
        else
            pos += 1
        end
    end

    chunk = strip(s[current_start:n])
    if !isempty(chunk) && chunk != "+"
        push!(terms, chunk)
    end

    terms
end

"""
    _commute_covd_pair(covd_str, covd_indices, swap_pos, tensor_name, inner_slots, manifold_sym)

Commute the adjacent CovD pair at positions `swap_pos` and `swap_pos+1` in a
CovD chain, producing the swapped chain plus Riemann correction terms.

The Riemann correction acts on ALL effective indices below the swap point:
the CovD indices from `swap_pos+2` to end, plus the innermost tensor's slots.

Returns a vector of string terms (the swapped main term + correction terms).
"""
function _commute_covd_pair(
    covd_str::AbstractString,
    covd_indices::Vector{String},
    swap_pos::Int,
    tensor_name::AbstractString,
    inner_slots::Vector{<:AbstractString},
    manifold_sym::Symbol,
)::Vector{String}
    idx1 = covd_indices[swap_pos]
    idx2 = covd_indices[swap_pos + 1]

    # Effective indices below the swap point: all CovD indices after the pair + tensor slots.
    # These are the free indices of the composite expression that ∇_{idx1} ∇_{idx2} acts on.
    # Each gets a Riemann correction term.
    lower_covd_indices = String[string(ci) for ci in covd_indices[(swap_pos + 2):end]]
    effective_slots = vcat(lower_covd_indices, String[string(s) for s in inner_slots])

    manifold_indices = _manifolds[manifold_sym].index_labels
    riemann_name = "Riemann" * covd_str

    # Collect all used index names
    used_idx = Set{String}()
    for ci in covd_indices
        push!(used_idx, lstrip(ci, '-'))
    end
    for s in inner_slots
        push!(used_idx, lstrip(string(s), '-'))
    end

    # Pick fresh dummy indices
    dummies = String[]
    for idx_sym in manifold_indices
        name = string(idx_sym)
        if name ∉ used_idx
            push!(dummies, name)
            push!(used_idx, name)
            length(dummies) >= length(effective_slots) && break
        end
    end
    length(dummies) < length(effective_slots) &&
        error("SortCovDs: not enough fresh indices in manifold $manifold_sym")

    # Build the swapped main term: swap positions swap_pos and swap_pos+1.
    # The FULL chain is preserved, only the two indices are swapped.
    swapped_indices = copy(covd_indices)
    swapped_indices[swap_pos] = idx2
    swapped_indices[swap_pos + 1] = idx1
    outer_indices = String[string(ci) for ci in covd_indices[1:(swap_pos - 1)]]

    main_term = _rebuild_covd_expr(
        covd_str, swapped_indices, tensor_name, String[string(s) for s in inner_slots]
    )

    parts = [main_term]

    # Build correction terms for each effective slot below the swap.
    #
    # The correction term for each slot j of the inner composite expression is:
    #   ±R^d_{j, idx1, idx2} * [inner_with_j_replaced_by_d]
    #
    # where "inner" is the CovD chain below the swap point: ∇_{a_{i+2}} ... ∇_{a_n} T[slots].
    # The correction is wrapped by the OUTER CovDs (positions 1..swap_pos-1) if any.
    # Importantly, the swapped pair (idx1, idx2) is NOT in the correction CovD chain —
    # the Riemann tensor takes their place.
    for (i, slot) in enumerate(effective_slots)
        covariant = startswith(slot, "-")
        index_name = lstrip(slot, '-')
        dummy = dummies[i]

        if i <= length(lower_covd_indices)
            # This slot is a CovD index below the swap — replace it in the inner chain
            new_lower = copy(lower_covd_indices)
            new_lower[i] = covariant ? "-" * dummy : dummy
            corr_inner = _rebuild_covd_expr(
                covd_str, new_lower, tensor_name, String[string(s) for s in inner_slots]
            )
        else
            # This slot is a tensor index — replace it in the tensor
            slot_idx = i - length(lower_covd_indices)
            new_slots = String[string(s) for s in inner_slots]
            new_slots[slot_idx] = covariant ? "-" * dummy : dummy
            corr_inner = _rebuild_covd_expr(
                covd_str, lower_covd_indices, tensor_name, new_slots
            )
        end

        # Wrap correction in outer CovDs (if any exist above the swap)
        corr_wrapped = corr_inner
        for oi in length(outer_indices):-1:1
            corr_wrapped = covd_str * "[" * outer_indices[oi] * "][" * corr_wrapped * "]"
        end

        if covariant
            riemann_args = "-" * index_name * "," * dummy * "," * idx1 * "," * idx2
            correction = "- " * riemann_name * "[" * riemann_args * "] " * corr_wrapped
        else
            riemann_args = index_name * ",-" * dummy * "," * idx1 * "," * idx2
            correction = "+ " * riemann_name * "[" * riemann_args * "] " * corr_wrapped
        end
        push!(parts, correction)
    end

    parts
end

"""
    SortCovDs(expr::AbstractString, covd_name::Symbol) → String

Sort all covariant derivatives in an expression into canonical (lexicographic)
order. For each out-of-order pair of adjacent CovDs, applies the commutation
identity to swap them (generating Riemann correction terms), then iterates
until all CovD orderings are canonical.

This is a bubble sort on CovD indices: given a chain like
`CD[-c][CD[-a][CD[-b][T[...]]]]`, it will sort the indices to
`CD[-a][CD[-b][CD[-c][T[...]]]]` plus curvature correction terms.

Arguments:

  - `expr`: String expression potentially containing CovD chains
  - `covd_name`: Symbol name of the covariant derivative (e.g. :CVD)

Returns a string expression with all CovD chains in canonical order.
Non-CovD terms (Riemann corrections) are simplified via `ToCanonical`.
"""
function SortCovDs(expr::AbstractString, covd_name::Symbol)::String
    s = strip(expr)
    (s == "0" || isempty(s)) && return "0"

    covd_str = string(covd_name)

    # Verify that the CovD is registered
    haskey(_metrics, covd_name) ||
        error("SortCovDs: no metric registered for covd $covd_name")

    metric_obj = _metrics[covd_name]
    manifold_sym = metric_obj.manifold

    # Pre-compile the CovD-start pattern (used in _extract_covd_chain + cleanup)
    _re_esc(s)::String = replace(s, r"([-\[\].\^$*+?{}|()])" => s"\\\1")
    covd_start_pat = Regex("(?<![A-Za-z0-9_])" * _re_esc(covd_str) * raw"\[")

    # Iterative bubble sort: keep processing until no unsorted CovD chains remain.
    max_iters = 100
    current = s

    for _ in 1:max_iters
        terms = _split_expression_terms(current)
        isempty(terms) && return "0"

        found_unsorted = false

        for (tidx, term) in enumerate(terms)
            chain = _extract_covd_chain(term, covd_str; cd_start_pat=covd_start_pat)
            isnothing(chain) && continue

            covd_indices, inner_tensor_name, inner_slots, prefix, suffix = chain
            swap_pos = _find_unsorted_pair(covd_indices)
            isnothing(swap_pos) && continue

            found_unsorted = true

            # Commute the unsorted pair
            new_parts = _commute_covd_pair(
                covd_str,
                covd_indices,
                swap_pos,
                inner_tensor_name,
                inner_slots,
                manifold_sym,
            )

            # Prepend prefix and append suffix to each part
            rebuilt_parts = String[]
            for (pi, part) in enumerate(new_parts)
                p = part
                if pi == 1 && !isempty(prefix)
                    p = prefix * " " * p
                end
                if pi == 1 && !isempty(suffix)
                    p = p * " " * suffix
                end
                push!(rebuilt_parts, p)
            end

            # Replace this term with the expanded terms
            terms[tidx] = join(rebuilt_parts, " ")
            current = join(terms, " ")
            break
        end

        !found_unsorted && break
    end

    # Simplify the non-CovD correction terms by canonicalizing them.
    # Split into terms that contain any CovD reference and those that don't.
    # Only the purely non-CovD terms can be safely sent through ToCanonical.
    terms = _split_expression_terms(current)
    isempty(terms) && return "0"

    covd_terms = String[]
    plain_terms = String[]
    # Reuse pre-compiled covd_start_pat (same pattern as _extract_covd_chain)
    for term in terms
        if !isnothing(match(covd_start_pat, term))
            push!(covd_terms, term)
        else
            push!(plain_terms, term)
        end
    end

    # Canonicalize plain terms together
    if !isempty(plain_terms)
        plain_expr = join(plain_terms, " ")
        plain_simplified = ToCanonical(plain_expr)
        if plain_simplified != "0"
            push!(covd_terms, plain_simplified)
        end
    end

    isempty(covd_terms) && return "0"

    # Build result, handling signs properly
    result_parts = String[]
    for (i, term) in enumerate(covd_terms)
        t = strip(term)
        isempty(t) && continue
        if i == 1
            push!(result_parts, t)
        elseif startswith(t, "-") || startswith(t, "- ")
            push!(result_parts, t)
        elseif startswith(t, "+") || startswith(t, "+ ")
            push!(result_parts, t)
        else
            push!(result_parts, "+ " * t)
        end
    end
    isempty(result_parts) && return "0"
    join(result_parts, " ")
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
        _is_zero_term(result) || push!(canon_terms, result)
    end

    isempty(canon_terms) && return "0"

    # Collect like terms: String key for O(1) hashing, structured data for identity/serialization
    coeff_map = Dict{String,Rational{Int}}()
    struct_map = Dict{String,_StructKey}()
    key_order = String[]

    for term in canon_terms
        skey = _term_key_str(term.factors)
        if !haskey(coeff_map, skey)
            coeff_map[skey] = 0 // 1
            struct_map[skey] = [(f.tensor_name, copy(f.indices)) for f in term.factors]
            push!(key_order, skey)
        end
        coeff_map[skey] += term.coeff
    end

    # Apply Bianchi identity reduction: R_{a[bcd]} = 0
    _apply_identities!(coeff_map, struct_map, key_order)

    # Drop zero-coefficient terms
    keys_nonzero = filter(k -> coeff_map[k] != 0, key_order)
    isempty(keys_nonzero) && return "0"

    # Sort keys for deterministic output (String keys sort lexicographically)
    sort!(keys_nonzero)

    # Serialize
    _serialize(keys_nonzero, coeff_map)
end

"""
Canonicalize a single term; returns nothing if the term is zero.
"""
function _canonicalize_term(term::TermAST)::TermAST
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
            return ZERO_TERM
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
function _serialize(keys::Vector{String}, coeff_map::Dict{String,Rational{Int}})::String
    parts = Tuple{Rational{Int},String}[]

    for skey in keys
        c = coeff_map[skey]
        c == 0 && continue

        mono = skey  # already a canonical string representation
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
