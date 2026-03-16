# InvarDB — Database loading and rule parser for the Invar pipeline
# Copyright (C) 2026 sxAct Contributors
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

"""
    InvarDB

Parser and loader for the Wolfram Invar database — pre-computed permutation
bases and simplification rules for Riemann invariants.

Database directory structure (relative to dbdir):
    Riemann/1/RInv-{case}-1       Step 1: Permutation basis (Maple format)
    Riemann/1/DInv-{case}-1       Step 1: Dual permutation basis (Maple format)
    Riemann/2/RInv-{case}-2       Step 2: Cyclic identity rules (Mathematica format)
    Riemann/3/RInv-{case}-3       Step 3: Bianchi identity rules
    Riemann/4/RInv-{case}-4       Step 4: CovD commutation rules
    Riemann/5_4/RInv-{case}-5_4   Step 5: Dimension-dependent rules (dim=4)
    Riemann/6_4/RInv-{case}-6_4   Step 6: Dual reduction rules (dim=4)

Reference: Wolfram Invar.m ReadInvarPerms (~line 284), ReadInvarRules (~line 293),
           filename (~line 255-260), intercase (~line 252).
"""

export InvarDB, LoadInvarDB
export read_invar_perms, read_invar_rules

# ============================================================
# InvarDB struct
# ============================================================

"""
    InvarDB

Holds all loaded database state: permutation bases (step 1) and
substitution rules (steps 2-6).

Fields:

  - `perms`:      case → (index → permutation in images notation)
  - `dual_perms`: case → (index → permutation in images notation)
  - `rules`:      step → (case → (dependent_index → [(independent_index, coefficient)]))
  - `dual_rules`: step → (case → (dependent_index → [(independent_index, coefficient)]))
"""
struct InvarDB
    perms::Dict{Vector{Int},Dict{Int,Vector{Int}}}
    dual_perms::Dict{Vector{Int},Dict{Int,Vector{Int}}}
    rules::Dict{Int,Dict{Vector{Int},Dict{Int,Vector{Tuple{Int,Rational{Int}}}}}}
    dual_rules::Dict{Int,Dict{Vector{Int},Dict{Int,Vector{Tuple{Int,Rational{Int}}}}}}
end

function Base.show(io::IO, db::InvarDB)
    np = sum(length(v) for v in values(db.perms); init=0)
    ndp = sum(length(v) for v in values(db.dual_perms); init=0)
    nr = sum(sum(length(v) for v in values(d); init=0) for d in values(db.rules); init=0)
    ndr = sum(
        sum(length(v) for v in values(d); init=0) for d in values(db.dual_rules); init=0
    )
    print(
        io,
        "InvarDB(",
        np,
        " perms, ",
        ndp,
        " dual_perms, ",
        nr,
        " rules, ",
        ndr,
        " dual_rules)",
    )
end

# ============================================================
# Filename Helpers
# ============================================================

"""
    _case_to_filename(deriv_orders::Vector{Int}) -> String

Encode a case vector as a filename component.
`[0,0]` → `"0_0"`, `[0]` → `"0"`, `[1,3]` → `"1_3"`.

Matches Wolfram `intercase` (Invar.m:252).
"""
function _case_to_filename(deriv_orders::Vector{Int})
    return join(string.(deriv_orders), "_")
end

"""
    _rinv_filename(step::Int, case::Vector{Int}; dim::Int=0) -> String

Build an RInv filename. Matches Wolfram `filename` (Invar.m:255-256).

    filename[step:(5|6), case, dim] = filename[step, case] * "_" * dim
    filename[step, case] = "RInv-" * intercase(case) * "-" * step
"""
function _rinv_filename(step::Int, case::Vector{Int}; dim::Int=0)
    base = "RInv-" * _case_to_filename(case) * "-" * string(step)
    if step in (5, 6) && dim > 0
        base *= "_" * string(dim)
    end
    return base
end

