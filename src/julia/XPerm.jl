"""
    XPerm

Julia implementation of Butler-Portugal tensor index canonicalization.

Permutations are 1-indexed image vectors (perm[i] = j means point i → j).
Signed permutations extend to degree n+2 where positions n+1, n+2 encode sign.

References:

  - xperm.c: C reference implementation (GPL, not used at runtime)
  - SymPy tensor_can.py: Python reference for Schreier-Sims
  - Butler (1991): "Fundamental Algorithms for Permutation Groups"
  - Niehoff (2018): Direct sorting shortcut for Sym/Antisym groups
"""
module XPerm

export StrongGenSet, SchreierVector

# Permutation utilities
export identity_perm, identity_signed_perm, compose, inverse_perm
export perm_sign, is_identity, on_point, on_list, perm_equal

# Group algorithms
export schreier_vector, trace_schreier, orbit
export schreier_sims, perm_member_q, order_of_group

# Coset algorithms (all return (Perm, Int) where Int ∈ {-1, 0, +1})
export right_coset_rep, double_coset_rep, canonical_perm

# Predefined groups
export symmetric_sgs, antisymmetric_sgs, riemann_sgs

# ============================================================
# Types
# ============================================================

const Perm = Vector{Int}        # 1-indexed, degree n (unsigned)
const SignedPerm = Vector{Int}  # 1-indexed, degree n+2; positions n+1,n+2 are sign bit

"""
Strong Generating Set for a permutation group G ≤ S_n.
base[i]  — a point moved by the i-th stabilizer but fixed by all later ones.
GS       — flat list of generators; each is a Perm (unsigned) or SignedPerm (signed).
n        — degree of the physical points (1..n).
signed   — true iff generators are signed (degree n+2); false iff unsigned (degree n).
"""
struct StrongGenSet
    base::Vector{Int}
    GS::Vector{Vector{Int}}  # Perm or SignedPerm depending on `signed`
    n::Int
    signed::Bool
end

"""
Schreier vector for orbit(root, generators, n).
orbit  — sorted list of points reachable from `root` under the generators.
nu     — length-n vector; nu[i] = index (1-based) into GS of the generator
that moved point i into the orbit tree, or 0 if i ∉ orbit.
w      — length-n vector; w[i] = the predecessor point from which i was reached
in BFS, or 0 if i ∉ orbit.
root   — the starting point.
"""
struct SchreierVector
    orbit::Vector{Int}
    nu::Vector{Int}    # length = n; nu[i] == 0 iff i ∉ orbit
    w::Vector{Int}     # length = n; w[i] == 0 iff i ∉ orbit
    root::Int
end

# ============================================================
# Permutation utilities
# ============================================================

"""
    identity_perm(n) → Perm

Return the identity permutation of degree n: [1, 2, ..., n].
"""
identity_perm(n::Int) = collect(1:n)

"""
    identity_signed_perm(n) → SignedPerm

Return the identity signed permutation of degree n+2: [1, 2, ..., n, n+1, n+2].
"""
identity_signed_perm(n::Int) = collect(1:(n + 2))

"""
    compose(p, q) → Perm

Return the composition p∘q: (p∘q)[i] = p[q[i]].
(Apply q first, then p.)
"""
function compose(p::Vector{Int}, q::Vector{Int})
    length(p) == length(q) ||
        error("compose: mismatched degrees $(length(p)) vs $(length(q))")
    [p[q[i]] for i in 1:length(p)]
end

"""
    inverse_perm(p) → Perm

Return the inverse of p: inv_p[p[i]] = i.
"""
function inverse_perm(p::Vector{Int})
    n = length(p)
    inv_p = similar(p)
    for i in 1:n
        inv_p[p[i]] = i
    end
    inv_p
end

"""
    on_point(p, i) → Int

Return the image of point i under permutation p: p[i].
"""
on_point(p::Vector{Int}, i::Int) = p[i]

"""
    on_list(p, lst) → Vector{Int}

Return the image of each point in lst under p: [p[i] for i in lst].
"""
on_list(p::Vector{Int}, lst::Vector{Int}) = [p[i] for i in lst]

"""
    is_identity(p) → Bool

True iff p is the identity permutation.
"""
is_identity(p::Vector{Int}) = all(p[i] == i for i in 1:length(p))

"""
    perm_equal(p, q) → Bool
"""
perm_equal(p::Vector{Int}, q::Vector{Int}) = p == q

"""
    perm_sign(p) → Int

Return the sign (+1 or -1) of an unsigned permutation p using cycle decomposition.
"""
function perm_sign(p::Vector{Int})
    n = length(p)
    visited = falses(n)
    sign = 1
    for i in 1:n
        if !visited[i]
            cycle_len = 0
            j = i
            while !visited[j]
                visited[j] = true
                j = p[j]
                cycle_len += 1
            end
            if iseven(cycle_len)
                sign = -sign
            end
        end
    end
    sign
end

# ============================================================
# Schreier vector and orbit computation
# ============================================================

"""
    schreier_vector(root, GS, n) → SchreierVector

Compute the Schreier vector for the orbit of `root` under the generators `GS`,
where each generator acts on points 1..n (or 1..n+2 for signed; only 1..n matter).
"""
function schreier_vector(root::Int, GS::Vector{Vector{Int}}, n::Int)::SchreierVector
    nu = zeros(Int, n)
    w = zeros(Int, n)
    in_orbit = falses(n)

    in_orbit[root] = true
    queue = [root]
    orbit_pts = [root]

    head = 1
    while head <= length(queue)
        pt = queue[head]
        head += 1
        for (gi, g) in enumerate(GS)
            # For signed perms (len = n+2), only points 1..n are physical
            img = g[pt]
            img > n && continue   # sign-bit points; skip
            if !in_orbit[img]
                in_orbit[img] = true
                nu[img] = gi
                w[img] = pt
                push!(queue, img)
                push!(orbit_pts, img)
            end
        end
    end

    SchreierVector(sort(orbit_pts), nu, w, root)
