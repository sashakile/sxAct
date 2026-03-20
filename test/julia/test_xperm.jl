# Tests for XPerm.jl — permutation utilities and canonicalization.
using Test
using xAct
using xAct.XPerm

@testset "XPerm" begin
    @testset "Permutation utilities" begin
        @test identity_perm(4) == [1, 2, 3, 4]
        @test identity_signed_perm(4) == [1, 2, 3, 4, 5, 6]

        p = [2, 1, 4, 3]
        @test perm_sign(p) == 1   # two 2-cycles = even
        @test perm_sign([2, 1, 3]) == -1  # one transposition = odd

        q = [3, 1, 2]
        @test compose(q, q) == [2, 3, 1]
        @test inverse_perm([2, 3, 1]) == [3, 1, 2]

        @test is_identity([1, 2, 3])
        @test !is_identity([2, 1, 3])

        @test on_point([2, 3, 1], 1) == 2
        @test on_list([2, 3, 1], [1, 2]) == [2, 3]
    end

    @testset "Schreier vector" begin
        # Single transposition on 3 points
        g = [2, 1, 3]  # swaps 1 and 2
        sv = schreier_vector(1, [[2, 1, 3]], 3)
        @test sort(sv.orbit) == [1, 2]

        sv2 = schreier_vector(3, [[2, 1, 3]], 3)
        @test sv2.orbit == [3]  # 3 is fixed
    end

    @testset "canonicalize_slots — Symmetric" begin
        # Symmetric tensor: sort indices lexicographically
        idxs = ["-cnb", "-cna"]  # out of order
        (result, sign) = canonicalize_slots(idxs, :Symmetric, [1, 2])
        @test result == ["-cna", "-cnb"]
        @test sign == 1

        # Already canonical
        idxs2 = ["-cna", "-cnb"]
        (result2, sign2) = canonicalize_slots(idxs2, :Symmetric, [1, 2])
        @test result2 == ["-cna", "-cnb"]
        @test sign2 == 1
    end

    @testset "canonicalize_slots — Antisymmetric" begin
        # Antisymmetric swap: T[-b,-a] = -T[-a,-b]
        idxs = ["-cnb", "-cna"]
        (result, sign) = canonicalize_slots(idxs, :Antisymmetric, [1, 2])
        @test result == ["-cna", "-cnb"]
        @test sign == -1

        # Already canonical
        idxs2 = ["-cna", "-cnb"]
        (result2, sign2) = canonicalize_slots(idxs2, :Antisymmetric, [1, 2])
        @test result2 == ["-cna", "-cnb"]
        @test sign2 == 1

        # Repeated index → zero
        idxs3 = ["-cna", "-cna"]
        (result3, sign3) = canonicalize_slots(idxs3, :Antisymmetric, [1, 2])
        @test sign3 == 0
    end

    @testset "canonicalize_slots — partial slots" begin
        # Antisymmetric on slots [2,3] only (like QGTorsion[a,-b,-c])
        idxs = ["qga", "-qgc", "-qgb"]   # slots 2,3 are out of order
        (result, sign) = canonicalize_slots(idxs, :Antisymmetric, [2, 3])
        @test result == ["qga", "-qgb", "-qgc"]
        @test sign == -1

        # Slot 1 unchanged
        @test result[1] == "qga"
    end

    @testset "canonicalize_slots — Riemann" begin
        # R[-a,-b,-c,-d] + R[-b,-a,-c,-d] = 0 (antisym in first pair)
        idxs = ["-cnb", "-cna", "-cnc", "-cnd"]  # swapped first pair
        (result, sign) = canonicalize_slots(idxs, :RiemannSymmetric, [1, 2, 3, 4])
        # Canonical should have a before b → ["-cna", "-cnb", "-cnc", "-cnd"] with sign=-1
        @test result == ["-cna", "-cnb", "-cnc", "-cnd"]
        @test sign == -1

        # Pair exchange: R[-a,-b,-c,-d] = R[-c,-d,-a,-b]
        # R[-c,-d,-a,-b] should canonicalize to R[-a,-b,-c,-d] with sign +1
        idxs2 = ["-cnc", "-cnd", "-cna", "-cnb"]
        (result2, sign2) = canonicalize_slots(idxs2, :RiemannSymmetric, [1, 2, 3, 4])
        @test result2 == ["-cna", "-cnb", "-cnc", "-cnd"]
        @test sign2 == 1

        # Second pair antisymmetry: R[-a,-b,-d,-c] = -R[-a,-b,-c,-d]
        idxs3 = ["-cna", "-cnb", "-cnd", "-cnc"]
        (result3, sign3) = canonicalize_slots(idxs3, :RiemannSymmetric, [1, 2, 3, 4])
        @test result3 == ["-cna", "-cnb", "-cnc", "-cnd"]
        @test sign3 == -1
    end

    @testset "NoSymmetry passthrough" begin
        idxs = ["-cnb", "-cna"]
        (result, sign) = canonicalize_slots(idxs, :NoSymmetry, Int[])
        @test result == idxs
        @test sign == 1
    end

    @testset "symmetric_sgs" begin
        sgs = symmetric_sgs([1, 2], 3)
        @test sgs.n == 3
        @test !sgs.signed
        @test length(sgs.GS) == 1
        @test sgs.GS[1] == [2, 1, 3]  # transposition of slots 1,2
    end

    @testset "antisymmetric_sgs" begin
        sgs = antisymmetric_sgs([1, 2], 3)
        @test sgs.n == 3
        @test sgs.signed
        g = sgs.GS[1]
        @test length(g) == 5  # n+2 = 5
        @test g[1] == 2 && g[2] == 1  # transposition
        @test g[4] == 5 && g[5] == 4  # sign flip
    end

    @testset "riemann_sgs" begin
        sgs = riemann_sgs((1, 2, 3, 4), 4)
        @test sgs.n == 4
        @test sgs.signed
        @test length(sgs.GS) == 3
    end

    @testset "double_coset_rep — empty dummy groups" begin
        # With no dummy groups, double_coset_rep reduces to right_coset_rep.
        sgs = symmetric_sgs([1, 2, 3], 4)
        perm = [3, 1, 2, 4]   # out-of-order; symmetric group should sort it
        (p_dc, s_dc) = double_coset_rep(perm, sgs, Vector{Vector{Int}}())
        (p_rc, s_rc) = right_coset_rep(perm, sgs)
        @test p_dc == p_rc
        @test s_dc == s_rc
    end

    @testset "double_coset_rep — single dummy pair, trivial slot symmetry" begin
        # n=4, no slot symmetry (trivial sgs), positions 1 and 2 are dummy (interchangeable).
        # Permutation [2,1,3,4]: after applying dummy swap (1↔2) we get [1,2,3,4] < [2,1,3,4].
        # double_coset_rep should find the minimum: [1,2,3,4].
        n = 4
        sgs = StrongGenSet(Int[], Vector{Int}[], n, false)  # trivial group
        perm = [2, 1, 3, 4]
        dummy_groups = [[1, 2]]
        (result, sign) = double_coset_rep(perm, sgs, dummy_groups)
        @test result == [1, 2, 3, 4]
        @test sign == 1
    end

    @testset "double_coset_rep — three-element dummy group, trivial slot symmetry" begin
        # Positions 1, 2, 3 are all dummy (freely interchangeable, n=4).
        # Permutation [3,1,2,4]: the 6 relabelings of {1,2,3} include [1,2,3,4].
        # The minimum representative should be [1,2,3,4].
        n = 4
        sgs = StrongGenSet(Int[], Vector{Int}[], n, false)  # trivial group
        perm = [3, 1, 2, 4]
        dummy_groups = [[1, 2, 3]]
        (result, sign) = double_coset_rep(perm, sgs, dummy_groups)
        @test result == [1, 2, 3, 4]
        @test sign == 1
    end

    @testset "double_coset_rep — dummy swap with antisymmetric slot symmetry" begin
        # n=4, antisymmetric on slots [1,2], positions 3 and 4 are dummy.
        # Permutation [1,2,4,3] (positions 3,4 swapped relative to canonical).
        # Dummy swap of positions 3↔4: gives [1,2,3,4].
        # right_coset_rep([1,2,4,3], antisym_sgs([1,2],4)):
        #   sgs fixes positions 3,4, so [1,2,4,3] stays as-is (positions 3,4 not in sgs base).
        # right_coset_rep([1,2,3,4], antisym_sgs([1,2],4)):
        #   Already canonical.
        # double_coset_rep should find [1,2,3,4] with sign +1.
        n = 4
        sgs = antisymmetric_sgs([1, 2], n)
        perm = [1, 2, 4, 3]
        # Pad perm to n+2 for signed sgs
        perm_full = vcat(perm, [n + 1, n + 2])
        (p_rc, s_rc) = right_coset_rep(perm_full, sgs)
        # p_rc is length n, s_rc is sign
        dummy_groups = [[3, 4]]
        (result, sign) = double_coset_rep(p_rc, sgs, dummy_groups)
        @test result == [1, 2, 3, 4]
        @test sign == 1
    end

    @testset "Young tableaux — standard_tableau" begin
        # Partition [3,2] on indices 1..5
        tab = standard_tableau([3, 2], [1, 2, 3, 4, 5])
        @test tab.partition == [3, 2]
        @test tab.filling == [[1, 2, 3], [4, 5]]

        # Partition [2,1] on indices 1..3
        tab2 = standard_tableau([2, 1], [1, 2, 3])
        @test tab2.partition == [2, 1]
        @test tab2.filling == [[1, 2], [3]]

        # Partition [1,1,1] — fully antisymmetric column
        tab3 = standard_tableau([1, 1, 1], [1, 2, 3])
        @test tab3.partition == [1, 1, 1]
        @test tab3.filling == [[1], [2], [3]]

        # Partition [3] — fully symmetric row
        tab4 = standard_tableau([3], [1, 2, 3])
        @test tab4.partition == [3]
        @test tab4.filling == [[1, 2, 3]]

        # Arbitrary slot indices
        tab5 = standard_tableau([2, 1], [3, 5, 7])
        @test tab5.filling == [[3, 5], [7]]
    end

    @testset "Young tableaux — row_symmetry_sgs" begin
        # Partition [2]: symmetric on 2 elements → S_2 of order 2
        tab = standard_tableau([2], [1, 2])
        sgs = row_symmetry_sgs(tab, 2)
        @test order_of_group(sgs) == 2
        @test !sgs.signed

        # Partition [3]: S_3 of order 6
        tab2 = standard_tableau([3], [1, 2, 3])
        sgs2 = row_symmetry_sgs(tab2, 3)
        @test order_of_group(sgs2) == 6
        @test !sgs2.signed

        # Partition [2,1]: S_2 × trivial = S_2 of order 2
        # Row 1 has slots {1,2}, row 2 has slot {3} — only row 1 contributes
        tab3 = standard_tableau([2, 1], [1, 2, 3])
        sgs3 = row_symmetry_sgs(tab3, 3)
        @test order_of_group(sgs3) == 2
        @test !sgs3.signed

        # Partition [2,2]: S_2 × S_2 of order 4
        tab4 = standard_tableau([2, 2], [1, 2, 3, 4])
        sgs4 = row_symmetry_sgs(tab4, 4)
        @test order_of_group(sgs4) == 4
        @test !sgs4.signed

        # Partition [1,1] on n=2: both rows are singletons → trivial group of order 1
        tab5 = standard_tableau([1, 1], [1, 2])
        sgs5 = row_symmetry_sgs(tab5, 2)
        @test order_of_group(sgs5) == 1
    end

    @testset "Young tableaux — col_antisymmetry_sgs" begin
        # Partition [1,1]: antisymmetric on 2 elements → alternating sign S_2 of order 2
        tab = standard_tableau([1, 1], [1, 2])
        sgs = col_antisymmetry_sgs(tab, 2)
        @test order_of_group(sgs) == 2
        @test sgs.signed

        # Partition [1,1,1] on n=3: antisymmetric on 3 elements → sign S_3 of order 6
        tab2 = standard_tableau([1, 1, 1], [1, 2, 3])
        sgs2 = col_antisymmetry_sgs(tab2, 3)
        @test order_of_group(sgs2) == 6
        @test sgs2.signed

        # Partition [2,1] on n=3:
        # Column 1 has slots {1,3} (rows 1,2 both have >= 1 element)
        # Column 2 has slot {2} (only row 1 has >= 2 elements)
        # Col group: sign transposition (1 3) → order 2
        tab3 = standard_tableau([2, 1], [1, 2, 3])
        sgs3 = col_antisymmetry_sgs(tab3, 3)
        @test order_of_group(sgs3) == 2
        @test sgs3.signed

        # Partition [3] (single row): all columns are singletons → trivial, order 1
        tab4 = standard_tableau([3], [1, 2, 3])
        sgs4 = col_antisymmetry_sgs(tab4, 3)
        @test order_of_group(sgs4) == 1

        # Partition [2,2] on n=4:
        # Column 1: slots {1,3} (rows 1,2 first elements)
        # Column 2: slots {2,4} (rows 1,2 second elements)
        # Col group: sign(1 3) × sign(2 4) → order 4
        tab5 = standard_tableau([2, 2], [1, 2, 3, 4])
        sgs5 = col_antisymmetry_sgs(tab5, 4)
        @test order_of_group(sgs5) == 4
        @test sgs5.signed
    end

    @testset "Young tableaux — young_projector" begin
        # Fully symmetric [2]: P = e + (12), 2 terms
        tab_sym = standard_tableau([2], [1, 2])
        terms_sym = young_projector(tab_sym, 2)
        @test length(terms_sym) == 2
        # All signs should be +1 (row group only, no col antisymmetrization)
        @test all(s == 1 for (_, s) in terms_sym)

        # Fully antisymmetric [1,1]: P = e - (12), 2 terms
        tab_anti = standard_tableau([1, 1], [1, 2])
        terms_anti = young_projector(tab_anti, 2)
        @test length(terms_anti) == 2
        # One term with +1, one with -1
        signs_anti = sort([s for (_, s) in terms_anti])
        @test signs_anti == [-1, 1]

        # Hook shape [2,1] on n=3:
        # Row group: {e, (12)}; Column group: {e, -(13)}
        # P = e·e + e·(12) - (13)·e - (13)·(12)
        # = e + (12) - (13) - (132)
        # 4 distinct permutations, each appearing once
        tab_hook = standard_tableau([2, 1], [1, 2, 3])
        terms_hook = young_projector(tab_hook, 3)
        @test length(terms_hook) == 4
        # Two positive, two negative terms
        pos = count(s > 0 for (_, s) in terms_hook)
        neg = count(s < 0 for (_, s) in terms_hook)
        @test pos == 2
        @test neg == 2

        # Fully symmetric [3]: P = sum of all 6 elements of S_3 with sign +1
        tab_sym3 = standard_tableau([3], [1, 2, 3])
        terms_sym3 = young_projector(tab_sym3, 3)
        @test length(terms_sym3) == 6
        @test all(s == 1 for (_, s) in terms_sym3)

        # Fully antisymmetric [1,1,1]: P = sum of all 6 elements of S_3 with sign = sign(perm)
        tab_anti3 = standard_tableau([1, 1, 1], [1, 2, 3])
        terms_anti3 = young_projector(tab_anti3, 3)
        @test length(terms_anti3) == 6
        # Even permutations get +1, odd get -1
        # S_3 has 3 even (e, (123), (132)) and 3 odd ((12),(13),(23)) permutations
        pos3 = count(s > 0 for (_, s) in terms_anti3)
        neg3 = count(s < 0 for (_, s) in terms_anti3)
        @test pos3 == 3
        @test neg3 == 3
    end

    @testset "YoungTableau empty partition" begin
        tab = YoungTableau(Int[], Int[])
        @test_throws ErrorException XPerm._young_columns(tab)
    end

    @testset "Cycles input validation" begin
        # Duplicate elements in a cycle
        @test_throws ErrorException Cycles([1, 2, 2])

        # Valid cycles should work fine
        @test Cycles([1, 2, 3]) == [2, 3, 1]
        @test Cycles([1, 2], [3, 4]) == [2, 1, 4, 3]
    end

    @testset "StablePoints" begin
        # Single permutation
        @test StablePoints([1, 3, 2]) == [1]  # point 1 is fixed
        @test StablePoints([1, 2, 3]) == [1, 2, 3]  # identity
        @test StablePoints([2, 1, 3]) == [3]

        # Generator set: gen1 swaps 1↔2 (fixes 3,4); gen2 swaps 3↔4 (fixes 1,2)
        # Only points stable under ALL generators: none
        @test StablePoints([[2, 1, 3, 4], [1, 2, 4, 3]]) == Int[]
        # Single generator fixes points 3,4
        @test StablePoints([[2, 1, 3, 4]]) == [3, 4]

        # StrongGenSet
        sgs = schreier_sims([1, 2, 3], [[2, 1, 3]], 3)
        @test 3 in StablePoints(sgs)  # point 3 is stable under (1 2) swap
    end
end
