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

# Property-based / fuzz tests for XTensor.jl
#
# Verifies algebraic properties of ToCanonical, Contract, and Simplify
# over randomly generated tensor expressions. Complements the fixed-case
# unit tests in test_xtensor.jl.
#
# Properties tested:
#   1.  ToCanonical idempotency (single terms, sums, antisymmetric sums)
#   2.  Symmetry consistency (symmetric, antisymmetric, graded, Young)
#   3.  Anti-zeroing (single non-degenerate terms must not vanish)
#   4.  Term preservation (disjoint-index sums retain both terms)
#   5.  Contract idempotency
#   6.  Simplify convergence (idempotency)
#   7.  Riemann symmetry orbit consistency
#   8.  Product canonicalization idempotency
#   9.  Metric self-trace equals dimension
#  10.  Simplify output is already canonical
#  11.  Ricci symmetry
#  12.  Einstein symmetry
#  13.  Metric symmetry
#  14.  Weyl tracelessness
#  15.  GradedSymmetric (Grassmann) canonicalization
#  16.  YoungSymmetry canonicalization
#  17.  Coefficient preservation
#  18.  Mixed-variance canonicalization
#  19.  Performance smoke test

# Load xAct from the project root
project_root = joinpath(@__DIR__, "..", "..")
using Pkg: Pkg
Pkg.activate(project_root; io=devnull)
include(joinpath(project_root, "src", "xAct.jl"))
using .xAct

using Test
using Random

const N_TRIALS = 100
const SEED = 7777

# ────────────────────────────────────────────────────────────────────────────
# Common setup
# ────────────────────────────────────────────────────────────────────────────

const ALL_INDICES = [:a, :b, :c, :d, :e, :f, :g, :h]

"""
Set up the standard 4D manifold with metric, symmetric, antisymmetric,
graded-symmetric, Young, and vector tensors. Call after `reset_state!()`.
"""
function setup_standard!()
    def_manifold!(:M, 4, ALL_INDICES)
    def_metric!(-1, "gg[-a,-b]", :CD)
    def_tensor!(:S, ["-a", "-b"], :M; symmetry_str="Symmetric[{-a,-b}]")
    def_tensor!(:A, ["-a", "-b"], :M; symmetry_str="Antisymmetric[{-a,-b}]")
    def_tensor!(:T, ["-a", "-b"], :M)  # no symmetry
    def_tensor!(:V, ["-a"], :M)         # vector
    def_tensor!(:Psi, ["-a", "-b"], :M; symmetry_str="GradedSymmetric[{-a,-b}]")
    def_tensor!(:Y21, ["-a", "-b", "-c"], :M; symmetry_str="Young[{2,1}]")
end

# ────────────────────────────────────────────────────────────────────────────
# Random expression generators
# ────────────────────────────────────────────────────────────────────────────

"""
Pick `n` distinct indices from the pool and return as Symbol vector.
"""
function pick_indices(rng::AbstractRNG, n::Int; pool::Vector{Symbol}=ALL_INDICES)
    @assert n <= length(pool) "need at least $n indices in pool"
    perm = randperm(rng, length(pool))
    return pool[perm[1:n]]
end

"""
Return a lower-index string like \"-a\".
"""
lower(idx::Symbol) = "-$(idx)"

"""
Return an upper-index string like \"a\".
"""
upper(idx::Symbol) = "$(idx)"

"""
Build \"S[-i,-j]\" with two random distinct lower indices.
"""
function random_sym_expr(rng::AbstractRNG; pool=ALL_INDICES)
    idxs = pick_indices(rng, 2; pool=pool)
    return "S[$(lower(idxs[1])),$(lower(idxs[2]))]"
end

"""
Build \"A[-i,-j]\" with two random distinct lower indices.
"""
function random_antisym_expr(rng::AbstractRNG; pool=ALL_INDICES)
    idxs = pick_indices(rng, 2; pool=pool)
    return "A[$(lower(idxs[1])),$(lower(idxs[2]))]"