end

"""
    trace_schreier(sv, p, GS) → Perm

Recover the group element (product of generators) that maps sv.root to point p,
by tracing the Schreier tree backwards from p to root.
Returns the permutation u such that u(root) = p.
"""
function trace_schreier(sv::SchreierVector, p::Int, GS::Vector{Vector{Int}})::Vector{Int}
    n = length(sv.nu)
    deg = isempty(GS) ? n : length(GS[1])  # n or n+2

    u = identity_perm(deg)
    cur = p
    while cur != sv.root
        gi = sv.nu[cur]
        gi == 0 && error("trace_schreier: point $cur not in orbit of $(sv.root)")
        g = GS[gi]
        # Append g: path is root →...→ w[cur] →(g)→ cur
        # u accumulates left-to-right: u = u_prev ∘ g so u(root) = cur
        u = compose(u, g)
        cur = sv.w[cur]
    end
    u
end

"""
    orbit(root, GS, n) → Vector{Int}

Return sorted list of all points reachable from `root` under generators `GS`.
"""
orbit(root::Int, GS::Vector{Vector{Int}}, n::Int) = schreier_vector(root, GS, n).orbit

# ============================================================
# Schreier-Sims algorithm
# ============================================================

"""
    _sift(p, sgs_levels, n) → (residual, depth)

Sift permutation p through the partial BSGS represented by sgs_levels.
Returns (residual, depth) where:

  - If residual is identity at depth == length(sgs_levels)+1, p ∈ group.
  - Otherwise, the residual is a new generator for level `depth`.
"""
function _sift(
    p::Vector{Int}, base::Vector{Int}, level_GS::Vector{Vector{Vector{Int}}}, n::Int
)
    cur = copy(p)
    for (i, b) in enumerate(base)
        img = cur[b]  # where does current permutation send base[i]?
        if i > length(level_GS)
            # No generators at this level yet — residual falls here
            return cur, i
        end
        GS_i = level_GS[i]
        # Use full generator degree for sign-bit base points (b > n).
        sv_n = if b <= n
            n
        elseif !isempty(GS_i)
            length(GS_i[1])
        else
            max(n, b)
        end
        sv = schreier_vector(b, GS_i, sv_n)
        if !(img in sv.orbit)
            return cur, i  # residual at level i
        end
        # Compute the coset rep u such that u(b) = img, then strip it
        u = trace_schreier(sv, img, GS_i)
        cur = compose(inverse_perm(u), cur)
    end
    cur, length(base) + 1
end

"""
    _sift_with_cache(p, base, level_GS, sv_cache, n) → (residual, depth)

Like `_sift` but uses a shared `sv_cache::Vector{Any}` of SchreierVectors
(entries are `nothing` when invalidated). Recomputes and stores missing entries.
This avoids redundant BFS inside the tight Schreier-Sims loop.
"""
function _sift_with_cache(
    p::Vector{Int},
    base::Vector{Int},
    level_GS::Vector{Vector{Vector{Int}}},
    sv_cache::Vector{Any},
    n::Int,
)
    cur = copy(p)
    for (i, b) in enumerate(base)
        img = cur[b]
        if i > length(level_GS)
            return cur, i
        end
        GS_i = level_GS[i]
        sv_n = if b <= n
            n
        elseif !isempty(GS_i)
            length(GS_i[1])
        else
            max(n, b)
        end
        sv = if i <= length(sv_cache) && sv_cache[i] !== nothing
            sv_cache[i]::SchreierVector
        else
            sv_new = schreier_vector(b, GS_i, sv_n)
            while i > length(sv_cache)
                push!(sv_cache, nothing)
            end
            sv_cache[i] = sv_new
            sv_new
        end
        if !(img in sv.orbit)
            return cur, i
        end
        u = trace_schreier(sv, img, GS_i)
        cur = compose(inverse_perm(u), cur)
    end
    cur, length(base) + 1
end

