# Tests for XTensor.jl — DefManifold, DefMetric, DefTensor, ToCanonical.
using Test

include(joinpath(@__DIR__, "..", "XTensor.jl"))
using .XTensor

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
        @test_throws ErrorException PerturbationOrder(:Pog)
        @test_throws ErrorException PerturbationOrder(:DoesNotExist)

        # PerturbationAtOrder returns the tensor registered at each order
        @test PerturbationAtOrder(:Pog, 1) == :PoPert1
        @test PerturbationAtOrder(:Pog, 2) == :PoPert2
        @test PerturbationAtOrder(:Pog, 3) == :PoPert3
        @test PerturbationAtOrder("Pog", 1) == :PoPert1

        # PerturbationAtOrder throws when no perturbation at the given order
        @test_throws ErrorException PerturbationAtOrder(:Pog, 4)
        @test_throws ErrorException PerturbationAtOrder(:DoesNotExist, 1)

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

        # IBP: phi * div(V) → -(grad phi) . V (non-zero, non-trivial)
        ibp_result = IBP("IBphi[] IBD[-ia][IBV[ia]]", "IBD")
        @test !isempty(ibp_result) && ibp_result != "0"

        # IBP: no CovD present → simplified form returned unchanged
        no_covd = IBP("IBphi[] RicciScalarIBD[]", "IBD")
        @test no_covd == Simplify("IBphi[] RicciScalarIBD[]")

        # IBP: V^a ∂_a phi (covd applied to phi, partner is V) → non-zero result
        ibp_grad = IBP("IBV[ia] IBD[-ia][IBphi[]]", "IBD")
        @test !isempty(ibp_grad) && ibp_grad != "0"

        # VarD tests
        # δ(phi * R) / δφ = R
        @test VarD("IBphi[] RicciScalarIBD[]", "IBphi", "IBD") ==
            Simplify("RicciScalarIBD[]")

        # δ(phi * div V) / δφ = div V
        # Note: VarD returns CovD expressions as-is (Simplify cannot handle CovD factors)
        let vard_div = VarD("IBphi[] IBD[-ia][IBV[ia]]", "IBphi", "IBD")
            @test !isempty(vard_div) && vard_div != "0"
            # Should contain IBD and IBV
            @test occursin("IBD", vard_div) && occursin("IBV", vard_div)
        end

        # δ(V^a ∂_a φ) / δφ = -∂_a V^a  (IBP moves derivative off φ)
        vard_grad = VarD("IBV[ia] IBD[-ia][IBphi[]]", "IBphi", "IBD")
        @test !isempty(vard_grad)

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
        err = @test_throws ErrorException ValidateSymbolInSession(:VSM4)
        @test occursin("manifold", err.value.msg)

        # VBundle collision (auto-created by def_manifold!)
        err = @test_throws ErrorException ValidateSymbolInSession(:TangentVSM4)
        @test occursin("vector bundle", err.value.msg)

        # Tensor collision
        def_tensor!(:VST, ["-vsa", "-vsb"], :VSM4; symmetry_str="Symmetric[{-vsa,-vsb}]")
        err = @test_throws ErrorException ValidateSymbolInSession(:VST)
        @test occursin("tensor", err.value.msg)

        # Metric / CovD collision
        def_metric!(1, "VSg[-vsa,-vsb]", :VScd)
        err = @test_throws ErrorException ValidateSymbolInSession(:VScd)
        @test occursin("covariant derivative", err.value.msg) ||
            occursin("metric", err.value.msg)

        # Perturbation collision
        def_tensor!(:VSpert, ["-vsa", "-vsb"], :VSM4; symmetry_str="Symmetric[{-vsa,-vsb}]")
        def_perturbation!(:VSpert, :VSg, 1)
        err = @test_throws ErrorException ValidateSymbolInSession(:VSpert)
        @test occursin("perturbation", err.value.msg) || occursin("tensor", err.value.msg)

        reset_state!()
    end

    @testset "def_manifold! rejects duplicate via ValidateSymbolInSession" begin
        reset_state!()
        def_manifold!(:DupM, 3, [:da, :db, :dc])
        @test_throws ErrorException def_manifold!(:DupM, 3, [:da, :db, :dc])
        reset_state!()
    end

    @testset "def_tensor! rejects name already used as manifold" begin
        reset_state!()
        def_manifold!(:CrossM, 2, [:ca, :cb])
        # Trying to define a tensor with the same name as the manifold
        @test_throws ErrorException def_tensor!(:CrossM, ["-ca", "-cb"], :CrossM)
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
end
