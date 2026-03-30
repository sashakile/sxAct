# ============================================================
# Christoffel symbols
# ============================================================

@testset "Christoffel" begin
    @testset "Christoffel tensor auto-created by def_metric!" begin
        reset_state!()
        def_manifold!(:Km4, 4, [:kma, :kmb, :kmc, :kmd])
        def_metric!(-1, "Kmg[-kma,-kmb]", :Kmd)
        @test TensorQ(:ChristoffelKmd)
        t = get_tensor(:ChristoffelKmd)
        @test length(t.slots) == 3
        @test t.slots[1].covariant == false   # up
        @test t.slots[2].covariant == true    # down
        @test t.slots[3].covariant == true    # down
        @test t.symmetry.type == :Symmetric
        @test t.symmetry.slots == [2, 3]
    end

    @testset "Christoffel created for 2D manifold" begin
        reset_state!()
        def_manifold!(:Km2, 2, [:km2a, :km2b])
        def_metric!(-1, "Km2g[-km2a,-km2b]", :Km2d)
        @test TensorQ(:ChristoffelKm2d)
        t = get_tensor(:ChristoffelKm2d)
        @test length(t.slots) == 3
        @test t.slots[1].covariant == false  # contravariant slot
        @test t.slots[2].covariant == true   # covariant
        @test t.slots[3].covariant == true   # covariant
    end

    @testset "Christoffel of Minkowski metric = 0" begin
        reset_state!()
        def_manifold!(:Fm4, 4, [:fma, :fmb, :fmc, :fmd])
        def_metric!(-1, "Fmg[-fma,-fmb]", :Fmd)
        def_chart!(:FC, :Fm4, [1, 2, 3, 4], [:ft, :fx, :fy, :fz])

        eta = Any[-1 0 0 0; 0 1 0 0; 0 0 1 0; 0 0 0 1]
        set_components!(:Fmg, eta, [:FC, :FC])

        ct = christoffel!(:Fmg, :FC)
        @test ct.tensor == :ChristoffelFmd
        @test ct.bases == [:FC, :FC, :FC]
        @test all(ct.array .≈ 0.0)
    end

    @testset "Christoffel of 3D diagonal metric" begin
        reset_state!()
        def_manifold!(:Dm3, 3, [:dma, :dmb, :dmc])
        def_metric!(1, "Dmg[-dma,-dmb]", :Dmd)
        def_chart!(:DC, :Dm3, [1, 2, 3], [:dx1, :dx2, :dx3])

        # Diagonal metric: g = diag(1, 4, 9)
        g_arr = Any[1 0 0; 0 4 0; 0 0 9]
        set_components!(:Dmg, g_arr, [:DC, :DC])

        # Constant metric → Christoffel = 0
        ct = christoffel!(:Dmg, :DC)
        @test all(ct.array .≈ 0.0)
    end

    @testset "Christoffel with non-trivial metric derivatives" begin
        reset_state!()
        def_manifold!(:Nm4, 4, [:nma, :nmb, :nmc, :nmd])
        def_metric!(-1, "Nmg[-nma,-nmb]", :Nmd)
        def_chart!(:NC, :Nm4, [1, 2, 3, 4], [:nt, :nr, :ntheta, :nphi])

        # Schwarzschild-like metric at r=3M, θ=π/2, with M=1:
        # g_{tt} = -(1-2/r), g_{rr} = 1/(1-2/r), g_{θθ} = r², g_{φφ} = r²sin²θ
        # At r=3, θ=π/2: f = 1-2/3 = 1/3
        r = 3.0
        M = 1.0
        theta = π / 2
        f = 1.0 - 2.0 * M / r  # 1/3

        g = zeros(4, 4)
        g[1, 1] = -f          # g_tt = -1/3
        g[2, 2] = 1.0 / f     # g_rr = 3
        g[3, 3] = r^2          # g_θθ = 9
        g[4, 4] = r^2 * sin(theta)^2  # g_φφ = 9 (sin(π/2)=1)
        set_components!(:Nmg, g, [:NC, :NC])

        # Metric derivatives: dg[c, a, b] = ∂_c g_{ab}
        # Only non-zero for ∂_r terms (index 2) and ∂_θ term for g_φφ
        dg = zeros(4, 4, 4)
        # ∂_r g_{tt} = ∂_r(-(1-2M/r)) = -2M/r²
        dg[2, 1, 1] = -2.0 * M / r^2
        # ∂_r g_{rr} = ∂_r((1-2M/r)^{-1}) = -2M/(r²f²)
        dg[2, 2, 2] = -2.0 * M / (r^2 * f^2)
        # ∂_r g_{θθ} = 2r = 6
        dg[2, 3, 3] = 2.0 * r
        # ∂_r g_{φφ} = 2r sin²θ = 6
        dg[2, 4, 4] = 2.0 * r * sin(theta)^2
        # ∂_θ g_{φφ} = 2r² sinθ cosθ = 0 at θ=π/2
        dg[3, 4, 4] = 2.0 * r^2 * sin(theta) * cos(theta)

        ct = christoffel!(:Nmg, :NC; metric_derivs=dg)

        # Verify known Schwarzschild Christoffels at r=3, θ=π/2, M=1:
        # Γ^t_{tr} = Γ^t_{rt} = M/(r²f) = 1/(9 * 1/3) = 1/3
        @test ct.array[1, 1, 2] ≈ 1.0 / 3.0 atol = 1e-12
        @test ct.array[1, 2, 1] ≈ 1.0 / 3.0 atol = 1e-12  # symmetry

        # Γ^r_{tt} = Mf/r² = (1/3)/9 = 1/27
        @test ct.array[2, 1, 1] ≈ M * f / r^2 atol = 1e-12

        # Γ^r_{rr} = -M/(r²f) = -1/(9*1/3) = -1/3
        @test ct.array[2, 2, 2] ≈ -M / (r^2 * f) atol = 1e-12

        # Γ^r_{θθ} = -(r - 2M) = -rf = -1
        @test ct.array[2, 3, 3] ≈ -r * f atol = 1e-12

        # Γ^r_{φφ} = -(r - 2M)sin²θ = -rf sin²θ = -1
        @test ct.array[2, 4, 4] ≈ -r * f * sin(theta)^2 atol = 1e-12

        # Γ^θ_{rθ} = 1/r = 1/3
        @test ct.array[3, 2, 3] ≈ 1.0 / r atol = 1e-12
        @test ct.array[3, 3, 2] ≈ 1.0 / r atol = 1e-12  # symmetry

        # Γ^θ_{φφ} = -sinθ cosθ = 0 at θ=π/2
        @test ct.array[3, 4, 4] ≈ 0.0 atol = 1e-12

        # Γ^φ_{rφ} = 1/r = 1/3
        @test ct.array[4, 2, 4] ≈ 1.0 / r atol = 1e-12
        @test ct.array[4, 4, 2] ≈ 1.0 / r atol = 1e-12  # symmetry

        # Γ^φ_{θφ} = cosθ/sinθ = 0 at θ=π/2
        @test ct.array[4, 3, 4] ≈ 0.0 atol = 1e-12

        # All other components should be 0
        # Γ^t_{tt} = 0
        @test ct.array[1, 1, 1] ≈ 0.0 atol = 1e-12
        # Γ^t_{rr} = 0
        @test ct.array[1, 2, 2] ≈ 0.0 atol = 1e-12
    end

    @testset "Christoffel stored as CTensor" begin
        reset_state!()
        def_manifold!(:Sm4, 4, [:sma, :smb, :smc, :smd])
        def_metric!(-1, "Smg[-sma,-smb]", :Smd)
        def_chart!(:SC, :Sm4, [1, 2, 3, 4], [:st, :sx, :sy, :sz])

        eta = Any[-1 0 0 0; 0 1 0 0; 0 0 1 0; 0 0 0 1]
        set_components!(:Smg, eta, [:SC, :SC])
        christoffel!(:Smg, :SC)

        @test CTensorQ(:ChristoffelSmd, :SC, :SC, :SC)
        ct = get_components(:ChristoffelSmd, [:SC, :SC, :SC])
        @test size(ct.array) == (4, 4, 4)
    end

    @testset "Christoffel string overload" begin
        reset_state!()
        def_manifold!(:So4, 4, [:soa, :sob, :soc, :sod])
        def_metric!(-1, "Sog[-soa,-sob]", :Sod)
        def_chart!(:SoC, :So4, [1, 2, 3, 4], [:sot, :sox, :soy, :soz])

        eta = Any[-1 0 0 0; 0 1 0 0; 0 0 1 0; 0 0 0 1]
        set_components!(:Sog, eta, [:SoC, :SoC])

        ct = christoffel!("Sog", "SoC")
        @test all(ct.array .≈ 0.0)
    end

    @testset "Christoffel error: no metric" begin
        reset_state!()
        @test_throws Exception christoffel!(:NoMetric, :NoBasis)
    end

    @testset "Christoffel error: wrong metric_derivs shape" begin
        reset_state!()
        def_manifold!(:Em4, 4, [:ema, :emb, :emc, :emd])
        def_metric!(-1, "Emg[-ema,-emb]", :Emd)
        def_chart!(:EC, :Em4, [1, 2, 3, 4], [:et, :ex, :ey, :ez])

        eta = Any[-1 0 0 0; 0 1 0 0; 0 0 1 0; 0 0 0 1]
        set_components!(:Emg, eta, [:EC, :EC])

        wrong_dg = zeros(3, 3, 3)
        @test_throws Exception christoffel!(:Emg, :EC; metric_derivs=wrong_dg)
    end
end

# ============================================================
# xTras tests
# ============================================================