"""
    schreier_sims(initbase, generators, n) → StrongGenSet

Build a Strong Generating Set via the basic Schreier-Sims algorithm.
initbase   — initial base (vector of points; extended during computation)
generators — initial generators (Perm or SignedPerm of degree n or n+2)
n          — number of physical points (1..n)
"""
function schreier_sims(
    initbase::Vector{Int}, generators::Vector{Vector{Int}}, n::Int
)::StrongGenSet
    if isempty(generators)
        return StrongGenSet(Int[], Vector{Int}[], n, false)
    end

    deg = length(generators[1])
    signed = (deg == n + 2)

    base = copy(initbase)
    level_GS = Vector{Vector{Vector{Int}}}()  # generators per level
    level_seen = Vector{Set{Vector{Int}}}()      # dedup sets per level
    sv_cache = Vector{Any}()                   # cached SchreierVector (or nothing)

    # Add generator g to level k with deduplication.
    # Invalidates the cached SV for level k if g is new.
    # Returns true iff g was not already present.
    function add_gen!(k::Int, g::Vector{Int})::Bool
        while k > length(level_GS)
            push!(level_GS, Vector{Vector{Int}}())
            push!(level_seen, Set{Vector{Int}}())
            push!(sv_cache, nothing)
        end
        g in level_seen[k] && return false
        push!(level_seen[k], g)
        push!(level_GS[k], g)
        sv_cache[k] = nothing  # SV is now stale for this level
        true
    end

    # Return (possibly cached) SchreierVector for level k.
    # Uses the full generator degree `deg` when the base point exceeds n,
    # so that sign-bit base points (> n) are handled correctly.
    function get_sv(k::Int)::SchreierVector
        # Ensure level_GS and sv_cache have an entry at position k.
        while k > length(level_GS)
            push!(level_GS, Vector{Vector{Int}}())
            push!(level_seen, Set{Vector{Int}}())
            push!(sv_cache, nothing)
        end
        while k > length(sv_cache)
            push!(sv_cache, nothing)
        end
        if sv_cache[k] === nothing
            b = base[k]
            sv_n = b <= n ? n : deg  # full degree for sign-bit base points
            sv_cache[k] = schreier_vector(b, level_GS[k], sv_n)
        end
        sv_cache[k]::SchreierVector
    end

    # Determine initial base from generators if caller passed empty base.
    if isempty(base)
        for g in generators
            moved = findfirst(i -> g[i] != i, 1:n)
            if !isnothing(moved) && !(moved in base)
                push!(base, moved)
                break
            end
        end
        isempty(base) && return StrongGenSet(Int[], copy(generators), n, signed)
    end

    # Seed level 1 with all initial generators (deduplicated).
    push!(level_GS, Vector{Vector{Int}}())
    push!(level_seen, Set{Vector{Int}}())
    push!(sv_cache, nothing)
    for g in generators
        add_gen!(1, g)
    end

    i = 1
    while i <= length(base)
        sv = get_sv(i)
        GS_i = copy(level_GS[i])  # snapshot to prevent iterator invalidation

        found_new = false
        min_dirty = i + 1  # lowest level that received a new generator this pass

        for γ in sv.orbit
            u_γ = trace_schreier(sv, γ, GS_i)
            for g in GS_i
                img_γ = g[γ]
                img_γ > n && continue
                !(img_γ in sv.orbit) && continue
                u_img = trace_schreier(sv, img_γ, GS_i)
                # Standard Schreier generator: u_{g(γ)}^{-1} · g · u_γ
                s = compose(inverse_perm(u_img), compose(g, u_γ))
                is_identity(s) && continue

                # Sift using shared SV cache to avoid redundant BFS.
                residual, depth = _sift_with_cache(s, base, level_GS, sv_cache, n)
                if !is_identity(residual)
                    found_new = true
                    if depth > length(base)
                        moved = findfirst(j -> residual[j] != j && !(j in base), 1:n)
                        !isnothing(moved) && push!(base, moved)
                    end
                    # Add residual at its level and all levels below it.
                    for k in 1:depth
                        if add_gen!(k, residual)
                            min_dirty = min(min_dirty, k)
                        end
                    end
                end
            end
        end

        if found_new
            # Only restart from the lowest level that was modified,
            # avoiding redundant reprocessing of unaffected levels.
            i = min_dirty
        else
            i += 1
        end
    end

    # Collect flat generator list (already deduplicated by level_seen).
    all_gens = Vector{Vector{Int}}()
    for gs in level_GS
        append!(all_gens, gs)
    end
    unique!(all_gens)

    StrongGenSet(base, all_gens, n, signed)
end

"""
    perm_member_q(p, sgs) → Bool

Test whether p belongs to the group described by sgs.
"""
function perm_member_q(p::Vector{Int}, sgs::StrongGenSet)::Bool
    if isempty(sgs.base)
        return is_identity(p)
    end
    # For signed-perm groups generators have degree n+2; pad p to match so
    # that compose() doesn't get a degree mismatch inside _sift.
    gdeg = isempty(sgs.GS) ? sgs.n : length(sgs.GS[1])
    padded = length(p) < gdeg ? vcat(p, collect((length(p) + 1):gdeg)) : p
    level_GS = _build_level_GS(sgs)
    residual, _ = _sift(padded, sgs.base, level_GS, sgs.n)
    is_identity(residual)
end

"""
    order_of_group(sgs) → Int

Compute |G| as product of orbit sizes at each base level.
"""
function order_of_group(sgs::StrongGenSet)::Int
    isempty(sgs.base) && return 1
    gdeg = isempty(sgs.GS) ? sgs.n : length(sgs.GS[1])
    level_GS = _build_level_GS(sgs)
    prod = 1
    for (i, b) in enumerate(sgs.base)
        # Use full generator degree for sign-bit base points (b > sgs.n).
        sv_n = b <= sgs.n ? sgs.n : gdeg
        sv = schreier_vector(b, level_GS[i], sv_n)
        prod *= length(sv.orbit)
    end
    prod
end

# Helper: reconstruct per-level GS from the flat GS using base stabilisers
function _build_level_GS(sgs::StrongGenSet)::Vector{Vector{Vector{Int}}}
    levels = Vector{Vector{Vector{Int}}}()
    # Level 1: all generators
    push!(levels, copy(sgs.GS))
    # Level i+1: generators that fix base[1], ..., base[i]
    for i in 1:(length(sgs.base) - 1)
        b_prev = sgs.base[i]
        prev = levels[i]
        stab = filter(g -> g[b_prev] == b_prev, prev)
        push!(levels, stab)
    end
    levels
end

# ============================================================
# Right coset representative
# ============================================================

