# Tests for XTensor.jl — DefManifold, DefMetric, DefTensor, ToCanonical.
using Test
using xAct

@testset "XTensor" begin

    # Reset state before each top-level testset
    reset_state!()

    @testset "DefManifold" begin
        reset_state!()
        m = def_manifold!(:Tn4, 4, [:tna, :tnb, :tnc, :tnd])
        @test m.name == :Tn4
        @test m.dimension == 4
        @test ManifoldQ(:Tn4)
        @test !ManifoldQ(:NotDefined)
        @test Dimension(:Tn4) == 4
        @test :Tn4 in list_manifolds()

        # VBundle auto-created
        @test VBundleQ(:TangentTn4)
        @test IndicesOfVBundle(:TangentTn4) == [:tna, :tnb, :tnc, :tnd]

        # Duplicate definition throws
        @test_throws Exception def_manifold!(:Tn4, 4, [:tna, :tnb, :tnc, :tnd])
    end

    @testset "DefTensor" begin
        reset_state!()
        def_manifold!(:Tm4, 4, [:tma, :tmb, :tmc, :tmd])

        # Symmetric tensor
        ts = def_tensor!(
            :TmS, ["-tma", "-tmb"], :Tm4; symmetry_str="Symmetric[{-tma,-tmb}]"
        )
        @test TensorQ(:TmS)
        @test ts.symmetry.type == :Symmetric
        @test ts.symmetry.slots == [1, 2]

        # Antisymmetric tensor
        ta = def_tensor!(
            :TmA, ["-tma", "-tmb"], :Tm4; symmetry_str="Antisymmetric[{-tma,-tmb}]"
        )
        @test ta.symmetry.type == :Antisymmetric

        # No symmetry
        tv = def_tensor!(:TmV, ["tma"], :Tm4)
        @test tv.symmetry.type == :NoSymmetry

        @test :TmS in list_tensors()
    end

    @testset "DefMetric — auto-curvature tensors" begin
        reset_state!()
        def_manifold!(:Cnm, 4, [:cna, :cnb, :cnc, :cnd])
        def_metric!(-1, "Cng[-cna,-cnb]", :Cnd)

        @test TensorQ(:Cng)
        @test TensorQ(:RiemannCnd)
        @test TensorQ(:RicciCnd)
        @test TensorQ(:RicciScalarCnd)
        @test TensorQ(:EinsteinCnd)
        @test TensorQ(:WeylCnd)

        # Riemann has RiemannSymmetric symmetry
        r = get_tensor(:RiemannCnd)
        @test r.symmetry.type == :RiemannSymmetric
        @test r.symmetry.slots == [1, 2, 3, 4]

        # Ricci is symmetric
        rc = get_tensor(:RicciCnd)
        @test rc.symmetry.type == :Symmetric

        # RicciScalar is scalar (no slots)
        rcs = get_tensor(:RicciScalarCnd)
        @test isempty(rcs.slots)
    end

    @testset "ToCanonical — zero and identity" begin
        reset_state!()
        @test ToCanonical("0") == "0"
        @test ToCanonical("") == "0"
    end

    @testset "ToCanonical — symmetric swap" begin
        reset_state!()
        def_manifold!(:Cnm, 4, [:cna, :cnb, :cnc, :cnd])
        def_tensor!(:Cns, ["-cna", "-cnb"], :Cnm; symmetry_str="Symmetric[{-cna,-cnb}]")

        # Cns[-cna,-cnb] - Cns[-cnb,-cna] == 0
        result = ToCanonical("Cns[-cna,-cnb] - Cns[-cnb,-cna]")
        @test result == "0"

        # Single term is canonical
        result2 = ToCanonical("Cns[-cna,-cnb]")
        @test result2 == "Cns[-cna,-cnb]"
    end

    @testset "ToCanonical — antisymmetric sum" begin
        reset_state!()
        def_manifold!(:Cnm, 4, [:cna, :cnb, :cnc, :cnd])
        def_tensor!(:Cna, ["-cna", "-cnb"], :Cnm; symmetry_str="Antisymmetric[{-cna,-cnb}]")

        # Cna[-cna,-cnb] + Cna[-cnb,-cna] == 0
        result = ToCanonical("Cna[-cna,-cnb] + Cna[-cnb,-cna]")
        @test result == "0"
    end

    @testset "ToCanonical — idempotency" begin
        reset_state!()
        def_manifold!(:Cnm, 4, [:cna, :cnb, :cnc, :cnd])
        def_tensor!(:Cns, ["-cna", "-cnb"], :Cnm; symmetry_str="Symmetric[{-cna,-cnb}]")
        def_tensor!(:Cnv, ["cna"], :Cnm)

        expr = "Cns[-cna,-cnb] + Cnv[cna]"
        once = ToCanonical(expr)
        twice = ToCanonical(once)
        @test once == twice
    end

    @testset "ToCanonical — Riemann antisymmetry" begin
        reset_state!()
        def_manifold!(:Cnm, 4, [:cna, :cnb, :cnc, :cnd])
        def_metric!(-1, "Cng[-cna,-cnb]", :Cnd)

        # R[-a,-b,-c,-d] + R[-b,-a,-c,-d] == 0
        result = ToCanonical(
            "RiemannCnd[-cna,-cnb,-cnc,-cnd] + RiemannCnd[-cnb,-cna,-cnc,-cnd]"
        )
        @test result == "0"

        # R[-a,-b,-c,-d] + R[-a,-b,-d,-c] == 0
        result2 = ToCanonical(
            "RiemannCnd[-cna,-cnb,-cnc,-cnd] + RiemannCnd[-cna,-cnb,-cnd,-cnc]"
        )
        @test result2 == "0"

        # R[-a,-b,-c,-d] - R[-c,-d,-a,-b] == 0 (pair exchange)
        result3 = ToCanonical(
            "RiemannCnd[-cna,-cnb,-cnc,-cnd] - RiemannCnd[-cnc,-cnd,-cna,-cnb]"
        )
        @test result3 == "0"
    end

    @testset "ToCanonical — Riemann idempotency" begin
        reset_state!()
        def_manifold!(:Cnm, 4, [:cna, :cnb, :cnc, :cnd])
        def_metric!(-1, "Cng[-cna,-cnb]", :Cnd)

        expr = "RiemannCnd[-cna,-cnb,-cnc,-cnd]"
        once = ToCanonical(expr)
        twice = ToCanonical(once)
        @test once == twice
    end

    @testset "ToCanonical — product expression" begin
        reset_state!()
        def_manifold!(:CInv4, 4, [:cia, :cib, :cic, :cid, :cie, :cif])
        def_metric!(-1, "CIg[-cia,-cib]", :CID)

        # Kretschner: R[-a,-b,-c,-d] R[a,b,c,d] - R[-c,-d,-a,-b] R[c,d,a,b] = 0
        # (dummy relabeling + pair exchange)
        result = ToCanonical(
            "RiemannCID[-cia,-cib,-cic,-cid] RiemannCID[cia,cib,cic,cid] - RiemannCID[-cic,-cid,-cia,-cib] RiemannCID[cic,cid,cia,cib]",
        )
        @test result == "0"
    end

    @testset "ToCanonical — torsion partial-slot antisymmetry" begin
        reset_state!()
        def_manifold!(:QGM4, 4, [:qga, :qgb, :qgc, :qgd, :qge, :qgf])
        def_tensor!(
            :QGTorsion,
            ["qga", "-qgb", "-qgc"],
            :QGM4;
            symmetry_str="Antisymmetric[{-qgb,-qgc}]",
        )

        # QGTorsion[a,-b,-c] + QGTorsion[a,-c,-b] == 0
        result = ToCanonical("QGTorsion[qga,-qgb,-qgc] + QGTorsion[qga,-qgc,-qgb]")
        @test result == "0"
    end

    @testset "MemberQ and predicates" begin
        reset_state!()
        def_manifold!(:Pm, 3, [:pa, :pb, :pc])
        def_tensor!(:Pv, ["pa"], :Pm)

        @test MemberQ(:Manifolds, :Pm)
        @test MemberQ(:Tensors, :Pv)
        @test !MemberQ(:Manifolds, :Pv)
    end

    @testset "reset_state!" begin
        reset_state!()
        def_manifold!(:Rm, 2, [:ra, :rb])
        @test ManifoldQ(:Rm)
        reset_state!()
        @test !ManifoldQ(:Rm)
        @test isempty(list_manifolds())
    end

    @testset "Contract" begin
        reset_state!()
        def_manifold!(:Cm, 4, [:ca, :cb, :cc, :cd])
        def_metric!(1, "Cg[-ca,-cb]", :Cd)
        def_tensor!(:Cv, ["-ca"], :Cm)

        # SignDetOfMetric
        @test SignDetOfMetric(:Cg) == 1

        # Raise index: g^{ab} v_b → v^a
        @test Contract("Cg[ca,cb] Cv[-cb]") == "Cv[ca]"

        # Lower index: g_{ab} v^b → v_{-a} (result: Cv[-ca])
        @test Contract("Cg[-ca,-cb] Cv[cb]") == "Cv[-ca]"

        # Weyl tracelessness: g^{ac} W_{abcd} = 0
        reset_state!()
        def_manifold!(:Cm4, 4, [:cxa, :cxb, :cxc, :cxd, :cxe, :cxf])
        def_metric!(-1, "CIg[-cxa,-cxb]", :CxD)
        @test Contract("CIg[cxa,cxc] WeylCxD[-cxa,-cxb,-cxc,-cxd]") == "0"

        # Einstein trace in 4D: g^{ab} G_{ab} = -R
        @test Contract("CIg[cxa,cxb] EinsteinCxD[-cxa,-cxb]") == "-RicciScalarCxD[]"
        @test ToCanonical(
            Contract("CIg[cxa,cxb] EinsteinCxD[-cxa,-cxb]") * " + RicciScalarCxD[]"
        ) == "0"

        # Einstein trace in 3D (odd dimension): g^{ab} G_{ab} = (1 - 3/2)*R = -1/2 R
        reset_state!()
        def_manifold!(:M3t, 3, [:t3a, :t3b, :t3c, :t3d, :t3e, :t3f])
        def_metric!(-1, "gM3t[-t3a,-t3b]", :CD3t)
        @test Contract("gM3t[t3a,t3b] EinsteinCD3t[-t3a,-t3b]") ==
            "-(1/2) RicciScalarCD3t[]"

        # Einstein trace in 5D: g^{ab} G_{ab} = (1 - 5/2)*R = -3/2 R
        reset_state!()
        def_manifold!(:M5t, 5, [:t5a, :t5b, :t5c, :t5d, :t5e, :t5f, :t5g, :t5h])
        def_metric!(-1, "gM5t[-t5a,-t5b]", :CD5t)
        @test Contract("gM5t[t5a,t5b] EinsteinCD5t[-t5a,-t5b]") ==
            "-(3/2) RicciScalarCD5t[]"
    end

    # ============================================================
    # Multi-Index Set (multi-manifold tensor) tests
    # ============================================================

    @testset "DefTensor — multi-manifold (multi-index set)" begin
        reset_state!()
        # Spacetime manifold M4 with indices spa, spb, spc, spd
        def_manifold!(:MIM4, 4, [:mia, :mib, :mic, :mid])
        # Internal gauge manifold G2 with indices ga, gb
        def_manifold!(:MIG2, 2, [:mga, :mgb])

        # Mixed tensor: spacetime covariant index + gauge covariant index
        # T_{μ a} where μ ∈ M4, a ∈ G2
        t = def_tensor!(:MITma, ["-mia", "-mga"], [:MIM4, :MIG2])
        @test TensorQ(:MITma)
        @test t.symmetry.type == :NoSymmetry
        @test t.manifold == :MIM4  # primary manifold

        # Mixed tensor with symmetry on spacetime indices
        # S_{μν a} antisymmetric in μ,ν
        s = def_tensor!(
            :MISma,
            ["-mia", "-mib", "-mga"],
            [:MIM4, :MIG2];
            symmetry_str="Antisymmetric[{-mia,-mib}]",
        )
        @test TensorQ(:MISma)
        @test s.symmetry.type == :Antisymmetric
        @test s.symmetry.slots == [1, 2]

        # Mixed tensor with internal index first (gauge then spacetime)
        u = def_tensor!(:MIUam, ["-mga", "-mia"], [:MIG2, :MIM4])
        @test TensorQ(:MIUam)
        @test u.manifold == :MIG2  # first manifold is primary

        # Error: index not in any manifold
        @test_throws Exception def_tensor!(:MIBad, ["-mia", "-zzz"], [:MIM4, :MIG2])
    end

    @testset "ToCanonical — multi-manifold antisymmetry" begin
        reset_state!()
        def_manifold!(:MIM4, 4, [:mia, :mib, :mic, :mid])
        def_manifold!(:MIG2, 2, [:mga, :mgb])

        # S_{μν a} antisymmetric in μ,ν (spacetime indices)
        def_tensor!(
            :MISma,
            ["-mia", "-mib", "-mga"],
            [:MIM4, :MIG2];
            symmetry_str="Antisymmetric[{-mia,-mib}]",
        )

        # S[-μ,-ν,-a] + S[-ν,-μ,-a] = 0  (antisymmetry in first pair)
        result = ToCanonical("MISma[-mia,-mib,-mga] + MISma[-mib,-mia,-mga]")
        @test result == "0"

        # S[-μ,-ν,-a] - S[-ν,-μ,-a] = 2*S[-μ,-ν,-a]  (antisymmetry → stays)
        result2 = ToCanonical("MISma[-mia,-mib,-mga] - MISma[-mib,-mia,-mga]")
        @test result2 != "0"  # should NOT be zero: it's 2*S[-mia,-mib,-mga]
    end

    @testset "ToCanonical — multi-manifold index independence" begin
        reset_state!()
        def_manifold!(:MIM4, 4, [:mia, :mib, :mic, :mid])
        def_manifold!(:MIG2, 2, [:mga, :mgb])

        # Symmetric tensor on spacetime indices only
        def_tensor!(:MISpST, ["-mia", "-mib"], :MIM4; symmetry_str="Symmetric[{-mia,-mib}]")
        # Symmetric tensor on gauge indices only
        def_tensor!(:MISpG, ["-mga", "-mgb"], :MIG2; symmetry_str="Symmetric[{-mga,-mgb}]")

        # Product: SpST[-μ,-ν] SpG[-a,-b] = SpST[-ν,-μ] SpG[-b,-a] (both symmetric)
        result = ToCanonical(
            "MISpST[-mia,-mib] MISpG[-mga,-mgb] - MISpST[-mib,-mia] MISpG[-mgb,-mga]"
        )
        @test result == "0"

        # Antisymmetric on spacetime; symmetric on gauge: mixed product
        def_tensor!(
            :MIAnST, ["-mia", "-mib"], :MIM4; symmetry_str="Antisymmetric[{-mia,-mib}]"
        )

        # AnST[-μ,-ν] SpG[-a,-b] + AnST[-ν,-μ] SpG[-a,-b] = 0
        result2 = ToCanonical(
            "MIAnST[-mia,-mib] MISpG[-mga,-mgb] + MIAnST[-mib,-mia] MISpG[-mga,-mgb]"
        )
        @test result2 == "0"
    end

    @testset "ToCanonical — multi-manifold mixed tensor canonical form" begin
        reset_state!()
        def_manifold!(:MIM4, 4, [:mia, :mib, :mic, :mid])
        def_manifold!(:MIG2, 2, [:mga, :mgb])

        # T_{μa} with no symmetry
        def_tensor!(:MITma, ["-mia", "-mga"], [:MIM4, :MIG2])

        # T[-μ,-a] is already canonical; no symmetry so no simplification
        result = ToCanonical("MITma[-mia,-mga]")
        @test result == "MITma[-mia,-mga]"

        # Sum of two unrelated terms stays as sum
        result2 = ToCanonical("MITma[-mia,-mga] + MITma[-mib,-mgb]")
        @test result2 != "0"

        # Idempotency: ToCanonical applied twice gives the same result
        expr = "MITma[-mia,-mga]"
        once = ToCanonical(expr)
        twice = ToCanonical(once)
        @test once == twice
    end

    @testset "YoungSymmetry — def_tensor! and ToCanonical" begin
        reset_state!()
        def_manifold!(:Ym4, 4, [:ya, :yb, :yc, :yd, :ye])

        # --- Young {2}: symmetric on 2 slots ---
        def_tensor!(:YT2, ["-ya", "-yb"], :Ym4; symmetry_str="Young[{2}]")
        t2 = get_tensor(:YT2)
        @test t2.symmetry.type == :YoungSymmetry
        @test t2.symmetry.partition == [2]
        @test t2.symmetry.slots == [1, 2]

        # Row symmetry: T2[-b,-a] = T2[-a,-b]
        @test ToCanonical("YT2[-yb,-ya]") == "YT2[-ya,-yb]"
        # Already canonical
        @test ToCanonical("YT2[-ya,-yb]") == "YT2[-ya,-yb]"
        # Sum collapses
        @test ToCanonical("YT2[-ya,-yb] + YT2[-yb,-ya]") == "2 YT2[-ya,-yb]"

        # --- Young {1,1}: antisymmetric on 2 slots ---
        def_tensor!(:YT11, ["-ya", "-yb"], :Ym4; symmetry_str="Young[{1,1}]")
        t11 = get_tensor(:YT11)
        @test t11.symmetry.type == :YoungSymmetry
        @test t11.symmetry.partition == [1, 1]

        # Col antisymmetry: T11[-b,-a] = -T11[-a,-b]
        @test ToCanonical("YT11[-yb,-ya]") == "-YT11[-ya,-yb]"
        # Repeated index → zero
        @test ToCanonical("YT11[-ya,-ya]") == "0"
        # Antisymmetric sum cancels
        @test ToCanonical("YT11[-ya,-yb] + YT11[-yb,-ya]") == "0"

        # --- Young {2,1}: hook shape on 3 slots ---
        def_tensor!(:YT21, ["-ya", "-yb", "-yc"], :Ym4; symmetry_str="Young[{2,1}]")
        t21 = get_tensor(:YT21)
        @test t21.symmetry.type == :YoungSymmetry
        @test t21.symmetry.partition == [2, 1]
        @test t21.symmetry.slots == [1, 2, 3]

        # Row symmetry (slots 1,2): T21[-b,-a,-c] = T21[-a,-b,-c]
        @test ToCanonical("YT21[-yb,-ya,-yc]") == "YT21[-ya,-yb,-yc]"
        # Col antisymmetry (slots 1,3): T21[-c,-b,-a] = -T21[-a,-b,-c]
        @test ToCanonical("YT21[-yc,-yb,-ya]") == "-YT21[-ya,-yb,-yc]"
        # Sum using row symmetry: T21[-a,-b,-c] + T21[-b,-a,-c] = 2 T21[-a,-b,-c]
        @test ToCanonical("YT21[-ya,-yb,-yc] + YT21[-yb,-ya,-yc]") == "2 YT21[-ya,-yb,-yc]"
        # Sum using col antisymmetry: T21[-a,-b,-c] + T21[-c,-b,-a] = 0
        @test ToCanonical("YT21[-ya,-yb,-yc] + YT21[-yc,-yb,-ya]") == "0"

        # --- Wrong partition sum raises error ---
        @test_throws Exception def_tensor!(
            :YTbad, ["-ya", "-yb"], :Ym4; symmetry_str="Young[{2,1}]"
        )
    end

    @testset "GradedSymmetric — FermionicQ and ToCanonical" begin
        reset_state!()
        def_manifold!(:Gm4, 4, [:ga, :gb, :gc, :gd])

        # Fermionic rank-2 tensor
        def_tensor!(:Psi, ["-ga", "-gb"], :Gm4; symmetry_str="GradedSymmetric[{-ga,-gb}]")

        # FermionicQ predicate
        @test FermionicQ(:Psi) == true
        @test FermionicQ(:Gm4) == false   # manifold is not a tensor
        @test FermionicQ(:Unknown) == false

        # Still recognised as a tensor
        @test TensorQ(:Psi) == true

        # Canonicalization: Psi[-b,-a] = -Psi[-a,-b]
        @test ToCanonical("Psi[-gb,-ga]") == "-Psi[-ga,-gb]"

        # Sum T[a,b] + T[b,a] = 0
        @test ToCanonical("Psi[-ga,-gb] + Psi[-gb,-ga]") == "0"

        # Repeated index → 0
        @test ToCanonical("Psi[-ga,-ga]") == "0"
    end

    @testset "perturb_curvature — first-order curvature perturbations" begin
        reset_state!()
        def_manifold!(:Bpc, 4, [:bpca, :bpcb, :bpcc, :bpcd])
        def_metric!(-1, "Cng[-bpca,-bpcb]", :Cnd)
        def_tensor!(
            :Pertg1, ["-bpca", "-bpcb"], :Bpc; symmetry_str="Symmetric[{-bpca,-bpcb}]"
        )
        def_perturbation!(:Pertg1, :Cng, 1)

        result = perturb_curvature(:Cnd, :Pertg1)

        # Returns a Dict with the four expected keys
        @test haskey(result, "Christoffel1")
        @test haskey(result, "Riemann1")
        @test haskey(result, "Ricci1")
        @test haskey(result, "RicciScalar1")

        # Each formula is non-empty
        @test !isempty(result["Christoffel1"])
        @test !isempty(result["Riemann1"])
        @test !isempty(result["Ricci1"])
        @test !isempty(result["RicciScalar1"])

        # Christoffel formula uses the metric and CovD names
        @test occursin("Cng", result["Christoffel1"])
        @test occursin("Cnd", result["Christoffel1"])
        @test occursin("Pertg1", result["Christoffel1"])

        # Riemann formula uses CovD and perturbation tensor (no background Riemann needed)
        @test occursin("Cnd", result["Riemann1"])
        @test occursin("Pertg1", result["Riemann1"])

        # Ricci formula uses the metric and CovD
        @test occursin("Cng", result["Ricci1"])
        @test occursin("Cnd", result["Ricci1"])
        @test occursin("Pertg1", result["Ricci1"])

        # RicciScalar formula references Ricci and metric
        @test occursin("RicciCnd", result["RicciScalar1"])
        @test occursin("Cng", result["RicciScalar1"])

        # Error: unknown covd
        @test_throws Exception perturb_curvature(:UnknownCovD, :Pertg1)

        # Error: order > 1 not implemented
        @test_throws Exception perturb_curvature(:Cnd, :Pertg1; order=2)
    end

    @testset "Simplify — Contract+ToCanonical integration" begin
        reset_state!()
        def_manifold!(:Sm4, 4, [:sa, :sb, :sc, :sd])
        def_metric!(1, "Sg[-sa,-sb]", :SgD)
        def_tensor!(:Sv, ["-sa"], :Sm4)

        # Metric self-trace: g^{ab}g_{ab} = 4 (dimension)
        @test Simplify("Sg[sa,sb] Sg[-sa,-sb]") == "4"

        # Simplify also canonicalizes: swap indices on symmetric metric
        @test Simplify("Sg[-sb,-sa]") == "Sg[-sa,-sb]"

        # Raise then canonicalize: g^{ab} v_b → v^a, then canonical form
        @test Simplify("Sg[sa,sb] Sv[-sb]") == "Sv[sa]"

        # Pure scalar: already zero
        @test Simplify("0") == "0"

        # Idempotency: applying Simplify twice gives the same result
        let once = Simplify("Sg[sa,sb] Sg[-sa,-sb]")
            @test Simplify(once) == once
        end
    end

    @testset "PerturbationOrder and PerturbationAtOrder" begin
        reset_state!()
        def_manifold!(:Bpo, 4, [:bpoa, :bpob, :bpoc, :bpod])
        def_tensor!(:Pog, ["-bpoa", "-bpob"], :Bpo; symmetry_str="Symmetric[{-bpoa,-bpob}]")
        def_tensor!(
            :PoPert1, ["-bpoa", "-bpob"], :Bpo; symmetry_str="Symmetric[{-bpoa,-bpob}]"
        )
        def_tensor!(
            :PoPert2, ["-bpoa", "-bpob"], :Bpo; symmetry_str="Symmetric[{-bpoa,-bpob}]"
        )
        def_tensor!(
            :PoPert3, ["-bpoa", "-bpob"], :Bpo; symmetry_str="Symmetric[{-bpoa,-bpob}]"
        )
        def_perturbation!(:PoPert1, :Pog, 1)
        def_perturbation!(:PoPert2, :Pog, 2)
        def_perturbation!(:PoPert3, :Pog, 3)

        # PerturbationOrder returns the registered order
        @test PerturbationOrder(:PoPert1) == 1
        @test PerturbationOrder(:PoPert2) == 2
        @test PerturbationOrder(:PoPert3) == 3
        @test PerturbationOrder("PoPert1") == 1

        # PerturbationOrder throws for unregistered tensors
        @test_throws ArgumentError PerturbationOrder(:Pog)
        @test_throws ArgumentError PerturbationOrder(:DoesNotExist)

        # PerturbationAtOrder returns the tensor registered at each order
        @test PerturbationAtOrder(:Pog, 1) == :PoPert1
        @test PerturbationAtOrder(:Pog, 2) == :PoPert2
        @test PerturbationAtOrder(:Pog, 3) == :PoPert3
        @test PerturbationAtOrder("Pog", 1) == :PoPert1

        # PerturbationAtOrder throws when no perturbation at the given order
        @test_throws ArgumentError PerturbationAtOrder(:Pog, 4)
        @test_throws ArgumentError PerturbationAtOrder(:DoesNotExist, 1)

        # Round-trip: PerturbationAtOrder(bg, PerturbationOrder(p)) == p
        @test PerturbationAtOrder(:Pog, PerturbationOrder(:PoPert1)) == :PoPert1
        @test PerturbationAtOrder(:Pog, PerturbationOrder(:PoPert2)) == :PoPert2

        # check_perturbation_order is consistent with PerturbationOrder
        @test check_perturbation_order(:PoPert1, PerturbationOrder(:PoPert1))
        @test !check_perturbation_order(:PoPert1, PerturbationOrder(:PoPert2))
    end

    @testset "perturb — multinomial Leibniz (order > 1)" begin
        reset_state!()
        def_manifold!(:Lbm, 4, [:la, :lb, :lc, :ld])
        def_tensor!(:Lg, ["-la", "-lb"], :Lbm; symmetry_str="Symmetric[{-la,-lb}]")
        def_tensor!(:LPg1, ["-la", "-lb"], :Lbm; symmetry_str="Symmetric[{-la,-lb}]")
        def_tensor!(:LPg2, ["-la", "-lb"], :Lbm; symmetry_str="Symmetric[{-la,-lb}]")
        def_perturbation!(:LPg1, :Lg, 1)
        def_perturbation!(:LPg2, :Lg, 2)

        def_tensor!(:LPsi, ["-la", "-lb"], :Lbm; symmetry_str="Symmetric[{-la,-lb}]")
        def_tensor!(:LPPsi1, ["-la", "-lb"], :Lbm; symmetry_str="Symmetric[{-la,-lb}]")
        def_perturbation!(:LPPsi1, :LPsi, 1)

        # ── Order-1 product (backward compatibility) ──────────────────────
        @test perturb("Lg LPsi", 1) == "LPg1 LPsi + Lg LPPsi1"

        # ── Order-2 two-factor product: δ²(A·B) = δ²A·B + 2·δA·δB + A·δ²B
        # Only Lg has a 2nd-order perturbation; LPsi does not → skip last term
        r2 = perturb("Lg LPsi", 2)
        @test r2 == "LPg2 LPsi + 2 LPg1 LPPsi1"

        # ── Order-2 single tensor still works ─────────────────────────────
        @test perturb("Lg", 2) == "LPg2"

        # ── Order-2 sum + product ─────────────────────────────────────────
        rsum = perturb("Lg + LPsi", 2)
        @test rsum == "LPg2 + 0"
        # LPsi has no order-2 perturbation → "0"

        # ── With numeric coefficient ──────────────────────────────────────
        rc = perturb("3 Lg LPsi", 2)
        @test rc == "3 LPg2 LPsi + 6 LPg1 LPPsi1"

        # ── Factor with no perturbation is treated as constant ────────────
        def_tensor!(:LConst, ["-la", "-lb"], :Lbm; symmetry_str="Symmetric[{-la,-lb}]")
        @test perturb("Lg LConst", 1) == "LPg1 LConst"
        @test perturb("LConst LConst", 1) == "0"

        # ── Three factors, order 1 ────────────────────────────────────────
        @test perturb("Lg LPsi LConst", 1) == "LPg1 LPsi LConst + Lg LPPsi1 LConst"
    end

    @testset "IBP and VarD" begin
        reset_state!()
        def_manifold!(:IBm, 4, [:ia, :ib, :ic, :id, :ie])
        def_metric!(-1, "IBg[-ia,-ib]", :IBD)
        def_tensor!(:IBphi, String[], :IBm)
        def_tensor!(:IBV, ["ia"], :IBm)
        def_tensor!(:IBT, ["-ia", "-ib"], :IBm; symmetry_str="Symmetric[{-ia,-ib}]")

        # Pure divergence → 0
        @test IBP("IBD[-ia][IBV[ia]]", "IBD") == "0"

        # TotalDerivativeQ
        @test TotalDerivativeQ("IBD[-ia][IBV[ia]]", "IBD") == true
        @test TotalDerivativeQ("IBphi[] IBD[-ia][IBV[ia]]", "IBD") == false

        # IBP: phi * div(V) → -(grad phi) . V
        ibp_result = IBP("IBphi[] IBD[-ia][IBV[ia]]", "IBD")
        @test ibp_result == "-IBD[-ia][IBphi[]] IBV[ia]"

        # IBP: no CovD present → simplified form returned unchanged
        no_covd = IBP("IBphi[] RicciScalarIBD[]", "IBD")
        @test no_covd == Simplify("IBphi[] RicciScalarIBD[]")

        # IBP: V^a ∂_a phi (covd applied to phi, partner is V) → -(div V) phi
        ibp_grad = IBP("IBV[ia] IBD[-ia][IBphi[]]", "IBD")
        @test ibp_grad == "-IBD[-ia][IBV[ia]] IBphi[]"

        # VarD tests
        # δ(phi * R) / δφ = R
        @test VarD("IBphi[] RicciScalarIBD[]", "IBphi", "IBD") ==
            Simplify("RicciScalarIBD[]")

        # δ(phi * div V) / δφ = div V
        @test VarD("IBphi[] IBD[-ia][IBV[ia]]", "IBphi", "IBD") == "IBD[-ia][IBV[ia]]"

        # δ(V^a ∂_a φ) / δφ = -∂_a V^a  (IBP moves derivative off φ)
        @test VarD("IBV[ia] IBD[-ia][IBphi[]]", "IBphi", "IBD") == "-IBD[-ia][IBV[ia]]"

        # δ(φ²) / δφ = 2φ
        @test VarD("IBphi[] IBphi[]", "IBphi", "IBD") == Simplify("2 IBphi[]")

        # VarD with no field occurrence → 0
        @test VarD("RicciScalarIBD[]", "IBphi", "IBD") == "0"

        # TotalDerivativeQ on a non-total-derivative → false
        @test TotalDerivativeQ("IBphi[] IBV[ia]", "IBD") == false

        # Helper: _split_factor_strings
        @test XTensor._split_factor_strings("IBphi[] IBV[ia]") == ["IBphi[]", "IBV[ia]"]
        @test XTensor._split_factor_strings("IBD[-ia][IBV[ia]]") == ["IBD[-ia][IBV[ia]]"]
        @test length(XTensor._split_factor_strings("IBphi[] IBD[-ia][IBV[ia]]")) == 2

        # Helper: _extract_leading_coeff
        @test XTensor._extract_leading_coeff("2 IBphi[]") == (2 // 1, "IBphi[]")
        @test XTensor._extract_leading_coeff("(1/2) IBphi[]") == (1 // 2, "IBphi[]")
        @test XTensor._extract_leading_coeff("IBphi[]") == (1 // 1, "IBphi[]")

        # Helper: _split_string_terms
        terms = XTensor._split_string_terms("IBphi[] + IBV[ia]")
        @test length(terms) == 2
        terms_neg = XTensor._split_string_terms("IBphi[] - IBV[ia]")
        @test length(terms_neg) == 2
        @test terms_neg[2][1] == -1

        reset_state!()
    end

    # ============================================================
    # ValidateSymbolInSession
    # ============================================================

    @testset "ValidateSymbolInSession" begin
        reset_state!()
        # Fresh symbol passes
        @test_nowarn ValidateSymbolInSession(:FreshSymbolXYZ)

        # Manifold collision
        def_manifold!(:VSM4, 4, [:vsa, :vsb, :vsc, :vsd])
        err = @test_throws ArgumentError ValidateSymbolInSession(:VSM4)
        @test occursin("manifold", err.value.msg)

        # VBundle collision (auto-created by def_manifold!)
        err = @test_throws ArgumentError ValidateSymbolInSession(:TangentVSM4)
        @test occursin("vector bundle", err.value.msg)

        # Tensor collision
        def_tensor!(:VST, ["-vsa", "-vsb"], :VSM4; symmetry_str="Symmetric[{-vsa,-vsb}]")
        err = @test_throws ArgumentError ValidateSymbolInSession(:VST)
        @test occursin("tensor", err.value.msg)

        # Metric / CovD collision
        def_metric!(1, "VSg[-vsa,-vsb]", :VScd)
        err = @test_throws ArgumentError ValidateSymbolInSession(:VScd)
        @test occursin("covariant derivative", err.value.msg) ||
            occursin("metric", err.value.msg)

        # Perturbation collision
        def_tensor!(:VSpert, ["-vsa", "-vsb"], :VSM4; symmetry_str="Symmetric[{-vsa,-vsb}]")
        def_perturbation!(:VSpert, :VSg, 1)
        err = @test_throws ArgumentError ValidateSymbolInSession(:VSpert)
        @test occursin("perturbation", err.value.msg) || occursin("tensor", err.value.msg)

        reset_state!()
    end

    @testset "def_manifold! rejects duplicate via ValidateSymbolInSession" begin
        reset_state!()
        def_manifold!(:DupM, 3, [:da, :db, :dc])
        @test_throws ArgumentError def_manifold!(:DupM, 3, [:da, :db, :dc])
        reset_state!()
    end

    @testset "def_tensor! rejects name already used as manifold" begin
        reset_state!()
        def_manifold!(:CrossM, 2, [:ca, :cb])
        # Trying to define a tensor with the same name as the manifold
        @test_throws ArgumentError def_tensor!(:CrossM, ["-ca", "-cb"], :CrossM)
        reset_state!()
    end

    # ============================================================
    # Symbol hooks integration
    # ============================================================

    @testset "set_symbol_hooks! wires validation" begin
        reset_state!()
        validated = String[]
        registered = Tuple{String,String}[]

        set_symbol_hooks!(
            name -> push!(validated, string(name)),
            (name, pkg) -> push!(registered, (string(name), pkg)),
        )

        def_manifold!(:HkM, 2, [:ha, :hb])
        @test "HkM" in validated
        @test ("HkM", "XTensor") in registered
        @test ("TangentHkM", "XTensor") in registered

        def_tensor!(:HkT, ["-ha", "-hb"], :HkM)
        @test "HkT" in validated
        @test ("HkT", "XTensor") in registered

        # Restore no-op hooks
        set_symbol_hooks!((_) -> nothing, (_, _) -> nothing)
        reset_state!()
    end

    @testset "set_symbol_hooks! validation error blocks definition" begin
        reset_state!()
        # Hook that rejects a specific name
        set_symbol_hooks!(
            name -> string(name) == "Blocked" && error("blocked by hook"), (_, _) -> nothing
        )

        @test_throws ErrorException def_manifold!(:Blocked, 2, [:ba, :bb])
        @test !ManifoldQ(:Blocked)   # not registered

        # Restore no-op hooks
        set_symbol_hooks!((_) -> nothing, (_, _) -> nothing)
        reset_state!()
    end

    # ==========================================================
    # Basis and Frame support
    # ==========================================================

    @testset "DefBasis" begin
        reset_state!()
        def_manifold!(:Bm4, 4, [:bma, :bmb, :bmc, :bmd])

        # Basic basis definition on tangent bundle
        b = def_basis!(:tetrad, :TangentBm4, [1, 2, 3, 4])
        @test b.name == :tetrad
        @test b.vbundle == :TangentBm4
        @test b.cnumbers == [1, 2, 3, 4]
        @test b.is_chart == false

        # Predicates
        @test BasisQ(:tetrad)
        @test !BasisQ(:nonexistent)

        # Accessors
        @test VBundleOfBasis(:tetrad) == :TangentBm4
        @test CNumbersOf(:tetrad) == [1, 2, 3, 4]
        @test PDOfBasis(:tetrad) == :PDtetrad

        # BasesOfVBundle
        bases = BasesOfVBundle(:TangentBm4)
        @test :tetrad in bases

        # Parallel derivative recognized as CovD
        @test CovDQ(:PDtetrad)

        # MemberQ
        @test MemberQ(:Bases, :tetrad)
        @test !MemberQ(:Bases, :nonexistent)

        # Appears in list
        @test :tetrad in list_bases()

        # Unsorted cnumbers get sorted
        b2 = def_basis!(:frame2, :TangentBm4, [4, 2, 1, 3])
        @test CNumbersOf(:frame2) == [1, 2, 3, 4]

        # Both bases on same vbundle
        bases2 = BasesOfVBundle(:TangentBm4)
        @test length(bases2) == 2
        @test :tetrad in bases2
        @test :frame2 in bases2
    end

    @testset "DefBasis validation" begin
        reset_state!()
        def_manifold!(:Bv3, 3, [:bva, :bvb, :bvc])

        # Wrong number of cnumbers
        @test_throws Exception def_basis!(:bad1, :TangentBv3, [1, 2])

        # Non-existent vbundle
        @test_throws Exception def_basis!(:bad2, :NoSuchBundle, [1, 2, 3])

        # Duplicate cnumbers
        @test_throws Exception def_basis!(:bad3, :TangentBv3, [1, 1, 2])

        # Duplicate name
        def_basis!(:good, :TangentBv3, [1, 2, 3])
        @test_throws Exception def_basis!(:good, :TangentBv3, [1, 2, 3])

        # Name collision with existing manifold
        @test_throws Exception def_basis!(:Bv3, :TangentBv3, [1, 2, 3])
    end

    @testset "DefChart" begin
        reset_state!()
        def_manifold!(:Cm4, 4, [:cma, :cmb, :cmc, :cmd])

        c = def_chart!(:Schw, :Cm4, [1, 2, 3, 4], [:t, :r, :theta, :phi])
        @test c.name == :Schw
        @test c.manifold == :Cm4
        @test c.scalars == [:t, :r, :theta, :phi]

        # Chart predicates
        @test ChartQ(:Schw)
        @test !ChartQ(:nonexistent)
        @test MemberQ(:Charts, :Schw)

        # Chart also creates a basis
        @test BasisQ(:Schw)
        b = get_basis(:Schw)
        @test b.is_chart == true
        @test b.vbundle == :TangentCm4

        # Accessors
        @test ManifoldOfChart(:Schw) == :Cm4
        @test ScalarsOfChart(:Schw) == [:t, :r, :theta, :phi]
        @test CNumbersOf(:Schw) == [1, 2, 3, 4]

        # Coordinate scalars registered as tensors
        @test TensorQ(:t)
        @test TensorQ(:r)
        @test TensorQ(:theta)
        @test TensorQ(:phi)

        # Parallel derivative recognized
        @test CovDQ(PDOfBasis(:Schw))

        # Appears in list
        @test :Schw in list_charts()
    end

    @testset "DefChart validation" begin
        reset_state!()
        def_manifold!(:Cv3, 3, [:cva, :cvb, :cvc])

        # Wrong number of cnumbers
        @test_throws Exception def_chart!(:bad1, :Cv3, [1, 2], [:x, :y, :z])

        # Wrong number of scalars
        @test_throws Exception def_chart!(:bad2, :Cv3, [1, 2, 3], [:x, :y])

        # Non-existent manifold
        @test_throws Exception def_chart!(:bad3, :NoManifold, [1, 2, 3], [:x, :y, :z])

        # Duplicate chart name
        def_chart!(:Cart, :Cv3, [1, 2, 3], [:x, :y, :z])
        @test_throws Exception def_chart!(:Cart, :Cv3, [1, 2, 3], [:u, :v, :w])
    end

    @testset "Basis/Chart reset" begin
        reset_state!()
        def_manifold!(:Rm4, 4, [:rma, :rmb, :rmc, :rmd])
        def_basis!(:eb, :TangentRm4, [1, 2, 3, 4])
        def_chart!(:Sph, :Rm4, [1, 2, 3, 4], [:t, :r, :th, :ph])

        @test BasisQ(:eb)
        @test ChartQ(:Sph)

        reset_state!()

        @test !BasisQ(:eb)
        @test !ChartQ(:Sph)
        @test isempty(list_bases())
        @test isempty(list_charts())
    end

    @testset "ValidateSymbolInSession: basis/chart collision" begin
        reset_state!()
        def_manifold!(:Sm4, 4, [:sma, :smb, :smc, :smd])
        def_basis!(:myframe, :TangentSm4, [1, 2, 3, 4])

        # Cannot reuse basis name as a tensor
        @test_throws Exception def_tensor!(:myframe, ["-sma"], :Sm4)

        # Cannot reuse basis name as a manifold
        @test_throws Exception def_manifold!(:myframe, 3, [:x, :y, :z])

        # Chart name collision
        def_chart!(:Polar, :Sm4, [1, 2, 3, 4], [:ct, :cr, :cth, :cph])
        @test_throws Exception def_tensor!(:Polar, ["-sma"], :Sm4)
    end

    @testset "String overloads for basis/chart" begin
        reset_state!()
        def_manifold!(:Om3, 3, [:oma, :omb, :omc])

        b = def_basis!("frame", "TangentOm3", [1, 2, 3])
        @test BasisQ(:frame)
        @test VBundleOfBasis("frame") == :TangentOm3
        @test CNumbersOf("frame") == [1, 2, 3]
        @test PDOfBasis("frame") == :PDframe

        c = def_chart!("Cart", "Om3", [1, 2, 3], ["x", "y", "z"])
        @test ChartQ(:Cart)
        @test ManifoldOfChart("Cart") == :Om3
        @test ScalarsOfChart("Cart") == [:x, :y, :z]

        @test BasesOfVBundle("TangentOm3") == BasesOfVBundle(:TangentOm3)
    end

    # ==========================================================
    # Coordinate transformations (basis changes)
    # ==========================================================

    @testset "set_basis_change! basic 2x2" begin
        reset_state!()
        def_manifold!(:Bc2, 2, [:bca, :bcb])
        def_chart!(:Cart2, :Bc2, [1, 2], [:x2, :y2])
        def_chart!(:Polar2, :Bc2, [1, 2], [:r2, :th2])

        M = Any[1 2; 3 4]
        bc = set_basis_change!(:Cart2, :Polar2, M)
        @test bc.from_basis == :Cart2
        @test bc.to_basis == :Polar2
        @test bc.matrix == M
        # Jacobian = det([1 2;3 4]) = 1*4 - 2*3 = -2
        @test bc.jacobian ≈ -2.0
        # Inverse
        @test bc.inverse ≈ inv(Float64.(M))
    end

    @testset "BasisChangeObj type parameterization" begin
        reset_state!()
        def_manifold!(:Btp, 2, [:bpa, :bpb])
        def_chart!(:BtpA, :Btp, [1, 2], [:bpx, :bpy])
        def_chart!(:BtpB, :Btp, [1, 2], [:bpq, :bpr])

        # Float64 matrix preserves element type
        Mf = Float64[1.0 0.5; 0.0 2.0]
        bc = set_basis_change!(:BtpA, :BtpB, Mf)
        @test eltype(bc.matrix) == Float64
        @test eltype(bc.inverse) == Float64
        @test bc.jacobian isa Float64
    end

    @testset "set_basis_change! 4x4" begin
        reset_state!()
        def_manifold!(:Bc4, 4, [:b4a, :b4b, :b4c, :b4d])
        def_chart!(:Cart4, :Bc4, [1, 2, 3, 4], [:cx, :cy, :cz, :cw])
        def_chart!(:Sph4, :Bc4, [1, 2, 3, 4], [:sr, :sth, :sph, :st])

        M4 = Float64[
            1 0 0 0
            0 2 0 0
            0 0 3 0
            0 0 0 4
        ]
        bc = set_basis_change!(:Cart4, :Sph4, M4)
        @test bc.jacobian ≈ 24.0  # 1*2*3*4
        @test bc.inverse ≈ inv(M4)
    end

    @testset "BasisChangeQ predicate" begin
        reset_state!()
        def_manifold!(:Bq2, 2, [:bqa, :bqb])
        def_chart!(:A2, :Bq2, [1, 2], [:ax, :ay])
        def_chart!(:B2, :Bq2, [1, 2], [:bx, :by])

        @test !BasisChangeQ(:A2, :B2)
        set_basis_change!(:A2, :B2, Any[1 0; 0 1])
        @test BasisChangeQ(:A2, :B2)
        # Bidirectional
        @test BasisChangeQ(:B2, :A2)
        # Non-existent pair
        @test !BasisChangeQ(:A2, :nonexistent)
    end

    @testset "BasisChangeMatrix / InverseBasisChangeMatrix" begin
        reset_state!()
        def_manifold!(:Bm2, 2, [:bma2, :bmb2])
        def_chart!(:X2, :Bm2, [1, 2], [:xx, :xy])
        def_chart!(:Y2, :Bm2, [1, 2], [:yx, :yy])

        M = Any[2 1; 0 3]
        set_basis_change!(:X2, :Y2, M)

        @test BasisChangeMatrix(:X2, :Y2) == M
        @test InverseBasisChangeMatrix(:X2, :Y2) ≈ inv(Float64.(M))

        # Reverse direction
        @test BasisChangeMatrix(:Y2, :X2) ≈ inv(Float64.(M))
        @test InverseBasisChangeMatrix(:Y2, :X2) ≈ Float64.(M)
    end

    @testset "Jacobian" begin
        reset_state!()
        def_manifold!(:Jm2, 2, [:jma, :jmb])
        def_chart!(:J1, :Jm2, [1, 2], [:j1x, :j1y])
        def_chart!(:J2, :Jm2, [1, 2], [:j2x, :j2y])

        M = Any[3 1; 0 2]
        set_basis_change!(:J1, :J2, M)

        @test Jacobian(:J1, :J2) ≈ 6.0   # det([3 1;0 2]) = 6
        @test Jacobian(:J2, :J1) ≈ 1.0 / 6.0  # inverse direction
    end

    @testset "set_basis_change! validation errors" begin
        reset_state!()
        def_manifold!(:Ve2, 2, [:vea, :veb])
        def_chart!(:V1, :Ve2, [1, 2], [:v1x, :v1y])
        def_chart!(:V2, :Ve2, [1, 2], [:v2x, :v2y])

        # Non-existent basis
        @test_throws Exception set_basis_change!(:V1, :nonexistent, Any[1 0; 0 1])
        @test_throws Exception set_basis_change!(:nonexistent, :V2, Any[1 0; 0 1])

        # Wrong matrix dimensions (3x3 for 2D basis)
        @test_throws Exception set_basis_change!(:V1, :V2, Any[1 0 0; 0 1 0; 0 0 1])

        # Singular matrix
        @test_throws Exception set_basis_change!(:V1, :V2, Any[1 2; 2 4])

        # Cross-vbundle: bases on different manifolds
        def_manifold!(:Ve3, 2, [:ve3a, :ve3b])
        def_chart!(:V3, :Ve3, [1, 2], [:v3x, :v3y])
        @test_throws Exception set_basis_change!(:V1, :V3, Any[1 0; 0 1])
    end

    @testset "change_basis rank-1" begin
        reset_state!()
        def_manifold!(:Cb2, 2, [:cba, :cbb])
        def_chart!(:C1, :Cb2, [1, 2], [:c1x, :c1y])
        def_chart!(:C2, :Cb2, [1, 2], [:c2x, :c2y])

        M = Any[0 1; 1 0]  # swap components
        set_basis_change!(:C1, :C2, M)

        v = [3.0, 7.0]
        result = change_basis(v, [:C1], 1, :C1, :C2)
        @test result ≈ [7.0, 3.0]  # swapped
    end

    @testset "change_basis rank-2" begin
        reset_state!()
        def_manifold!(:Cr2, 2, [:cra, :crb])
        def_chart!(:R1, :Cr2, [1, 2], [:r1x, :r1y])
        def_chart!(:R2, :Cr2, [1, 2], [:r2x, :r2y])

        M = Float64[2 0; 0 3]
        set_basis_change!(:R1, :R2, M)

        A = Float64[1 2; 3 4]

        # Transform slot 1: result[i',j] = M[i',i] * A[i,j]
        result1 = change_basis(A, [:R1, :R1], 1, :R1, :R2)
        @test result1 ≈ M * A

        # Transform slot 2: result[i,j'] = A[i,j] * M'[j,j'] = (M * A')'
        result2 = change_basis(A, [:R1, :R1], 2, :R1, :R2)
        @test result2 ≈ (M * A')'
    end

    @testset "reset_state! clears basis changes" begin
        reset_state!()
        def_manifold!(:Rs2, 2, [:rsa, :rsb])
        def_chart!(:S1, :Rs2, [1, 2], [:s1x, :s1y])
        def_chart!(:S2, :Rs2, [1, 2], [:s2x, :s2y])

        set_basis_change!(:S1, :S2, Any[1 0; 0 1])
        @test BasisChangeQ(:S1, :S2)

        reset_state!()

        @test !BasisChangeQ(:S1, :S2)
    end

    @testset "Bidirectional storage" begin
        reset_state!()
        def_manifold!(:Bd2, 2, [:bda, :bdb])
        def_chart!(:D1, :Bd2, [1, 2], [:d1x, :d1y])
        def_chart!(:D2, :Bd2, [1, 2], [:d2x, :d2y])

        M = Any[1 2; 3 4]
        set_basis_change!(:D1, :D2, M)

        # Forward
        @test BasisChangeQ(:D1, :D2)
        @test BasisChangeMatrix(:D1, :D2) == M

        # Reverse: matrix should be inverse
        @test BasisChangeQ(:D2, :D1)
        @test BasisChangeMatrix(:D2, :D1) ≈ inv(Float64.(M))
        @test InverseBasisChangeMatrix(:D2, :D1) ≈ Float64.(M)
    end

    @testset "String overloads for basis change" begin
        reset_state!()
        def_manifold!(:So2, 2, [:soa, :sob])
        def_chart!(:E1, :So2, [1, 2], [:e1x, :e1y])
        def_chart!(:E2, :So2, [1, 2], [:e2x, :e2y])

        set_basis_change!("E1", "E2", Any[1 0; 0 1])
        @test BasisChangeQ("E1", "E2")
        @test Jacobian("E1", "E2") ≈ 1.0
    end

    # ============================================================
    # CTensor (Component Tensor) tests
    # ============================================================

    @testset "set_components! rank-2 (matrix)" begin
        reset_state!()
        def_manifold!(:Cm4, 4, [:cma, :cmb, :cmc, :cmd])
        def_metric!(-1, "Cmg[-cma,-cmb]", :Cmd)
        def_chart!(:CC1, :Cm4, [1, 2, 3, 4], [:cx1, :cx2, :cx3, :cx4])

        # Minkowski metric components
        eta = Any[-1 0 0 0; 0 1 0 0; 0 0 1 0; 0 0 0 1]
        ct = set_components!(:Cmg, eta, [:CC1, :CC1])
        @test ct.tensor == :Cmg
        @test ct.array == eta
        @test ct.bases == [:CC1, :CC1]
        @test ct.weight == 0
    end

    @testset "set_components! rank-1 (vector)" begin
        reset_state!()
        def_manifold!(:Cv2, 2, [:cva, :cvb])
        def_chart!(:Cb1, :Cv2, [1, 2], [:cv1x, :cv1y])
        def_tensor!(:Cvv, ["cva"], :Cv2)

        v = Any[3, 7]
        ct = set_components!(:Cvv, v, [:Cb1])
        @test ct.tensor == :Cvv
        @test ct.array == v
        @test ct.bases == [:Cb1]
    end

    @testset "set_components! rank-0 (scalar)" begin
        reset_state!()
        def_manifold!(:Cs2, 2, [:csa, :csb])
        def_chart!(:Csb, :Cs2, [1, 2], [:csx, :csy])
        def_tensor!(:Csc, String[], :Cs2)  # scalar tensor

        ct = set_components!(:Csc, fill(42), Symbol[])
        @test ct.tensor == :Csc
        @test ct.array[] == 42
        @test ct.bases == Symbol[]
    end

    @testset "get_components retrieval" begin
        reset_state!()
        def_manifold!(:Cg2, 2, [:cga, :cgb])
        def_chart!(:Cgb, :Cg2, [1, 2], [:cgx, :cgy])
        def_tensor!(:Cgt, ["-cga", "-cgb"], :Cg2; symmetry_str="Symmetric[{-cga,-cgb}]")

        arr = Any[1 2; 2 3]
        set_components!(:Cgt, arr, [:Cgb, :Cgb])

        ct = get_components(:Cgt, [:Cgb, :Cgb])
        @test ct.array == arr
        @test ct.bases == [:Cgb, :Cgb]
    end

    @testset "CTensorQ predicate" begin
        reset_state!()
        def_manifold!(:Cq2, 2, [:cqa, :cqb])
        def_chart!(:Cqb, :Cq2, [1, 2], [:cqx, :cqy])
        def_tensor!(:Cqt, ["-cqa", "-cqb"], :Cq2)

        @test !CTensorQ(:Cqt, :Cqb, :Cqb)

        set_components!(:Cqt, Any[1 0; 0 1], [:Cqb, :Cqb])

        @test CTensorQ(:Cqt, :Cqb, :Cqb)
        @test !CTensorQ(:Cqt, :Cqb)  # wrong number of bases
    end

    @testset "component_value" begin
        reset_state!()
        def_manifold!(:Ci3, 3, [:cia, :cib, :cic])
        def_chart!(:Cib, :Ci3, [1, 2, 3], [:cix, :ciy, :ciz])
        def_tensor!(:Cit, ["-cia", "-cib"], :Ci3)

        arr = Any[1 2 3; 4 5 6; 7 8 9]
        set_components!(:Cit, arr, [:Cib, :Cib])

        @test component_value(:Cit, [1, 1], [:Cib, :Cib]) == 1
        @test component_value(:Cit, [2, 3], [:Cib, :Cib]) == 6
        @test component_value(:Cit, [3, 3], [:Cib, :Cib]) == 9
    end

    @testset "component_value out of range" begin
        reset_state!()
        def_manifold!(:Cr2, 2, [:cra, :crb])
        def_chart!(:Crb, :Cr2, [1, 2], [:crx, :cry])
        def_tensor!(:Crt, ["-cra", "-crb"], :Cr2)

        set_components!(:Crt, Any[1 2; 3 4], [:Crb, :Crb])
        @test_throws Exception component_value(:Crt, [3, 1], [:Crb, :Crb])
    end

    @testset "ComponentArray" begin
        reset_state!()
        def_manifold!(:Ca2, 2, [:caa, :cab])
        def_chart!(:Cab, :Ca2, [1, 2], [:cax, :cay])
        def_tensor!(:Cat, ["-caa"], :Ca2)

        set_components!(:Cat, Any[10, 20], [:Cab])
        @test ComponentArray(:Cat, [:Cab]) == Any[10, 20]
    end

    @testset "get_components with basis change (auto-transform)" begin
        reset_state!()
        def_manifold!(:Cx2, 2, [:cxa, :cxb])
        def_chart!(:Cx1, :Cx2, [1, 2], [:cx1x, :cx1y])
        def_chart!(:Cx2c, :Cx2, [1, 2], [:cx2x, :cx2y])
        def_tensor!(:Cxv, ["cxa"], :Cx2)

        # Store components in Cx1 basis
        set_components!(:Cxv, Any[1.0, 0.0], [:Cx1])

        # Register basis change
        M = Any[0 1; 1 0]  # swap axes
        set_basis_change!(:Cx1, :Cx2c, M)

        # Get components in Cx2c basis — should auto-transform
        ct = get_components(:Cxv, [:Cx2c])
        @test ct.array ≈ [0.0, 1.0]
        @test ct.bases == [:Cx2c]
    end

    @testset "get_components rank-2 auto-transform" begin
        reset_state!()
        def_manifold!(:Cy2, 2, [:cya, :cyb])
        def_chart!(:Cy1, :Cy2, [1, 2], [:cy1x, :cy1y])
        def_chart!(:Cy2c, :Cy2, [1, 2], [:cy2x, :cy2y])
        def_metric!(-1, "Cyg[-cya,-cyb]", :Cyd)

        # Minkowski 2D: diag(-1, 1)
        eta = Any[-1.0 0.0; 0.0 1.0]
        set_components!(:Cyg, eta, [:Cy1, :Cy1])

        # Rotation by pi/4
        c = cos(pi / 4)
        s = sin(pi / 4)
        R = Any[c -s; s c]
        set_basis_change!(:Cy1, :Cy2c, R)

        # Get metric in new basis: g' = R * g * R'
        ct = get_components(:Cyg, [:Cy2c, :Cy2c])
        expected = Float64.(R) * Float64.(eta) * Float64.(R)'
        @test ct.array ≈ expected
    end

    @testset "ctensor_contract rank-2 (trace)" begin
        reset_state!()
        def_manifold!(:Ct3, 3, [:cta, :ctb, :ctc])
        def_chart!(:Ctb, :Ct3, [1, 2, 3], [:ctx, :cty, :ctz])
        def_tensor!(:Ctt, ["-cta", "-ctb"], :Ct3)

        arr = Any[1 0 0; 0 2 0; 0 0 3]
        set_components!(:Ctt, arr, [:Ctb, :Ctb])

        ct_result = ctensor_contract(:Ctt, [:Ctb, :Ctb], 1, 2)
        @test ct_result.array[] == 6  # trace = 1 + 2 + 3
        @test ct_result.bases == Symbol[]
    end

    @testset "set_components! validation errors" begin
        reset_state!()
        def_manifold!(:Ce2, 2, [:cea, :ceb])
        def_chart!(:Ceb, :Ce2, [1, 2], [:cex, :cey])
        def_tensor!(:Cet, ["-cea", "-ceb"], :Ce2)

        # Wrong rank: provide rank-1 array for rank-2 tensor
        @test_throws Exception set_components!(:Cet, Any[1, 2], [:Ceb, :Ceb])

        # Wrong dimension: provide 3x3 for a 2D basis
        @test_throws Exception set_components!(:Cet, Any[1 0 0; 0 1 0; 0 0 1], [:Ceb, :Ceb])

        # Non-existent tensor
        @test_throws Exception set_components!(:NoSuchTensor, Any[1 0; 0 1], [:Ceb, :Ceb])

        # Non-existent basis
        @test_throws Exception set_components!(:Cet, Any[1 0; 0 1], [:NoSuchBasis, :Ceb])
    end

    @testset "get_components no path error" begin
        reset_state!()
        def_manifold!(:Cn2, 2, [:cna, :cnb])
        def_chart!(:Cnb1, :Cn2, [1, 2], [:cn1x, :cn1y])
        def_chart!(:Cnb2, :Cn2, [1, 2], [:cn2x, :cn2y])
        def_tensor!(:Cnt, ["-cna", "-cnb"], :Cn2)

        # No components stored and no basis change
        @test_throws Exception get_components(:Cnt, [:Cnb1, :Cnb1])
    end

    @testset "reset_state! clears ctensors" begin
        reset_state!()
        def_manifold!(:Cr2b, 2, [:crba, :crbb])
        def_chart!(:Crbb, :Cr2b, [1, 2], [:crbx, :crby])
        def_tensor!(:Crbt, ["-crba", "-crbb"], :Cr2b)

        set_components!(:Crbt, Any[1 0; 0 1], [:Crbb, :Crbb])
        @test CTensorQ(:Crbt, :Crbb, :Crbb)

        reset_state!()
        @test !CTensorQ(:Crbt, :Crbb, :Crbb)
    end

    @testset "set_components! with weight" begin
        reset_state!()
        def_manifold!(:Cw2, 2, [:cwa, :cwb])
        def_chart!(:Cwb, :Cw2, [1, 2], [:cwx, :cwy])
        def_tensor!(:Cwt, ["-cwa", "-cwb"], :Cw2)

        ct = set_components!(:Cwt, Any[1 0; 0 1], [:Cwb, :Cwb]; weight=2)
        @test ct.weight == 2
    end

    @testset "CTensorQ string overloads" begin
        reset_state!()
        def_manifold!(:Cs2b, 2, [:csba, :csbb])
        def_chart!(:Csbb, :Cs2b, [1, 2], [:csbx, :csby])
        def_tensor!(:Csbt, ["-csba", "-csbb"], :Cs2b)

        set_components!(:Csbt, Any[1 0; 0 1], [:Csbb, :Csbb])
        @test CTensorQ("Csbt", "Csbb", "Csbb")
    end

    @testset "ctensor_contract validation errors" begin
        reset_state!()
        def_manifold!(:Cv3, 3, [:cva3a, :cva3b, :cva3c])
        def_chart!(:Cvb3, :Cv3, [1, 2, 3], [:cv3x, :cv3y, :cv3z])
        def_tensor!(:Cvt3, ["-cva3a", "-cva3b"], :Cv3)

        set_components!(:Cvt3, Any[1 0 0; 0 2 0; 0 0 3], [:Cvb3, :Cvb3])

        # Same slot
        @test_throws Exception ctensor_contract(:Cvt3, [:Cvb3, :Cvb3], 1, 1)
        # Out of range
        @test_throws Exception ctensor_contract(:Cvt3, [:Cvb3, :Cvb3], 1, 3)
    end

    @testset "get_components / component_value string overloads" begin
        reset_state!()
        def_manifold!(:Cso2, 2, [:csoa, :csob])
        def_chart!(:Csob, :Cso2, [1, 2], [:csox, :csoy])
        def_tensor!(:Csot, ["-csoa", "-csob"], :Cso2)

        set_components!(:Csot, Any[5 6; 7 8], [:Csob, :Csob])
        ct = get_components("Csot", ["Csob", "Csob"])
        @test ct.array == Any[5 6; 7 8]

        @test component_value("Csot", [1, 2], ["Csob", "Csob"]) == 6
    end

    # ================================================================
    # ToBasis / FromBasis / TraceBasisDummy
    # ================================================================

    @testset "ToBasis single tensor" begin
        reset_state!()
        def_manifold!(:Tb3, 3, [:tba, :tbb, :tbc])
        def_chart!(:Tbc, :Tb3, [1, 2, 3], [:tbx, :tby, :tbz])
        def_tensor!(:Tbt, ["-tba", "-tbb"], :Tb3)

        arr = Any[1 2 3; 4 5 6; 7 8 9]
        set_components!(:Tbt, arr, [:Tbc, :Tbc])

        ct = ToBasis("Tbt[-tba,-tbb]", :Tbc)
        @test ct.tensor == :Tbt
        @test ct.array == Float64[1 2 3; 4 5 6; 7 8 9]
        @test ct.bases == [:Tbc, :Tbc]
    end

    @testset "ToBasis vector" begin
        reset_state!()
        def_manifold!(:Tv3, 3, [:tva, :tvb, :tvc])
        def_chart!(:Tvc, :Tv3, [1, 2, 3], [:tvx, :tvy, :tvz])
        def_tensor!(:Tvv, ["tva"], :Tv3)

        set_components!(:Tvv, Any[10, 20, 30], [:Tvc])

        ct = ToBasis("Tvv[tva]", :Tvc)
        @test ct.array == Float64[10, 20, 30]
        @test ct.bases == [:Tvc]
    end

    @testset "ToBasis contraction (g * v)" begin
        reset_state!()
        def_manifold!(:Tc2, 2, [:tca, :tcb])
        def_chart!(:Tcc, :Tc2, [1, 2], [:tcx, :tcy])
        def_metric!(1, "Tcg[-tca,-tcb]", :Tcd)
        def_tensor!(:Tcv, ["tca"], :Tc2)

        # g = identity, v = [3, 7]
        set_components!(:Tcg, Any[1 0; 0 1], [:Tcc, :Tcc])
        set_components!(:Tcv, Any[3, 7], [:Tcc])

        # g_{ab} v^a = sum_a g_{a,b} v^a
        ct = ToBasis("Tcg[-tca,-tcb] Tcv[tca]", :Tcc)
        @test ct.array ≈ Float64[3.0, 7.0]
        @test length(ct.bases) == 1
    end

    @testset "ToBasis contraction non-identity metric" begin
        reset_state!()
        def_manifold!(:Tn2, 2, [:tna, :tnb])
        def_chart!(:Tnc, :Tn2, [1, 2], [:tnx, :tny])
        def_metric!(-1, "Tng[-tna,-tnb]", :Tnd)
        def_tensor!(:Tnv, ["tna"], :Tn2)

        # Minkowski-like: g = diag(-1, 1), v = [2, 5]
        set_components!(:Tng, Any[-1 0; 0 1], [:Tnc, :Tnc])
        set_components!(:Tnv, Any[2, 5], [:Tnc])

        # g_{ab} v^a = [-1*2 + 0*5, 0*2 + 1*5] = [-2, 5]
        ct = ToBasis("Tng[-tna,-tnb] Tnv[tna]", :Tnc)
        @test ct.array ≈ Float64[-2.0, 5.0]
    end

    @testset "ToBasis full trace (scalar result)" begin
        reset_state!()
        def_manifold!(:Tt3, 3, [:tta, :ttb, :ttc])
        def_chart!(:Ttc, :Tt3, [1, 2, 3], [:ttx, :tty, :ttz])
        def_tensor!(:Ttt, ["-tta", "ttb"], :Tt3)

        # Mixed tensor with trace = 1+5+9 = 15
        set_components!(:Ttt, Any[1 2 3; 4 5 6; 7 8 9], [:Ttc, :Ttc])

        ct = ToBasis("Ttt[-tta,tta]", :Ttc)
        @test ct.array[] ≈ 15.0
        @test ct.bases == Symbol[]
    end

    @testset "ToBasis sum of tensors" begin
        reset_state!()
        def_manifold!(:Ts2, 2, [:tsa, :tsb])
        def_chart!(:Tsc, :Ts2, [1, 2], [:tsx, :tsy])
        def_tensor!(:TsA, ["-tsa", "-tsb"], :Ts2)
        def_tensor!(:TsB, ["-tsa", "-tsb"], :Ts2)

        set_components!(:TsA, Any[1 2; 3 4], [:Tsc, :Tsc])
        set_components!(:TsB, Any[10 20; 30 40], [:Tsc, :Tsc])

        ct = ToBasis("TsA[-tsa,-tsb] + TsB[-tsa,-tsb]", :Tsc)
        @test ct.array ≈ Float64[11 22; 33 44]
    end

    @testset "ToBasis with coefficient" begin
        reset_state!()
        def_manifold!(:Tk2, 2, [:tka, :tkb])
        def_chart!(:Tkc, :Tk2, [1, 2], [:tkx, :tky])
        def_tensor!(:Tkt, ["-tka", "-tkb"], :Tk2)

        set_components!(:Tkt, Any[2 0; 0 3], [:Tkc, :Tkc])

        ct = ToBasis("3*Tkt[-tka,-tkb]", :Tkc)
        @test ct.array ≈ Float64[6 0; 0 9]
    end

    @testset "ToBasis difference of tensors" begin
        reset_state!()
        def_manifold!(:Td2, 2, [:tda, :tdb])
        def_chart!(:Tdc, :Td2, [1, 2], [:tdx, :tdy])
        def_tensor!(:TdA, ["-tda", "-tdb"], :Td2)
        def_tensor!(:TdB, ["-tda", "-tdb"], :Td2)

        set_components!(:TdA, Any[10 20; 30 40], [:Tdc, :Tdc])
        set_components!(:TdB, Any[1 2; 3 4], [:Tdc, :Tdc])

        ct = ToBasis("TdA[-tda,-tdb] - TdB[-tda,-tdb]", :Tdc)
        @test ct.array ≈ Float64[9 18; 27 36]
    end

    @testset "ToBasis error: non-existent basis" begin
        reset_state!()
        def_manifold!(:Te2, 2, [:tea, :teb])
        def_tensor!(:Tet, ["-tea", "-teb"], :Te2)
        @test_throws Exception ToBasis("Tet[-tea,-teb]", :NoSuchBasis)
    end

    @testset "ToBasis string overload" begin
        reset_state!()
        def_manifold!(:To2, 2, [:toa, :tob])
        def_chart!(:Toc, :To2, [1, 2], [:tox, :toy])
        def_tensor!(:Tot, ["-toa", "-tob"], :To2)

        set_components!(:Tot, Any[1 0; 0 1], [:Toc, :Toc])

        ct = ToBasis("Tot[-toa,-tob]", "Toc")
        @test ct.array ≈ Float64[1 0; 0 1]
    end

    @testset "FromBasis tensor" begin
        reset_state!()
        def_manifold!(:Fb2, 2, [:fba, :fbb])
        def_chart!(:Fbc, :Fb2, [1, 2], [:fbx, :fby])
        def_tensor!(:Fbt, ["-fba", "fbb"], :Fb2)

        set_components!(:Fbt, Any[1 0; 0 1], [:Fbc, :Fbc])

        result = FromBasis(:Fbt, [:Fbc, :Fbc])
        @test result == "Fbt[-fba,fbb]"
    end

    @testset "FromBasis metric" begin
        reset_state!()
        def_manifold!(:Fm2, 2, [:fma, :fmb])
        def_chart!(:Fmc, :Fm2, [1, 2], [:fmx, :fmy])
        def_metric!(1, "Fmg[-fma,-fmb]", :Fmd)

        set_components!(:Fmg, Any[1 0; 0 1], [:Fmc, :Fmc])

        result = FromBasis(:Fmg, [:Fmc, :Fmc])
        @test result == "Fmg[-fma,-fmb]"
    end

    @testset "FromBasis string overload" begin
        reset_state!()
        def_manifold!(:Fs2, 2, [:fsa, :fsb])
        def_chart!(:Fsc, :Fs2, [1, 2], [:fsx, :fsy])
        def_tensor!(:Fst, ["-fsa", "-fsb"], :Fs2)

        set_components!(:Fst, Any[1 0; 0 1], [:Fsc, :Fsc])

        result = FromBasis("Fst", ["Fsc", "Fsc"])
        @test result == "Fst[-fsa,-fsb]"
    end

    @testset "FromBasis error: no components" begin
        reset_state!()
        def_manifold!(:Fe2, 2, [:fea, :feb])
        def_chart!(:Fec, :Fe2, [1, 2], [:fex, :fey])
        def_tensor!(:Fet, ["-fea", "-feb"], :Fe2)
        @test_throws Exception FromBasis(:Fet, [:Fec, :Fec])
    end

    @testset "TraceBasisDummy rank-2 mixed" begin
        reset_state!()
        def_manifold!(:Tr3, 3, [:tra, :trb, :trc])
        def_chart!(:Trc, :Tr3, [1, 2, 3], [:trx, :try, :trz])
        # Mixed tensor: T^a_{b} (first up, second down)
        def_tensor!(:Trt, ["tra", "-trb"], :Tr3)

        set_components!(:Trt, Any[1 0 0; 0 2 0; 0 0 3], [:Trc, :Trc])

        ct = TraceBasisDummy(:Trt, [:Trc, :Trc])
        @test ct.array[] ≈ 6.0  # 1 + 2 + 3
        @test ct.bases == Symbol[]
    end

    @testset "TraceBasisDummy rank-4 mixed" begin
        reset_state!()
        def_manifold!(:Tr4, 2, [:tra4, :trb4, :trc4, :trd4])
        def_chart!(:Tr4c, :Tr4, [1, 2], [:tr4x, :tr4y])
        # T^a_{b,c}^d — slots 1 up, 2 down, 3 down, 4 up
        def_tensor!(:Tr4t, ["tra4", "-trb4", "-trc4", "trd4"], :Tr4)

        # 2x2x2x2 array
        arr = zeros(Int, 2, 2, 2, 2)
        # Set some values: trace on slots (1,2) and (3,4) should contract both pairs
        # For simplicity: identity-like on slots 1-2 and 3-4
        for i in 1:2, j in 1:2, k in 1:2, l in 1:2
            arr[i, j, k, l] = (i == j ? 1 : 0) * (k == l ? 1 : 0)
        end
        set_components!(:Tr4t, arr, [:Tr4c, :Tr4c, :Tr4c, :Tr4c])

        ct = TraceBasisDummy(:Tr4t, [:Tr4c, :Tr4c, :Tr4c, :Tr4c])
        # Contracts (1,2) then (3,4) → trace of 2x2 identity twice = 2 * 2 = 4
        @test ct.array[] ≈ 4.0
        @test ct.bases == Symbol[]
    end

    @testset "TraceBasisDummy no dummy pair errors" begin
        reset_state!()
        def_manifold!(:Tn3, 2, [:tna3, :tnb3])
        def_chart!(:Tn3c, :Tn3, [1, 2], [:tn3x, :tn3y])
        # Both slots covariant — no opposite-variance pair
        def_tensor!(:Tn3t, ["-tna3", "-tnb3"], :Tn3)

        set_components!(:Tn3t, Any[1 0; 0 1], [:Tn3c, :Tn3c])
        @test_throws Exception TraceBasisDummy(:Tn3t, [:Tn3c, :Tn3c])
    end

    @testset "TraceBasisDummy string overload" begin
        reset_state!()
        def_manifold!(:Tso2, 2, [:tsoa, :tsob])
        def_chart!(:Tsoc, :Tso2, [1, 2], [:tsox, :tsoy])
        def_tensor!(:Tsot, ["tsoa", "-tsob"], :Tso2)

        set_components!(:Tsot, Any[5 0; 0 3], [:Tsoc, :Tsoc])

        ct = TraceBasisDummy("Tsot", ["Tsoc", "Tsoc"])
        @test ct.array[] ≈ 8.0
    end
end

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

    @testset "Christoffel not created for dim < 3 labels" begin
        reset_state!()
        def_manifold!(:Km2, 2, [:km2a, :km2b])
        def_metric!(-1, "Km2g[-km2a,-km2b]", :Km2d)
        @test !TensorQ(:ChristoffelKm2d)
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