"""
    _dinv_filename(step::Int, case::Vector{Int}; dim::Int=0) -> String

Build a DInv (dual) filename. Matches Wolfram `dualfilename` (Invar.m:259-260).
"""
function _dinv_filename(step::Int, case::Vector{Int}; dim::Int=0)
    base = "DInv-" * _case_to_filename(case) * "-" * string(step)
    if step == 5 && dim > 0
        base *= "_" * string(dim)
    end
    return base
end

# ============================================================
# Cycle-to-Images Conversion
# ============================================================

"""
    _cycles_to_images(cycles::Vector{Vector{Int}}, degree::Int) -> Vector{Int}

Convert a list of disjoint cycles to images (one-line) notation.

Each cycle `[a, b, c, ...]` means a→b, b→c, ..., last→a.
Fixed points map to themselves.

Example: `[[2,1],[4,3]]` on degree 4 → `[2,1,4,3]`
Example: `[[1,3,2]]` on degree 4 → `[3,2,1,4]` (1→3, 3→2, 2→1, 4→4)
"""
function _cycles_to_images(cycles::Vector{Vector{Int}}, degree::Int)
    images = collect(1:degree)
    for cycle in cycles
        n = length(cycle)
        n <= 1 && continue
        for i in 1:n
            images[cycle[i]] = cycle[mod1(i + 1, n)]
        end
    end
    return images
end

# ============================================================
# Step 1 Parser — Maple format
# ============================================================

"""
    _parse_maple_perm_line(line::String) -> Union{Nothing, Vector{Int}}

Parse a single line of step-1 (Maple format) perm file.

Raw format (from Wolfram Invar database):
RInv[{0,0},1] := [[2,1],[4,3],[6,5],[8,7]];

The Wolfram parser (`ReadInvarPerms`, Invar.m:284):

 1. `readline`: extracts substring after `:=` up to last char before `;`
 2. `replacebrackets`: `[` → `{`, `]` → `}`
 3. `ToExpression`: evaluates to Mathematica list of cycles

We replicate this: extract cycles part, parse the nested lists, convert to images.
Returns `nothing` for blank or comment lines.
"""
function _parse_maple_perm_line(line::AbstractString)
    stripped = strip(line)
    isempty(stripped) && return nothing

    # Find " := " delimiter (Wolfram's readline function)
    assign_pos = findfirst(" := ", stripped)
    assign_pos === nothing && return nothing

    # Extract RHS: everything after " := " and before trailing ";"
    rhs_start = last(assign_pos) + 1
    rhs = strip(stripped[rhs_start:end])

    # Strip trailing semicolon
    if endswith(rhs, ";")
        rhs = rhs[1:(end - 1)]
    end

    # Parse the cycle notation: [[a,b],[c,d],...]
    cycles = _parse_nested_intlist(rhs)
    isempty(cycles) && return nothing

    # Determine degree from max element
    max_elem = maximum(maximum(c) for c in cycles if !isempty(c); init=0)
    max_elem == 0 && return nothing

    return _cycles_to_images(cycles, max_elem)
end

"""
    _parse_nested_intlist(s::String) -> Vector{Vector{Int}}

Parse a string like `[[2,1],[4,3],[6,5],[8,7]]` into a vector of int vectors.
Handles both `[...]` (Maple) and `{...}` (Mathematica) bracket styles.
"""
function _parse_nested_intlist(s::AbstractString)
    result = Vector{Int}[]
    # Normalize brackets
    s = replace(s, '{' => '[', '}' => ']')
    s = strip(s)

    # Must start and end with outer brackets
    if !startswith(s, '[') || !endswith(s, ']')
        return result
    end

    # Strip outer brackets
    inner = s[2:(end - 1)]

    # Parse inner sublists
    depth = 0
    current = ""
    for ch in inner
        if ch == '['
            depth += 1
            if depth == 1
                current = ""
                continue
            end
        elseif ch == ']'
            depth -= 1
            if depth == 0
                # Parse the accumulated numbers
                nums = _parse_int_csv(current)
                !isempty(nums) && push!(result, nums)
                current = ""
                continue
            end
        elseif depth == 0 && ch == ','
            # Skip commas between sublists at depth 0
            continue
        end
        if depth >= 1
            current *= ch
        end
    end

    return result