"""
    right_coset_rep(perm, sgs) → (Perm, Int)

Find the lex-minimum (by base order) element of the right coset S · perm,
where S is the group described by sgs.
Returns (canonical_perm, sign).

  - sign = +1 always for unsigned groups (sgs.signed == false)
  - sign extracted from position n+1 for signed groups
"""
function right_coset_rep(perm::Vector{Int}, sgs::StrongGenSet)::Tuple{Vector{Int},Int}
    n = sgs.n
    isempty(sgs.base) && return (copy(perm), _extract_sign(perm, n, sgs.signed))

    level_GS = _build_level_GS(sgs)
    cur = copy(perm)

    for (i, b) in enumerate(sgs.base)
        GS_i = level_GS[i]
        sv = schreier_vector(b, GS_i, n)
        # Find the element in the orbit of cur[b] that gives minimum image
        # We want to pick s ∈ S_i such that s(cur)[b] is minimized
        # The orbit of b under GS_i are the possible values s(b)
        # We want to find u in the stabilizer chain such that u∘cur maps b to min orbit element
        min_img = cur[b]
        best_u = identity_perm(length(cur))

        for γ in sv.orbit
            # γ is a possible image for position b
            # The coset rep u such that u(b) = γ is trace_schreier(sv, γ, GS_i)
            u_γ = trace_schreier(sv, γ, GS_i)
            # Apply u_γ^{-1} to cur: new_cur = u_γ^{-1} ∘ cur
            candidate_img = γ  # u_γ^{-1}(cur(b)) is not what we want
            # Actually: (u_γ^{-1} ∘ cur)[b] = u_γ^{-1}[cur[b]]
            # We want the image at position b in the new permutation = u_γ^{-1}(cur[b])
            # But for lex-min, we want to minimize the image of cur at position b
            # In the right coset S·perm, elements are s·perm for s ∈ S
            # (s·perm)[b] = s[perm[b]] = s[cur[b]] (since cur = g·perm for current g)
            # The orbit of cur[b] under S_i is what matters
            img_b = γ  # orbit elements of b under S_i
            # But what we want: for s ∈ S_i, (s ∘ cur)[b] = s[cur[b]]
            # So we need the orbit of cur[b] under S_i, not of b
            _ = img_b  # unused, fix below
            break  # We'll redo this properly
        end

        # Correct approach: orbit of cur[b] under S_i
        sv_cur = schreier_vector(cur[b], GS_i, n)
        min_img = minimum(sv_cur.orbit)
        # Find s ∈ S_i such that s[cur[b]] = min_img
        u_to_min = trace_schreier(sv_cur, min_img, GS_i)
        cur = compose(u_to_min, cur)
    end

    sign = _extract_sign(cur, n, sgs.signed)
    # Return unsigned part
    result = cur[1:n]
    (result, sign)
end

function _extract_sign(perm::Vector{Int}, n::Int, signed::Bool)::Int
    !signed && return 1
    length(perm) < n + 1 && return 1
    perm[n + 1] == n+1 ? 1 : -1
end

# ============================================================
# Double coset representative
# ============================================================

"""
    double_coset_rep(perm, sgs, dummy_groups) → (Perm, Int)

Find the canonical representative of S · perm · D.
For Tier 1 tests (no dummy indices), dummy_groups is empty → reduces to right_coset_rep.
"""
function double_coset_rep(
    perm::Vector{Int}, sgs::StrongGenSet, dummy_groups::Vector{Vector{Int}}
)::Tuple{Vector{Int},Int}
    # For Tier 1: no dummy indices → dummy group is trivial
    isempty(dummy_groups) && return right_coset_rep(perm, sgs)

    # Full double coset: deferred to Tier 2 implementation
    # For now, fall back to right coset rep (correct when D is trivial)
    right_coset_rep(perm, sgs)
end

# ============================================================
# Main entry point
# ============================================================

"""
    canonical_perm(perm, sgs, free_points, dummy_groups) → (Perm, Int)

Returns (canonical_perm, sign) where sign ∈ {-1, 0, +1}.
Returns (Int[], 0) if the expression is zero (repeated antisymmetric index).
"""
function canonical_perm(
    perm::Vector{Int},
    sgs::StrongGenSet,
    free_points::Vector{Int},
    dummy_groups::Vector{Vector{Int}},
)::Tuple{Vector{Int},Int}
    isempty(sgs.base) && return (copy(perm[1:sgs.n]), 1)
    p1, s1 = right_coset_rep(perm, sgs)
    s1 == 0 && return (Int[], 0)
    p2, s2 = double_coset_rep(p1, sgs, dummy_groups)
    s2 == 0 && return (Int[], 0)
    (p2, s1 * s2)
end

# ============================================================
# Predefined symmetry groups
# ============================================================

"""
    symmetric_sgs(slots, n) → StrongGenSet

Symmetric group S_k on `slots` (1-indexed positions in 1..n).
Generators: adjacent transpositions of consecutive slot positions.
Returns unsigned StrongGenSet (signed=false).
"""
function symmetric_sgs(slots::Vector{Int}, n::Int)::StrongGenSet
    k = length(slots)
    k <= 1 && return StrongGenSet(Int[], Vector{Int}[], n, false)

    gens = Vector{Vector{Int}}()
    for i in 1:(k - 1)
        g = identity_perm(n)
        g[slots[i]], g[slots[i + 1]] = slots[i + 1], slots[i]
        push!(gens, g)
    end
    base = slots[1:(k - 1)]
    StrongGenSet(base, gens, n, false)
end

