@testset "xTras" begin

    # ----------------------------------------------------------
    # CollectTensors
    # ----------------------------------------------------------
    @testset "CollectTensors" begin
        reset_state!()
        def_manifold!(:XM, 4, [:xa, :xb, :xc, :xd])
        def_metric!(1, "XG[-xa,-xb]", :XD)
        def_tensor!(:XT, ["-xa", "-xb"], :XM; symmetry_str="Symmetric[{-xa,-xb}]")
        def_tensor!(:XA, ["-xa", "-xb"], :XM; symmetry_str="Antisymmetric[{-xa,-xb}]")

        # Two identical terms combine
        @test CollectTensors("XT[-xa,-xb] + XT[-xa,-xb]") == "2 XT[-xa,-xb]"

        # Opposite terms cancel
        @test CollectTensors("XT[-xa,-xb] - XT[-xa,-xb]") == "0"

        # Symmetric equivalence: T[-a,-b] + T[-b,-a] = 2*T[-a,-b]
        @test CollectTensors("XT[-xa,-xb] + XT[-xb,-xa]") == "2 XT[-xa,-xb]"

        # Antisymmetric cancellation: A[-a,-b] + A[-b,-a] = 0
        @test CollectTensors("XA[-xa,-xb] + XA[-xb,-xa]") == "0"

        # Single term passes through
        @test CollectTensors("XT[-xa,-xb]") == "XT[-xa,-xb]"
    end

    # ----------------------------------------------------------
    # AllContractions
    # ----------------------------------------------------------
    @testset "AllContractions" begin
        reset_state!()
        def_manifold!(:XM, 4, [:xa, :xb, :xc, :xd])
        def_metric!(1, "XG[-xa,-xb]", :XD)
        def_tensor!(:XT, ["-xa", "-xb"], :XM; symmetry_str="Symmetric[{-xa,-xb}]")

        # Metric trace: g^{ab} g_{ab} = dim = 4
        result = AllContractions("XG[-xa,-xb]", :XG)
        @test length(result) == 1
        @test result[1] == "4"
    end

    # ----------------------------------------------------------
    # SymmetryOf
    # ----------------------------------------------------------
    @testset "SymmetryOf" begin
        reset_state!()
        def_manifold!(:XM, 4, [:xa, :xb, :xc, :xd])
        def_metric!(1, "XG[-xa,-xb]", :XD)
        def_tensor!(:XT, ["-xa", "-xb"], :XM; symmetry_str="Symmetric[{-xa,-xb}]")
        def_tensor!(:XA, ["-xa", "-xb"], :XM; symmetry_str="Antisymmetric[{-xa,-xb}]")
        def_tensor!(:XN, ["-xa", "-xb"], :XM)

        # Symmetric tensor
        @test SymmetryOf("XT[-xa,-xb]") == "Symmetric"

        # Antisymmetric tensor
        @test SymmetryOf("XA[-xa,-xb]") == "Antisymmetric"

        # Metric is symmetric
        @test SymmetryOf("XG[-xa,-xb]") == "Symmetric"

        # Zero is symmetric
        @test SymmetryOf("0") == "Symmetric"

        # Scalar is symmetric
        @test SymmetryOf("RicciScalarXD[]") == "Symmetric"

        # General tensor (no symmetry)
        @test SymmetryOf("XN[-xa,-xb]") == "NoSymmetry"
    end

    # ----------------------------------------------------------
    # MakeTraceFree
    # ----------------------------------------------------------
    @testset "MakeTraceFree" begin
        reset_state!()
        def_manifold!(:XM, 4, [:xa, :xb, :xc, :xd])
        def_metric!(1, "XG[-xa,-xb]", :XD)
        def_tensor!(:XT, ["-xa", "-xb"], :XM; symmetry_str="Symmetric[{-xa,-xb}]")

        # Trace-free of metric is zero (g_{ab} - (1/4)*g_{ab}*4 = 0)
        @test MakeTraceFree("XG[-xa,-xb]", :XG) == "0"

        # Trace-free of zero is zero
        @test MakeTraceFree("0", :XG) == "0"

        # 2*metric is also zero
        @test MakeTraceFree("2 XG[-xa,-xb]", :XG) == "0"

        # Trace-free of symmetric tensor should have structure T - (1/dim)*g*tr(T)
        tf = MakeTraceFree("XT[-xa,-xb]", :XG)
        @test tf != "0"  # Non-trivial for general symmetric tensor
        @test occursin("XT", tf)

        # Weyl tensor is in traceless registry
        @test :WeylXD in XTensor._traceless_tensors
    end
end

# ============================================================
# Multi-term identity framework
# ============================================================