end

"""
    _parse_int_csv(s::String) -> Vector{Int}

Parse a comma-separated string of integers: `"2,1"` → `[2, 1]`.
"""
function _parse_int_csv(s::AbstractString)
    parts = split(strip(s), r"\s*,\s*")
    result = Int[]
    for p in parts
        p = strip(p)
        isempty(p) && continue
        n = tryparse(Int, p)
        n === nothing && continue
        push!(result, n)
    end
    return result
end

# ============================================================
# Steps 2-6 Parser — Mathematica format
# ============================================================

"""
    _parse_mma_rule(line::String) -> Union{Nothing, Tuple{Int, Vector{Tuple{Int, Rational{Int}}}}}

Parse a single line of steps 2-6 (Mathematica format) rule file.

Format: `RInv[{0,0},3] -> RInv[{0,0},1] - RInv[{0,0},2]`

Returns `(dependent_index, [(independent_index, coefficient), ...])` or `nothing`.

The LHS is always a single `RInv[{case},idx]` or `DualRInv[{case},idx]`.
The RHS is a linear combination of RInv/DualRInv terms with rational coefficients.
"""
function _parse_mma_rule(line::AbstractString)
    stripped = strip(line)
    isempty(stripped) && return nothing

    # Split on " -> " (Mathematica Rule notation)
    arrow_pos = findfirst(" -> ", stripped)
    arrow_pos === nothing && return nothing

    lhs = strip(stripped[1:(first(arrow_pos) - 1)])
    rhs = strip(stripped[(last(arrow_pos) + 1):end])

    # Parse LHS index: extract the last integer argument from RInv[{...},N] or DualRInv[{...},N]
    lhs_idx = _extract_inv_index(lhs)
    lhs_idx === nothing && return nothing

    # Parse RHS: linear combination of RInv/DualRInv terms
    terms = _parse_linear_combination(rhs)
    isempty(terms) && return nothing

    return (lhs_idx, terms)
end

"""
    _extract_inv_index(s::String) -> Union{Nothing, Int}

Extract the invariant index from `RInv[{0,0},3]` or `DualRInv[{0,0},3]` → 3.
"""
function _extract_inv_index(s::AbstractString)
    # Match pattern: ...},N] at the end
    m = match(r"},\s*(\d+)\s*\]$", s)
    m === nothing && return nothing
    return parse(Int, m.captures[1])
end

"""
    _extract_inv_case(s::String) -> Union{Nothing, Vector{Int}}

Extract the case vector from `RInv[{0,0},3]` → [0,0].
"""
function _extract_inv_case(s::AbstractString)
    m = match(r"\{([^}]*)\}", s)
    m === nothing && return nothing
    return _parse_int_csv(m.captures[1])
end

"""
    _parse_linear_combination(s::String) -> Vector{Tuple{Int, Rational{Int}}}

Parse a linear combination of RInv/DualRInv terms.

Examples:

  - `RInv[{0,0},1] - RInv[{0,0},2]` → [(1, 1//1), (2, -1//1)]
  - `2*RInv[{0,0},1]` → [(1, 2//1)]
  - `-3/2*RInv[{0,0},1] + RInv[{0,0},2]` → [(1, -3//2), (2, 1//1)]
  - `sigma*RInv[{0,0},1]` → [(1, 1//1)] with sigma flag
"""
function _parse_linear_combination(s::AbstractString)
    terms = Tuple{Int,Rational{Int}}[]
    s = strip(s)
    isempty(s) && return terms

    # Tokenize: find all RInv[...] or DualRInv[...] occurrences and their coefficients
    # Strategy: use regex to find each term pattern
    #   Optional coefficient (possibly negative, possibly rational, possibly with sigma)
    #   followed by RInv[{...},N] or DualRInv[{...},N]

    # First normalize: ensure + and - at term boundaries have spaces
    # Handle "- RInv" and "+ RInv" patterns

    # Find all invariant references and work backwards for coefficients
    inv_pattern = r"((?:Dual)?[RWD]Inv)\[\{[^}]*\},\s*(\d+)\s*\]"

    positions = collect(eachmatch(inv_pattern, s))
    isempty(positions) && return terms

    for (i, m) in enumerate(positions)
        idx = parse(Int, m.captures[2])

        # Extract the coefficient: everything between previous match end and current match start
        coeff_start = i == 1 ? 1 : m.offset
        if i > 1
            prev_end = positions[i - 1].offset + length(positions[i - 1].match)
            coeff_str = strip(s[prev_end:(m.offset - 1)])
        else
            coeff_str = strip(s[1:(m.offset - 1)])
        end

        coeff = _parse_coefficient(coeff_str)
        push!(terms, (idx, coeff))
    end

    return terms