"""
    antisymmetric_sgs(slots, n) → StrongGenSet

Alternating-sign group A_k on `slots`.
Adjacent transpositions each carry sign=-1 (transposed via n+1 ↔ n+2 in extended rep).
Returns signed StrongGenSet (signed=true).
"""
function antisymmetric_sgs(slots::Vector{Int}, n::Int)::StrongGenSet
    k = length(slots)
    k <= 1 && return StrongGenSet(Int[], Vector{Int}[], n, true)

    gens = Vector{Vector{Int}}()
    for i in 1:(k - 1)
        g = identity_signed_perm(n)  # degree n+2
        # Swap slots[i] and slots[i+1]
        g[slots[i]], g[slots[i + 1]] = slots[i + 1], slots[i]
        # Flip sign bit: swap positions n+1 and n+2
        g[n + 1], g[n + 2] = n+2, n+1
        push!(gens, g)
    end
    base = slots[1:(k - 1)]
    StrongGenSet(base, gens, n, true)
end

"""
    riemann_sgs(slots, n) → StrongGenSet

Riemann symmetry group on exactly 4 slots (i,j,k,l) (1-indexed).
Generators (signed):
g1 = swap slots i,j with sign=-1  (antisym in first pair)
g2 = swap slots k,l with sign=-1  (antisym in second pair)
g3 = cycle (i↔k, j↔l) with sign=+1  (pair exchange)
Group order = 8. Returns signed StrongGenSet.
"""
function riemann_sgs(slots::NTuple{4,Int}, n::Int)::StrongGenSet
    i, j, k, l = slots

    # g1: swap i↔j, flip sign
    g1 = identity_signed_perm(n)
    g1[i], g1[j] = j, i
    g1[n + 1], g1[n + 2] = n+2, n+1

    # g2: swap k↔l, flip sign
    g2 = identity_signed_perm(n)
    g2[k], g2[l] = l, k
    g2[n + 1], g2[n + 2] = n+2, n+1

    # g3: swap i↔k and j↔l, keep sign (+1, no flip)
    g3 = identity_signed_perm(n)
    g3[i], g3[k] = k, i
    g3[j], g3[l] = l, j

    gens = [g1, g2, g3]
    base = [i, j, k]
    StrongGenSet(base, gens, n, true)
end

# ============================================================
# High-level canonicalization for specific symmetry types
# ============================================================

"""
    _bare_label(s) → String

Strip leading '-' from an index label for comparison purposes.
"""
_bare_label(s::AbstractString) = startswith(s, "-") ? s[2:end] : string(s)

"""
    _canonicalize_symmetric(indices, slots) → (Vector{String}, Int)

Niehoff shortcut for Symmetric groups: sort slot positions by bare label name.
Returns (new_indices, sign=+1).
"""
function _canonicalize_symmetric(
    indices::Vector{String}, slots::Vector{Int}
)::Tuple{Vector{String},Int}
    vals = [indices[s] for s in slots]
    order = sortperm(vals; by=_bare_label)
    sorted = vals[order]
    new_indices = copy(indices)
    for (i, s) in enumerate(slots)
        new_indices[s] = sorted[i]
    end
    (new_indices, 1)
end

"""
    _canonicalize_antisymmetric(indices, slots) → (Vector{String}, Int)

Niehoff shortcut for Antisymmetric groups: sort slot positions by bare label name.
Returns (new_indices, sign) where sign=parity(sort_permutation), or ([], 0) if repeated.
"""
function _canonicalize_antisymmetric(
    indices::Vector{String}, slots::Vector{Int}
)::Tuple{Vector{String},Int}
    vals = [indices[s] for s in slots]
    bare = [_bare_label(v) for v in vals]

    # Check for repeated indices (would make expression zero)
    if length(unique(bare)) < length(bare)
        return (String[], 0)
    end

    order = sortperm(vals; by=_bare_label)
    sorted = vals[order]

    # Compute parity of the sorting permutation
    sign = perm_sign(order)

    new_indices = copy(indices)
    for (i, s) in enumerate(slots)
        new_indices[s] = sorted[i]
    end
    (new_indices, sign)
end

"""
    _riemann_8_elements(i, j, k, l) → Vector{Tuple{NTuple{4,Int}, Int}}

Return all 8 elements of the Riemann symmetry group as (slot_image, sign) pairs.
slot_image[m] = which original slot position goes to position m.
"""
function _riemann_8_elements(i::Int, j::Int, k::Int, l::Int)
    # Each entry: (4-tuple of slot indices in positions [i,j,k,l], sign)
    [
        ((i, j, k, l), +1),   # identity
        ((j, i, k, l), -1),   # g1: swap ij
        ((i, j, l, k), -1),   # g2: swap kl
        ((j, i, l, k), +1),   # g1·g2
        ((k, l, i, j), +1),   # g3: pair exchange
        ((l, k, i, j), -1),   # g3·g1
        ((k, l, j, i), -1),   # g3·g2
        ((l, k, j, i), +1),   # g3·g1·g2
    ]
end

