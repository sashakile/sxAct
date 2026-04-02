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
        _is_zero_term(contracted) && continue
        push!(result_terms, contracted)
    end

    isempty(result_terms) && return "0"

    # Run ToCanonical on the contracted result
    ToCanonical(_serialize_terms(result_terms))
end

"""
Return the bare index label (strip leading '-').
"""
_bare(s::AbstractString)::String = startswith(s, "-") ? String(s[2:end]) : String(s)

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
function _factor_as_metric(f::TensorFactor)::Union{Tuple{Symbol,MetricObj,Symbol},Nothing}
    length(f.indices) == 2 || return nothing
    covd = get(_metric_name_index, f.tensor_name, nothing)
    isnothing(covd) && return nothing
    metric = _metrics[covd]
    i1_cov = _is_covariant(f.indices[1])
    i2_cov = _is_covariant(f.indices[2])
    if !i1_cov && !i2_cov
        return (covd, metric, :contravariant)  # g^{ab}
    elseif i1_cov && i2_cov
        return (covd, metric, :covariant)       # g_{ab}
    end
    nothing
end
# CovDFactor is never a metric
_factor_as_metric(::CovDFactor)::Nothing = nothing

"""
Apply ContractMetric to a single term.
Returns the contracted TermAST, or nothing if the term is zero.
"""
function _contract_term(term::TermAST)::TermAST
    # Iteratively contract metrics until none remain
    current = term
    max_iters = 20
    for _ in 1:max_iters
        result = _contract_one_metric(current)
        if _is_zero_term(result)
            return ZERO_TERM
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
    _apply_trace_rules(...) → (:zero, nothing) | (:replaced, TermAST) | (:none, nothing)

Dispatch trace rules through registries. Returns:

  - `(:zero, nothing)` when the trace vanishes (traceless tensor)
  - `(:replaced, term)` when a trace rule fired
  - `(:none, nothing)` when no rule matched (caller should fall through)
"""
function _apply_trace_rules(
    term::TermAST,
    factors::Vector{FactorNode},
    new_other::TensorFactor,
    metric_pos::Int,
    other_pos::Int,
    has_1::Bool,
    has_2::Bool,
    bare_1::String,
    bare_2::String,
    metric_obj::MetricObj,
)::Tuple{Symbol,Union{TermAST,Nothing}}
    # Traceless tensor → term vanishes
    if new_other.tensor_name in _traceless_tensors
        return (:zero, nothing)
    end
    # Registered trace scalar (e.g. tr(Einstein) → coeff * RicciScalar)
    if has_1 && has_2 && haskey(_trace_scalars, new_other.tensor_name)
        remaining_free = [
            idx for
            idx in new_other.indices if !(_bare(idx) == bare_1 || _bare(idx) == bare_2)
        ]
        if isempty(remaining_free)
            (scalar_name, coeff_int) = _trace_scalars[new_other.tensor_name]
            new_factors = FactorNode[]
            for (k, ff) in enumerate(factors)
                k == metric_pos && continue
                k == other_pos && continue
                push!(new_factors, ff)
            end
            push!(new_factors, TensorFactor(scalar_name, String[]))
            return (:replaced, TermAST(term.coeff * coeff_int, new_factors))
        end
    end
    # Metric self-contraction → dimension
    if has_1 && has_2
        other_as_metric = _factor_as_metric(new_other)
        if !isnothing(other_as_metric)
            (_, other_metric_obj, _) = other_as_metric
            manifold = get(_manifolds, other_metric_obj.manifold, nothing)
            if !isnothing(manifold) && other_metric_obj.name == metric_obj.name
                remaining = [
                    ff for
                    (k, ff) in enumerate(factors) if k != metric_pos && k != other_pos
                ]
                return (:replaced, TermAST(term.coeff * manifold.dimension, remaining))
            end
        end
    end
    return (:none, nothing)
end

"""
Find one metric factor and contract it with another factor (or apply a trace rule).
Returns the updated TermAST, the same TermAST if no metric found, or nothing if zero.
"""
function _contract_one_metric(term::TermAST)::TermAST
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
        # CovDFactor cannot be contracted via metric (needs Phase C unification)
        other isa CovDFactor && continue

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
        new_other = TensorFactor(other.tensor_name, new_indices)

        # Detect traces:
        # 1. Double contraction (has_1 && has_2 against the same factor) is always a trace.
        #    For a rank-2 tensor: full trace (scalar).  For rank-4: trace on 2 slots.
        # 2. Self-trace after substitution: same bare label appears twice in new_indices.
        bare_new = [_bare(idx) for idx in new_indices]
        self_trace_from_subst = length(unique(bare_new)) < length(bare_new)
        is_trace = (has_1 && has_2) || self_trace_from_subst

        if is_trace && !isnothing(metric_obj)
            (status, trace_term) = _apply_trace_rules(
                term,
                factors,
                new_other,
                metric_pos,
                j,
                has_1,
                has_2,
                bare_1,
                bare_2,
                metric_obj,
            )
            status == :zero && return ZERO_TERM
            if status == :replaced && !isnothing(trace_term)
                return trace_term::TermAST
            end
            # :none → no special rule, fall through to normal contraction
        end

        # Remove the metric factor, replace `other` with `new_other`
        new_factors = FactorNode[]
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