end

"""
    _parse_coefficient(s::String) -> Rational{Int}

Parse a coefficient string that may include:

  - Empty or "+" → 1//1
  - "-" → -1//1
  - "2*" → 2//1
  - "-3/2*" → -3//2
  - "sigma*" → 1//1 (sigma is the sign of the metric determinant, treated as symbolic)
  - "- sigma*" → -1//1

Note: `sigma` appears in some step-6 (dual) rules. We store it as ±1
since the actual sign is resolved at application time.
"""
function _parse_coefficient(s::AbstractString)
    s = strip(s)

    # Remove trailing * if present
    if endswith(s, "*")
        s = strip(s[1:(end - 1)])
    end

    # Handle sigma factor (Invar.m uses Block[{sigma}, ...] for step 6)
    has_sigma = false
    if occursin("sigma", s)
        has_sigma = true
        s = replace(s, "sigma" => "")
        s = replace(s, "**" => "*")  # clean up double *
        s = strip(s)
        if endswith(s, "*")
            s = strip(s[1:(end - 1)])
        end
    end

    # Empty, pure "+", or pure "-"
    isempty(s) && return 1 // 1
    s == "+" && return 1 // 1
    s == "-" && return -1 // 1

    # Strip leading +
    if startswith(s, "+")
        s = strip(s[2:end])
    end

    # Try parsing as rational: "3/2" or "-3/2"
    if occursin("/", s)
        parts = split(s, "/")
        if length(parts) == 2
            num = tryparse(Int, strip(parts[1]))
            den = tryparse(Int, strip(parts[2]))
            if num !== nothing && den !== nothing && den != 0
                return num // den
            end
        end
    end

    # Try parsing as integer
    n = tryparse(Int, s)
    n !== nothing && return n // 1

    # Fallback
    return 1 // 1
end

# ============================================================
# File Readers
# ============================================================

"""
    read_invar_perms(filepath::String) -> Dict{Int, Vector{Int}}

Read a step-1 (Maple format) permutation basis file.
Returns Dict mapping invariant index (1-based, positional) to permutation in images notation.

Each line in the file defines one invariant's contraction permutation.
Lines are indexed sequentially: line 1 = invariant 1, line 2 = invariant 2, etc.

Reference: Wolfram `ReadInvarPerms` (Invar.m:284).
"""
function read_invar_perms(filepath::String)
    result = Dict{Int,Vector{Int}}()

    if !isfile(filepath)
        @warn "Invar database file not found" filepath
        return result
    end

    lines = readlines(filepath)
    idx = 0
    for line in lines
        perm = _parse_maple_perm_line(line)
        perm === nothing && continue
        idx += 1
        result[idx] = perm
    end

    return result
end

"""
    read_invar_rules(filepath::String) -> Dict{Int, Vector{Tuple{Int, Rational{Int}}}}

Read a steps 2-6 (Mathematica format) rule file.
Returns Dict mapping dependent invariant index to its linear combination
of independent invariants: [(index, coefficient), ...].

Reference: Wolfram `ReadInvarRules` (Invar.m:293).
"""
function read_invar_rules(filepath::String)
    result = Dict{Int,Vector{Tuple{Int,Rational{Int}}}}()

    if !isfile(filepath)
        @warn "Invar database file not found" filepath
        return result
    end

    lines = readlines(filepath)
    for line in lines
        parsed = _parse_mma_rule(line)
        parsed === nothing && continue
        dep_idx, terms = parsed
        result[dep_idx] = terms
    end

    return result
