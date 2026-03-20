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

using ...validate_perm: validate_perm
using ...validate_disjoint_cycles: validate_disjoint_cycles

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
        (1 <= p[i] <= n) ||
            error("inverse_perm: element p[$i]=$(p[i]) out of range [1, $n]")
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

Find the canonical representative of S · perm · D where D is the dummy symmetry group.

`dummy_groups` is a Vector of Vector{Int}: each inner vector lists positions (1-indexed)
that are freely exchangeable (dummy index relabeling symmetry).  For each group, every
transposition of two positions in the group is a generator of D.

Algorithm:

 1. Build generators of D from transpositions within each dummy group.
 2. Enumerate all elements of D by BFS over the Cayley graph (small groups in practice).
 3. For each d ∈ D, compute right_coset_rep(perm ∘ d, sgs).
 4. Return the lex-minimum result (by comparing the returned unsigned perm).

For Tier 1 tests (no dummy indices), dummy_groups is empty → reduces to right_coset_rep.
"""
function double_coset_rep(
    perm::Vector{Int}, sgs::StrongGenSet, dummy_groups::Vector{Vector{Int}}
)::Tuple{Vector{Int},Int}
    # For Tier 1: no dummy indices → dummy group is trivial
    isempty(dummy_groups) && return right_coset_rep(perm, sgs)

    n = sgs.n

    # Step 1: Build generators of D — transpositions within each dummy group.
    # Each generator acts on 1..n (unsigned, degree n).
    d_gens = Vector{Vector{Int}}()
    for grp in dummy_groups
        length(grp) <= 1 && continue
        for ii in 1:length(grp)
            for jj in (ii + 1):length(grp)
                a, b = grp[ii], grp[jj]
                g = identity_perm(n)
                g[a], g[b] = b, a
                push!(d_gens, g)
            end
        end
    end

    # If all dummy groups are singletons, D is trivial.
    if isempty(d_gens)
        return right_coset_rep(perm, sgs)
    end

    # Step 2: Enumerate all elements of D by BFS over the Cayley graph.
    id_n = identity_perm(n)
    d_elements = Vector{Vector{Int}}([id_n])
    seen_d = Set{Vector{Int}}([id_n])
    head = 1
    while head <= length(d_elements)
        cur_d = d_elements[head]
        head += 1
        for g in d_gens
            new_d = compose(g, cur_d)
            if !(new_d in seen_d)
                push!(seen_d, new_d)
                push!(d_elements, new_d)
            end
        end
    end

    # Determine generator degree (n for unsigned, n+2 for signed).
    gdeg = sgs.signed ? n + 2 : n

    # Step 3: For each d ∈ D, compute right_coset_rep(perm ∘ d, sgs).
    best_perm = nothing
    best_sign = 1

    for d in d_elements
        # Compose perm ∘ d (right-multiply: apply d first, then perm).
        # perm is length n (unsigned part from a prior right_coset_rep call).
        # d is length n.
        pd = [perm[d[i]] for i in 1:n]

        # Pad to generator degree if sgs is signed.
        if gdeg > n
            pd_full = vcat(pd, collect((n + 1):gdeg))
        else
            pd_full = pd
        end

        cand_perm, cand_sign = right_coset_rep(pd_full, sgs)

        if best_perm === nothing || cand_perm < best_perm
            best_perm = cand_perm
            best_sign = cand_sign
        end
    end

    (best_perm, best_sign)
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

    isnothing(best_vals) && error(
        "_canonicalize_riemann: no valid Riemann symmetry element found (internal error)",
    )
    vals = best_vals
    new_indices = copy(indices)
    for (m, s) in enumerate([i, j, k, l])
        new_indices[s] = vals[m]
    end
    (new_indices, best_sign)
end

"""
    _canonicalize_young(indices, partition, slots) → (Vector{String}, Int)

Canonicalize `indices` at `slots` under the Young symmetry group defined by `partition`.