"""
    _canonicalize_riemann(indices, slots) → (Vector{String}, Int)

Butler-Portugal via enumeration for the Riemann symmetry group (order 8).
Finds the lex-min (by bare label) arrangement among the 8 group elements.
"""
function _canonicalize_riemann(
    indices::Vector{String}, slots::Vector{Int}
)::Tuple{Vector{String},Int}
    length(slots) == 4 || error("RiemannSymmetric requires exactly 4 slots")
    i, j, k, l = slots[1], slots[2], slots[3], slots[4]
    elements = _riemann_8_elements(i, j, k, l)

    best_labels = nothing
    best_sign = 1
    best_vals = nothing

    for (slot_img, sign) in elements
        # slot_img gives the indices at original slot positions i,j,k,l in this variant
        # The variant has: positions i,j,k,l get the indices from slot_img
        # i.e., new_indices[i]=indices[slot_img[1]], new_indices[j]=indices[slot_img[2]], etc.
        variant_vals = [indices[slot_img[m]] for m in 1:4]
        variant_bare = [_bare_label(v) for v in variant_vals]

        if isnothing(best_labels) || variant_bare < best_labels
            best_labels = variant_bare
            best_sign = sign
            best_vals = variant_vals
        end
    end

    new_indices = copy(indices)
    for (m, s) in enumerate([i, j, k, l])
        new_indices[s] = best_vals[m]
    end
    (new_indices, best_sign)
end

"""
    canonicalize_slots(indices, sym_type, slots) → (Vector{String}, Int)

Apply symmetry canonicalization to `indices` at the given `slots`.
sym_type: one of :Symmetric, :Antisymmetric, :RiemannSymmetric, :NoSymmetry
Returns (new_indices, sign) where sign ∈ {-1, 0, +1}.
"""
function canonicalize_slots(
    indices::Vector{String}, sym_type::Symbol, slots::Vector{Int}
)::Tuple{Vector{String},Int}
    if sym_type == :NoSymmetry || isempty(slots)
        return (indices, 1)
    elseif sym_type == :Symmetric
        return _canonicalize_symmetric(indices, slots)
    elseif sym_type == :Antisymmetric
        return _canonicalize_antisymmetric(indices, slots)
    elseif sym_type == :RiemannSymmetric
        return _canonicalize_riemann(indices, slots)
    else
        error("Unknown symmetry type: $sym_type")
    end
end

export canonicalize_slots

# ============================================================
# WL-Compatibility Layer
# High-level API mirroring Wolfram xPerm function names.
# Used by the Julia adapter when evaluating butler-example tests.
# ============================================================

export Cycles, GenSet, PermMemberQ, OrderOfGroup, Perm, PermDeg
export Orbit, Orbits, Permute, TranslatePerm, SchreierSims, ID

"""
Identity permutation sentinel. `PermMemberQ(ID, sgs)` expands to identity_perm(sgs.n).
"""
struct _IDType end
const ID = _IDType()

"""
    Cycles(cycle1, cycle2, ...) → Vector{Int}

Create a permutation image-vector from cycle notation.
`Cycles([1,2,3,4])` produces the 4-cycle 1→2→3→4→1.
`Cycles()` returns `Int[]` (identity of degree 0).
"""
function Cycles(cycles::AbstractVector{<:Integer}...)
    isempty(cycles) && return Int[]
    nonempty = [c for c in cycles if !isempty(c)]
    isempty(nonempty) && return Int[]
    n = maximum(maximum(c) for c in nonempty)
    img = collect(1:n)
    for cyc in nonempty
        k = length(cyc)
        k <= 1 && continue
        for i in 1:k
            img[cyc[i]] = cyc[mod1(i + 1, k)]
        end
    end
    return img
end
Cycles() = Int[]

"""
    GenSet(p1, p2, ...) → Vector{Vector{Int}}

Collect permutations into a generator list.
"""
GenSet(perms::AbstractVector{<:Integer}...) = Vector{Int}[Vector{Int}(p) for p in perms]
function GenSet(perms::AbstractVector{<:AbstractVector{<:Integer}})
    Vector{Int}[Vector{Int}(p) for p in perms]
end
GenSet() = Vector{Int}[]

"""
    StrongGenSet(base, genset) → StrongGenSet

WL-style constructor: build a strong generating set via Schreier-Sims
from a base vector and a generator list.
"""
function StrongGenSet(base::AbstractVector{<:Integer}, genset::Vector{Vector{Int}})
    b = Vector{Int}(base)
    if isempty(genset)
        return StrongGenSet(b, Vector{Int}[], 0, false)
    end
    # Normalize: pad shorter generators to max degree (identity extension)
    deg = maximum(length(g) for g in genset)
    padded = Vector{Vector{Int}}()
    for g in genset
        if length(g) < deg
            p = copy(g)
            append!(p, (length(g) + 1):deg)
            push!(padded, p)
        else
            push!(padded, copy(g))
        end
    end
    # Detect signed permutations: last 2 positions always map to {deg-1, deg}
    n =
        if deg >= 2 && all(
            g ->
                (g[deg - 1] == deg-1 || g[deg - 1] == deg) &&
                (g[deg] == deg-1 || g[deg] == deg),
            padded,
        )
            deg - 2   # physical degree; schreier_sims will detect signed=true
        else
            deg
        end
    return schreier_sims(b, padded, n)
end
# Fallback for base types like Vector{Any} (from WL {} translated to Julia [])
function StrongGenSet(base::AbstractVector, genset::Vector{Vector{Int}})
    StrongGenSet(Vector{Int}(base), genset)
end

"""
    PermMemberQ(perm, sgs) → Bool

Test whether `perm` is an element of the group described by `sgs`.
`ID` is treated as the identity permutation of degree `sgs.n`.
An empty permutation `Int[]` is also treated as identity.
"""
function PermMemberQ(perm, sgs::StrongGenSet)
    gdeg = isempty(sgs.GS) ? sgs.n : length(sgs.GS[1])
    if perm isa _IDType || isempty(perm)
        p = gdeg == 0 ? Int[] : identity_perm(gdeg)
    else
        p = Vector{Int}(perm)
    end
    return perm_member_q(p, sgs)
