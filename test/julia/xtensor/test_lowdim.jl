@testset "Low-dim manifolds" begin
    @testset "1D manifold: no curvature tensors" begin
        reset_state!()
        def_manifold!(:M1d, 1, [:xa, :xb])
        def_metric!(1, "g1d[-xa,-xb]", :D1d)
        # 1D: Ricci exists (2 indices), but Riemann does not (needs 4)
        @test TensorQ(:RicciD1d)
        @test TensorQ(:RicciScalarD1d)
        @test !TensorQ(:RiemannD1d)
        @test !TensorQ(:WeylD1d)
        # Christoffel exists (2D+ labels)
        @test TensorQ(:ChristoffelD1d)
    end

    @testset "2D manifold: curvature and Christoffel" begin
        reset_state!()
        def_manifold!(:M2d, 2, [:ya, :yb, :yc, :yd])
        def_metric!(-1, "g2d[-ya,-yb]", :D2d)
        @test TensorQ(:RiemannD2d)
        @test TensorQ(:RicciD2d)
        @test TensorQ(:EinsteinD2d)
        @test TensorQ(:WeylD2d)
        @test TensorQ(:ChristoffelD2d)

        # Riemann antisymmetry holds in 2D
        result = ToCanonical("RiemannD2d[-ya,-yb,-yc,-yd] + RiemannD2d[-yb,-ya,-yc,-yd]")
        @test result == "0"
    end

    @testset "3D manifold: Einstein trace" begin
        reset_state!()
        def_manifold!(:M3d, 3, [:za, :zb, :zc, :zd, :ze, :zf])
        def_metric!(1, "g3d[-za,-zb]", :D3d)
        # Einstein trace: G^a_a = (1 - n/2) R = (1 - 3/2) R = -1/2 R
        result = Contract("EinsteinD3d[za,-za]")
        @test occursin("RicciScalarD3d", result)
    end

    @testset "perturb order 0 throws" begin
        reset_state!()
        def_manifold!(:Mp, 4, [:pa, :pb, :pc, :pd])
        def_metric!(-1, "gp[-pa,-pb]", :Dp)
        def_tensor!(:Tp, ["-pa", "-pb"], :Mp)
        @test_throws ArgumentError perturb("Tp[-pa,-pb]", 0)
    end

    # ============================================================
    # Session struct tests (Phase F: sxAct-mbzz)
    # ============================================================

    @testset "Session" begin
        @testset "Session() constructor creates empty state" begin
            s = Session()
            @test s.generation == 0
            @test isempty(s.manifolds)
            @test isempty(s.tensors)
            @test isempty(s.metrics)
            @test isempty(s.vbundles)
            @test isempty(s.perturbations)
            @test isempty(s.bases)
            @test isempty(s.charts)
            @test isempty(s.basis_changes)
            @test isempty(s.ctensors)
            @test isempty(s.metric_name_index)
            @test isempty(s.parallel_deriv_index)
            @test isempty(s.manifold_list)
            @test isempty(s.tensor_list)
            @test isempty(s.vbundle_list)
            @test isempty(s.perturbation_list)
            @test isempty(s.basis_list)
            @test isempty(s.chart_list)
            @test isempty(s.traceless_tensors)
            @test isempty(s.trace_scalars)
            @test isempty(s.einstein_expansion)
            @test isempty(s.identity_registry)
        end

        @testset "two Sessions define :M independently" begin
            s1 = Session()
            s2 = Session()
            def_manifold!(:M, 4, [:a, :b, :c, :d]; session=s1)
            def_manifold!(:M, 3, [:x, :y, :z]; session=s2)

            # Each session has its own :M with different dimension
            @test s1.manifolds[:M].dimension == 4
            @test s2.manifolds[:M].dimension == 3

            # Default session is unaffected
            @test !ManifoldQ(:M)
        end

        @testset "reset_session! increments generation" begin
            s = Session()
            @test s.generation == 0
            def_manifold!(:R, 2, [:u, :v]; session=s)
            @test haskey(s.manifolds, :R)

            reset_session!(s)
            @test s.generation == 1
            @test isempty(s.manifolds)
            @test isempty(s.manifold_list)

            reset_session!(s)
            @test s.generation == 2
        end

        @testset "default session works transparently" begin
            reset_state!()
            def_manifold!(:X, 4, [:xa, :xb, :xc, :xd])
            @test ManifoldQ(:X)
            @test list_manifolds() == [:X]

            # The default session reflects the same state
            ds = XTensor._default_session[]
            @test haskey(ds.manifolds, :X)
            @test ds.manifolds[:X].dimension == 4
        end

        @testset "stale detection via generation" begin
            s = Session()
            def_manifold!(:S, 2, [:i, :j]; session=s)
            old_gen = s.generation
            @test old_gen == 0

            reset_session!(s)
            @test s.generation != old_gen
            @test s.generation == old_gen + 1
            # After reset, the manifold is gone
            @test !haskey(s.manifolds, :S)
        end

        @testset "session isolation: def_metric! cascade" begin
            s = Session()
            def_manifold!(:Iso, 4, [:ia, :ib, :ic, :id]; session=s)
            def_metric!(-1, "giso[-ia,-ib]", :DIso; session=s)

            # Curvature tensors auto-created in the isolated session
            @test haskey(s.tensors, :RiemannDIso)
            @test haskey(s.tensors, :RicciDIso)
            @test haskey(s.tensors, :RicciScalarDIso)
            @test haskey(s.tensors, :EinsteinDIso)
            @test haskey(s.tensors, :WeylDIso)
            @test haskey(s.tensors, :ChristoffelDIso)
            @test haskey(s.metrics, :DIso)

            # Default session is unaffected
            @test !TensorQ(:RiemannDIso)
            @test !MetricQ(:DIso)
        end

        @testset "session isolation: def_tensor! with symmetry" begin
            s = Session()
            def_manifold!(:Ts, 4, [:ta, :tb, :tc, :td]; session=s)
            def_tensor!(
                :Asym,
                ["-ta", "-tb"],
                :Ts;
                symmetry_str="Antisymmetric[{-ta,-tb}]",
                session=s,
            )
            @test haskey(s.tensors, :Asym)
            @test s.tensors[:Asym].symmetry.type == :Antisymmetric

            # Default session unaffected
            @test !TensorQ(:Asym)
        end
    end
end