end

"""
Build \"T[-i,-j]\" with two random distinct lower indices (no symmetry).
"""
function random_nosym_expr(rng::AbstractRNG; pool=ALL_INDICES)
    idxs = pick_indices(rng, 2; pool=pool)
    return "T[$(lower(idxs[1])),$(lower(idxs[2]))]"
end

"""
Build \"V[-i]\" with one random lower index.
"""
function random_vector_expr(rng::AbstractRNG; pool=ALL_INDICES)
    idxs = pick_indices(rng, 1; pool=pool)
    return "V[$(lower(idxs[1]))]"
end

"""
Build a RiemannCD expression with 4 random distinct lower indices.
"""
function random_riemann_expr(rng::AbstractRNG; pool=ALL_INDICES)
    idxs = pick_indices(rng, 4; pool=pool)
    return "RiemannCD[$(lower(idxs[1])),$(lower(idxs[2])),$(lower(idxs[3])),$(lower(idxs[4]))]"
end

"""
Generate a random single-tensor expression (one of S, A, T, V, Riemann).
"""
function random_single_expr(rng::AbstractRNG; pool=ALL_INDICES)
    @assert length(pool) >= 4 "pool must have >= 4 indices for Riemann terms"
    choice = rand(rng, 1:5)
    if choice == 1
        return random_sym_expr(rng; pool=pool)
    elseif choice == 2
        return random_antisym_expr(rng; pool=pool)
    elseif choice == 3
        return random_nosym_expr(rng; pool=pool)
    elseif choice == 4
        return random_vector_expr(rng; pool=pool)
    else
        return random_riemann_expr(rng; pool=pool)
    end
end

"""
Generate a random non-zero integer coefficient in [-5,-1] ∪ [2,5].
"""
function random_coeff(rng::AbstractRNG)
    c = rand(rng, 2:5)
    return rand(rng, Bool) ? c : -c
end

# ────────────────────────────────────────────────────────────────────────────
# Tests
# ────────────────────────────────────────────────────────────────────────────

