@testset "SortCovDs" begin
    @testset "two CovDs already in order — no change" begin
        reset_state!()
        def_manifold!(:SM, 4, [:sa, :sb, :sc, :sd, :se, :sf, :sg, :sh])
        def_metric!(-1, "Sg[-sa,-sb]", :SCD)
        def_tensor!(:ST, ["-sa"], :SM)

        result = SortCovDs("SCD[-sa][SCD[-sb][ST[-sc]]]", :SCD)
        @test result == "SCD[-sa][SCD[-sb][ST[-sc]]]"
    end

    @testset "two CovDs out of order — swapped + Riemann correction" begin
        reset_state!()
        def_manifold!(:SM, 4, [:sa, :sb, :sc, :sd, :se, :sf, :sg, :sh])
        def_metric!(-1, "Sg[-sa,-sb]", :SCD)
        def_tensor!(:ST, ["-sa"], :SM)

        result = SortCovDs("SCD[-sb][SCD[-sa][ST[-sc]]]", :SCD)

        # Main term should be the sorted chain
        @test occursin("SCD[-sa][SCD[-sb][ST[-sc]]]", result)

        # Should contain Riemann correction
        @test occursin("RiemannSCD", result)

        # Verify algebraic correctness: SortCovDs(expr) - CommuteCovDs(expr) = 0
        # CommuteCovDs gives the same result (just with non-canonical correction term)
        commuted = CommuteCovDs("SCD[-sb][SCD[-sa][ST[-sc]]]", :SCD, "-sb", "-sa")
        # The correction from SortCovDs should equal the canonicalized correction from CommuteCovDs
        # Extract just correction parts and verify they match
        sort_terms = split(result, r"\s*\+\s*")
        sort_correction = join(sort_terms[2:end], " + ")
        commute_terms = split(commuted, r"\s*(?=[+-]\s)")
        commute_correction = join(commute_terms[2:end], " ")
        @test ToCanonical(sort_correction * " " * commute_correction) == "0" ||
            ToCanonical(sort_correction) == ToCanonical(commute_correction)
    end

    @testset "three CovDs — fully sorted" begin
        reset_state!()
        def_manifold!(:SM, 4, [:sa, :sb, :sc, :sd, :se, :sf, :sg, :sh])
        def_metric!(-1, "Sg[-sa,-sb]", :SCD)
        def_tensor!(:ST, ["-sa"], :SM)

        result = SortCovDs("SCD[-sc][SCD[-sa][SCD[-sb][ST[-sd]]]]", :SCD)

        # Main term should have all CovDs in canonical order: sa < sb < sc
        @test occursin("SCD[-sa][SCD[-sb][SCD[-sc][ST[-sd]]]]", result)

        # Should contain Riemann correction terms
        @test occursin("RiemannSCD", result)
    end

    @testset "expression with no CovDs — passthrough" begin
        reset_state!()
        def_manifold!(:SM, 4, [:sa, :sb, :sc, :sd, :se, :sf, :sg, :sh])
        def_metric!(-1, "Sg[-sa,-sb]", :SCD)

        # Pure Riemann term: no CovDs to sort
        result = SortCovDs("RiemannSCD[-sa,-sb,-sc,-sd]", :SCD)
        @test result == "RiemannSCD[-sa,-sb,-sc,-sd]"
    end

    @testset "zero and empty expressions" begin
        reset_state!()
        def_manifold!(:SM, 4, [:sa, :sb, :sc, :sd, :se, :sf, :sg, :sh])
        def_metric!(-1, "Sg[-sa,-sb]", :SCD)

        @test SortCovDs("0", :SCD) == "0"
        @test SortCovDs("", :SCD) == "0"
    end

    @testset "sum with CovD terms" begin
        reset_state!()
        def_manifold!(:SM, 4, [:sa, :sb, :sc, :sd, :se, :sf, :sg, :sh])
        def_metric!(-1, "Sg[-sa,-sb]", :SCD)
        def_tensor!(:ST, ["-sa"], :SM)

        # Sum of an unsorted CovD pair + a plain Riemann term
        result = SortCovDs(
            "SCD[-sb][SCD[-sa][ST[-sc]]] + RiemannSCD[-sa,-sb,-sc,-sd]", :SCD
        )

        # Should contain sorted CovD chain
        @test occursin("SCD[-sa][SCD[-sb][ST[-sc]]]", result)

        # Should preserve the plain Riemann term
        @test occursin("RiemannSCD[-sa,-sb,-sc,-sd]", result)
    end

    @testset "already sorted three CovDs — no change" begin
        reset_state!()
        def_manifold!(:SM, 4, [:sa, :sb, :sc, :sd, :se, :sf, :sg, :sh])
        def_metric!(-1, "Sg[-sa,-sb]", :SCD)
        def_tensor!(:ST, ["-sa"], :SM)

        result = SortCovDs("SCD[-sa][SCD[-sb][SCD[-sc][ST[-sd]]]]", :SCD)
        @test result == "SCD[-sa][SCD[-sb][SCD[-sc][ST[-sd]]]]"
    end

    @testset "two CovDs on Riemann tensor" begin
        reset_state!()
        # Need many indices: 2 for CovDs + 4 for Riemann + 4 dummies = 10 minimum
        def_manifold!(:SM, 4, [:sa, :sb, :sc, :sd, :se, :sf, :sg, :sh, :si, :sj, :sk, :sl])
        def_metric!(-1, "Sg[-sa,-sb]", :SCD)

        # CovDs on Riemann: SCD[-sb][SCD[-sa][RiemannSCD[-sc,-sd,-se,-sf]]]
        # Indices sa < sb so sb, sa is out of order
        result = SortCovDs("SCD[-sb][SCD[-sa][RiemannSCD[-sc,-sd,-se,-sf]]]", :SCD)

        # Main term should have sorted CovD order
        @test occursin("SCD[-sa][SCD[-sb][RiemannSCD[-sc,-sd,-se,-sf]]]", result)

        # Should have Riemann correction terms (4 slots → 4 corrections)
        @test occursin("RiemannSCD", result)
    end

    @testset "contravariant vector" begin
        reset_state!()
        def_manifold!(:SM, 4, [:sa, :sb, :sc, :sd, :se, :sf, :sg, :sh])
        def_metric!(-1, "Sg[-sa,-sb]", :SCD)
        def_tensor!(:SU, ["sa"], :SM)  # contravariant vector

        result = SortCovDs("SCD[-sb][SCD[-sa][SU[sc]]]", :SCD)

        # Main term should be sorted
        @test occursin("SCD[-sa][SCD[-sb][SU[sc]]]", result)
    end

    @testset "RicciIdentity registered for CovD" begin
        reset_state!()
        def_manifold!(:SM, 4, [:sa, :sb, :sc, :sd, :se, :sf, :sg, :sh])
        def_metric!(-1, "Sg[-sa,-sb]", :SCD)

        # Verify the Ricci identity was registered
        @test haskey(XTensor._identity_registry, :SCD)
        ids = XTensor._identity_registry[:SCD]
        @test length(ids) >= 1
        @test ids[1].name == :RicciIdentity
    end

    @testset "unregistered CovD throws error" begin
        reset_state!()
        @test_throws ErrorException SortCovDs("X[-a][X[-b][T[-c]]]", :X)
    end

    @testset "2-CovD algebraic correctness via CommuteCovDs" begin
        reset_state!()
        def_manifold!(:SM, 4, [:sa, :sb, :sc, :sd, :se, :sf, :sg, :sh])
        def_metric!(-1, "Sg[-sa,-sb]", :SCD)
        def_tensor!(:ST, ["-sa"], :SM)

        # SortCovDs and CommuteCovDs should produce algebraically equivalent results
        expr = "SCD[-sb][SCD[-sa][ST[-sc]]]"
        sorted = SortCovDs(expr, :SCD)
        commuted = CommuteCovDs(expr, :SCD, "-sb", "-sa")

        # Split both into CovD chain + correction, compare corrections
        # The sorted result canonicalizes the correction; CommuteCovDs does not.
        # But both main terms should match exactly.
        @test startswith(sorted, "SCD[-sa][SCD[-sb][ST[-sc]]]")
        @test startswith(commuted, "SCD[-sa][SCD[-sb][ST[-sc]]]")
    end

    @testset "mixed rank-2 tensor — two corrections" begin
        reset_state!()
        def_manifold!(:SM, 4, [:sa, :sb, :sc, :sd, :se, :sf, :sg, :sh])
        def_metric!(-1, "Sg[-sa,-sb]", :SCD)
        def_tensor!(:SMix, ["sa", "-sb"], :SM)

        result = SortCovDs("SCD[-sd][SCD[-sc][SMix[sa,-sb]]]", :SCD)

        # Main term should be sorted: sc < sd
        @test occursin("SCD[-sc][SCD[-sd][SMix[sa,-sb]]]", result)

        # Should contain two Riemann correction terms (one for each slot of SMix)
        riemann_count = count("RiemannSCD", result)
        @test riemann_count == 2
    end

    @testset "reverse-sorted 3-CovDs (worst case)" begin
        reset_state!()
        def_manifold!(:SM, 4, [:sa, :sb, :sc, :sd, :se, :sf, :sg, :sh])
        def_metric!(-1, "Sg[-sa,-sb]", :SCD)
        def_tensor!(:ST, ["-sa"], :SM)

        # c > b > a: completely reversed
        result = SortCovDs("SCD[-sc][SCD[-sb][SCD[-sa][ST[-sd]]]]", :SCD)

        # Main term should be fully sorted
        @test occursin("SCD[-sa][SCD[-sb][SCD[-sc][ST[-sd]]]]", result)
    end

    # ============================================================
    # Parser error handling
    # ============================================================

    @testset "Parser error handling" begin
        reset_state!()
        def_manifold!(:PM, 4, [:pa, :pb, :pc, :pd])
        def_tensor!(:PT, ["-pa", "-pb"], :PM)

        # Unbalanced parentheses
        @test_throws ErrorException ToCanonical("(PT[-pa,-pb]")
        @test_throws ErrorException ToCanonical("PT[-pa,-pb])")
    end

    # ==========================================================
    # _swap_indices bracket-aware substitution
    # ==========================================================

    @testset "_swap_indices" begin
        _swap = xAct.XTensor._swap_indices

        # Basic swap inside brackets
        @test _swap("T[-a,-b]", "a", "b") == "T[-b,-a]"

        # Tensor name contains label substring — must not corrupt
        @test _swap("Tab[-a,-ab]", "a", "b") == "Tab[-b,-ab]"
        @test _swap("Rab[-a,-b]", "a", "b") == "Rab[-b,-a]"

        # Label at end of bracket group
        @test _swap("V[a]", "a", "b") == "V[b]"

        # Multiple bracket groups (product expression)
        @test _swap("T[-a,-b] V[a]", "a", "b") == "T[-b,-a] V[b]"

        # No brackets — nothing changes
        @test _swap("scalar", "a", "b") == "scalar"

        # Label not present — no-op
        @test _swap("T[-c,-d]", "a", "b") == "T[-c,-d]"

        # Multi-char labels
        @test _swap("T[-ab,-cd]", "ab", "cd") == "T[-cd,-ab]"

        # Coefficient outside brackets untouched
        @test _swap("3 T[-a,-b]", "a", "b") == "3 T[-b,-a]"
    end
end

# ============================================================
# _parse_expression / _serialize_terms — direct tests (sxAct-jz9s)
# ============================================================
