using Test
using xAct

@testset "Validation" begin
    @testset "validate_identifier" begin
        # Valid identifiers
        @test xAct.validate_identifier(:M) == :M
        @test xAct.validate_identifier(:MyTensor) == :MyTensor
        @test xAct.validate_identifier(:_private) == :_private
        @test xAct.validate_identifier(:T123) == :T123
        @test xAct.validate_identifier("abc") == :abc

        # Invalid: code injection
        @test_throws ArgumentError xAct.validate_identifier(Symbol("M; evil()"))
        @test_throws ArgumentError xAct.validate_identifier(Symbol("rm -rf /"))
        # Invalid: special characters
        @test_throws ArgumentError xAct.validate_identifier(Symbol("a b"))
        @test_throws ArgumentError xAct.validate_identifier(Symbol("a.b"))
        @test_throws ArgumentError xAct.validate_identifier(Symbol("a[0]"))
        # Invalid: empty / starts with digit
        @test_throws ArgumentError xAct.validate_identifier(Symbol(""))
        @test_throws ArgumentError xAct.validate_identifier(Symbol("1abc"))
        # Invalid: Unicode (ASCII-only by design)
        @test_throws ArgumentError xAct.validate_identifier(Symbol("α"))

        # Context appears in error message
        try
            xAct.validate_identifier(Symbol("bad name"); context="manifold name")
            @test false  # should not reach
        catch e
            @test e isa ArgumentError
            @test occursin("manifold name", e.msg)
        end
    end

    @testset "validate_perm" begin
        # Valid permutations
        @test xAct.validate_perm([1, 2, 3]) === nothing
        @test xAct.validate_perm([2, 1]) === nothing
        @test xAct.validate_perm([3, 1, 2]) === nothing
        @test xAct.validate_perm(Int[]) === nothing  # empty is valid

        # Invalid: duplicate
        @test_throws ArgumentError xAct.validate_perm([1, 1, 3])
        @test_throws ArgumentError xAct.validate_perm([2, 2])
        # Invalid: out of range
        @test_throws ArgumentError xAct.validate_perm([1, 4, 3])
        @test_throws ArgumentError xAct.validate_perm([0, 1, 2])
    end

    @testset "validate_disjoint_cycles" begin
        # Valid: disjoint
        @test xAct.validate_disjoint_cycles([[1, 2], [3, 4]]) === nothing
        @test xAct.validate_disjoint_cycles([[1, 2, 3]]) === nothing
        @test xAct.validate_disjoint_cycles(Vector{Int}[]) === nothing  # empty

        # Invalid: overlapping element
        @test_throws ArgumentError xAct.validate_disjoint_cycles([[1, 2], [2, 3]])
        @test_throws ArgumentError xAct.validate_disjoint_cycles([[1], [1]])
        @test_throws ArgumentError xAct.validate_disjoint_cycles([[1, 2], [3, 4], [4, 5]])
    end

    @testset "validate_order" begin
        # Valid orders
        @test xAct.validate_order(1) === nothing
        @test xAct.validate_order(2) === nothing
        @test xAct.validate_order(100) === nothing

        # Invalid: zero and negative
        @test_throws ArgumentError xAct.validate_order(0)
        @test_throws ArgumentError xAct.validate_order(-1)
        @test_throws ArgumentError xAct.validate_order(-100)
    end

    @testset "validate_deriv_orders" begin
        # Valid: sorted non-decreasing, non-negative
        @test xAct.validate_deriv_orders([0]) === nothing
        @test xAct.validate_deriv_orders([0, 0, 2]) === nothing
        @test xAct.validate_deriv_orders([0, 2, 4]) === nothing
        @test xAct.validate_deriv_orders(Int[]) === nothing  # empty

        # Invalid: unsorted
        @test_throws ArgumentError xAct.validate_deriv_orders([2, 0])
        @test_throws ArgumentError xAct.validate_deriv_orders([0, 2, 1])
        # Invalid: negative
        @test_throws ArgumentError xAct.validate_deriv_orders([-1, 0])
    end

    @testset "Integration: Cycles cross-cycle disjointness" begin
        # Cycles with overlapping elements across different cycles should error
        @test_throws Exception Cycles([1, 2], [2, 3])
        @test_throws Exception Cycles([1, 2, 3], [3, 4, 5])
        # Existing within-cycle duplicate detection still works
        @test_throws Exception Cycles([1, 2, 2])
    end

    @testset "Integration: inverse_perm" begin
        # Valid perm still works
        @test inverse_perm([2, 1]) == [2, 1]
        @test inverse_perm([3, 1, 2]) == [2, 3, 1]
        # Out-of-range still caught by existing range check
        @test_throws Exception inverse_perm([1, 5, 3])
    end

    @testset "Integration: def_manifold! identifier validation" begin
        reset_state!()
        # Valid manifold name works
        m = def_manifold!(:TestM, 4, [:a, :b, :c, :d])
        @test m.name == :TestM

        # Invalid manifold name fails
        reset_state!()
        @test_throws ArgumentError def_manifold!(Symbol("M; evil()"), 4, [:a, :b, :c, :d])
    end

    @testset "Integration: perturb order validation" begin
        reset_state!()
        def_manifold!(:PM, 4, [:pa, :pb, :pc, :pd])
        def_metric!(1, "gPM[-pa,-pb]", :CovDPM)
        def_tensor!(:TPM, ["-pa", "-pb"], :PM)
        def_tensor!(:dTPM, ["-pa", "-pb"], :PM)
        def_perturbation!(:dTPM, :TPM, 1)

        # Valid order works
        @test perturb("TPM[-pa,-pb]", 1) != ""

        # Zero and negative orders fail
        @test_throws ArgumentError perturb("TPM[-pa,-pb]", 0)
        @test_throws ArgumentError perturb("TPM[-pa,-pb]", -1)
    end

    @testset "Integration: InvariantCase deriv_orders validation" begin
        # Valid construction
        c = InvariantCase([0, 2])
        @test c.deriv_orders == [0, 2]

        # Unsorted should fail
        @test_throws ArgumentError InvariantCase([2, 0])
        # Negative should fail
        @test_throws ArgumentError InvariantCase([-1, 0])
    end
end