The Young symmetry group is {c·r : c ∈ col_group, r ∈ row_group} with sign = sgn(c).
We enumerate all orbit elements and return the lexicographically minimal representative
together with its sign s such that T[canonical] = s · T[original].
"""
function _canonicalize_young(
    indices::Vector{String}, partition::Vector{Int}, slots::Vector{Int}
)::Tuple{Vector{String},Int}
    n = length(indices)
    k = length(slots)
    sum(partition) == k || error("Young partition sum $(sum(partition)) ≠ slot count $k")

    tab = standard_tableau(partition, slots)

    # If any column has repeated bare indices, the tensor is zero.
    # (Antisymmetrization over identical indices vanishes.)
    slot_vals = [indices[s] for s in slots]
    slot_bare = [_bare_label(v) for v in slot_vals]
    for col in _young_columns(tab)
        col_bare = [
            let idx = findfirst(==(s), slots)
                isnothing(idx) &&
                    error("_canonicalize_young: slot $s not found in slots $slots")
                slot_bare[idx]
            end for s in col
        ]
        if length(unique(col_bare)) < length(col_bare)
            return (String[], 0)
        end
    end

    row_sgs = row_symmetry_sgs(tab, n)
    col_sgs = col_antisymmetry_sgs(tab, n)

    row_elems = _enumerate_group_elements(row_sgs)
    col_elems = _enumerate_signed_group_elements(col_sgs)

    best_bare = nothing
    best_vals = nothing
    best_sign = 1

    for r in row_elems
        for (c, c_sign) in col_elems
            σ = compose(c, r)
            σ_inv = inverse_perm(σ)
            variant_vals = [indices[σ_inv[s]] for s in slots]
            variant_bare = [_bare_label(v) for v in variant_vals]

            if isnothing(best_bare) || variant_bare < best_bare
                best_bare = variant_bare
                best_vals = variant_vals
                best_sign = c_sign
            end
        end
    end

    isnothing(best_vals) &&
        error("_canonicalize_young: no valid Young symmetry element found (internal error)")
    vals = best_vals
    new_indices = copy(indices)
    for (i, s) in enumerate(slots)
        new_indices[s] = vals[i]
    end
    (new_indices, best_sign)
end

"""
    canonicalize_slots(indices, sym_type, slots[, partition]) → (Vector{String}, Int)

Apply symmetry canonicalization to `indices` at the given `slots`.
sym_type: one of :Symmetric, :Antisymmetric, :GradedSymmetric, :RiemannSymmetric, :YoungSymmetry, :NoSymmetry
For :YoungSymmetry, `partition` must be provided (e.g. [2,1]).
Returns (new_indices, sign) where sign ∈ {-1, 0, +1}.
"""
function canonicalize_slots(
    indices::Vector{String},
    sym_type::Symbol,
    slots::Vector{Int},
    partition::Vector{Int}=Int[],
)::Tuple{Vector{String},Int}
    if sym_type == :NoSymmetry || isempty(slots)
        return (indices, 1)
    elseif sym_type == :Symmetric
        return _canonicalize_symmetric(indices, slots)
    elseif sym_type == :Antisymmetric || sym_type == :GradedSymmetric
        return _canonicalize_antisymmetric(indices, slots)
    elseif sym_type == :RiemannSymmetric
        return _canonicalize_riemann(indices, slots)
    elseif sym_type == :YoungSymmetry
        return _canonicalize_young(indices, partition, slots)
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
export Group

"""
Identity permutation sentinel. `PermMemberQ(ID, sgs)` expands to identity_perm(sgs.n).
"""
struct _IDType end
const ID = _IDType()

# ---------------------------------------------------------------------------
# Group: ordered list of group elements returned by Dimino
# ---------------------------------------------------------------------------

"""
    Group(elem1, elem2, ...) → Group

