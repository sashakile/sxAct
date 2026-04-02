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
    # Pre-compile the 3 replacement patterns (stable across all brackets)
    pat_a = _label_pattern(label_a)
    pat_b = _label_pattern(label_b)
    pat_tmp = _label_pattern("__TMP__")

    # Only substitute inside bracket groups [...], leaving tensor names untouched
    result = IOBuffer()
    i = 1
    while i <= ncodeunits(expr)
        if expr[i] == '['
            j = findnext(']', expr, i)
            isnothing(j) && error("_swap_indices: unmatched '[' in expression")
            bracket = SubString(expr, i, j)
            bracket = replace(bracket, pat_a => "__TMP__")
            bracket = replace(bracket, pat_b => label_a)
            bracket = replace(bracket, pat_tmp => label_b)
            write(result, bracket)
            i = j + 1
        else
            write(result, expr[i])
            i += 1
        end
    end
    String(take!(result))
end

"""
Build a label-boundary regex for _swap_indices (cached per label string).
"""
function _label_pattern(label::AbstractString)::Regex
    pat = "(?<=[\\[,\\s-]|^)" * _regex_escape(label) * "(?=[\\],\\s-]|\$)"
    Regex(String(pat))
end

"""
Replace a whole index label inside a bracket string, bounded by delimiters.
"""
function _replace_label(s::AbstractString, old::AbstractString, new::AbstractString)
    # Boundaries: start of string, [, ], comma, -, whitespace
    pat_str = "(?<=[\\[,\\s-]|^)" * _regex_escape(old) * "(?=[\\],\\s-]|\$)"
    pat = Regex(String(pat_str))
    replace(s, pat => new)
end

"""
Escape special regex characters in a string.
"""
function _regex_escape(s::AbstractString)::String
    String(replace(String(s), r"([.+*?^${}()|\\[\]])" => s"\\\1"))
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
        new_factors = FactorNode[]
        # Add g_{ab} (same variance as free indices)
        push!(new_factors, TensorFactor(metric_name, [g_a, g_b]))
        # Add g^{cd} (opposite variance for contraction)
        m_da = startswith(g_a, "-") ? d1 : "-$d1"
        m_db = startswith(g_b, "-") ? d2 : "-$d2"
        contra_d1 = startswith(g_a, "-") ? d1 : "-$d1"
        contra_d2 = startswith(g_b, "-") ? d2 : "-$d2"
        push!(new_factors, TensorFactor(metric_name, [contra_d1, contra_d2]))
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
            push!(new_factors, TensorFactor(f.tensor_name, new_idxs))
        end
        push!(sub_terms, TermAST(-term.coeff * (1 // dim), new_factors))
    end

    # Serialize the subtraction terms
    sub_str = _serialize_terms(sub_terms)

    # Combine: original + subtraction, then simplify
    combined = "$canon + $sub_str"
    Simplify(combined)
end