end
# WL xPerm order: PermMemberQ[sgs, perm]
PermMemberQ(sgs::StrongGenSet, perm) = PermMemberQ(perm, sgs)

"""
    OrderOfGroup(sgs) → Int
"""
OrderOfGroup(sgs::StrongGenSet) = order_of_group(sgs)

"""
    Orbit(pt, genset_or_sgs) → Vector{Int}

Return the orbit of `pt` under the generators, in BFS discovery order
(matching xPerm's Mathematica output).
"""
function Orbit(pt::Integer, GS::Vector{Vector{Int}})
    isempty(GS) && return [Int(pt)]
    n = max(Int(pt), maximum(maximum(g) for g in GS))
    _orbit_bfs(Int(pt), GS, n)
end
function Orbit(pt::Integer, sgs::StrongGenSet)
    _orbit_bfs(Int(pt), sgs.GS, sgs.n)
end

function _orbit_bfs(root::Int, GS::Vector{Vector{Int}}, n::Int)
    in_orbit = falses(n)
    in_orbit[root] = true
    queue = [root]
    head = 1
    while head <= length(queue)
        cur = queue[head];
        head += 1
        for g in GS
            cur > length(g) && continue  # generator acts as identity beyond its length
            img = g[cur]
            img > n && continue
            if !in_orbit[img]
                in_orbit[img] = true
                push!(queue, img)
            end
        end
    end
    queue
end

"""
    Orbits(genset_or_sgs [, n]) → Vector{Vector{Int}}

Return all orbits of the generators, each in BFS discovery order.
"""
function Orbits(GS::Vector{Vector{Int}}, n::Integer)
    n = Int(n)
    seen = falses(n)
    result = Vector{Vector{Int}}()
    for i in 1:n
        seen[i] && continue
        orb = _orbit_bfs(i, GS, n)
        for p in orb
            ;
            seen[p] = true;
        end
        push!(result, orb)
    end
    result
end
function Orbits(GS::Vector{Vector{Int}})
    isempty(GS) && return Vector{Vector{Int}}()
    n = maximum(maximum(g) for g in GS)
    Orbits(GS, n)
end
function Orbits(sgs::StrongGenSet)
    Orbits(sgs.GS, sgs.n)
end

"""
    Permute(a, b, ...) → Vector{Int}

Compose permutations left-to-right: `Permute(a, b)` means apply `a` first,
then `b`, i.e. `compose(b, a)` in right-to-left convention.
"""
function Permute(a::AbstractVector{<:Integer}, b::AbstractVector{<:Integer})
    pa, pb = Vector{Int}(a), Vector{Int}(b)
    n = max(length(pa), length(pb))
    # Pad shorter permutation with identity (fixed points)
    if length(pa) < n
        append!(pa, (length(pa) + 1):n)
    end
    if length(pb) < n
        append!(pb, (length(pb) + 1):n)
    end
    compose(pb, pa)
end
function Permute(perms::AbstractVector{<:Integer}...)
    length(perms) == 0 && return Int[]
    result = Vector{Int}(perms[1])
    for p in perms[2:end]
        result = Permute(result, Vector{Int}(p))
    end
    result
end

"""
    TranslatePerm(perm, format) → Vector{Int}

Identity conversion: the image vector is already in the right format.
"""
TranslatePerm(perm::AbstractVector{<:Integer}, ::Any) = Vector{Int}(perm)
TranslatePerm(::_IDType, ::Any) = Int[]

"""
    SchreierSims(base, genset, n) → StrongGenSet
    SchreierSims(genset) → StrongGenSet

WL-style Schreier-Sims wrapper.
"""
function SchreierSims(
    base::AbstractVector{<:Integer}, genset::Vector{Vector{Int}}, n::Integer
)
    schreier_sims(Vector{Int}(base), genset, Int(n))
end
function SchreierSims(genset::Vector{Vector{Int}})
    isempty(genset) && return StrongGenSet(Int[], Vector{Int}[], 0, false)
    n = maximum(maximum(g) for g in genset)
    schreier_sims(Int[], genset, n)
end

"""
    PermDeg(sgs) → Int

Return the physical degree (number of non-sign points) of the group.
For a GenSet (Vector{Vector{Int}}), returns the maximum permutation length.
"""
PermDeg(sgs::StrongGenSet) = sgs.n
PermDeg(gs::Vector{Vector{Int}}) = isempty(gs) ? 0 : maximum(length(g) for g in gs)

# ---------------------------------------------------------------------------
# Stabilizer
# ---------------------------------------------------------------------------

"""
    Stabilizer(pts, GS) → GenSet

Return the subset of generators in `GS` that fix every point in `pts`.
"""
function Stabilizer(pts::AbstractVector{<:Integer}, GS::Vector{Vector{Int}})
    filter(g -> all(p <= length(g) ? g[p] == p : true for p in pts), GS)
end
export Stabilizer

# ---------------------------------------------------------------------------
# SchreierOrbit
# ---------------------------------------------------------------------------

"""
    SchreierResult

Result of SchreierOrbit: orbit, label vector (generator name or 0), parent vector.
Displays as WL-style `Schreier[{orbit}, {labels}, {parents}]`.
"""
struct SchreierResult
    orbit::Vector{Int}
    label_vec::Vector{Any}   # 0 (Int) or String generator name
    parent_vec::Vector{Int}
end