Ordered list of group elements as returned by xPerm's Dimino.
Each element is either a String (named generator or "ID") or a Vector{Int} (Cycles form).
Equality treats "ID" and Int[] as equivalent identity representations.
"""
struct Group
    elems::Vector{Any}
    Group(elems::Vector{Any}) = new(elems)
end
Group(args...) = Group(Any[a for a in args])

function _perm_eq_normalized(p::Vector{Int}, q::Vector{Int})
    n = max(length(p), length(q))
    p_ext = length(p) < n ? vcat(p, collect((length(p) + 1):n)) : p
    q_ext = length(q) < n ? vcat(q, collect((length(q) + 1):n)) : q
    return p_ext == q_ext
end

function _group_elem_eq(a, b)
    a === b && return true
    # "ID" and Int[] are both representations of the identity
    if a isa String && a == "ID" && b isa Vector{Int} && isempty(b)
        return true
    end
    if b isa String && b == "ID" && a isa Vector{Int} && isempty(a)
        return true
    end
    if a isa Vector{Int} && b isa Vector{Int}
        return _perm_eq_normalized(a, b)
    end
    # String name vs Vector{Int}: look up the Julia variable in Main scope
    if a isa String && b isa Vector{Int}
        try
            val = Main.eval(Symbol(a))
            if val isa Vector{Int}
                return _perm_eq_normalized(val, b)
            end
        catch e
            e isa UndefVarError || rethrow()
        end
    end
    if b isa String && a isa Vector{Int}
        try
            val = Main.eval(Symbol(b))
            if val isa Vector{Int}
                return _perm_eq_normalized(a, val)
            end
        catch e
            e isa UndefVarError || rethrow()
        end
    end
    a == b
end

function Base.:(==)(a::Group, b::Group)
    length(a.elems) == length(b.elems) || return false
    all(_group_elem_eq(x, y) for (x, y) in zip(a.elems, b.elems))
end

Base.length(g::Group) = length(g.elems)
Length(g::Group) = length(g.elems)

function Base.show(io::IO, g::Group)
    print(io, "Group[")
    for (i, e) in enumerate(g.elems)
        i > 1 && print(io, ", ")
        if e isa String
            print(io, '"', e, '"')
        elseif e isa Vector{Int}
            # Use WL-style curly-brace list so _wl_to_jl can translate back to Julia
            print(io, "{", join(e, ", "), "}")
        else
            print(io, e)
        end
    end
    print(io, "]")
end

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
    # Validate cycle elements
    for cyc in nonempty
        for x in cyc
            (1 <= x <= n) || error("Cycles: element $x out of valid range [1, $n]")
        end
        if length(unique(cyc)) != length(cyc)
            dups = [x for x in cyc if count(==(x), cyc) > 1]
            error("Cycles: duplicate elements in cycle: $(unique(dups))")
        end
    end
    # Validate disjointness across cycles
    validate_disjoint_cycles(nonempty)
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
    (1 <= root <= n) || error("_orbit_bfs: root=$root outside valid range [1, $n]")
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
function SchreierSims(base::AbstractVector, genset::Vector{Vector{Int}}, n::Integer)
    b = isempty(base) ? Int[] : Vector{Int}(Int[x for x in base])
    ni = Int(n)
    # Pad generators to uniform degree ni (identity extension)
    padded = Vector{Vector{Int}}()
    for g in genset
        if length(g) < ni
            p = copy(g);
            append!(p, (length(g) + 1):ni);
            push!(padded, p)
        else
            push!(padded, g)
        end
    end
    schreier_sims(b, isempty(padded) ? genset : padded, ni)
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
# StablePoints
# ---------------------------------------------------------------------------

"""
    StablePoints(perm) → Vector{Int}
    StablePoints(gs::Vector) → Vector{Int}
    StablePoints(sgs::StrongGenSet) → Vector{Int}

Return the sorted list of points fixed by all generators.
"""
function StablePoints(perm::AbstractVector{<:Integer})
    n = length(perm)
    [i for i in 1:n if perm[i] == i]
end

function StablePoints(gs::Vector{Vector{Int}})
    isempty(gs) && return Int[]
    n = maximum(length(g) for g in gs)
    [i for i in 1:n if all(length(g) < i || g[i] == i for g in gs)]
end

function StablePoints(sgs::StrongGenSet)
    StablePoints(sgs.sgs)
end

export StablePoints

# ---------------------------------------------------------------------------
# RightCosetRepresentative
# ---------------------------------------------------------------------------

"""
    RightCosetRepresentative(perm, n, sgs) → Vector{Int}