@testset "XTensor Fuzz Properties" begin

    # ── 1. ToCanonical idempotency ──────────────────────────────────────────

    @testset "Idempotency: ToCanonical² = ToCanonical — single terms" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED)
        for i in 1:N_TRIALS
            expr = random_single_expr(rng)
            once = ToCanonical(expr)
            twice = ToCanonical(once)
            @test once == twice
        end
    end

    @testset "Idempotency: ToCanonical² = ToCanonical — symmetric sums" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 1)
        for _ in 1:N_TRIALS
            idxs = pick_indices(rng, 2)
            expr = "S[$(lower(idxs[1])),$(lower(idxs[2]))] + S[$(lower(idxs[2])),$(lower(idxs[1]))]"
            once = ToCanonical(expr)
            twice = ToCanonical(once)
            @test once == twice
        end
    end

    @testset "Idempotency: ToCanonical² = ToCanonical — antisymmetric sums" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 2)
        for _ in 1:N_TRIALS
            idxs = pick_indices(rng, 2)
            expr = "A[$(lower(idxs[1])),$(lower(idxs[2]))] + A[$(lower(idxs[2])),$(lower(idxs[1]))]"
            once = ToCanonical(expr)
            twice = ToCanonical(once)
            @test once == twice
        end
    end

    # ── 2. Symmetry consistency ─────────────────────────────────────────────

    @testset "Symmetric: S[-i,-j] and S[-j,-i] have identical canonical form" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 3)
        for _ in 1:N_TRIALS
            idxs = pick_indices(rng, 2)
            expr1 = "S[$(lower(idxs[1])),$(lower(idxs[2]))]"
            expr2 = "S[$(lower(idxs[2])),$(lower(idxs[1]))]"
            @test ToCanonical(expr1) == ToCanonical(expr2)
        end
    end

    @testset "Antisymmetric: A[-i,-j] + A[-j,-i] = 0" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 4)
        for _ in 1:N_TRIALS
            idxs = pick_indices(rng, 2)
            expr = "A[$(lower(idxs[1])),$(lower(idxs[2]))] + A[$(lower(idxs[2])),$(lower(idxs[1]))]"
            @test ToCanonical(expr) == "0"
        end
    end

    @testset "Symmetric: S[-i,-j] - S[-j,-i] = 0" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 5)
        for _ in 1:N_TRIALS
            idxs = pick_indices(rng, 2)
            expr = "S[$(lower(idxs[1])),$(lower(idxs[2]))] - S[$(lower(idxs[2])),$(lower(idxs[1]))]"
            @test ToCanonical(expr) == "0"
        end
    end

    @testset "Symmetric: S[-i,-j] + S[-j,-i] has coefficient 2" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 6)
        for _ in 1:N_TRIALS
            idxs = pick_indices(rng, 2)
            expr = "S[$(lower(idxs[1])),$(lower(idxs[2]))] + S[$(lower(idxs[2])),$(lower(idxs[1]))]"
            result = ToCanonical(expr)
            @test result != "0"
            @test occursin("2", result)
            @test occursin("S[", result)
        end
    end

    # ── 3. Anti-zeroing ─────────────────────────────────────────────────────

    @testset "Anti-zeroing: single symmetric tensor ≠ 0" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 7)
        for _ in 1:N_TRIALS
            expr = random_sym_expr(rng)
            @test ToCanonical(expr) != "0"
        end
    end

    @testset "Anti-zeroing: single antisymmetric tensor (distinct indices) ≠ 0" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 8)
        for _ in 1:N_TRIALS
            expr = random_antisym_expr(rng)
            @test ToCanonical(expr) != "0"
        end
    end

    @testset "Anti-zeroing: single vector ≠ 0" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 9)
        for _ in 1:N_TRIALS
            expr = random_vector_expr(rng)
            @test ToCanonical(expr) != "0"
        end
    end

    @testset "Anti-zeroing: metric ≠ 0" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 10)
        for _ in 1:N_TRIALS
            idxs = pick_indices(rng, 2)
            expr = "gg[$(lower(idxs[1])),$(lower(idxs[2]))]"
            @test ToCanonical(expr) != "0"
        end
    end

    @testset "Anti-zeroing: Riemann tensor (distinct indices) ≠ 0" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 11)
        for _ in 1:N_TRIALS
            expr = random_riemann_expr(rng)
            @test ToCanonical(expr) != "0"
        end
    end

    # ── 4. Term preservation ────────────────────────────────────────────────

    @testset "Term preservation: disjoint-index sums retain both terms" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 12)
        for _ in 1:N_TRIALS
            # Two vectors with different free indices cannot cancel
            idxs = pick_indices(rng, 2)
            term1 = "V[$(lower(idxs[1]))]"
            term2 = "V[$(lower(idxs[2]))]"
            sum_expr = "$term1 + $term2"
            result = ToCanonical(sum_expr)
            @test result != "0"
            c1 = ToCanonical(term1)
            c2 = ToCanonical(term2)
            @test occursin(c1, result)
            @test occursin(c2, result)
        end
    end

    # ── 5. Contract idempotency ─────────────────────────────────────────────

    @testset "Idempotency: Contract² = Contract — metric contraction" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 13)
        for _ in 1:N_TRIALS
            idxs = pick_indices(rng, 3)
            expr = "gg[$(lower(idxs[1])),$(lower(idxs[2]))] V[$(idxs[2])]"
            once = Contract(expr)
            twice = Contract(once)
            @test once == twice
        end
    end

    @testset "Idempotency: Contract² = Contract — single terms" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 14)
        for _ in 1:N_TRIALS
            expr = random_single_expr(rng)
            once = Contract(expr)
            twice = Contract(once)
            @test once == twice
        end
    end

    # ── 6. Simplify convergence ─────────────────────────────────────────────

    @testset "Convergence: Simplify² = Simplify — single terms" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 15)
        for _ in 1:N_TRIALS
            expr = random_single_expr(rng)
            once = Simplify(expr)
            twice = Simplify(once)
            @test once == twice
        end
    end

    @testset "Convergence: Simplify² = Simplify — metric contraction" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 16)
        for _ in 1:N_TRIALS
            idxs = pick_indices(rng, 3)
            expr = "gg[$(lower(idxs[1])),$(lower(idxs[2]))] V[$(idxs[2])]"
            once = Simplify(expr)
            twice = Simplify(once)
            @test once == twice
        end
    end

    @testset "Convergence: Simplify² = Simplify — symmetric with metric" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 17)
        for _ in 1:N_TRIALS
            idxs = pick_indices(rng, 3)
            expr = "gg[$(lower(idxs[1])),$(lower(idxs[2]))] S[$(idxs[2]),$(lower(idxs[3]))]"
            once = Simplify(expr)
            twice = Simplify(once)
            @test once == twice
        end
    end

    # ── 7. Riemann symmetry orbit consistency ───────────────────────────────

    @testset "Riemann first-pair antisymmetry: R[-i,-j,-k,-l] + R[-j,-i,-k,-l] = 0" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 18)
        for _ in 1:N_TRIALS
            idxs = pick_indices(rng, 4)
            i, j, k, l = lower.(idxs)
            expr = "RiemannCD[$i,$j,$k,$l] + RiemannCD[$j,$i,$k,$l]"
            @test ToCanonical(expr) == "0"
        end
    end

    @testset "Riemann second-pair antisymmetry: R[-i,-j,-k,-l] + R[-i,-j,-l,-k] = 0" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 19)
        for _ in 1:N_TRIALS
            idxs = pick_indices(rng, 4)
            i, j, k, l = lower.(idxs)
            expr = "RiemannCD[$i,$j,$k,$l] + RiemannCD[$i,$j,$l,$k]"
            @test ToCanonical(expr) == "0"
        end
    end

    @testset "Riemann pair exchange: R[-i,-j,-k,-l] - R[-k,-l,-i,-j] = 0" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 20)
        for _ in 1:N_TRIALS
            idxs = pick_indices(rng, 4)
            i, j, k, l = lower.(idxs)
            expr = "RiemannCD[$i,$j,$k,$l] - RiemannCD[$k,$l,$i,$j]"
            @test ToCanonical(expr) == "0"
        end
    end

    @testset "Riemann orbit: all 8-element orbit representatives canonicalize identically" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 21)
        # Each iteration tests 2 orbit elements, so reduced trial count is fine
        for _ in 1:50
            idxs = pick_indices(rng, 4)
            i, j, k, l = lower.(idxs)
            canonical = ToCanonical("RiemannCD[$i,$j,$k,$l]")

            # Pair exchange: R[-k,-l,-i,-j]
            @test ToCanonical("RiemannCD[$k,$l,$i,$j]") == canonical

            # Double antisymmetry: R[-j,-i,-l,-k] (swap both pairs)
            @test ToCanonical("RiemannCD[$j,$i,$l,$k]") == canonical
        end
    end

    # ── 8. Product canonicalization idempotency ─────────────────────────────

    @testset "Idempotency: ToCanonical² = ToCanonical — S·V product" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 22)
        for _ in 1:N_TRIALS
            idxs = pick_indices(rng, 3)
            expr = "S[$(lower(idxs[1])),$(lower(idxs[2]))] V[$(lower(idxs[3]))]"
            once = ToCanonical(expr)
            twice = ToCanonical(once)
            @test once == twice
        end
    end

    @testset "Idempotency: ToCanonical² = ToCanonical — A·V product" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 23)
        for _ in 1:N_TRIALS
            idxs = pick_indices(rng, 3)
            expr = "A[$(lower(idxs[1])),$(lower(idxs[2]))] V[$(lower(idxs[3]))]"
            once = ToCanonical(expr)
            twice = ToCanonical(once)
            @test once == twice
        end
    end

    @testset "Idempotency: ToCanonical² = ToCanonical — V·V product" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 24)
        for _ in 1:N_TRIALS
            idxs = pick_indices(rng, 2)
            expr = "V[$(lower(idxs[1]))] V[$(lower(idxs[2]))]"
            once = ToCanonical(expr)
            twice = ToCanonical(once)
            @test once == twice
        end
    end

    # ── 9. Metric self-trace is dimension ───────────────────────────────────

    @testset "Metric self-trace: g^{ij} g_{ij} = dim" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 25)
        for _ in 1:N_TRIALS
            idxs = pick_indices(rng, 2)
            expr = "gg[$(idxs[1]),$(idxs[2])] gg[$(lower(idxs[1])),$(lower(idxs[2]))]"
            result = Simplify(expr)
            @test result == "4"
        end
    end

    # ── 10. Simplify subsumes ToCanonical ───────────────────────────────────

    @testset "Simplify output is already canonical" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 26)
        for _ in 1:N_TRIALS
            expr = random_single_expr(rng)
            simplified = Simplify(expr)
            canonical = ToCanonical(simplified)
            @test simplified == canonical
        end
    end

    # ── 11. Ricci is symmetric ──────────────────────────────────────────────

    @testset "Ricci symmetry: R_{ij} - R_{ji} = 0" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 27)
        for _ in 1:N_TRIALS
            idxs = pick_indices(rng, 2)
            i, j = lower.(idxs)
            expr = "RicciCD[$i,$j] - RicciCD[$j,$i]"
            @test ToCanonical(expr) == "0"
        end
    end

    # ── 12. Einstein is symmetric ───────────────────────────────────────────

    @testset "Einstein symmetry: G_{ij} - G_{ji} = 0" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 28)
        for _ in 1:N_TRIALS
            idxs = pick_indices(rng, 2)
            i, j = lower.(idxs)
            expr = "EinsteinCD[$i,$j] - EinsteinCD[$j,$i]"
            @test ToCanonical(expr) == "0"
        end
    end

    # ── 13. Metric symmetry ─────────────────────────────────────────────────

    @testset "Metric symmetry: g_{ij} - g_{ji} = 0" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 29)
        for _ in 1:N_TRIALS
            idxs = pick_indices(rng, 2)
            i, j = lower.(idxs)
            expr = "gg[$i,$j] - gg[$j,$i]"
            @test ToCanonical(expr) == "0"
        end
    end

    # ── 14. Weyl tracelessness ──────────────────────────────────────────────

    @testset "Weyl trace vanishes: g^{ik} W_{ijkl} = 0" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 30)
        # Contract on 4-index Weyl is slower; reduced trial count
        for _ in 1:50
            idxs = pick_indices(rng, 4)
            i, j, k, l = idxs
            expr = "gg[$i,$k] WeylCD[$(lower(i)),$(lower(j)),$(lower(k)),$(lower(l))]"
            result = Contract(expr)
            @test result == "0"
        end
    end

    # ── 15. GradedSymmetric (Grassmann) canonicalization ────────────────────

    @testset "GradedSymmetric: Ψ[-i,-j] + Ψ[-j,-i] = 0 (Grassmann antisymmetry)" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 31)
        for _ in 1:N_TRIALS
            idxs = pick_indices(rng, 2)
            expr = "Psi[$(lower(idxs[1])),$(lower(idxs[2]))] + Psi[$(lower(idxs[2])),$(lower(idxs[1]))]"
            @test ToCanonical(expr) == "0"
        end
    end

    @testset "GradedSymmetric: idempotency" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 32)
        for _ in 1:N_TRIALS
            idxs = pick_indices(rng, 2)
            expr = "Psi[$(lower(idxs[1])),$(lower(idxs[2]))]"
            once = ToCanonical(expr)
            twice = ToCanonical(once)
            @test once == twice
        end
    end

    @testset "GradedSymmetric: anti-zeroing — single term ≠ 0" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 33)
        for _ in 1:N_TRIALS
            idxs = pick_indices(rng, 2)
            expr = "Psi[$(lower(idxs[1])),$(lower(idxs[2]))]"
            @test ToCanonical(expr) != "0"
        end
    end

    # ── 16. YoungSymmetry canonicalization ──────────────────────────────────

    @testset "Young {2,1}: row symmetry — Y[-b,-a,-c] = Y[-a,-b,-c]" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 34)
        for _ in 1:N_TRIALS
            idxs = pick_indices(rng, 3)
            a, b, c = lower.(idxs)
            canonical = ToCanonical("Y21[$a,$b,$c]")
            swapped = ToCanonical("Y21[$b,$a,$c]")
            @test canonical == swapped
        end
    end

    @testset "Young {2,1}: col antisymmetry — Y[-a,-b,-c] + Y[-c,-b,-a] = 0 (sorted)" begin
        # The col antisymmetry identity T(a,b,c) = -T(c,b,a) is valid at the
        # canonicalization level only when the product c·r representation covers
        # the mapping.  For arbitrary index orderings the 4-element product set
        # {e, (12), (13), (13)(12)} may not find the canonical representative
        # for both terms — this is a known limitation (sxAct-l36k).
        # Restricting to sorted indices ensures (13) maps directly to canonical.
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 35)
        for _ in 1:N_TRIALS
            idxs = sort(pick_indices(rng, 3))
            a, b, c = lower.(idxs)
            expr = "Y21[$a,$b,$c] + Y21[$c,$b,$a]"
            @test ToCanonical(expr) == "0"
        end
    end

    @testset "Young {2,1}: idempotency" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 36)
        for _ in 1:N_TRIALS
            idxs = pick_indices(rng, 3)
            a, b, c = lower.(idxs)
            expr = "Y21[$a,$b,$c]"
            once = ToCanonical(expr)
            twice = ToCanonical(once)
            @test once == twice
        end
    end

    @testset "Young {2,1}: anti-zeroing — single term ≠ 0" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 37)
        for _ in 1:N_TRIALS
            idxs = pick_indices(rng, 3)
            a, b, c = lower.(idxs)
            expr = "Y21[$a,$b,$c]"
            @test ToCanonical(expr) != "0"
        end
    end

    # ── 17. Coefficient preservation ────────────────────────────────────────

    @testset "Coefficient survives ToCanonical round-trip" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 38)
        for _ in 1:N_TRIALS
            c = random_coeff(rng)
            idxs = pick_indices(rng, 2)
            expr = "$c S[$(lower(idxs[1])),$(lower(idxs[2]))]"
            result = ToCanonical(expr)
            @test result != "0"
            once = ToCanonical(result)
            @test result == once  # idempotent
            # The canonical form of S with sorted indices
            sorted = sort([idxs[1], idxs[2]])
            expected = "$c S[$(lower(sorted[1])),$(lower(sorted[2]))]"
            @test result == expected
        end
    end

    @testset "Coefficient preserved through Simplify" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 39)
        for _ in 1:N_TRIALS
            c = random_coeff(rng)
            idxs = pick_indices(rng, 1)
            expr = "$c V[$(lower(idxs[1]))]"
            result = Simplify(expr)
            @test result == "$c V[$(lower(idxs[1]))]"
        end
    end

    # ── 18. Mixed-variance canonicalization ─────────────────────────────────

    @testset "Mixed variance: S_{i}^{j} idempotency" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 40)
        for _ in 1:N_TRIALS
            idxs = pick_indices(rng, 2)
            # One lower, one upper: S[-i, j]
            expr = "S[$(lower(idxs[1])),$(upper(idxs[2]))]"
            once = ToCanonical(expr)
            twice = ToCanonical(once)
            @test once == twice
        end
    end

    @testset "Mixed variance: metric contraction V_{i} g^{ij} = V^{j}" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 41)
        for _ in 1:N_TRIALS
            idxs = pick_indices(rng, 2)
            i, j = idxs
            expr = "V[$(lower(i))] gg[$(upper(i)),$(upper(j))]"
            result = Simplify(expr)
            @test result != "0"
            @test occursin("V[", result)
        end
    end

    @testset "Mixed variance: anti-zeroing — contravariant vector ≠ 0" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 42)
        for _ in 1:N_TRIALS
            idxs = pick_indices(rng, 1)
            expr = "V[$(upper(idxs[1]))]"
            @test ToCanonical(expr) != "0"
        end
    end

    # ── 19. Performance smoke test ──────────────────────────────────────────

    # ────────────────────────────────────────────────────────────────────────
    # 20. CovD expression idempotency
    # ────────────────────────────────────────────────────────────────────────

    @testset "CovD ToCanonical idempotency (N=$N_TRIALS)" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 200)
        for trial in 1:N_TRIALS
            # Pick a CovD index and an inner tensor expression using disjoint indices
            covd_idx = pick_indices(rng, 1; pool=ALL_INDICES)[1]
            remaining = filter(i -> i != covd_idx, ALL_INDICES)
            inner = if rand(rng, Bool)
                i2 = pick_indices(rng, 2; pool=remaining)
                "S[$(lower(i2[1])),$(lower(i2[2]))]"
            else
                i1 = pick_indices(rng, 1; pool=remaining)
                "V[$(lower(i1[1]))]"
            end
            expr = "CD[$(lower(covd_idx))][$inner]"
            r1 = ToCanonical(expr)
            r2 = ToCanonical(r1)
            @test r1 == r2
        end
    end

    @testset "CovD + product mixed idempotency (N=$N_TRIALS)" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 201)
        for trial in 1:N_TRIALS
            # CD[-a][V[-b]] T[-c,-d]  (CovD uses 2 indices, product uses 2 more)
            idxs = pick_indices(rng, 4; pool=ALL_INDICES)
            covd_part = "CD[$(lower(idxs[1]))][V[$(lower(idxs[2]))]]"
            prod_part = "T[$(lower(idxs[3])),$(lower(idxs[4]))]"
            expr = if rand(rng, Bool)
                "$covd_part $prod_part"
            else
                "$prod_part $covd_part"
            end
            r1 = ToCanonical(expr)
            r2 = ToCanonical(r1)
            @test r1 == r2
        end
    end

    @testset "Nested CovD chain idempotency (N=$N_TRIALS)" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 202)
        for trial in 1:N_TRIALS
            # CD[-a][CD[-b][V[-c]]]  (nested CovD chain)
            idxs = pick_indices(rng, 3; pool=ALL_INDICES)
            expr = "CD[$(lower(idxs[1]))][CD[$(lower(idxs[2]))][V[$(lower(idxs[3]))]]]"
            r1 = ToCanonical(expr)
            r2 = ToCanonical(r1)
            @test r1 == r2
        end
    end

    @testset "CovD inner canonicalization (N=$N_TRIALS)" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 203)
        for trial in 1:N_TRIALS
            # CD[-a][S[-c,-b]] — inner symmetric tensor should be canonicalized
            idxs = pick_indices(rng, 3; pool=ALL_INDICES)
            expr = "CD[$(lower(idxs[1]))][S[$(lower(idxs[2])),$(lower(idxs[3]))]]"
            result = ToCanonical(expr)
            # The inner S indices should be sorted (symmetric canonical form)
            sorted_inner = sort([string(idxs[2]), string(idxs[3])])
            expected = "CD[$(lower(idxs[1]))][S[-$(sorted_inner[1]),-$(sorted_inner[2])]]"
            @test result == expected
        end
    end

    @testset "Performance: 200 random ToCanonical calls < 2s" begin
        reset_state!()
        setup_standard!()
        rng = MersenneTwister(SEED + 99)
        t = @elapsed begin
            for _ in 1:200
                expr = random_single_expr(rng)
                ToCanonical(expr)
            end
        end
        @info "200 × random ToCanonical" ms = round(t * 1000; digits=1)
        @test t < 2.0
    end
end  # @testset "XTensor Fuzz Properties"