function Base.show(io::IO, sr::SchreierResult)
    orbit_s = join(sr.orbit, ", ")
    label_s = join(map(x -> x === 0 ? "0" : "\"$(x)\"", sr.label_vec), ", ")
    parent_s = join(sr.parent_vec, ", ")
    print(io, "Schreier[{$(orbit_s)}, {$(label_s)}, {$(parent_s)}]")
end

"""
    Schreier(args...) → SchreierResult or MultiSchreierResult

WL-style constructor for SchreierResult (used in assertion comparisons).

  - 3-arg form: Schreier(orbit, labels, parents)
  - 4+-arg form: Schreier(orbit1, orbit2, ..., labels, parents)
"""
function Schreier(orbit, label_vec, parent_vec)
    SchreierResult(Vector{Int}(orbit), Vector{Any}(label_vec), Vector{Int}(parent_vec))
end

# Multi-orbit form: last two args are labels and parents, rest are orbits
function Schreier(args...)
    length(args) >= 3 || error("Schreier: need at least 3 arguments")
    orbits = [Vector{Int}(args[i]) for i in 1:(length(args) - 2)]
    label_vec = Vector{Any}(args[end - 1])
    parent_vec = Vector{Int}(args[end])
    MultiSchreierResult(orbits, label_vec, parent_vec)
end

function Base.:(==)(a::SchreierResult, b::SchreierResult)
    a.orbit == b.orbit && a.label_vec == b.label_vec && a.parent_vec == b.parent_vec
end

export Schreier

# ---------------------------------------------------------------------------
# MultiSchreierResult (for SchreierOrbits)
# ---------------------------------------------------------------------------

struct MultiSchreierResult
    orbits::Vector{Vector{Int}}
    label_vec::Vector{Any}
    parent_vec::Vector{Int}
end

function Base.show(io::IO, mr::MultiSchreierResult)
    parts = ["{" * join(o, ", ") * "}" for o in mr.orbits]
    label_s = join(map(x -> x === 0 ? "0" : "\"$(x)\"", mr.label_vec), ", ")
    parent_s = join(mr.parent_vec, ", ")
    print(io, "Schreier[$(join(parts, ", ")), {$(label_s)}, {$(parent_s)}]")
end

function Base.:(==)(a::MultiSchreierResult, b::MultiSchreierResult)
    a.orbits == b.orbits && a.label_vec == b.label_vec && a.parent_vec == b.parent_vec
end

export MultiSchreierResult

"""
    SchreierOrbits(GS, n, names) → MultiSchreierResult

Compute all orbits under generators `GS` (named by `names`) in [1..n].
Returns all orbits and combined label/parent vectors.
"""
function SchreierOrbits(GS::Vector{Vector{Int}}, n::Int, names::Vector{String})
    label_vec = Vector{Any}(fill(0, n))
    parent_vec = zeros(Int, n)
    visited = falses(n)
    orbits = Vector{Vector{Int}}()

    for start in 1:n
        visited[start] && continue
        # BFS from start
        visited[start] = true
        orbit = [start]
        head = 1
        while head <= length(orbit)
            cur = orbit[head];
            head += 1
            for (gi, g) in enumerate(GS)
                cur > length(g) && continue
                img = g[cur]
                (img < 1 || img > n) && continue
                if !visited[img]
                    visited[img] = true
                    push!(orbit, img)
                    label_vec[img] = names[gi]
                    parent_vec[img] = cur
                end
            end
        end
        push!(orbits, orbit)
    end
    MultiSchreierResult(orbits, label_vec, parent_vec)
end

export SchreierOrbits

"""
    SchreierOrbit(root, GS, n, names) → SchreierResult

BFS from `root` under generators `GS` (each named by `names[i]`) in [1..n].
Returns a SchreierResult with orbit, label vector, and parent vector.
"""
function SchreierOrbit(root::Int, GS::Vector{Vector{Int}}, n::Int, names::Vector{String})
    label_vec = Vector{Any}(fill(0, n))
    parent_vec = zeros(Int, n)
    in_orbit = falses(n)
    1 <= root <= n && (in_orbit[root] = true)
    orbit = [root]
    head = 1
    while head <= length(orbit)
        cur = orbit[head];
        head += 1
        for (gi, g) in enumerate(GS)
            cur > length(g) && continue
            img = g[cur]
            (img < 1 || img > n) && continue
            if !in_orbit[img]
                in_orbit[img] = true
                push!(orbit, img)
                label_vec[img] = names[gi]
                parent_vec[img] = cur
            end
        end
    end
    SchreierResult(orbit, label_vec, parent_vec)
end

export SchreierResult, SchreierOrbit

# ---------------------------------------------------------------------------
# Dimino group enumeration
# ---------------------------------------------------------------------------

"""
    Dimino(GS) → Vector{Vector{Int}}

Enumerate all elements of the group generated by `GS` via BFS (right multiplication).
Returns elements in BFS order: identity first. Supports `Length[Dimino[...]]` tests.
"""
function Dimino(GS::Vector{Vector{Int}})
    isempty(GS) && return [Int[]]
    n = maximum(length(g) for g in GS)
    padded = [length(g) < n ? vcat(g, collect((length(g) + 1):n)) : copy(g) for g in GS]
    identity_p = collect(1:n)
    seen = Set{Vector{Int}}([identity_p])
    queue = [identity_p]
    head = 1
    while head <= length(queue)
        h = queue[head];
        head += 1
        for g in padded
            new_e = compose(g, h)
            if !(new_e in seen)
                push!(seen, new_e)
                push!(queue, new_e)
            end
        end
    end
    queue
end

export Dimino

end  # module XPerm