WL-compatible wrapper: return the canonical (lex-minimum) representative
of the right coset S·perm in the group defined by `sgs`.
"""
function RightCosetRepresentative(
    perm::AbstractVector{<:Integer}, n::Integer, sgs::StrongGenSet
)
    p = if length(perm) < n
        vcat(Vector{Int}(perm), collect((length(perm) + 1):n))
    else
        Vector{Int}(perm)
    end
    p_canon, sign = right_coset_rep(p, sgs)
    Any[p_canon, sign]  # WL returns {canonical_perm, sign}; First[] extracts the perm
end

export RightCosetRepresentative

First(x) = first(x)
export First

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
    Dimino(GS, names) → Group

Enumerate all elements of the group generated by `GS` using the Dimino algorithm.
Returns a Group with elements in coset-expansion order (identity first).
`names` is an optional Vector{Pair{String,Vector{Int}}} mapping name → permutation vector.
Named elements appear as their String name; others appear as their permutation vector.

The algorithm: for each new generator s not yet in G, iterate through all current
elements and left-multiply by s, appending new elements. This produces xPerm-compatible
coset ordering.
"""
function Dimino(
    GS::Vector{Vector{Int}},
    names::Vector{Pair{String,Vector{Int}}}=Pair{String,Vector{Int}}[],
)
    if isempty(GS)
        return Group(Any["ID"])
    end
    n = maximum(length(g) for g in GS)
    padded = [length(g) < n ? vcat(g, collect((length(g) + 1):n)) : copy(g) for g in GS]
    identity_p = collect(1:n)

    # Build name lookup: padded_vec → name string
    name_lookup = Dict{Vector{Int},String}()
    for (nm, vec) in names
        padded_vec = length(vec) < n ? vcat(vec, collect((length(vec) + 1):n)) : vec
        name_lookup[padded_vec] = nm
    end

    G = [identity_p]
    seen = Set{Vector{Int}}([identity_p])

    for (ki, s) in enumerate(padded)
        s in seen && continue

        # Snapshot of the current subgroup H = G before adding this coset
        H = copy(G)

        # Add the first new coset: s * H
        for h in H
            x = compose(s, h)
            if !(x in seen)
                push!(seen, x)
                push!(G, x)
            end
        end

        # Find additional new cosets by applying each generator (so far) to each
        # known coset representative, until no new cosets emerge.
        # coset_reps[1] = s (the first new rep); we scan forward as we discover more.
        first_new = length(H) + 1   # index in G of the first new coset rep
        ri = first_new
        while ri <= length(G)
            t = G[ri]
            # Apply each generator s1,...,s_ki to this coset rep
            for gen in padded[1:ki]
                x = compose(gen, t)
                if !(x in seen)
                    # x is a new coset rep — add x * H
                    push!(seen, x)
                    push!(G, x)
                    for h in H
                        xh = compose(x, h)
                        if !(xh in seen)
                            push!(seen, xh)
                            push!(G, xh)
                        end
                    end
                end
            end
            ri += 1
        end
    end

    # Convert G to Group elements with name lookup
    elems = Any[]
    for (i, p) in enumerate(G)
        if i == 1
            push!(elems, "ID")          # identity always first
        elseif haskey(name_lookup, p)
            push!(elems, name_lookup[p])
        else
            push!(elems, p)             # raw vector; compared by == against Cycles(...)
        end
    end
    Group(elems)
end

export Dimino

# ---------------------------------------------------------------------------
# WL-compatible show for StrongGenSet
# Outputs StrongGenSet[{base...}, GenSet[gen1, gen2, ...]] using Cycles notation.
# This ensures $result substitution round-trips correctly through _wl_to_jl.
# ---------------------------------------------------------------------------

function _to_cycles(p::Vector{Int})::Vector{Vector{Int}}
    n = length(p)
    visited = falses(n)
    cycles = Vector{Vector{Int}}()
    for i in 1:n
        visited[i] && continue
        p[i] == i && (visited[i]=true; continue)
        cycle = Int[]
        j = i
        while !visited[j]
            visited[j] = true
            push!(cycle, j)
            j = p[j]
        end
        push!(cycles, cycle)
    end
    cycles
end

function _perm_to_wl_cycles_str(p::Vector{Int})::String
    cycs = _to_cycles(p)
    isempty(cycs) && return "Cycles[]"
    parts = join(["{" * join(c, ", ") * "}" for c in cycs], ", ")
    "Cycles[$parts]"
end

function _get_main_named_perms()::Dict{Vector{Int},String}
    lookup = Dict{Vector{Int},String}()
    all_nms = try
        filter(
            nm -> begin
                s = String(nm)
                !isempty(s) && isascii(s[1]) && isletter(s[1]) && length(s) <= 8
            end,
            names(Main; all=true),
        )
    catch e
        e isa ErrorException || e isa UndefVarError || rethrow()
        Symbol[]
    end
    for nm in all_nms
        try
            val = Main.eval(nm)
            val isa Vector{Int} || continue
            isempty(val) && continue
            n = length(val)
            while n > 0 && val[n] == n
                n -= 1
            end
            key = n == 0 ? Int[] : val[1:n]
            haskey(lookup, key) || (lookup[key] = String(nm))
        catch e
            e isa UndefVarError || e isa ErrorException || rethrow()
        end
    end
    lookup
