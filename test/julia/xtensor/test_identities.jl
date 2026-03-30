@testset "MultiTermIdentity" begin
    reset_state!()

    @testset "registration and query" begin
        # Define a manifold and Riemann-symmetric tensor
        def_manifold!(:MI, 4, [:mia, :mib, :mic, :mid, :mie, :mif, :mig, :mih])
        def_metric!(-1, "gMI[-mia,-mib]", "DI")

        # Riemann tensor should auto-register first Bianchi
        @test haskey(XTensor._identity_registry, :RiemannDI)
        ids = XTensor._identity_registry[:RiemannDI]
        @test length(ids) == 1
        @test ids[1].name == :FirstBianchi
        @test ids[1].tensor == :RiemannDI
        @test ids[1].n_slots == 4
        @test ids[1].fixed_slots == [1]
        @test ids[1].cycled_slots == [2, 3, 4]
        @test ids[1].slot_perms == [[1, 2, 3], [2, 1, 3], [3, 1, 2]]
        @test ids[1].coefficients == [1 // 1, -1 // 1, 1 // 1]
        @test ids[1].eliminate == 3

        # Weyl tensor also has RiemannSymmetric → also registered
        @test haskey(XTensor._identity_registry, :WeylDI)
        @test XTensor._identity_registry[:WeylDI][1].name == :FirstBianchi
    end

    @testset "reset_state! clears registry" begin
        reset_state!()
        @test isempty(XTensor._identity_registry)
    end

    @testset "manual registration" begin
        reset_state!()
        def_manifold!(:MR, 4, [:ra, :rb, :rc, :rd, :re, :rf, :rg, :rh])

        # Define a non-Riemann tensor, manually register an identity
        def_tensor!(
            :TR, ["-ra", "-rb", "-rc"], :MR; symmetry_str="Antisymmetric[{-ra,-rb,-rc}]"
        )
        @test !haskey(XTensor._identity_registry, :TR)

        # Register a custom identity
        id = MultiTermIdentity(
            :TestIdentity,
            :TR,
            3,
            Int[],
            [1, 2, 3],
            [[1, 2, 3], [2, 3, 1], [3, 1, 2]],
            [1 // 1, 1 // 1, 1 // 1],
            3,
        )
        RegisterIdentity!(:TR, id)
        @test haskey(XTensor._identity_registry, :TR)
        @test length(XTensor._identity_registry[:TR]) == 1
        @test XTensor._identity_registry[:TR][1].name == :TestIdentity
    end

    @testset "first Bianchi via framework matches hardcoded" begin
        reset_state!()
        def_manifold!(:MB, 4, [:ba, :bb, :bc, :bd, :be, :bf, :bg, :bh])
        def_metric!(-1, "gB[-ba,-bb]", "DB")

        # The first Bianchi identity: R[-a,-b,-c,-d] + R[-b,-c,-a,-d] + R[-c,-a,-b,-d] = 0
        r1 = ToCanonical(
            "RiemannDB[-ba,-bb,-bc,-bd] + RiemannDB[-bb,-bc,-ba,-bd] + RiemannDB[-bc,-ba,-bb,-bd]",
        )
        @test r1 == "0"

        # X₃ term should be eliminated when all three are present
        # R[a,d,b,c] is the X₃ form (second index = d, largest of {b,c,d})
        # After canonicalization, it should be re-expressed via X₁ and X₂
        expr = "RiemannDB[-ba,-bb,-bc,-bd] + RiemannDB[-ba,-bc,-bb,-bd] + RiemannDB[-ba,-bd,-bb,-bc]"
        result = ToCanonical(expr)
        # X₁ = R[-ba,-bb,-bc,-bd] (second idx = bb, smallest)
        # X₂ = R[-ba,-bc,-bb,-bd] (second idx = bc, middle)
        # X₃ = R[-ba,-bd,-bb,-bc] (second idx = bd, largest) → eliminated
        # X₃ = X₂ - X₁, so: X₁ + X₂ + (X₂ - X₁) = 2*X₂
        @test result == "2 RiemannDB[-ba,-bc,-bb,-bd]"

        # Kretschner scalar should still simplify correctly
        kr = Simplify("RiemannDB[-ba,-bb,-bc,-bd] RiemannDB[ba,bb,bc,bd]")
        @test occursin("RiemannDB", kr)
    end

    @testset "framework handles multiple tensors" begin
        reset_state!()
        def_manifold!(:MM, 4, [:ma, :mb, :mc, :md, :me, :mf, :mg, :mh])
        def_metric!(-1, "gM[-ma,-mb]", "DM")

        # Both Riemann and Weyl should have Bianchi registered
        @test haskey(XTensor._identity_registry, :RiemannDM)
        @test haskey(XTensor._identity_registry, :WeylDM)

        # Bianchi should work for Weyl too
        weyl_bianchi = ToCanonical(
            "WeylDM[-ma,-mb,-mc,-md] + WeylDM[-mb,-mc,-ma,-md] + WeylDM[-mc,-ma,-mb,-md]"
        )
        @test weyl_bianchi == "0"
    end

    @testset "user-defined RiemannSymmetric tensor gets Bianchi" begin
        reset_state!()
        def_manifold!(:MU, 4, [:ua, :ub, :uc, :ud, :ue, :uf, :ug, :uh])

        # User-defined tensor with RiemannSymmetric symmetry
        def_tensor!(
            :UserRiem,
            ["-ua", "-ub", "-uc", "-ud"],
            :MU;
            symmetry_str="RiemannSymmetric[{-ua,-ub,-uc,-ud}]",
        )
        @test haskey(XTensor._identity_registry, :UserRiem)
        @test XTensor._identity_registry[:UserRiem][1].name == :FirstBianchi

        # Bianchi identity should apply
        result = ToCanonical(
            "UserRiem[-ua,-ub,-uc,-ud] + UserRiem[-ub,-uc,-ua,-ud] + UserRiem[-uc,-ua,-ub,-ud]",
        )
        @test result == "0"
    end
end

# ============================================================
# SortCovDs tests
# ============================================================
