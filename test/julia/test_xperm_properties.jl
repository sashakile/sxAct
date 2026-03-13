# Property-based tests for XPerm.jl
#
# Uses random sampling to verify mathematical laws of permutation groups.
# Each testset verifies a specific algebraic property over many random inputs,
# serving as a complement to the fixed-case unit tests in test_xperm.jl.
#
# Theoretic references:
#   - Butler (1991): Fundamental Algorithms for Permutation Groups
#   - Dixon (1969): High speed computation of group characters

using Test
using Random

include(joinpath(@__DIR__, "..", "XPerm.jl"))
using .XPerm

# ────────────────────────────────────────────────────────────────────────────
# Helpers (defined before the testsets that use them)
# ────────────────────────────────────────────────────────────────────────────

const N_TRIALS = 200
const SEED = 42

rand_perm(n, rng) = randperm(rng, n)

# Sample a pair of distinct indices from a range.
function sample_pair(rng, r)
    i = rand(rng, r)
    j = rand(rng, r)
    while j == i
        j = rand(rng, r)
    end
    (i, j)
end

# Generate all permutations of [1..n] via simple recursive backtracking.
function all_perms(n::Int)::Vector{Vector{Int}}
    result = Vector{Vector{Int}}()
    _perms_rec!(result, collect(1:n), 1)
    result
end

function _perms_rec!(result::Vector{Vector{Int}}, a::Vector{Int}, k::Int)
    if k > length(a)
        push!(result, copy(a))
        return nothing
    end
    for i in k:length(a)
        a[k], a[i] = a[i], a[k]
        _perms_rec!(result, a, k + 1)
        a[k], a[i] = a[i], a[k]
    end
end

# The 8-element Riemann symmetry group on positions {1,2,3,4}:
# G = ⟨(1,2), (3,4), (1,3)(2,4)⟩ — each applied as a slot-permutation.
# Returns all 8 group elements as permutation vectors on 1..4.
function riemann_group_elements()::Vector{Vector{Int}}
    s1 = [2, 1, 3, 4]   # swap positions 1,2
    s2 = [1, 2, 4, 3]   # swap positions 3,4
    s3 = [3, 4, 1, 2]   # pair-exchange
    gens = [s1, s2, s3]
    elems = Set{Vector{Int}}()
    push!(elems, [1, 2, 3, 4])
    queue = [[1, 2, 3, 4]]
    while !isempty(queue)
        cur = popfirst!(queue)
        for g in gens
            nxt = [cur[g[i]] for i in 1:4]   # apply g: new[i] = cur[g[i]]
            if nxt ∉ elems
                push!(elems, nxt)
                push!(queue, nxt)
            end
        end
    end
    collect(elems)
end

# ────────────────────────────────────────────────────────────────────────────
# Tests
# ────────────────────────────────────────────────────────────────────────────