end

function _perm_to_wl_str(p::Vector{Int}, names::Dict{Vector{Int},String})::String
    n = length(p)
    while n > 0 && p[n] == n
        n -= 1
    end
    trimmed = n == 0 ? Int[] : p[1:n]
    haskey(names, trimmed) && return "\"$(names[trimmed])\""
    _perm_to_wl_cycles_str(trimmed)
end

function Base.show(io::IO, sgs::StrongGenSet)
    names = _get_main_named_perms()
    base_s = "{" * join(sgs.base, ", ") * "}"
    # For signed SGS, strip the sign-bit suffix from each generator for display
    gens_strs = [_perm_to_wl_str(g, names) for g in sgs.GS]
    print(io, "StrongGenSet[$base_s, GenSet[$(join(gens_strs, ", "))]]")
end

# ---------------------------------------------------------------------------
# Timing / AbsoluteTiming  (WL compatibility wrappers)
# Returns a 2-tuple (elapsed, result) matching WL's {time, result} structure.
# ---------------------------------------------------------------------------

Timing(f) = (0.0, f)
AbsoluteTiming(f) = (0.0, f)
const Second = 1.0
export Timing, AbsoluteTiming, Second

# ---------------------------------------------------------------------------
# PermWord
# ---------------------------------------------------------------------------

"""
    PermWordResult

Result of PermWord: a list of permutation-vector coset representatives.
Stores actual Vector{Int} values (suitable for splatting into Permute).
show() outputs WL-compatible {elem, ...} notation, substituting names from
Julia's Main scope for any generator that matches a named variable.
"""
struct PermWordResult
    word::Vector{Vector{Int}}
end

function Base.show(io::IO, pw::PermWordResult)
    names = _get_main_named_perms()
    parts = [_perm_to_wl_str(e, names) for e in pw.word]
    print(io, "{$(join(parts, ", "))}")
end

# Make PermWordResult iterable so that `Permute(pw...)` splats the word elements.
function Base.iterate(pw::PermWordResult, state=1)
    state > length(pw.word) ? nothing : (pw.word[state], state + 1)
end
Base.length(pw::PermWordResult) = length(pw.word)

export PermWordResult

"""
    PermWord(perm, sgs) → PermWordResult

Decompose `perm` as a product of coset representatives from the stabilizer chain.
Returns the word `[residual, u_k, ..., u_1]` (residual first, then coset reps
in reverse sift order) such that:

    perm = u_1 ∘ u_2 ∘ ... ∘ u_k ∘ residual

Named generators (variables in Julia's Main scope) are returned as strings.
"""
function PermWord(perm::Vector{Int}, sgs::StrongGenSet)::PermWordResult
    n = sgs.n
    gdeg = isempty(sgs.GS) ? n : length(sgs.GS[1])
    padded = if length(perm) < gdeg
        vcat(Vector{Int}(perm), collect((length(perm) + 1):gdeg))
    else
        Vector{Int}(perm)
    end

    level_GS = _build_level_GS(sgs)
    cur = copy(padded)
    coset_reps = Vector{Vector{Int}}()

    for (i, b) in enumerate(sgs.base)
        i > length(level_GS) && break
        GS_i = level_GS[i]
        isempty(GS_i) && break
        img = cur[b]
        sv_n = b <= n ? n : gdeg
        sv = schreier_vector(b, GS_i, sv_n)
        !(img in sv.orbit) && break  # perm not in group at this level
        u = trace_schreier(sv, img, GS_i)
        push!(coset_reps, u)
        cur = compose(inverse_perm(u), cur)
    end

    # residual trimmed to physical degree
    residual = cur[1:min(n, length(cur))]
    nr = length(residual)
    while nr > 0 && residual[nr] == nr
        nr -= 1
    end
    res_trimmed = nr == 0 ? Int[] : residual[1:nr]

    word = Vector{Vector{Int}}([res_trimmed])
    for i in length(coset_reps):-1:1
        u = coset_reps[i]
        nu = length(u)
        while nu > 0 && u[nu] == nu
            nu -= 1
        end
        u_tr = nu == 0 ? Int[] : u[1:nu]
        push!(word, u_tr)
    end

    PermWordResult(word)
end

export PermWord

# ---------------------------------------------------------------------------
# DeleteRedundantGenerators
# ---------------------------------------------------------------------------