end

# ============================================================
# Database Loader
# ============================================================

"""
    _step_subdir(step::Int; dim::Int=4) -> String

Return the subdirectory name for a given step.

    Step 1: "1"
    Step 2: "2"
    Step 3: "3"
    Step 4: "4"
    Step 5: "5_\$dim" (e.g. "5_4")
    Step 6: "6_\$dim" (e.g. "6_4")
"""
function _step_subdir(step::Int; dim::Int=4)
    if step in (5, 6)
        return string(step) * "_" * string(dim)
    end
    return string(step)
end

"""
    LoadInvarDB(dbdir::String; dim::Int=4) -> InvarDB

Load all Invar database files from `dbdir`.

The database directory should contain a `Riemann/` subdirectory with the
standard step structure. Missing files are skipped with a warning.

Arguments:

  - `dbdir`: Path to the directory containing `Riemann/`.
  - `dim`: Spacetime dimension for dimension-dependent rules (steps 5, 6). Default: 4.
"""
function LoadInvarDB(dbdir::String; dim::Int=4)
    riemann_dir = joinpath(dbdir, "Riemann")

    perms = Dict{Vector{Int},Dict{Int,Vector{Int}}}()
    dual_perms = Dict{Vector{Int},Dict{Int,Vector{Int}}}()
    rules = Dict{Int,Dict{Vector{Int},Dict{Int,Vector{Tuple{Int,Rational{Int}}}}}}()
    dual_rules = Dict{Int,Dict{Vector{Int},Dict{Int,Vector{Tuple{Int,Rational{Int}}}}}}()

    # Initialize rule dicts for each step
    for step in 2:6
        rules[step] = Dict{Vector{Int},Dict{Int,Vector{Tuple{Int,Rational{Int}}}}}()
        dual_rules[step] = Dict{Vector{Int},Dict{Int,Vector{Tuple{Int,Rational{Int}}}}}()
    end

    if !isdir(riemann_dir)
        @warn "Riemann database directory not found" riemann_dir
        return InvarDB(perms, dual_perms, rules, dual_rules)
    end

    # Collect all non-dual cases
    all_cases = Vector{Int}[]
    for c in InvarCases()
        push!(all_cases, c.deriv_orders)
    end
    all_cases = unique(all_cases)

    # Collect all dual cases
    all_dual_cases = Vector{Int}[]
    for c in InvarDualCases()
        push!(all_dual_cases, c.deriv_orders)
    end
    all_dual_cases = unique(all_dual_cases)

    # Step 1: Permutation bases (Maple format)
    step1_dir = joinpath(riemann_dir, "1")
    for case in all_cases
        fname = _rinv_filename(1, case)
        fpath = joinpath(step1_dir, fname)
        if isfile(fpath)
            perms[case] = read_invar_perms(fpath)
        end
    end
    for case in all_dual_cases
        fname = _dinv_filename(1, case)
        fpath = joinpath(step1_dir, fname)
        if isfile(fpath)
            dual_perms[case] = read_invar_perms(fpath)
        end
    end

    # Steps 2-6: Substitution rules (Mathematica format)
    for step in 2:6
        subdir = _step_subdir(step; dim=dim)
        step_dir = joinpath(riemann_dir, subdir)

        for case in all_cases
            fname = _rinv_filename(step, case; dim=dim)
            fpath = joinpath(step_dir, fname)
            if isfile(fpath)
                rules[step][case] = read_invar_rules(fpath)
            end
        end

        # Dual rules (steps 2-5 only; step 6 has no dual rules per Invar.m:614-615)
        if step <= 5
            for case in all_dual_cases
                fname = _dinv_filename(step, case; dim=dim)
                fpath = joinpath(step_dir, fname)
                if isfile(fpath)
                    dual_rules[step][case] = read_invar_rules(fpath)
                end
            end
        end
    end

    return InvarDB(perms, dual_perms, rules, dual_rules)
end