@testset "XPerm Properties" begin

    # ── 1. Group axioms: identity and inverse ────────────────────────────────

    @testset "Group axioms: identity left/right" begin
        rng = MersenneTwister(SEED)
        for _ in 1:N_TRIALS
            n = rand(rng, 2:8)
            p = rand_perm(n, rng)
            id = identity_perm(n)
            @test compose(p, id) == p
            @test compose(id, p) == p
        end
    end

    @testset "Group axioms: inverse cancellation" begin
        rng = MersenneTwister(SEED + 1)
        for _ in 1:N_TRIALS
            n = rand(rng, 2:8)
            p = rand_perm(n, rng)
            id = identity_perm(n)
            @test compose(p, inverse_perm(p)) == id
            @test compose(inverse_perm(p), p) == id
        end
    end

    @testset "Group axioms: associativity" begin
        rng = MersenneTwister(SEED + 2)
        for _ in 1:N_TRIALS
            n = rand(rng, 2:8)
            p = rand_perm(n, rng)
            q = rand_perm(n, rng)
            r = rand_perm(n, rng)
            @test compose(compose(p, q), r) == compose(p, compose(q, r))
        end
    end

    @testset "Double inverse is identity" begin
        rng = MersenneTwister(SEED + 3)
        for _ in 1:N_TRIALS
            n = rand(rng, 2:8)
            p = rand_perm(n, rng)
            @test inverse_perm(inverse_perm(p)) == p
        end
    end

    # ── 2. Sign homomorphism ─────────────────────────────────────────────────

    @testset "Sign is a homomorphism: sign(p∘q) = sign(p)·sign(q)" begin
        rng = MersenneTwister(SEED + 4)
        for _ in 1:N_TRIALS
            n = rand(rng, 2:8)
            p = rand_perm(n, rng)
            q = rand_perm(n, rng)
            @test perm_sign(compose(p, q)) == perm_sign(p) * perm_sign(q)
        end
    end

    @testset "Sign of inverse equals sign of original" begin
        # Inverse has the same cycle structure, so the same sign.
        rng = MersenneTwister(SEED + 5)
        for _ in 1:N_TRIALS
            n = rand(rng, 2:8)
            p = rand_perm(n, rng)
            @test perm_sign(inverse_perm(p)) == perm_sign(p)
        end
    end

    @testset "Identity has sign +1" begin
        for n in 1:8
            @test perm_sign(identity_perm(n)) == 1
        end
    end

    @testset "Transposition has sign -1" begin
        # Any single transposition (i ↔ j) should have sign -1.
        rng = MersenneTwister(SEED + 6)
        for _ in 1:N_TRIALS
            n = rand(rng, 2:8)
            i, j = sample_pair(rng, 1:n)
            p = identity_perm(n)
            p[i], p[j] = j, i
            @test perm_sign(p) == -1
        end
    end

    # ── 3. Orbit properties ──────────────────────────────────────────────────

    @testset "Orbit: root is always in orbit" begin
        rng = MersenneTwister(SEED + 7)
        for _ in 1:50
            n = rand(rng, 3:8)
            k = rand(rng, 1:3)
            GS = [rand_perm(n, rng) for _ in 1:k]
            root = rand(rng, 1:n)
            orb = orbit(root, GS, n)
            @test root in orb
        end
    end

    @testset "Orbit: closed under generator application" begin
        rng = MersenneTwister(SEED + 8)
        for _ in 1:50
            n = rand(rng, 3:8)
            k = rand(rng, 1:3)
            GS = [rand_perm(n, rng) for _ in 1:k]
            root = rand(rng, 1:n)
            orb_set = Set(orbit(root, GS, n))
            for x in orb_set, g in GS
                @test g[x] in orb_set
            end
        end
    end

    @testset "Orbit: symmetric — x ∈ orbit(root) ↔ root ∈ orbit(x)" begin
        rng = MersenneTwister(SEED + 9)
        for _ in 1:50
            n = rand(rng, 3:8)
            k = rand(rng, 1:3)
            GS = [rand_perm(n, rng) for _ in 1:k]
            r1 = rand(rng, 1:n)
            for r2 in orbit(r1, GS, n)
                @test r1 in orbit(r2, GS, n)
            end
        end
    end

    # ── 4. Schreier vector trace ─────────────────────────────────────────────

    @testset "trace_schreier: u(root) = p for each p in orbit" begin
        rng = MersenneTwister(SEED + 10)
        for _ in 1:50
            n = rand(rng, 3:8)
            k = rand(rng, 1:3)
            GS = [rand_perm(n, rng) for _ in 1:k]
            root = rand(rng, 1:n)
            sv = schreier_vector(root, GS, n)
            for p in sv.orbit
                u = trace_schreier(sv, p, GS)
                @test u[root] == p
            end
        end
    end

    # ── 5. Schreier-Sims: membership laws ────────────────────────────────────

    @testset "Schreier-Sims: all generators are members" begin
        rng = MersenneTwister(SEED + 11)
        for _ in 1:50
            n = rand(rng, 3:6)
            k = rand(rng, 1:3)
            gens = [rand_perm(n, rng) for _ in 1:k]
            sgs = schreier_sims(Int[], gens, n)
            for g in sgs.GS
                @test perm_member_q(g, sgs)
            end
        end
    end

    @testset "Schreier-Sims: identity is always a member" begin
        rng = MersenneTwister(SEED + 12)
        for _ in 1:50
            n = rand(rng, 2:8)
            k = rand(rng, 1:3)
            gens = [rand_perm(n, rng) for _ in 1:k]
            sgs = schreier_sims(Int[], gens, n)
            @test perm_member_q(identity_perm(n), sgs)
        end
    end

    @testset "Schreier-Sims: membership closed under composition" begin
        rng = MersenneTwister(SEED + 13)
        for _ in 1:50
            n = rand(rng, 2:5)
            k = rand(rng, 2:3)
            gens = [rand_perm(n, rng) for _ in 1:k]
            sgs = schreier_sims(Int[], gens, n)
            length(sgs.GS) < 2 && continue
            g1, g2 = sgs.GS[1], sgs.GS[2]
            @test perm_member_q(compose(g1, g2), sgs)
            @test perm_member_q(compose(g2, g1), sgs)
        end
    end

    @testset "Schreier-Sims: membership closed under inverse" begin
        rng = MersenneTwister(SEED + 14)
        for _ in 1:50
            n = rand(rng, 2:6)
            k = rand(rng, 1:3)
            gens = [rand_perm(n, rng) for _ in 1:k]
            sgs = schreier_sims(Int[], gens, n)
            for g in sgs.GS
                @test perm_member_q(inverse_perm(g), sgs)
            end
        end
    end

    @testset "Schreier-Sims: known non-members are rejected" begin
        # Trivial group (no generators): only the identity is a member.
        for n in 2:6
            sgs = StrongGenSet(Int[], Vector{Int}[], n, false)
            @test perm_member_q(identity_perm(n), sgs)
            @test !perm_member_q(vcat([2, 1], collect(3:n)), sgs)
        end
    end

    # ── 6. Group order formulas ──────────────────────────────────────────────

    @testset "Order of symmetric group S_n equals n!" begin
        for n in 2:7
            sgs = symmetric_sgs(collect(1:n), n)
            @test order_of_group(sgs) == factorial(n)
        end
    end

    @testset "Order of cyclic group Z_n equals n" begin
        # n-cycle: 1→2→3→…→n→1
        for n in 2:8
            gen = vcat(2:n, [1])
            sgs = schreier_sims(Int[], [gen], n)
            @test order_of_group(sgs) == n
        end
    end

    @testset "Order of dihedral group D_n equals 2n" begin
        # D_n = ⟨r, s⟩ where r is the n-cycle and s is the reflection.
        for n in 3:7
            r = vcat(2:n, [1])
            s = reverse(collect(1:n))
            sgs = schreier_sims(Int[], [r, s], n)
            @test order_of_group(sgs) == 2 * n
        end
    end

    @testset "Alternating group: exactly half of S_n perms are even" begin
        # Verifies perm_sign is consistent across all n! elements.
        for n in 3:6
            all_p = all_perms(n)
            even_count = count(p -> perm_sign(p) == 1, all_p)
            odd_count = count(p -> perm_sign(p) == -1, all_p)
            @test even_count == factorial(n) ÷ 2
            @test odd_count == factorial(n) ÷ 2
        end
    end

    # ── 7. Canonicalization idempotency ─────────────────────────────────────

    @testset "canonicalize_slots idempotency — Symmetric" begin
        rng = MersenneTwister(SEED + 15)
        labels = ["a", "b", "c", "d", "e"]
        for _ in 1:N_TRIALS
            n = rand(rng, 2:4)
            idxs = [labels[i] for i in randperm(rng, n)]
            slots = collect(1:n)
            (r1, _) = canonicalize_slots(idxs, :Symmetric, slots)
            (r2, s2) = canonicalize_slots(r1, :Symmetric, slots)
            @test r1 == r2
            @test s2 == 1   # already canonical → sign is +1
        end
    end

    @testset "canonicalize_slots idempotency — Antisymmetric" begin
        rng = MersenneTwister(SEED + 16)
        labels = ["a", "b", "c", "d", "e"]
        for _ in 1:N_TRIALS
            n = rand(rng, 2:4)
            idxs = [labels[i] for i in randperm(rng, n)]
            slots = collect(1:n)
            (r1, s1) = canonicalize_slots(idxs, :Antisymmetric, slots)
            s1 == 0 && continue   # repeated index → zero, skip
            (r2, s2) = canonicalize_slots(r1, :Antisymmetric, slots)
            @test r1 == r2
            @test s2 == 1
        end
    end

    @testset "canonicalize_slots idempotency — Riemann" begin
        rng = MersenneTwister(SEED + 17)
        labels = ["-a", "-b", "-c", "-d"]
        for _ in 1:50
            perm = randperm(rng, 4)
            idxs = [labels[perm[i]] for i in 1:4]
            slots = [1, 2, 3, 4]
            (r1, _) = canonicalize_slots(idxs, :RiemannSymmetric, slots)
            (r2, s2) = canonicalize_slots(r1, :RiemannSymmetric, slots)
            @test r1 == r2
            @test s2 == 1
        end
    end

    # ── 8. Canonicalization uniqueness ──────────────────────────────────────

    @testset "Symmetric: all orderings of k distinct labels give same canonical form" begin
        for n in 2:4
            labels = ["-$('a'+i-1)" for i in 1:n]
            forms = Set{Vector{String}}()
            for perm in all_perms(n)
                idxs = [labels[perm[i]] for i in 1:n]
                (result, _) = canonicalize_slots(idxs, :Symmetric, collect(1:n))
                push!(forms, result)
            end
            @test length(forms) == 1
        end
    end

    @testset "Antisymmetric: all orderings of distinct labels give same canonical form" begin
        for n in 2:4
            labels = ["-$('a'+i-1)" for i in 1:n]
            forms = Set{Vector{String}}()
            for perm in all_perms(n)
                idxs = [labels[perm[i]] for i in 1:n]
                (result, sign) = canonicalize_slots(idxs, :Antisymmetric, collect(1:n))
                sign == 0 && continue
                push!(forms, result)
            end
            @test length(forms) == 1
        end
    end

    @testset "Antisymmetric: adjacent transposition flips sign" begin
        labels = ["-a", "-b", "-c", "-d", "-e"]
        for n in 2:5
            slots = collect(1:n)
            (canon, _) = canonicalize_slots(labels[1:n], :Antisymmetric, slots)
            for i in 1:(n - 1)
                swapped = copy(canon)
                swapped[i], swapped[i + 1] = swapped[i + 1], swapped[i]
                (_, sign) = canonicalize_slots(swapped, :Antisymmetric, slots)
                @test sign == -1
            end
        end
    end

    @testset "Riemann: the 8-element symmetry group partitions 24 perms into 3 orbits" begin
        # The Riemann group G = ⟨(12),(34),(13)(24)⟩ has order 8.
        # Acting on S_4 by slot-permutation: 24 / 8 = 3 orbits.
        labels = ["-a", "-b", "-c", "-d"]
        forms = Set{Vector{String}}()
        for perm in all_perms(4)
            idxs = [labels[perm[i]] for i in 1:4]
            (result, _) = canonicalize_slots(idxs, :RiemannSymmetric, [1, 2, 3, 4])
            push!(forms, result)
        end
        @test length(forms) == 3
    end

    @testset "Riemann: all 8 group-related arrangements give same canonical form" begin
        # Within each orbit the canonical form must be identical.
        labels = ["-a", "-b", "-c", "-d"]
        grp_elems = riemann_group_elements()
        @test length(grp_elems) == 8   # sanity check
        for start_perm in all_perms(4)[1:3:end]   # sample ~8 orbit representatives
            base_idxs = [labels[start_perm[i]] for i in 1:4]
            (canon_base, _) = canonicalize_slots(base_idxs, :RiemannSymmetric, [1, 2, 3, 4])
            for g in grp_elems
                # Apply group element g to rearrange the index positions
                related_idxs = [base_idxs[g[i]] for i in 1:4]
                (canon_rel, _) = canonicalize_slots(
                    related_idxs, :RiemannSymmetric, [1, 2, 3, 4]
                )
                @test canon_rel == canon_base
            end
        end
    end

    @testset "Riemann antisymmetry: first-pair swap flips sign" begin
        # R[-a,-b,-c,-d] = -R[-b,-a,-c,-d]
        labels = ["-a", "-b", "-c", "-d"]
        swapped = [labels[2], labels[1], labels[3], labels[4]]
        (_, sign) = canonicalize_slots(swapped, :RiemannSymmetric, [1, 2, 3, 4])
        @test sign == -1
    end

    @testset "Riemann antisymmetry: second-pair swap flips sign" begin
        labels = ["-a", "-b", "-c", "-d"]
        swapped = [labels[1], labels[2], labels[4], labels[3]]
        (_, sign) = canonicalize_slots(swapped, :RiemannSymmetric, [1, 2, 3, 4])
        @test sign == -1
    end

    @testset "Riemann pair-exchange: sign is +1" begin
        # R[-a,-b,-c,-d] = R[-c,-d,-a,-b]
        labels = ["-a", "-b", "-c", "-d"]
        swapped = [labels[3], labels[4], labels[1], labels[2]]
        (_, sign) = canonicalize_slots(swapped, :RiemannSymmetric, [1, 2, 3, 4])
        @test sign == 1
    end

    # ── 9. Partial-slot canonicalization ────────────────────────────────────

    @testset "Partial slots: non-slot positions are unchanged" begin
        rng = MersenneTwister(SEED + 18)
        labels = ["p", "q", "r", "s"]
        for _ in 1:50
            fixed = labels[rand(rng, 1:4)]
            a, b = rand(rng, Bool) ? ("q", "r") : ("r", "q")
            idxs = [fixed, a, b]
            for sym in [:Symmetric, :Antisymmetric]
                (result, sign) = canonicalize_slots(idxs, sym, [2, 3])
                sign == 0 && continue
                @test result[1] == fixed
            end
        end
    end

    @testset "Partial slots: canonicalization on subset commutes with untouched slots" begin
        # Permuting only the active slots should not change inactive slots.
        rng = MersenneTwister(SEED + 19)
        labels = ["-a", "-b", "-c", "-d", "-e"]
        for _ in 1:50
            n = 5
            idxs = [labels[i] for i in randperm(rng, n)]
            slots = [2, 4]   # only slots 2 and 4 are symmetrized
            (result, sign) = canonicalize_slots(idxs, :Antisymmetric, slots)
            sign == 0 && continue
            # Slots NOT in [2,4] must be unchanged
            for j in [1, 3, 5]
                @test result[j] == idxs[j]
            end
        end
    end

    # ── 10. Performance smoke tests ──────────────────────────────────────────

    @testset "Performance: symmetric_sgs + order for S_8" begin
        times = Float64[]
        for _ in 1:5
            t = @elapsed begin
                sgs = symmetric_sgs(collect(1:8), 8)
                @assert order_of_group(sgs) == factorial(8)
            end
            push!(times, t)
        end
        med = sort(times)[3]
        @info "S_8 order computation median" ms=round(med * 1000, digits=1)
        @test med < 2.0
    end

    @testset "Performance: schreier_sims for random degree-6 generators" begin
        rng = MersenneTwister(SEED + 20)
        times = Float64[]
        for _ in 1:20
            gens = [rand_perm(6, rng) for _ in 1:3]
            t = @elapsed schreier_sims(Int[], gens, 6)
            push!(times, t)
        end
        med = sort(times)[10]
        @info "schreier_sims(n=6, k=3) median" ms=round(med * 1000, digits=3)
        @test med < 0.5
    end

    @testset "Performance: 100 perm_member_q queries in S_6" begin
        sgs = symmetric_sgs(collect(1:6), 6)
        rng = MersenneTwister(SEED + 21)
        t = @elapsed begin
            for _ in 1:100
                perm_member_q(rand_perm(6, rng), sgs)
            end
        end
        @info "100 × perm_member_q(S_6)" ms=round(t * 1000, digits=2)
        @test t < 1.0
    end

    @testset "Performance: 1000 × canonicalize_slots(:RiemannSymmetric)" begin
        rng = MersenneTwister(SEED + 22)
        labels = ["-a", "-b", "-c", "-d"]
        t = @elapsed begin
            for _ in 1:1000
                perm = randperm(rng, 4)
                idxs = [labels[perm[i]] for i in 1:4]
                canonicalize_slots(idxs, :RiemannSymmetric, [1, 2, 3, 4])
            end
        end
        @info "1000 × canonicalize_slots(:RiemannSymmetric)" ms=round(t * 1000, digits=2)
        @test t < 1.0
    end

    @testset "Performance: 1000 × canonicalize_slots(:Antisymmetric, n=6)" begin
        rng = MersenneTwister(SEED + 23)
        labels = ["-a", "-b", "-c", "-d", "-e", "-f"]
        t = @elapsed begin
            for _ in 1:1000
                perm = randperm(rng, 6)
                idxs = [labels[perm[i]] for i in 1:6]
                canonicalize_slots(idxs, :Antisymmetric, collect(1:6))
            end
        end
        @info "1000 × canonicalize_slots(:Antisymmetric, n=6)" ms=round(t * 1000, digits=2)
        @test t < 1.0
    end
end