"""
    DeleteRedundantGenerators(sgs) → StrongGenSet

Remove generators from `sgs` that are redundant (expressible as products of
the remaining generators).  Iterates through the flat generator list, removing
each generator whose removal does not change the group order.
"""
function DeleteRedundantGenerators(sgs::StrongGenSet)::StrongGenSet
    isempty(sgs.GS) && return sgs
    target_order = order_of_group(sgs)
    gens = copy(sgs.GS)
    i = 1
    while i <= length(gens)
        candidate = vcat(gens[1:(i - 1)], gens[(i + 1):end])
        if isempty(candidate)
            i += 1
            continue
        end
        new_sgs = schreier_sims(copy(sgs.base), candidate, sgs.n)
        if order_of_group(new_sgs) == target_order
            deleteat!(gens, i)
        else
            i += 1
        end
    end
    schreier_sims(copy(sgs.base), gens, sgs.n)
end

export DeleteRedundantGenerators

# ============================================================
# Young Tableaux and Young Projectors
# ============================================================

"""
    YoungTableau

Represents a Young tableau for a partition λ = (λ₁ ≥ λ₂ ≥ ... ≥ λₖ) of n.

Fields:
partition  — row lengths in descending order, e.g. [3, 2, 1] for a 6-index tensor.
filling    — filling[row] = sorted list of index positions (1-indexed) in that row.

The standard filling places indices left-to-right in each row:
row 1: positions 1..λ₁
row 2: positions λ₁+1..λ₁+λ₂
etc.

For a custom filling (e.g. to apply the symmetrizer to specific slot positions),
use `standard_tableau(partition, indices)` which reindexes from an arbitrary
list of `n` slot positions.
"""
struct YoungTableau
    partition::Vector{Int}        # row lengths, sorted descending
    filling::Vector{Vector{Int}}  # filling[row] = list of slot positions in that row
end

"""
    standard_tableau(partition, indices) → YoungTableau

Construct a Young tableau for `partition` using the given `indices` (slot positions).
The filling is assigned left-to-right within each row, top-to-bottom across rows.

# Arguments

  - `partition::Vector{Int}`: row lengths in descending order, must sum to length(indices).
  - `indices::Vector{Int}`: 1-indexed slot positions to fill into the tableau.

# Example

```julia
# Partition [3,2] on indices [1,2,3,4,5]
tab = standard_tableau([3, 2], [1, 2, 3, 4, 5])
# tab.filling == [[1, 2, 3], [4, 5]]
```
"""
function standard_tableau(partition::Vector{Int}, indices::Vector{Int})::YoungTableau
    n = length(indices)
    sum(partition) == n ||
        error("standard_tableau: partition sum $(sum(partition)) ≠ length(indices) $n")
    issorted(partition; rev=true) ||
        error("standard_tableau: partition must be in descending order")
    filling = Vector{Vector{Int}}()
    offset = 0
    for row_len in partition
        push!(filling, indices[(offset + 1):(offset + row_len)])
        offset += row_len
    end
    YoungTableau(copy(partition), filling)
end

"""
    _young_columns(tab) → Vector{Vector{Int}}

Return the columns of a YoungTableau as lists of slot positions.
Column j contains tab.filling[i][j] for each row i that has ≥ j elements.
"""
function _young_columns(tab::YoungTableau)::Vector{Vector{Int}}
    isempty(tab.partition) && error("_young_columns: empty partition in YoungTableau")
    ncols = tab.partition[1]
    cols = [Int[] for _ in 1:ncols]
    for row in tab.filling
        for (j, s) in enumerate(row)
            push!(cols[j], s)
        end
    end
    cols
end

"""
    row_symmetry_sgs(tableau, n) → StrongGenSet

Return the unsigned StrongGenSet for the row symmetrization group of `tableau`.
The row group is the direct product S_{λ₁} × S_{λ₂} × ... where S_{λᵢ} permutes
within row i.  Generators are adjacent transpositions within each row.

The group acts on points 1..n (unsigned permutations, sign = +1 for all elements).
"""
function row_symmetry_sgs(tableau::YoungTableau, n::Int)::StrongGenSet
    gens = Vector{Vector{Int}}()
    base_pts = Vector{Int}()
    for row in tableau.filling
        k = length(row)
        k <= 1 && continue
        for i in 1:(k - 1)
            g = identity_perm(n)
            g[row[i]], g[row[i + 1]] = row[i + 1], row[i]
            push!(gens, g)
            push!(base_pts, row[i])
        end
    end
    isempty(gens) && return StrongGenSet(Int[], Vector{Int}[], n, false)
    # Build proper BSGS via Schreier-Sims
    schreier_sims(base_pts, gens, n)
end

"""
    col_antisymmetry_sgs(tableau, n) → StrongGenSet

Return the signed StrongGenSet for the column antisymmetrization group of `tableau`.
The column group permutes within each column, with sign = sign(permutation).
Generators are adjacent transpositions within each column (degree n, signed = true).

For partition [λ₁, λ₂, ...], column j contains the j-th element of each row
that is long enough.
"""
function col_antisymmetry_sgs(tableau::YoungTableau, n::Int)::StrongGenSet
    # Compute columns: column j contains filling[row][j] for rows long enough
    max_row_len = isempty(tableau.partition) ? 0 : tableau.partition[1]
    gens = Vector{Vector{Int}}()
    base_pts = Vector{Int}()
    for col_idx in 1:max_row_len
        # Collect the slot positions in this column (rows that have >= col_idx elements)
        col_slots = Vector{Int}()
        for row in tableau.filling
            col_idx <= length(row) && push!(col_slots, row[col_idx])
        end
        length(col_slots) <= 1 && continue
        for i in 1:(length(col_slots) - 1)
            g = identity_signed_perm(n)  # degree n+2
            g[col_slots[i]], g[col_slots[i + 1]] = col_slots[i + 1], col_slots[i]
            g[n + 1], g[n + 2] = n + 2, n + 1  # flip sign
            push!(gens, g)
            push!(base_pts, col_slots[i])
        end
    end
    isempty(gens) && return StrongGenSet(Int[], Vector{Int}[], n, true)
    schreier_sims(base_pts, gens, n)
end

"""
    _enumerate_group_elements(sgs) → Vector{Perm}

Enumerate all elements of the group described by `sgs` via BFS on the Cayley graph.
Returns unsigned permutations of degree `sgs.n`.
"""
function _enumerate_group_elements(sgs::StrongGenSet)::Vector{Vector{Int}}
    n = sgs.n
    id = identity_perm(n)
    isempty(sgs.GS) && return [id]

    # Use unsigned generators (strip sign bits if signed)
    unsigned_gens = Vector{Vector{Int}}()
    for g in sgs.GS
        push!(unsigned_gens, g[1:n])
    end
    # Also include inverses for complete BFS
    for g in copy(unsigned_gens)
        inv_g = inverse_perm(g)
        push!(unsigned_gens, inv_g)
    end

    seen = Set{Vector{Int}}([id])
    queue = [id]
    head = 1
    while head <= length(queue)
        cur = queue[head];
        head += 1
        for g in unsigned_gens
            new_elem = compose(g, cur)  # left-multiply
            if !(new_elem in seen)
                push!(seen, new_elem)
                push!(queue, new_elem)
            end
        end
    end
    queue
end

"""
    _enumerate_signed_group_elements(sgs) → Vector{Tuple{Perm, Int}}

Enumerate all elements of a signed group described by `sgs` via BFS.
Returns (unsigned_perm, sign) pairs where unsigned_perm has degree `sgs.n`.
"""
function _enumerate_signed_group_elements(sgs::StrongGenSet)::Vector{Tuple{Vector{Int},Int}}
    n = sgs.n
    id_unsigned = identity_perm(n)
    isempty(sgs.GS) && return [(id_unsigned, 1)]

    # Include generators and their inverses for BFS
    gen_pairs = Vector{Tuple{Vector{Int},Int}}()
    for g in sgs.GS
        unsigned_g = g[1:n]
        sign_g = _extract_sign(g, n, true)
        push!(gen_pairs, (unsigned_g, sign_g))
        inv_g = inverse_perm(unsigned_g)
        push!(gen_pairs, (inv_g, sign_g))  # inverse has same sign as transposition
    end

    seen = Dict{Vector{Int},Int}()  # perm -> sign
    seen[id_unsigned] = 1
    queue = [(id_unsigned, 1)]
    head = 1
    while head <= length(queue)
        (cur_p, cur_s) = queue[head];
        head += 1
        for (g, sg) in gen_pairs
            new_p = compose(g, cur_p)
            new_s = sg * cur_s
            if !haskey(seen, new_p)
                seen[new_p] = new_s
                push!(queue, (new_p, new_s))
            end
        end
    end
    collect((_ -> [(k, v) for (k, v) in seen])(values(seen)))
end

"""
    young_projector(tableau, n) → Vector{Tuple{Vector{Int}, Int}}

Compute the Young projector (symmetrizer) P_λ = Q_λ · R_λ for the given Young tableau.

The Young projector is:
P_λ = Σ_{q ∈ col_group} Σ_{r ∈ row_group} sign(q) · q · r

Returns a vector of `(perm, sign)` pairs representing the expansion of P_λ in S_n,
where `perm` is a permutation of degree `n` and `sign` ∈ {-1, +1}.

Duplicate permutations are collected and their signs summed; entries with net
sign zero are dropped.  The result is the "support" of the projector.

# Arguments

  - `tableau::YoungTableau`: the Young tableau.
  - `n::Int`: degree of the symmetric group (total number of physical points).

# Example

```julia
# Partition [2,1]: hook shape on n=3 indices [1,2,3]
# Row group: {e, (12)};  Column group: {e, -(13)}
# P = e·e + e·(12) - (13)·e - (13)·(12)
tab = standard_tableau([2, 1], [1, 2, 3])
terms = young_projector(tab, 3)
# 4 terms (before collecting): each with sign ±1
```
"""
function young_projector(tableau::YoungTableau, n::Int)::Vector{Tuple{Vector{Int},Int}}
    row_sgs = row_symmetry_sgs(tableau, n)
    col_sgs = col_antisymmetry_sgs(tableau, n)

    # Enumerate row group (unsigned)
    row_elems = _enumerate_group_elements(row_sgs)

    # Enumerate column group (signed)
    col_elems = _enumerate_signed_group_elements(col_sgs)

    # Build P_λ = Σ_q Σ_r sign(q) · (q ∘ r)
    # Collect sign contributions for each permutation
    sign_map = Dict{Vector{Int},Int}()
    for (q, sq) in col_elems
        for r in row_elems
            # q ∘ r: apply r first, then q
            qr = compose(q, r)
            current = get(sign_map, qr, 0)
            sign_map[qr] = current + sq
        end
    end

    # Drop zero contributions, return sorted list
    result = [(p, s) for (p, s) in sign_map if s != 0]
    sort!(result; by=x -> x[1])
    result
end

export YoungTableau, standard_tableau
export row_symmetry_sgs, col_antisymmetry_sgs, young_projector

# ---------------------------------------------------------------------------
# WL-compatible CamelCase aliases for Young tableau functions
# These are used by the TOML test adapter (which translates WL bracket syntax
# but cannot preserve underscores in snake_case function names).
# ---------------------------------------------------------------------------

"""
    YoungTableau(partition, indices) → YoungTableau

WL-compatible constructor alias for `standard_tableau`.
"""
function YoungTableau(partition::Vector{Int}, indices::Vector{Int})
    standard_tableau(partition, indices)
end

"""
    StandardTableau(partition, indices) → YoungTableau

WL-compatible alias for `standard_tableau`.
"""
function StandardTableau(partition::Vector{Int}, indices::Vector{Int})
    standard_tableau(partition, indices)
end

"""
    RowSymmetrySGS(tableau, n) → StrongGenSet

WL-compatible alias for `row_symmetry_sgs`.
"""
RowSymmetrySGS(tableau::YoungTableau, n::Int) = row_symmetry_sgs(tableau, n)

"""
    ColAntisymmetrySGS(tableau, n) → StrongGenSet

WL-compatible alias for `col_antisymmetry_sgs`.
"""
ColAntisymmetrySGS(tableau::YoungTableau, n::Int) = col_antisymmetry_sgs(tableau, n)

"""
    YoungProjector(tableau, n) → Vector{Tuple{Vector{Int}, Int}}

WL-compatible alias for `young_projector`.
"""
YoungProjector(tableau::YoungTableau, n::Int) = young_projector(tableau, n)

"""
    TableauFilling(tableau) → Vector{Vector{Int}}

Return the filling of a YoungTableau (for WL-compatible field access).
"""
TableauFilling(tableau::YoungTableau) = tableau.filling

"""
    TableauPartition(tableau) → Vector{Int}

Return the partition of a YoungTableau (for WL-compatible field access).
"""
TableauPartition(tableau::YoungTableau) = tableau.partition

export StandardTableau, RowSymmetrySGS, ColAntisymmetrySGS, YoungProjector
export TableauFilling, TableauPartition

end  # module XPerm
