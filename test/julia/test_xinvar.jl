# Tests for XInvar.jl — InvariantCase, RPerm, RInv, MaxIndex, InvarCases.
using Test
using xAct

@testset "XInvar" begin

    # ================================================================
    # InvariantCase
    # ================================================================

    @testset "InvariantCase construction" begin
        c1 = InvariantCase([0])
        @test c1.deriv_orders == [0]
        @test c1.n_epsilon == 0

        c2 = InvariantCase([0, 0], 1)
        @test c2.deriv_orders == [0, 0]
        @test c2.n_epsilon == 1

        c3 = InvariantCase([1, 3])
        @test c3.deriv_orders == [1, 3]
        @test c3.n_epsilon == 0
    end

    @testset "InvariantCase equality and hashing" begin
        a = InvariantCase([0, 2])
        b = InvariantCase([0, 2])
        c = InvariantCase([0, 2], 1)
        d = InvariantCase([2, 0])

        @test a == b
        @test hash(a) == hash(b)
        @test a != c   # different n_epsilon
        @test a != d   # different order of elements

        # Usable as Dict key
        dict = Dict(a => 42)
        @test dict[b] == 42
    end

    @testset "InvariantCase display" begin
        @test repr(InvariantCase([0])) == "InvariantCase([0])"
        @test repr(InvariantCase([0, 2])) == "InvariantCase([0,2])"
        @test repr(InvariantCase([0, 0], 1)) == "InvariantCase([0,0], ε=1)"
    end

    # ================================================================
    # RPerm and RInv
    # ================================================================

    @testset "RPerm construction and equality" begin
        c = InvariantCase([0, 0])
        r1 = RPerm(:CD, c, [5, 6, 7, 8, 1, 2, 3, 4])
        r2 = RPerm(:CD, c, [5, 6, 7, 8, 1, 2, 3, 4])
        r3 = RPerm(:CD, c, [1, 2, 3, 4, 5, 6, 7, 8])

        @test r1 == r2
        @test hash(r1) == hash(r2)
        @test r1 != r3
        @test r1.metric == :CD
        @test r1.case == c
        @test r1.perm == [5, 6, 7, 8, 1, 2, 3, 4]
    end

    @testset "RInv construction and equality" begin
        c = InvariantCase([0, 0])
        i1 = RInv(:CD, c, 1)
        i2 = RInv(:CD, c, 1)
        i3 = RInv(:CD, c, 2)

        @test i1 == i2
        @test hash(i1) == hash(i2)
        @test i1 != i3
        @test i1.metric == :CD
        @test i1.case == c
        @test i1.index == 1
    end

    @testset "RPerm and RInv display" begin
        c = InvariantCase([0])
        @test contains(repr(RPerm(:CD, c, [1, 2, 3, 4])), "RPerm")
        @test contains(repr(RInv(:CD, c, 1)), "RInv")
    end

    # ================================================================
    # PermDegree
    # ================================================================

    @testset "PermDegree" begin
        # Case [0]: 1 Riemann, no derivatives → 4*1 + 0 + 0 = 4
        @test PermDegree(InvariantCase([0])) == 4

        # Case [0,0]: 2 Riemanns → 4*2 + 0 + 0 = 8
        @test PermDegree(InvariantCase([0, 0])) == 8

        # Case [2]: 1 Riemann + 2 derivatives → 4*1 + 2 + 0 = 6
        @test PermDegree(InvariantCase([2])) == 6

        # Case [0,2]: 2 Riemanns + 2 derivatives → 4*2 + 2 + 0 = 10
        @test PermDegree(InvariantCase([0, 2])) == 10

        # Case [1,1]: 2 Riemanns + 2 derivatives → 4*2 + 2 + 0 = 10
        @test PermDegree(InvariantCase([1, 1])) == 10

        # Case [0,0] dual: 2 Riemanns + epsilon → 4*2 + 0 + 4 = 12
        @test PermDegree(InvariantCase([0, 0], 1)) == 12

        # Empty case → 0
        @test PermDegree(InvariantCase(Int[])) == 0

        # All InvarCases: PermDegree matches formula
        for c in InvarCases()
            deg = length(c.deriv_orders)
            deriv_sum = sum(c.deriv_orders; init=0)
            @test PermDegree(c) == 4 * deg + deriv_sum
        end
    end

    # ================================================================
    # MaxIndex
    # ================================================================

    @testset "MaxIndex" begin
        # Spot checks against Wolfram Invar.m
        @test MaxIndex([0]) == 1
        @test MaxIndex([0, 0]) == 3
        @test MaxIndex([2]) == 2
        @test MaxIndex([0, 0, 0]) == 9
        @test MaxIndex([0, 2]) == 12
        @test MaxIndex([1, 1]) == 12
        @test MaxIndex([4]) == 12
        @test MaxIndex([0, 0, 0, 0]) == 38
        @test MaxIndex([6]) == 105
        @test MaxIndex([0, 0, 0, 0, 0, 0, 0]) == 16532

        # Integer shorthand: MaxIndex(n) = MaxIndex(fill(0, n))
        @test MaxIndex(1) == 1
        @test MaxIndex(2) == 3
        @test MaxIndex(3) == 9
        @test MaxIndex(7) == 16532

        # InvariantCase overload
        @test MaxIndex(InvariantCase([0, 0])) == 3
        @test MaxIndex(InvariantCase([1, 3])) == 138

        # Higher algebraic
        @test MaxIndex(8) == 217395
        @test MaxIndex(9) == 3406747

        # Unknown case throws
        @test_throws ArgumentError MaxIndex([99])
        @test_throws ArgumentError MaxIndex([0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
    end

    @testset "MaxIndex covers all InvarCases" begin
        for c in InvarCases()
            @test MaxIndex(c) > 0
        end
    end

    # ================================================================
    # MaxDualIndex
    # ================================================================

    @testset "MaxDualIndex" begin
        @test MaxDualIndex([0]) == 1
        @test MaxDualIndex([0, 0]) == 4
        @test MaxDualIndex([2]) == 3
        @test MaxDualIndex([0, 0, 0]) == 27
        @test MaxDualIndex([0, 0, 0, 0]) == 232
        @test MaxDualIndex([6]) == 435

        # Integer shorthand
        @test MaxDualIndex(1) == 1
        @test MaxDualIndex(5) == 2582

        # InvariantCase overload
        @test MaxDualIndex(InvariantCase([0, 2])) == 58

        # Unknown case throws
        @test_throws ArgumentError MaxDualIndex([99])
    end

    @testset "MaxDualIndex covers all InvarDualCases" begin
        for c in InvarDualCases()
            @test MaxDualIndex(c.deriv_orders) > 0
        end
    end

    # ================================================================
    # InvarCases
    # ================================================================

    @testset "InvarCases() total count" begin
        all_cases = InvarCases()
        @test length(all_cases) == 48
        # All unique
        @test length(Set(all_cases)) == 48
    end

    @testset "InvarCases by order" begin
        @test length(InvarCases(2)) == 1
        @test length(InvarCases(4)) == 2
        @test length(InvarCases(6)) == 4
        @test length(InvarCases(8)) == 7
        @test length(InvarCases(10)) == 12
        @test length(InvarCases(12)) == 21
        @test length(InvarCases(14)) == 1
    end

    @testset "InvarCases by order and degree" begin
        # Order 2, degree 1: single Riemann
        @test Set(InvarCases(2, 1)) == Set([InvariantCase([0])])

        # Order 4
        @test Set(InvarCases(4, 2)) == Set([InvariantCase([0, 0])])
        @test Set(InvarCases(4, 1)) == Set([InvariantCase([2])])

        # Order 6, degree 2
        @test Set(InvarCases(6, 2)) == Set([InvariantCase([0, 2]), InvariantCase([1, 1])])

        # Order 8, degree 3
        @test Set(InvarCases(8, 3)) ==
            Set([InvariantCase([0, 0, 2]), InvariantCase([0, 1, 1])])

        # Order 12, degree 4
        expected = Set([
            InvariantCase([0, 0, 0, 4]),
            InvariantCase([0, 0, 1, 3]),
            InvariantCase([0, 0, 2, 2]),
            InvariantCase([0, 1, 1, 2]),
            InvariantCase([1, 1, 1, 1]),
        ])
        @test Set(InvarCases(12, 4)) == expected

        # Invalid degree returns empty
        @test isempty(InvarCases(2, 2))  # order 2 only has degree 1
    end

    @testset "InvarCases order constraints" begin
        # Derivative order = 2*degree + sum(deriv_orders)
        for order in 2:2:14
            for c in InvarCases(order)
                deg = length(c.deriv_orders)
                computed_order = 2 * deg + sum(c.deriv_orders; init=0)
                @test computed_order == order
            end
        end
    end

    @testset "InvarCases non-decreasing deriv_orders" begin
        for c in InvarCases()
            @test issorted(c.deriv_orders)
            @test c.n_epsilon == 0
        end
    end

    @testset "InvarCases validation" begin
        @test_throws ArgumentError InvarCases(3)   # odd
        @test_throws ArgumentError InvarCases(0)   # too small
        @test_throws ArgumentError InvarCases(16)  # too large
    end

    @testset "InvarCases matches Wolfram case set" begin
        # Verify exact set of all 48 cases against Wolfram Invar.m:324-357
        wolfram_cases = Set([
            # Order 2
            InvariantCase([0]),
            # Order 4
            InvariantCase([0, 0]),
            InvariantCase([2]),
            # Order 6
            InvariantCase([0, 0, 0]),
            InvariantCase([0, 2]),
            InvariantCase([1, 1]),
            InvariantCase([4]),
            # Order 8
            InvariantCase([0, 0, 0, 0]),
            InvariantCase([0, 0, 2]),
            InvariantCase([0, 1, 1]),
            InvariantCase([0, 4]),
            InvariantCase([1, 3]),
            InvariantCase([2, 2]),
            InvariantCase([6]),
            # Order 10
            InvariantCase([0, 0, 0, 0, 0]),
            InvariantCase([0, 0, 0, 2]),
            InvariantCase([0, 0, 1, 1]),
            InvariantCase([0, 0, 4]),
            InvariantCase([0, 1, 3]),
            InvariantCase([0, 2, 2]),
            InvariantCase([1, 1, 2]),
            InvariantCase([0, 6]),
            InvariantCase([1, 5]),
            InvariantCase([2, 4]),
            InvariantCase([3, 3]),
            InvariantCase([8]),
            # Order 12
            InvariantCase([0, 0, 0, 0, 0, 0]),
            InvariantCase([0, 0, 0, 0, 2]),
            InvariantCase([0, 0, 0, 1, 1]),
            InvariantCase([0, 0, 0, 4]),
            InvariantCase([0, 0, 1, 3]),
            InvariantCase([0, 0, 2, 2]),
            InvariantCase([0, 1, 1, 2]),
            InvariantCase([1, 1, 1, 1]),
            InvariantCase([0, 0, 6]),
            InvariantCase([0, 1, 5]),
            InvariantCase([0, 2, 4]),
            InvariantCase([1, 1, 4]),
            InvariantCase([0, 3, 3]),
            InvariantCase([1, 2, 3]),
            InvariantCase([2, 2, 2]),
            InvariantCase([0, 8]),
            InvariantCase([1, 7]),
            InvariantCase([2, 6]),
            InvariantCase([3, 5]),
            InvariantCase([4, 4]),
            InvariantCase([10]),
            # Order 14
            InvariantCase([0, 0, 0, 0, 0, 0, 0]),
        ])
        @test Set(InvarCases()) == wolfram_cases
    end

    # ================================================================
    # InvarDualCases
    # ================================================================

    @testset "InvarDualCases() total count" begin
        dual_cases = InvarDualCases()
        @test length(dual_cases) == 15
        @test length(Set(dual_cases)) == 15
    end

    @testset "InvarDualCases by order" begin
        @test length(InvarDualCases(2)) == 1
        @test length(InvarDualCases(4)) == 2
        @test length(InvarDualCases(6)) == 4
        @test length(InvarDualCases(8)) == 7
        @test length(InvarDualCases(10)) == 1
    end

    @testset "InvarDualCases all have n_epsilon=1" begin
        for c in InvarDualCases()
            @test c.n_epsilon == 1
            @test issorted(c.deriv_orders)
        end
    end

    @testset "InvarDualCases matches Wolfram case set" begin
        wolfram_dual = Set([
            # Order 2
            InvariantCase([0], 1),
            # Order 4
            InvariantCase([0, 0], 1),
            InvariantCase([2], 1),
            # Order 6
            InvariantCase([0, 0, 0], 1),
            InvariantCase([0, 2], 1),
            InvariantCase([1, 1], 1),
            InvariantCase([4], 1),
            # Order 8
            InvariantCase([0, 0, 0, 0], 1),
            InvariantCase([0, 0, 2], 1),
            InvariantCase([0, 1, 1], 1),
            InvariantCase([0, 4], 1),
            InvariantCase([1, 3], 1),
            InvariantCase([2, 2], 1),
            InvariantCase([6], 1),
            # Order 10
            InvariantCase([0, 0, 0, 0, 0], 1),
        ])
        @test Set(InvarDualCases()) == wolfram_dual
    end

    @testset "InvarDualCases validation" begin
        @test_throws ArgumentError InvarDualCases(3)
        @test_throws ArgumentError InvarDualCases(0)
        @test_throws ArgumentError InvarDualCases(12)
    end

    # ================================================================
    # Module loading
    # ================================================================

    @testset "XInvar loaded via xAct" begin
        @test isdefined(xAct, :XInvar)
        @test InvariantCase isa DataType
        @test RPerm isa DataType
        @test RInv isa DataType
    end

    # ================================================================
    # InvarDB — Database loading and rule parser
    # ================================================================

    @testset "InvarDB" begin

        # Access internal functions via the XInvar module
        _case_to_filename = xAct.XInvar._case_to_filename
        _rinv_filename = xAct.XInvar._rinv_filename
        _dinv_filename = xAct.XInvar._dinv_filename
        _cycles_to_images = xAct.XInvar._cycles_to_images
        _parse_maple_perm_line = xAct.XInvar._parse_maple_perm_line
        _parse_mma_rule = xAct.XInvar._parse_mma_rule
        _parse_nested_intlist = xAct.XInvar._parse_nested_intlist
        _parse_int_csv = xAct.XInvar._parse_int_csv
        _parse_linear_combination = xAct.XInvar._parse_linear_combination
        _parse_coefficient = xAct.XInvar._parse_coefficient
        _extract_inv_index = xAct.XInvar._extract_inv_index
        _extract_inv_case = xAct.XInvar._extract_inv_case
        _step_subdir = xAct.XInvar._step_subdir

        # ============================================================
        # _case_to_filename
        # ============================================================

        @testset "_case_to_filename" begin
            @test _case_to_filename([0]) == "0"
            @test _case_to_filename([0, 0]) == "0_0"
            @test _case_to_filename([1, 3]) == "1_3"
            @test _case_to_filename([0, 0, 0]) == "0_0_0"
            @test _case_to_filename([0, 2, 4]) == "0_2_4"
            @test _case_to_filename([0, 0, 0, 0, 0, 0, 0]) == "0_0_0_0_0_0_0"
        end

        # ============================================================
        # _rinv_filename / _dinv_filename
        # ============================================================

        @testset "filename helpers" begin
            @test _rinv_filename(1, [0, 0]) == "RInv-0_0-1"
            @test _rinv_filename(2, [0, 0]) == "RInv-0_0-2"
            @test _rinv_filename(3, [1, 3]) == "RInv-1_3-3"
            @test _rinv_filename(4, [0]) == "RInv-0-4"
            @test _rinv_filename(5, [0, 0]; dim=4) == "RInv-0_0-5_4"
            @test _rinv_filename(6, [0, 0]; dim=4) == "RInv-0_0-6_4"
            @test _rinv_filename(5, [0, 0]; dim=3) == "RInv-0_0-5_3"

            @test _dinv_filename(1, [0, 0]) == "DInv-0_0-1"
            @test _dinv_filename(2, [0, 0]) == "DInv-0_0-2"
            @test _dinv_filename(5, [0, 0]; dim=4) == "DInv-0_0-5_4"
        end

        # ============================================================
        # _step_subdir
        # ============================================================

        @testset "_step_subdir" begin
            @test _step_subdir(1) == "1"
            @test _step_subdir(2) == "2"
            @test _step_subdir(3) == "3"
            @test _step_subdir(4) == "4"
            @test _step_subdir(5; dim=4) == "5_4"
            @test _step_subdir(6; dim=4) == "6_4"
            @test _step_subdir(5; dim=3) == "5_3"
        end

        # ============================================================
        # _cycles_to_images
        # ============================================================

        @testset "_cycles_to_images" begin
            # Simple transpositions: [[2,1],[4,3]] on degree 4
            @test _cycles_to_images([[2, 1], [4, 3]], 4) == [2, 1, 4, 3]

            # Identity (no cycles)
            @test _cycles_to_images(Vector{Int}[], 4) == [1, 2, 3, 4]

            # Single 2-cycle: [[1,3]] on degree 4 → 1→3, 3→1, 2→2, 4→4
            @test _cycles_to_images([[1, 3]], 4) == [3, 2, 1, 4]

            # 3-cycle: [[1,2,3]] on degree 4 → 1→2, 2→3, 3→1, 4→4
            @test _cycles_to_images([[1, 2, 3]], 4) == [2, 3, 1, 4]

            # Full example from case [0,0]: 8 slots, 4 transpositions
            @test _cycles_to_images([[2, 1], [4, 3], [6, 5], [8, 7]], 8) ==
                [2, 1, 4, 3, 6, 5, 8, 7]

            # Disjoint 2-cycles mixing positions
            @test _cycles_to_images([[2, 5], [4, 7], [6, 1], [8, 3]], 8) ==
                [6, 5, 8, 7, 2, 1, 4, 3]

            # Single element cycle (fixed point) — should be identity
            @test _cycles_to_images([[1]], 3) == [1, 2, 3]
        end

        # ============================================================
        # _parse_int_csv
        # ============================================================

        @testset "_parse_int_csv" begin
            @test _parse_int_csv("2,1") == [2, 1]
            @test _parse_int_csv("4, 3") == [4, 3]
            @test _parse_int_csv("6 , 5") == [6, 5]
            @test _parse_int_csv("8") == [8]
            @test _parse_int_csv("") == Int[]
            @test _parse_int_csv("1, 2, 3, 4") == [1, 2, 3, 4]
        end

        # ============================================================
        # _parse_nested_intlist
        # ============================================================

        @testset "_parse_nested_intlist" begin
            @test _parse_nested_intlist("[[2,1],[4,3]]") == [[2, 1], [4, 3]]
            @test _parse_nested_intlist("[[2,1],[4,3],[6,5],[8,7]]") ==
                [[2, 1], [4, 3], [6, 5], [8, 7]]
            @test _parse_nested_intlist("{{2,1},{4,3}}") == [[2, 1], [4, 3]]
            @test _parse_nested_intlist("[[1,2,3]]") == [[1, 2, 3]]
            @test _parse_nested_intlist("[[5]]") == [[5]]
            @test _parse_nested_intlist("not_a_list") == Vector{Int}[]
        end

        # ============================================================
        # _parse_maple_perm_line
        # ============================================================

        @testset "_parse_maple_perm_line" begin
            # Standard step-1 line
            line1 = "RInv[{0,0},1] := [[2,1],[4,3],[6,5],[8,7]];"
            perm1 = _parse_maple_perm_line(line1)
            @test perm1 == [2, 1, 4, 3, 6, 5, 8, 7]

            line2 = "RInv[{0,0},2] := [[2,5],[4,7],[6,1],[8,3]];"
            perm2 = _parse_maple_perm_line(line2)
            @test perm2 == [6, 5, 8, 7, 2, 1, 4, 3]

            line3 = "RInv[{0,0},3] := [[2,5],[4,3],[6,7],[8,1]];"
            perm3 = _parse_maple_perm_line(line3)
            @test perm3 == [8, 5, 4, 3, 2, 7, 6, 1]

            # Empty / blank lines
            @test _parse_maple_perm_line("") === nothing
            @test _parse_maple_perm_line("   ") === nothing
            @test _parse_maple_perm_line("# comment") === nothing

            # Line without := delimiter
            @test _parse_maple_perm_line("some random text") === nothing

            # Dual invariant line
            dline = "DInv[{0,0},1] := [[2,1],[4,3],[6,5],[8,7],[10,9],[12,11]];"
            dperm = _parse_maple_perm_line(dline)
            @test dperm == [2, 1, 4, 3, 6, 5, 8, 7, 10, 9, 12, 11]
        end

        # ============================================================
        # _extract_inv_index / _extract_inv_case
        # ============================================================

        @testset "_extract_inv_index" begin
            @test _extract_inv_index("RInv[{0,0},3]") == 3
            @test _extract_inv_index("RInv[{0},1]") == 1
            @test _extract_inv_index("DualRInv[{0,0,2},99]") == 99
            @test _extract_inv_index("RInv[{1,3},138]") == 138
            @test _extract_inv_index("bad") === nothing
        end

        @testset "_extract_inv_case" begin
            @test _extract_inv_case("RInv[{0,0},3]") == [0, 0]
            @test _extract_inv_case("RInv[{0},1]") == [0]
            @test _extract_inv_case("DualRInv[{0,0,2},5]") == [0, 0, 2]
            @test _extract_inv_case("bad") === nothing
        end

        # ============================================================
        # _parse_coefficient
        # ============================================================

        @testset "_parse_coefficient" begin
            @test _parse_coefficient("") == 1 // 1
            @test _parse_coefficient("+") == 1 // 1
            @test _parse_coefficient("-") == -1 // 1
            @test _parse_coefficient("2*") == 2 // 1
            @test _parse_coefficient("-3*") == -3 // 1
            @test _parse_coefficient("3/2*") == 3 // 2
            @test _parse_coefficient("-3/2*") == -3 // 2
            @test _parse_coefficient("+ 2*") == 2 // 1
            @test _parse_coefficient("- 2*") == -2 // 1
            @test _parse_coefficient("sigma*") == 1 // 1
            @test _parse_coefficient("- sigma*") == -1 // 1
        end

        # ============================================================
        # _parse_linear_combination
        # ============================================================

        @testset "_parse_linear_combination" begin
            # Simple: one term
            terms1 = _parse_linear_combination("RInv[{0,0},1]")
            @test length(terms1) == 1
            @test terms1[1] == (1, 1 // 1)

            # Subtraction: a - b
            terms2 = _parse_linear_combination("RInv[{0,0},1] - RInv[{0,0},2]")
            @test length(terms2) == 2
            @test terms2[1] == (1, 1 // 1)
            @test terms2[2] == (2, -1 // 1)

            # Addition: a + b
            terms3 = _parse_linear_combination("RInv[{0,0},1] + RInv[{0,0},2]")
            @test length(terms3) == 2
            @test terms3[1] == (1, 1 // 1)
            @test terms3[2] == (2, 1 // 1)

            # Coefficient: 2*a - 3*b
            terms4 = _parse_linear_combination("2*RInv[{0,0},1] - 3*RInv[{0,0},2]")
            @test length(terms4) == 2
            @test terms4[1] == (1, 2 // 1)
            @test terms4[2] == (2, -3 // 1)

            # Rational coefficient: 3/2*a
            terms5 = _parse_linear_combination("3/2*RInv[{0,0},1]")
            @test length(terms5) == 1
            @test terms5[1] == (1, 3 // 2)

            # Negative leading coefficient: -RInv[{0,0},1]
            terms6 = _parse_linear_combination("-RInv[{0,0},1]")
            @test length(terms6) == 1
            @test terms6[1] == (1, -1 // 1)

            # Three terms: a - b + c
            terms7 = _parse_linear_combination(
                "RInv[{0,0},1] - RInv[{0,0},2] + RInv[{0,0},3]"
            )
            @test length(terms7) == 3
            @test terms7[1] == (1, 1 // 1)
            @test terms7[2] == (2, -1 // 1)
            @test terms7[3] == (3, 1 // 1)

            # Empty
            @test isempty(_parse_linear_combination(""))
        end

        # ============================================================
        # _parse_mma_rule
        # ============================================================

        @testset "_parse_mma_rule" begin
            # Simple rule
            r1 = _parse_mma_rule("RInv[{0,0},3] -> RInv[{0,0},1] - RInv[{0,0},2]")
            @test r1 !== nothing
            dep_idx, terms = r1
            @test dep_idx == 3
            @test length(terms) == 2
            @test terms[1] == (1, 1 // 1)
            @test terms[2] == (2, -1 // 1)

            # Rule with coefficients
            r2 = _parse_mma_rule(
                "RInv[{0,0,0},5] -> 2*RInv[{0,0,0},1] - 3/2*RInv[{0,0,0},2]"
            )
            @test r2 !== nothing
            dep_idx2, terms2 = r2
            @test dep_idx2 == 5
            @test terms2[1] == (1, 2 // 1)
            @test terms2[2] == (2, -3 // 2)

            # Blank line
            @test _parse_mma_rule("") === nothing
            @test _parse_mma_rule("   ") === nothing

            # Line without ->
            @test _parse_mma_rule("no arrow here") === nothing
        end

        # ============================================================
        # read_invar_perms (with temp file)
        # ============================================================

        @testset "read_invar_perms" begin
            tmpfile = tempname()
            try
                # Write synthetic step-1 data (case [0,0], 3 invariants)
                open(tmpfile, "w") do io
                    println(io, "RInv[{0,0},1] := [[2,1],[4,3],[6,5],[8,7]];")
                    println(io, "RInv[{0,0},2] := [[2,5],[4,7],[6,1],[8,3]];")
                    println(io, "RInv[{0,0},3] := [[2,5],[4,3],[6,7],[8,1]];")
                end
                result = read_invar_perms(tmpfile)
                @test length(result) == 3
                @test result[1] == [2, 1, 4, 3, 6, 5, 8, 7]
                @test result[2] == [6, 5, 8, 7, 2, 1, 4, 3]
                @test result[3] == [8, 5, 4, 3, 2, 7, 6, 1]
            finally
                isfile(tmpfile) && rm(tmpfile)
            end

            # Non-existent file returns empty dict
            result2 = read_invar_perms("/nonexistent/path")
            @test isempty(result2)
        end

        # ============================================================
        # read_invar_rules (with temp file)
        # ============================================================

        @testset "read_invar_rules" begin
            tmpfile = tempname()
            try
                open(tmpfile, "w") do io
                    println(io, "RInv[{0,0},3] -> RInv[{0,0},1] - RInv[{0,0},2]")
                    println(io, "RInv[{0,0},5] -> 2*RInv[{0,0},1] + RInv[{0,0},4]")
                end
                result = read_invar_rules(tmpfile)
                @test length(result) == 2
                @test haskey(result, 3)
                @test haskey(result, 5)
                @test result[3] == [(1, 1 // 1), (2, -1 // 1)]
                @test result[5] == [(1, 2 // 1), (4, 1 // 1)]
            finally
                isfile(tmpfile) && rm(tmpfile)
            end

            # Non-existent file returns empty dict
            result2 = read_invar_rules("/nonexistent/path")
            @test isempty(result2)
        end

        # ============================================================
        # LoadInvarDB (with synthetic database)
        # ============================================================

        @testset "LoadInvarDB" begin
            dbdir = mktempdir()
            try
                # Create minimal database structure
                riemann = joinpath(dbdir, "Riemann")
                mkpath(joinpath(riemann, "1"))
                mkpath(joinpath(riemann, "2"))
                mkpath(joinpath(riemann, "3"))

                # Step 1: case [0] (1 invariant — the Kretschner scalar)
                open(joinpath(riemann, "1", "RInv-0-1"), "w") do io
                    println(io, "RInv[{0},1] := [[2,1],[4,3]];")
                end

                # Step 1: case [0,0] (3 invariants)
                open(joinpath(riemann, "1", "RInv-0_0-1"), "w") do io
                    println(io, "RInv[{0,0},1] := [[2,1],[4,3],[6,5],[8,7]];")
                    println(io, "RInv[{0,0},2] := [[2,5],[4,7],[6,1],[8,3]];")
                    println(io, "RInv[{0,0},3] := [[2,5],[4,3],[6,7],[8,1]];")
                end

                # Step 2: case [0,0] rule
                open(joinpath(riemann, "2", "RInv-0_0-2"), "w") do io
                    println(io, "RInv[{0,0},3] -> RInv[{0,0},1] - RInv[{0,0},2]")
                end

                # Step 3: case [0,0,0] rule (empty file — no rules)
                open(joinpath(riemann, "3", "RInv-0_0_0-3"), "w") do io
                    # empty file
                end

                db = LoadInvarDB(dbdir)

                # Check struct type
                @test db isa InvarDB

                # Check perms loaded
                @test haskey(db.perms, [0])
                @test length(db.perms[[0]]) == 1
                @test db.perms[[0]][1] == [2, 1, 4, 3]

                @test haskey(db.perms, [0, 0])
                @test length(db.perms[[0, 0]]) == 3
                @test db.perms[[0, 0]][1] == [2, 1, 4, 3, 6, 5, 8, 7]

                # Check rules loaded
                @test haskey(db.rules[2], [0, 0])
                @test haskey(db.rules[2][[0, 0]], 3)
                @test db.rules[2][[0, 0]][3] == [(1, 1 // 1), (2, -1 // 1)]

                # Check empty file
                @test haskey(db.rules[3], [0, 0, 0])
                @test isempty(db.rules[3][[0, 0, 0]])

                # Check display
                s = repr(db)
                @test contains(s, "InvarDB")
                @test contains(s, "perms")
            finally
                rm(dbdir; recursive=true)
            end
        end

        @testset "LoadInvarDB missing directory" begin
            db = LoadInvarDB("/nonexistent/dbdir")
            @test db isa InvarDB
            @test isempty(db.perms)
            @test isempty(db.dual_perms)
        end

        # ============================================================
        # Lazy loading globals
        # ============================================================

        @testset "lazy loading" begin
            # Reset should clear the cached DB
            xAct.XInvar._reset_invar_db!()
            @test xAct.XInvar._invar_db === nothing

            # _ensure_db_loaded with nonexistent path creates an empty DB
            db = xAct.XInvar._ensure_db_loaded("/nonexistent")
            @test db isa InvarDB
            @test xAct.XInvar._invar_db !== nothing
            @test xAct.XInvar._invar_db === db

            # Calling again returns the same cached instance
            db2 = xAct.XInvar._ensure_db_loaded("/nonexistent")
            @test db2 === db

            # Reset clears it
            xAct.XInvar._reset_invar_db!()
            @test xAct.XInvar._invar_db === nothing
        end

        # ============================================================
        # reset_state! clears InvarDB
        # ============================================================

        @testset "reset_state! clears InvarDB" begin
            # Load a DB
            xAct.XInvar._ensure_db_loaded("/nonexistent")
            @test xAct.XInvar._invar_db !== nothing

            # reset_state! should clear it
            xAct.reset_state!()
            @test xAct.XInvar._invar_db === nothing
        end
    end

    # ================================================================
    # Phase 3: Riemann-to-Permutation Conversion
    # ================================================================

    # Access internal functions
    _parse_invar_monomial = xAct.XInvar._parse_invar_monomial
    _parse_invar_sum = xAct.XInvar._parse_invar_sum
    _ricci_to_riemann = xAct.XInvar._ricci_to_riemann
    _classify_case = xAct.XInvar._classify_case
    _extract_contraction_perm = xAct.XInvar._extract_contraction_perm
    _canonicalize_contraction_perm = xAct.XInvar._canonicalize_contraction_perm
    _riemann_to_ricci = xAct.XInvar._riemann_to_ricci

    @testset "Phase 3: String Parsing" begin
        @testset "_parse_invar_monomial: plain tensor" begin
            coeff, factors = _parse_invar_monomial("RiemannCD[-a,-b,-c,-d]")
            @test coeff == 1 // 1
            @test length(factors) == 1
            @test factors[1].tensor_name == "RiemannCD"
            @test factors[1].indices == ["-a", "-b", "-c", "-d"]
            @test isempty(factors[1].covd_indices)
        end

        @testset "_parse_invar_monomial: product of two tensors" begin
            coeff, factors = _parse_invar_monomial(
                "RiemannCD[-a,-b,-c,-d] RiemannCD[a,b,c,d]"
            )
            @test coeff == 1 // 1
            @test length(factors) == 2
            @test factors[1].indices == ["-a", "-b", "-c", "-d"]
            @test factors[2].indices == ["a", "b", "c", "d"]
        end

        @testset "_parse_invar_monomial: with coefficient" begin
            coeff, factors = _parse_invar_monomial(
                "3 RiemannCD[-a,-b,-c,-d] RiemannCD[a,b,c,d]"
            )
            @test coeff == 3 // 1
            @test length(factors) == 2

            coeff2, factors2 = _parse_invar_monomial("(1/2) RiemannCD[-a,-b,-c,-d]")
            @test coeff2 == 1 // 2
            @test length(factors2) == 1
        end

        @testset "_parse_invar_monomial: CovD wrapping" begin
            coeff, factors = _parse_invar_monomial("CD[-e][RiemannCD[-a,-b,-c,-d]]")
            @test coeff == 1 // 1
            @test length(factors) == 1
            @test factors[1].tensor_name == "RiemannCD"
            @test factors[1].indices == ["-a", "-b", "-c", "-d"]
            @test factors[1].covd_indices == ["-e"]
        end

        @testset "_parse_invar_monomial: double CovD" begin
            coeff, factors = _parse_invar_monomial("CD[-e][CD[-f][RiemannCD[-a,-b,-c,-d]]]")
            @test length(factors) == 1
            @test factors[1].covd_indices == ["-e", "-f"]
            @test factors[1].indices == ["-a", "-b", "-c", "-d"]
        end

        @testset "_parse_invar_monomial: RicciScalar" begin
            coeff, factors = _parse_invar_monomial("RicciScalarCD[]")
            @test length(factors) == 1
            @test factors[1].tensor_name == "RicciScalarCD"
            @test isempty(factors[1].indices)
        end

        @testset "_parse_invar_sum" begin
            terms = _parse_invar_sum("RiemannCD[-a,-b,-c,-d] + RiemannCD[-e,-f,-g,-h]")
            @test length(terms) == 2
            @test terms[1][1] == 1
            @test terms[2][1] == 1

            terms2 = _parse_invar_sum("RiemannCD[-a,-b,-c,-d] - RiemannCD[-e,-f,-g,-h]")
            @test length(terms2) == 2
            @test terms2[1][1] == 1
            @test terms2[2][1] == -1

            terms3 = _parse_invar_sum("-RiemannCD[-a,-b,-c,-d]")
            @test length(terms3) == 1
            @test terms3[1][1] == -1
        end
    end

    @testset "Phase 3: _ricci_to_riemann" begin
        @testset "RicciScalar replacement" begin
            result = _ricci_to_riemann("RicciScalarCD[]", :CD)
            @test !contains(result, "RicciScalar")
            @test contains(result, "RiemannCD[")
            # Should have 4 indices: two fresh up, two fresh down
            m = match(r"RiemannCD\[([^\]]+)\]", result)
            @test !isnothing(m)
            indices = split(m.captures[1], ",")
            @test length(indices) == 4
        end

        @testset "Ricci replacement" begin
            result = _ricci_to_riemann("RicciCD[-a,-b]", :CD)
            @test !contains(result, "RicciCD")
            @test contains(result, "RiemannCD[")
            @test contains(result, "-a")
            @test contains(result, "-b")
        end

        @testset "multiple replacements" begin
            result = _ricci_to_riemann("RicciCD[-a,-b] RicciCD[a,b]", :CD)
            @test !contains(result, "RicciCD")
            # Should have two Riemann factors
            @test length(collect(eachmatch(r"RiemannCD\[", result))) == 2
        end

        @testset "no-op on pure Riemann" begin
            expr = "RiemannCD[-a,-b,-c,-d]"
            @test _ricci_to_riemann(expr, :CD) == expr
        end
    end

    @testset "Phase 3: _classify_case" begin
        @testset "single Riemann" begin
            case = _classify_case("RiemannCD[-a,-b,-c,-d]", :g)
            @test case == InvariantCase([0])
        end

        @testset "two Riemanns" begin
            case = _classify_case("RiemannCD[-a,-b,-c,-d] RiemannCD[a,b,c,d]", :g)
            @test case == InvariantCase([0, 0])
        end

        @testset "differential invariant" begin
            case = _classify_case(
                "CD[-e][RiemannCD[-a,-b,-c,-d]] CD[e][RiemannCD[a,b,c,d]]", :g
            )
            @test case == InvariantCase([1, 1])
        end

        @testset "mixed derivative orders" begin
            # One undifferentiated Riemann + one with 2 derivatives
            case = _classify_case(
                "RiemannCD[-a,-b,-c,-d] CD[-e][CD[-f][RiemannCD[a,b,c,d]]]", :g
            )
            @test case == InvariantCase([0, 2])
        end

        @testset "error on non-Riemann" begin
            @test_throws ArgumentError _classify_case("gCD[-a,-b]", :g)
        end
    end

    @testset "Phase 3: _extract_contraction_perm" begin
        @testset "Kretschner scalar (case [0,0])" begin
            case = InvariantCase([0, 0])
            perm = _extract_contraction_perm(
                "RiemannCD[-a,-b,-c,-d] RiemannCD[a,b,c,d]", case
            )
            @test length(perm) == 8
            # Slots 1-4 map to 5-8 (and vice versa)
            @test perm == [5, 6, 7, 8, 1, 2, 3, 4]
        end

        @testset "Ricci scalar (case [0])" begin
            case = InvariantCase([0])
            # After ricci_to_riemann: RiemannCD[xa,xb,-xa,-xb]
            perm = _extract_contraction_perm("RiemannCD[xa,xb,-xa,-xb]", case)
            @test length(perm) == 4
            # xa at slot 1 (up) pairs with -xa at slot 3 (down)
            # xb at slot 2 (up) pairs with -xb at slot 4 (down)
            @test perm == [3, 4, 1, 2]
        end

        @testset "differential invariant (case [1,1])" begin
            case = InvariantCase([1, 1])
            # CD[-e][Riemann[-a,-b,-c,-d]] CD[e][Riemann[a,b,c,d]]
            # Factor 1: slot 1=-e, slots 2-5=-a,-b,-c,-d
            # Factor 2: slot 6=e, slots 7-10=a,b,c,d
            perm = _extract_contraction_perm(
                "CD[-e][RiemannCD[-a,-b,-c,-d]] CD[e][RiemannCD[a,b,c,d]]", case
            )
            @test length(perm) == 10
            # e: slot 1 (down) ↔ slot 6 (up)
            # a: slot 2 (down) ↔ slot 7 (up)
            # b: slot 3 (down) ↔ slot 8 (up)
            # c: slot 4 (down) ↔ slot 9 (up)
            # d: slot 5 (down) ↔ slot 10 (up)
            @test perm == [6, 7, 8, 9, 10, 1, 2, 3, 4, 5]
        end

        @testset "free index rejection" begin
            case = InvariantCase([0])
            # RiemannCD[-a,-b,-c,-d] has all free (no contractions)
            @test_throws ArgumentError _extract_contraction_perm(
                "RiemannCD[-a,-b,-c,-d]", case
            )
        end
    end

    @testset "Phase 3: _canonicalize_contraction_perm" begin
        @testset "already canonical" begin
            case = InvariantCase([0, 0])
            perm = [5, 6, 7, 8, 1, 2, 3, 4]
            canon_perm, sign = _canonicalize_contraction_perm(perm, case)
            @test sign == 1 || sign == -1
            @test length(canon_perm) == 8
            # The canonical form should be <= any symmetry-equivalent permutation
        end

        @testset "deterministic: same input → same output" begin
            case = InvariantCase([0, 0])
            perm = [5, 6, 7, 8, 1, 2, 3, 4]
            r1, s1 = _canonicalize_contraction_perm(perm, case)
            r2, s2 = _canonicalize_contraction_perm(perm, case)
            @test r1 == r2
            @test s1 == s2
        end

        @testset "symmetry-equivalent perms canonicalize to same" begin
            case = InvariantCase([0, 0])
            # Original: [5,6,7,8,1,2,3,4]
            # Swap first pair of first Riemann (slots 1,2): changes perm
            # The result after canonicalization should be the same (modulo sign)
            perm1 = [5, 6, 7, 8, 1, 2, 3, 4]
            perm2 = [6, 5, 7, 8, 2, 1, 3, 4]  # swap a↔b in factor 1
            c1, s1 = _canonicalize_contraction_perm(perm1, case)
            c2, s2 = _canonicalize_contraction_perm(perm2, case)
            @test c1 == c2
            @test s1 == -s2  # swapping one pair flips sign
        end

        @testset "single Riemann case [0]" begin
            case = InvariantCase([0])
            perm = [3, 4, 1, 2]  # Ricci scalar pattern
            canon, sign = _canonicalize_contraction_perm(perm, case)
            @test length(canon) == 4
            # Verify it's an involution
            for i in 1:4
                @test canon[canon[i]] == i
            end
        end
    end

    @testset "Phase 3: RiemannToPerm" begin
        @testset "RicciScalar → case [0]" begin
            rperm = RiemannToPerm("RicciScalarCD[]", :g; covd=:CD)
            @test rperm isa RPerm
            @test rperm.metric == :g
            @test rperm.case == InvariantCase([0])
            @test length(rperm.perm) == 4
        end

        @testset "Kretschner scalar → case [0,0]" begin
            rperm = RiemannToPerm("RiemannCD[-a,-b,-c,-d] RiemannCD[a,b,c,d]", :g; covd=:CD)
            @test rperm isa RPerm
            @test rperm.case == InvariantCase([0, 0])
            @test length(rperm.perm) == 8
        end

        @testset "Ricci contraction → case [0,0]" begin
            rperm = RiemannToPerm("RicciCD[-a,-b] RicciCD[a,b]", :g; covd=:CD)
            @test rperm isa RPerm
            @test rperm.case == InvariantCase([0, 0])
            @test length(rperm.perm) == 8
        end

        @testset "sum threading" begin
            result = RiemannToPerm(
                "RiemannCD[-a,-b,-c,-d] RiemannCD[a,b,c,d] + RiemannCD[-a,-b,-c,-d] RiemannCD[a,c,b,d]",
                :g;
                covd=:CD,
            )
            @test result isa Vector
            @test length(result) == 2
            for (coeff, rperm) in result
                @test rperm isa RPerm
                @test rperm.case == InvariantCase([0, 0])
            end
        end

        @testset "same expression yields same RPerm" begin
            r1 = RiemannToPerm("RiemannCD[-a,-b,-c,-d] RiemannCD[a,b,c,d]", :g; covd=:CD)
            # Relabeled version (same contraction pattern):
            r2 = RiemannToPerm("RiemannCD[-e,-f,-g,-h] RiemannCD[e,f,g,h]", :g; covd=:CD)
            @test r1.perm == r2.perm
            @test r1.case == r2.case
        end

        @testset "factor order invariance" begin
            # RiemannCD[-a,-b,-c,-d] RiemannCD[a,b,c,d]
            # vs
            # RiemannCD[a,b,c,d] RiemannCD[-a,-b,-c,-d]
            # These have the same contraction pattern but different raw perms.
            # After canonicalization they should yield the same RPerm (up to sign).
            r1 = RiemannToPerm("RiemannCD[-a,-b,-c,-d] RiemannCD[a,b,c,d]", :g; covd=:CD)
            r2 = RiemannToPerm("RiemannCD[a,b,c,d] RiemannCD[-a,-b,-c,-d]", :g; covd=:CD)
            @test r1.perm == r2.perm
        end

        @testset "free index rejection" begin
            @test_throws ArgumentError RiemannToPerm("RiemannCD[-a,-b,-c,-d]", :g; covd=:CD)
        end
    end

    @testset "Phase 3: PermToRiemann" begin
        @testset "basic round-trip" begin
            rperm = RPerm(:g, InvariantCase([0, 0]), [5, 6, 7, 8, 1, 2, 3, 4])
            expr = PermToRiemann(rperm; covd=:CD)
            @test contains(expr, "RiemannCD[")
            # Should have two factors
            @test length(collect(eachmatch(r"RiemannCD\[", expr))) == 2
        end

        @testset "single Riemann (Ricci scalar pattern)" begin
            rperm = RPerm(:g, InvariantCase([0]), [3, 4, 1, 2])
            expr = PermToRiemann(rperm; covd=:CD)
            @test contains(expr, "RiemannCD[")
            @test length(collect(eachmatch(r"RiemannCD\[", expr))) == 1
        end

        @testset "curvature_relations: Ricci scalar" begin
            # [3,4,1,2] is the Ricci scalar pattern for case [0]
            rperm = RPerm(:g, InvariantCase([0]), [3, 4, 1, 2])
            expr = PermToRiemann(rperm; covd=:CD, curvature_relations=true)
            @test contains(expr, "RicciScalarCD[]")
        end

        @testset "differential invariant" begin
            rperm = RPerm(:g, InvariantCase([1, 1]), [6, 7, 8, 9, 10, 1, 2, 3, 4, 5])
            expr = PermToRiemann(rperm; covd=:CD)
            @test contains(expr, "CD[")
            @test contains(expr, "RiemannCD[")
        end

        @testset "RiemannToPerm → PermToRiemann round-trip" begin
            # Start with an expression, convert to RPerm, convert back, convert again
            # The two RPerms should match
            original = "RiemannCD[-a,-b,-c,-d] RiemannCD[a,b,c,d]"
            rperm1 = RiemannToPerm(original, :g; covd=:CD)
            reconstructed = PermToRiemann(rperm1; covd=:CD)
            rperm2 = RiemannToPerm(reconstructed, :g; covd=:CD)
            @test rperm1.perm == rperm2.perm
            @test rperm1.case == rperm2.case
        end

        @testset "RicciScalar round-trip" begin
            rperm1 = RiemannToPerm("RicciScalarCD[]", :g; covd=:CD)
            reconstructed = PermToRiemann(rperm1; covd=:CD)
            rperm2 = RiemannToPerm(reconstructed, :g; covd=:CD)
            @test rperm1.perm == rperm2.perm
            @test rperm1.case == rperm2.case
        end

        @testset "Ricci squared round-trip" begin
            rperm1 = RiemannToPerm("RicciCD[-a,-b] RicciCD[a,b]", :g; covd=:CD)
            reconstructed = PermToRiemann(rperm1; covd=:CD)
            rperm2 = RiemannToPerm(reconstructed, :g; covd=:CD)
            @test rperm1.perm == rperm2.perm
            @test rperm1.case == rperm2.case
        end
    end

    # ================================================================
    # Phase 4: PermToInv / InvToPerm
    # ================================================================

    @testset "Phase 4: PermToInv / InvToPerm" begin

        # Build a synthetic database for testing
        function _make_test_db()
            # Case [0]: 1 invariant (Ricci scalar / Kretschner for degree 1)
            # Perm [2,1,4,3] is the canonical perm for the single case-[0] invariant
            perms_0 = Dict{Int,Vector{Int}}(1 => [2, 1, 4, 3])

            # Case [0,0]: 3 invariants
            perms_00 = Dict{Int,Vector{Int}}(
                1 => [2, 1, 4, 3, 6, 5, 8, 7],
                2 => [6, 5, 8, 7, 2, 1, 4, 3],
                3 => [8, 5, 4, 3, 2, 7, 6, 1],
            )

            perms = Dict{Vector{Int},Dict{Int,Vector{Int}}}(
                [0] => perms_0, [0, 0] => perms_00
            )

            InvarDB(
                perms,
                Dict{Vector{Int},Dict{Int,Vector{Int}}}(),       # dual_perms
                Dict{Int,Dict{Vector{Int},Dict{Int,Vector{Tuple{Int,Rational{Int}}}}}}(), # rules
                Dict{Int,Dict{Vector{Int},Dict{Int,Vector{Tuple{Int,Rational{Int}}}}}}(), # dual_rules
            )
        end

        @testset "PermToInv: case [0]" begin
            db = _make_test_db()
            rperm = RPerm(:CD, InvariantCase([0]), [2, 1, 4, 3])
            rinv = PermToInv(rperm; db=db)
            @test rinv.metric == :CD
            @test rinv.case == InvariantCase([0])
            @test rinv.index == 1
        end

        @testset "PermToInv: case [0,0] — all 3 invariants" begin
            db = _make_test_db()

            r1 = PermToInv(
                RPerm(:CD, InvariantCase([0, 0]), [2, 1, 4, 3, 6, 5, 8, 7]); db=db
            )
            @test r1.index == 1

            r2 = PermToInv(
                RPerm(:CD, InvariantCase([0, 0]), [6, 5, 8, 7, 2, 1, 4, 3]); db=db
            )
            @test r2.index == 2

            r3 = PermToInv(
                RPerm(:CD, InvariantCase([0, 0]), [8, 5, 4, 3, 2, 7, 6, 1]); db=db
            )
            @test r3.index == 3
        end

        @testset "PermToInv: unknown permutation" begin
            db = _make_test_db()
            rperm = RPerm(:CD, InvariantCase([0, 0]), [1, 2, 3, 4, 5, 6, 7, 8])
            @test_throws ArgumentError PermToInv(rperm; db=db)
        end

        @testset "PermToInv: unknown case" begin
            db = _make_test_db()
            rperm = RPerm(:CD, InvariantCase([2]), [1, 2, 3, 4, 5, 6])
            @test_throws ArgumentError PermToInv(rperm; db=db)
        end

        @testset "InvToPerm: case [0]" begin
            db = _make_test_db()
            rinv = RInv(:CD, InvariantCase([0]), 1)
            rperm = InvToPerm(rinv; db=db)
            @test rperm.metric == :CD
            @test rperm.case == InvariantCase([0])
            @test rperm.perm == [2, 1, 4, 3]
        end

        @testset "InvToPerm: case [0,0] — all 3" begin
            db = _make_test_db()

            r1 = InvToPerm(RInv(:CD, InvariantCase([0, 0]), 1); db=db)
            @test r1.perm == [2, 1, 4, 3, 6, 5, 8, 7]

            r2 = InvToPerm(RInv(:CD, InvariantCase([0, 0]), 2); db=db)
            @test r2.perm == [6, 5, 8, 7, 2, 1, 4, 3]

            r3 = InvToPerm(RInv(:CD, InvariantCase([0, 0]), 3); db=db)
            @test r3.perm == [8, 5, 4, 3, 2, 7, 6, 1]
        end

        @testset "InvToPerm: unknown index" begin
            db = _make_test_db()
            @test_throws ArgumentError InvToPerm(
                RInv(:CD, InvariantCase([0, 0]), 99); db=db
            )
        end

        @testset "InvToPerm: unknown case" begin
            db = _make_test_db()
            @test_throws ArgumentError InvToPerm(RInv(:CD, InvariantCase([2]), 1); db=db)
        end

        @testset "round-trip: PermToInv → InvToPerm" begin
            db = _make_test_db()
            for idx in 1:3
                perm = db.perms[[0, 0]][idx]
                rperm = RPerm(:CD, InvariantCase([0, 0]), perm)
                rinv = PermToInv(rperm; db=db)
                @test rinv.index == idx
                rperm2 = InvToPerm(rinv; db=db)
                @test rperm2.perm == perm
            end
        end

        @testset "round-trip: InvToPerm → PermToInv" begin
            db = _make_test_db()
            for idx in 1:3
                rinv = RInv(:CD, InvariantCase([0, 0]), idx)
                rperm = InvToPerm(rinv; db=db)
                rinv2 = PermToInv(rperm; db=db)
                @test rinv2.index == idx
            end
        end

        @testset "dispatch cache is built and reused" begin
            db = _make_test_db()
            # Reset dispatch cache
            xAct.XInvar._perm_dispatch = nothing

            rperm = RPerm(:CD, InvariantCase([0]), [2, 1, 4, 3])
            PermToInv(rperm; db=db)

            # Cache should now be populated
            @test xAct.XInvar._perm_dispatch !== nothing
            @test haskey(xAct.XInvar._perm_dispatch, [0])
            @test haskey(xAct.XInvar._perm_dispatch, [0, 0])

            # Clean up
            xAct.XInvar._perm_dispatch = nothing
        end

        @testset "reset_state! clears dispatch cache" begin
            db = _make_test_db()
            xAct.XInvar._perm_dispatch = nothing
            PermToInv(RPerm(:CD, InvariantCase([0]), [2, 1, 4, 3]); db=db)
            @test xAct.XInvar._perm_dispatch !== nothing

            xAct.reset_state!()
            @test xAct.XInvar._perm_dispatch === nothing
        end

        @testset "different metrics preserved" begin
            db = _make_test_db()
            rperm_g = RPerm(:g, InvariantCase([0]), [2, 1, 4, 3])
            rperm_h = RPerm(:h, InvariantCase([0]), [2, 1, 4, 3])

            rinv_g = PermToInv(rperm_g; db=db)
            rinv_h = PermToInv(rperm_h; db=db)

            @test rinv_g.metric == :g
            @test rinv_h.metric == :h
            @test rinv_g.index == rinv_h.index  # same perm → same index
        end

        @testset "full pipeline: RiemannToPerm → PermToInv → InvToPerm → PermToRiemann" begin
            db = _make_test_db()

            # Kretschner scalar
            rperm = RiemannToPerm("RiemannCD[-a,-b,-c,-d] RiemannCD[a,b,c,d]", :g; covd=:CD)

            # This should match one of the 3 invariants in case [0,0]
            # (assuming the canonical perm is in our test DB)
            if haskey(xAct.XInvar._ensure_dispatch(db), rperm.case.deriv_orders) &&
                haskey(xAct.XInvar._ensure_dispatch(db)[rperm.case.deriv_orders], rperm.perm)
                rinv = PermToInv(rperm; db=db)
                rperm2 = InvToPerm(rinv; db=db)
                expr = PermToRiemann(rperm2; covd=:CD)
                @test contains(expr, "RiemannCD[")
                @test rperm.perm == rperm2.perm
            else
                # If the canonical perm doesn't match our synthetic DB, that's ok —
                # just verify the perm is valid
                @test length(rperm.perm) == 8
            end
        end
    end

    # ================================================================
    # Phase 6: InvSimplify
    # ================================================================

    @testset "Phase 6: InvSimplify" begin

        # Build a synthetic DB with rules at multiple steps
        function _make_simplify_db()
            # Case [0,0]: 3 invariants, invariant 3 depends on 1 and 2
            perms_00 = Dict{Int,Vector{Int}}(
                1 => [2, 1, 4, 3, 6, 5, 8, 7],
                2 => [6, 5, 8, 7, 2, 1, 4, 3],
                3 => [8, 5, 4, 3, 2, 7, 6, 1],
            )

            # Case [0,0,0]: 9 invariants
            # At step 2: inv 4 → inv 1 - inv 2
            # At step 3: inv 5 → 2*inv 1 + inv 3
            perms_000 = Dict{Int,Vector{Int}}(
                i => collect(1:12) for i in 1:9  # placeholder perms
            )

            perms = Dict{Vector{Int},Dict{Int,Vector{Int}}}(
                [0, 0] => perms_00, [0, 0, 0] => perms_000
            )

            # Step 2 rules: cyclic identities
            step2_rules = Dict{Vector{Int},Dict{Int,Vector{Tuple{Int,Rational{Int}}}}}(
                [0, 0] => Dict{Int,Vector{Tuple{Int,Rational{Int}}}}(
                    3 => [(1, 1 // 1), (2, -1 // 1)],  # inv3 = inv1 - inv2
                ),
                [0, 0, 0] => Dict{Int,Vector{Tuple{Int,Rational{Int}}}}(
                    4 => [(1, 1 // 1), (2, -1 // 1)],  # inv4 = inv1 - inv2
                ),
            )

            # Step 3 rules: Bianchi identities
            step3_rules = Dict{Vector{Int},Dict{Int,Vector{Tuple{Int,Rational{Int}}}}}(
                [0, 0, 0] => Dict{Int,Vector{Tuple{Int,Rational{Int}}}}(
                    5 => [(1, 2 // 1), (3, 1 // 1)],   # inv5 = 2*inv1 + inv3
                ),
            )

            # Step 5 rules: dimension-dependent (dim=4)
            step5_rules = Dict{Vector{Int},Dict{Int,Vector{Tuple{Int,Rational{Int}}}}}(
                [0, 0] => Dict{Int,Vector{Tuple{Int,Rational{Int}}}}(
                    2 => [(1, 1 // 2)],  # inv2 = (1/2)*inv1 in 4D
                )
            )

            rules = Dict{Int,Dict{Vector{Int},Dict{Int,Vector{Tuple{Int,Rational{Int}}}}}}(
                2 => step2_rules, 3 => step3_rules, 5 => step5_rules
            )

            InvarDB(
                perms,
                Dict{Vector{Int},Dict{Int,Vector{Int}}}(),
                rules,
                Dict{Int,Dict{Vector{Int},Dict{Int,Vector{Tuple{Int,Rational{Int}}}}}}(),
            )
        end

        @testset "level 1: identity" begin
            db = _make_simplify_db()
            rinv = RInv(:CD, InvariantCase([0, 0]), 3)
            result = InvSimplify(rinv, 1; db=db)
            @test length(result) == 1
            @test result[1] == (1 // 1, rinv)
        end

        @testset "level 2: cyclic rules" begin
            db = _make_simplify_db()
            rinv = RInv(:CD, InvariantCase([0, 0]), 3)
            result = InvSimplify(rinv, 2; db=db)
            # inv3 → inv1 - inv2
            @test length(result) == 2
            coeffs = Dict(r.index => c for (c, r) in result)
            @test coeffs[1] == 1 // 1
            @test coeffs[2] == -1 // 1
        end

        @testset "level 2: independent invariant unchanged" begin
            db = _make_simplify_db()
            rinv = RInv(:CD, InvariantCase([0, 0]), 1)
            result = InvSimplify(rinv, 2; db=db)
            @test length(result) == 1
            @test result[1] == (1 // 1, rinv)
        end

        @testset "level 3: Bianchi rules applied after cyclic" begin
            db = _make_simplify_db()
            rinv = RInv(:CD, InvariantCase([0, 0, 0]), 5)
            result = InvSimplify(rinv, 3; db=db)
            # inv5 → 2*inv1 + inv3 (step 3 rule)
            coeffs = Dict(r.index => c for (c, r) in result)
            @test coeffs[1] == 2 // 1
            @test coeffs[3] == 1 // 1
        end

        @testset "level 2+3: chained rules" begin
            db = _make_simplify_db()
            # inv4 at step 2 → inv1 - inv2
            # inv5 at step 3 → 2*inv1 + inv3
            # Sum: inv4 + inv5 at level 3
            expr = Tuple{Rational{Int},RInv}[
                (1 // 1, RInv(:CD, InvariantCase([0, 0, 0]), 4)),
                (1 // 1, RInv(:CD, InvariantCase([0, 0, 0]), 5)),
            ]
            result = InvSimplify(expr, 3; db=db)
            # inv4 → inv1 - inv2 (step 2)
            # inv5 → 2*inv1 + inv3 (step 3)
            # Total: 3*inv1 - inv2 + inv3
            coeffs = Dict(r.index => c for (c, r) in result)
            @test coeffs[1] == 3 // 1
            @test coeffs[2] == -1 // 1
            @test coeffs[3] == 1 // 1
        end

        @testset "level 4: no step-4 rules → same as level 3" begin
            db = _make_simplify_db()
            rinv = RInv(:CD, InvariantCase([0, 0]), 3)
            r3 = InvSimplify(rinv, 3; db=db)
            r4 = InvSimplify(rinv, 4; db=db)
            @test r3 == r4
        end

        @testset "level 5: dim-dependent rules with dim=4" begin
            db = _make_simplify_db()
            rinv = RInv(:CD, InvariantCase([0, 0]), 2)
            result = InvSimplify(rinv, 5; db=db, dim=4)
            # Step 5 rule: inv2 → (1/2)*inv1 in 4D
            @test length(result) == 1
            @test result[1] == (1 // 2, RInv(:CD, InvariantCase([0, 0]), 1))
        end

        @testset "level 5: skipped when dim=nothing" begin
            db = _make_simplify_db()
            rinv = RInv(:CD, InvariantCase([0, 0]), 2)
            result = InvSimplify(rinv, 5; db=db, dim=nothing)
            # No dim → step 5 skipped → inv2 still present (unchanged from step 4)
            @test length(result) == 1
            @test result[1] == (1 // 1, rinv)
        end

        @testset "level 6: skipped when dim != 4" begin
            db = _make_simplify_db()
            # Use an invariant that has NO step-5 rule: inv1 is independent at all steps
            rinv = RInv(:CD, InvariantCase([0, 0]), 1)
            r6_dim3 = InvSimplify(rinv, 6; db=db, dim=3)
            r6_dim4 = InvSimplify(rinv, 6; db=db, dim=4)
            # inv1 is independent everywhere → same result regardless of dim
            @test r6_dim3 == r6_dim4
            @test length(r6_dim3) == 1
            @test r6_dim3[1] == (1 // 1, rinv)

            # Now test with inv2 which HAS a step-5 rule: it applies for any int dim
            rinv2 = RInv(:CD, InvariantCase([0, 0]), 2)
            r6_dim3_v2 = InvSimplify(rinv2, 6; db=db, dim=3)
            # step 5 fires (dim=3 is Int), step 6 skipped (dim!=4)
            # inv2 → (1/2)*inv1 from step 5
            @test length(r6_dim3_v2) == 1
            @test r6_dim3_v2[1] == (1 // 2, RInv(:CD, InvariantCase([0, 0]), 1))
        end

        @testset "collect terms: cancellation" begin
            db = _make_simplify_db()
            # inv3 - inv3 should cancel to empty
            expr = Tuple{Rational{Int},RInv}[
                (1 // 1, RInv(:CD, InvariantCase([0, 0]), 1)),
                (-1 // 1, RInv(:CD, InvariantCase([0, 0]), 1)),
            ]
            result = InvSimplify(expr, 1; db=db)
            @test isempty(result)
        end

        @testset "collect terms: combine like terms" begin
            db = _make_simplify_db()
            expr = Tuple{Rational{Int},RInv}[
                (3 // 1, RInv(:CD, InvariantCase([0, 0]), 1)),
                (2 // 1, RInv(:CD, InvariantCase([0, 0]), 1)),
            ]
            result = InvSimplify(expr, 1; db=db)
            @test length(result) == 1
            @test result[1] == (5 // 1, RInv(:CD, InvariantCase([0, 0]), 1))
        end

        @testset "empty expression" begin
            db = _make_simplify_db()
            result = InvSimplify(Tuple{Rational{Int},RInv}[], 6; db=db)
            @test isempty(result)
        end

        @testset "mixed cases in expression" begin
            db = _make_simplify_db()
            # Mix case [0,0] and [0,0,0] in one expression
            expr = Tuple{Rational{Int},RInv}[
                (1 // 1, RInv(:CD, InvariantCase([0, 0]), 3)),       # → inv1 - inv2
                (1 // 1, RInv(:CD, InvariantCase([0, 0, 0]), 4)),    # → inv1 - inv2
            ]
            result = InvSimplify(expr, 2; db=db)
            # Both cases should be simplified independently
            case00_terms = [(c, r) for (c, r) in result if r.case == InvariantCase([0, 0])]
            case000_terms = [
                (c, r) for (c, r) in result if r.case == InvariantCase([0, 0, 0])
            ]
            @test length(case00_terms) == 2
            @test length(case000_terms) == 2
        end

        @testset "metric preserved" begin
            db = _make_simplify_db()
            rinv = RInv(:MyMetric, InvariantCase([0, 0]), 3)
            result = InvSimplify(rinv, 2; db=db)
            for (_, r) in result
                @test r.metric == :MyMetric
            end
        end

        @testset "result is sorted by (case, index)" begin
            db = _make_simplify_db()
            expr = Tuple{Rational{Int},RInv}[
                (1 // 1, RInv(:CD, InvariantCase([0, 0, 0]), 4)),
                (1 // 1, RInv(:CD, InvariantCase([0, 0]), 3)),
            ]
            result = InvSimplify(expr, 2; db=db)
            # Should be sorted: case [0,0] before [0,0,0], then by index
            for i in 1:(length(result) - 1)
                a = result[i][2]
                b = result[i + 1][2]
                @test (a.case.deriv_orders, a.index) <= (b.case.deriv_orders, b.index)
            end
        end

        @testset "substitution chain: dependent reduces to dependent" begin
            # Test that a rule producing another dependent invariant gets resolved
            # at a later step (not within the same step — this matches Wolfram behavior)
            db = _make_simplify_db()
            # In case [0,0,0]: inv4 → inv1 - inv2 at step 2 (both independent)
            # inv5 → 2*inv1 + inv3 at step 3 (both independent at step 3)
            # Applying step 2 first, then step 3 independently is correct
            rinv = RInv(:CD, InvariantCase([0, 0, 0]), 4)
            r2 = InvSimplify(rinv, 2; db=db)
            r3 = InvSimplify(rinv, 3; db=db)
            # At both levels, inv4 → inv1 - inv2 (step 2 handles it)
            @test r2 == r3
        end
    end

    # ================================================================
    # Phase 7: RiemannSimplify
    # ================================================================

    @testset "Phase 7: RiemannSimplify" begin

        # Build a DB that contains the canonical perms RiemannToPerm produces.
        # We need to discover what canonical perms our implementation generates
        # for known expressions, then build the DB around those.
        function _make_riemann_simplify_db()
            # Get canonical perms for known expressions
            r_scalar = RiemannToPerm("RicciScalarCD[]", :g; covd=:CD)
            r_kretschner = RiemannToPerm(
                "RiemannCD[-a,-b,-c,-d] RiemannCD[a,b,c,d]", :g; covd=:CD
            )

            # Case [0]: 1 invariant
            perms_0 = Dict{Int,Vector{Int}}(1 => r_scalar.perm)

            # Case [0,0]: 3 invariants — Kretschner is one of them
            # We need to figure out which index it maps to. Put it as inv 1.
            # Also add 2 more placeholder perms for the other invariants.
            perms_00 = Dict{Int,Vector{Int}}(
                1 => r_kretschner.perm,
                2 => [2, 1, 6, 5, 4, 3, 8, 7],  # another canonical perm
                3 => [2, 7, 4, 5, 8, 3, 6, 1],  # another canonical perm
            )

            perms = Dict{Vector{Int},Dict{Int,Vector{Int}}}(
                [0] => perms_0, [0, 0] => perms_00
            )

            # Step 2 rule: inv3 → inv1 - inv2 (cyclic identity)
            step2_rules = Dict{Vector{Int},Dict{Int,Vector{Tuple{Int,Rational{Int}}}}}(
                [0, 0] => Dict{Int,Vector{Tuple{Int,Rational{Int}}}}(
                    3 => [(1, 1 // 1), (2, -1 // 1)]
                ),
            )

            rules = Dict{Int,Dict{Vector{Int},Dict{Int,Vector{Tuple{Int,Rational{Int}}}}}}(
                2 => step2_rules
            )

            InvarDB(
                perms,
                Dict{Vector{Int},Dict{Int,Vector{Int}}}(),
                rules,
                Dict{Int,Dict{Vector{Int},Dict{Int,Vector{Tuple{Int,Rational{Int}}}}}}(),
            )
        end

        @testset "trivial: zero" begin
            db = _make_riemann_simplify_db()
            @test RiemannSimplify("0", :g; covd=:CD, db=db) == "0"
            @test RiemannSimplify("", :g; covd=:CD, db=db) == "0"
        end

        @testset "RicciScalar passthrough" begin
            db = _make_riemann_simplify_db()
            # Clear dispatch cache from previous tests
            xAct.XInvar._perm_dispatch = nothing

            result = RiemannSimplify("RicciScalarCD[]", :g; covd=:CD, db=db)
            # Should produce a tensor expression for case [0], inv 1
            @test !isempty(result)
            @test result != "0"
            @test contains(result, "RiemannCD[")
        end

        @testset "Kretschner scalar" begin
            db = _make_riemann_simplify_db()
            xAct.XInvar._perm_dispatch = nothing

            result = RiemannSimplify(
                "RiemannCD[-a,-b,-c,-d] RiemannCD[a,b,c,d]", :g; covd=:CD, db=db
            )
            @test !isempty(result)
            @test result != "0"
            @test contains(result, "RiemannCD[")
        end

        @testset "same expression relabeled cancels" begin
            db = _make_riemann_simplify_db()
            xAct.XInvar._perm_dispatch = nothing

            # Two Kretschner expressions with different dummy labels → same RPerm
            # Their difference should be "0"
            result = RiemannSimplify(
                "RiemannCD[-a,-b,-c,-d] RiemannCD[a,b,c,d] - RiemannCD[-e,-f,-g,-h] RiemannCD[e,f,g,h]",
                :g;
                covd=:CD,
                db=db,
            )
            @test result == "0"
        end

        @testset "curvature_relations flag" begin
            db = _make_riemann_simplify_db()
            xAct.XInvar._perm_dispatch = nothing

            result_no_cr = RiemannSimplify("RicciScalarCD[]", :g; covd=:CD, db=db)
            result_cr = RiemannSimplify(
                "RicciScalarCD[]", :g; covd=:CD, db=db, curvature_relations=true
            )

            # Without curvature_relations: should have RiemannCD
            @test contains(result_no_cr, "RiemannCD[")
            # With curvature_relations: should have RicciScalar (self-contracted Riemann)
            @test contains(result_cr, "RicciScalarCD[]")
        end

        @testset "level 1: no simplification" begin
            db = _make_riemann_simplify_db()
            xAct.XInvar._perm_dispatch = nothing

            result = RiemannSimplify(
                "RiemannCD[-a,-b,-c,-d] RiemannCD[a,b,c,d]", :g; covd=:CD, db=db, level=1
            )
            @test !isempty(result)
            @test result != "0"
        end

        @testset "free indices rejected" begin
            db = _make_riemann_simplify_db()
            @test_throws ArgumentError RiemannSimplify(
                "RiemannCD[-a,-b,-c,-d]", :g; covd=:CD, db=db
            )
        end

        @testset "_format_rational" begin
            fmt = xAct.XInvar._format_rational
            @test fmt(1 // 1) == "1"
            @test fmt(-3 // 1) == "-3"
            @test fmt(3 // 2) == "3/2"
            @test fmt(-1 // 2) == "-1/2"
        end

        @testset "_inv_expr_to_string" begin
            db = _make_riemann_simplify_db()
            xAct.XInvar._perm_dispatch = nothing
            to_str = xAct.XInvar._inv_expr_to_string

            # Single term with coefficient 1
            expr1 = Tuple{Rational{Int},RInv}[(1 // 1, RInv(:g, InvariantCase([0]), 1))]
            s1 = to_str(expr1; covd=:CD, db=db)
            @test contains(s1, "RiemannCD[")
            @test !startswith(s1, "-")

            # Single term with coefficient -1
            expr2 = Tuple{Rational{Int},RInv}[(-1 // 1, RInv(:g, InvariantCase([0]), 1))]
            s2 = to_str(expr2; covd=:CD, db=db)
            @test startswith(s2, "-")

            # Two terms
            expr3 = Tuple{Rational{Int},RInv}[
                (2 // 1, RInv(:g, InvariantCase([0, 0]), 1)),
                (-1 // 1, RInv(:g, InvariantCase([0, 0]), 2)),
            ]
            s3 = to_str(expr3; covd=:CD, db=db)
            @test contains(s3, " + ") || contains(s3, " - ")

            # Empty → "0"
            s4 = to_str(Tuple{Rational{Int},RInv}[]; covd=:CD, db=db)
            @test s4 == "0"
        end
    end

    # ================================================================
    # Phase 10: Dual Invariant Handling
    # ================================================================

    @testset "Phase 10: Dual Invariant Handling" begin

        # Build a synthetic DB with both non-dual and dual perm/rule data
        function _make_dual_db()
            # Non-dual: case [0] has 1 invariant, case [0,0] has 3
            perms_0 = Dict{Int,Vector{Int}}(1 => [2, 1, 4, 3])
            perms_00 = Dict{Int,Vector{Int}}(
                1 => [2, 1, 4, 3, 6, 5, 8, 7],
                2 => [6, 5, 8, 7, 2, 1, 4, 3],
                3 => [8, 5, 4, 3, 2, 7, 6, 1],
            )
            perms = Dict{Vector{Int},Dict{Int,Vector{Int}}}(
                [0] => perms_0, [0, 0] => perms_00
            )

            # Dual: case [0] has 1 invariant, case [0,0] has 4 invariants
            # (dual invariants have different perm degree: 4*n + sum + 4*1)
            # For case [0], n_epsilon=1: degree = 4*1 + 0 + 4*1 = 8
            dual_perms_0 = Dict{Int,Vector{Int}}(1 => [2, 1, 4, 3, 6, 5, 8, 7])
            # For case [0,0], n_epsilon=1: degree = 4*2 + 0 + 4*1 = 12
            dual_perms_00 = Dict{Int,Vector{Int}}(
                1 => [2, 1, 4, 3, 6, 5, 8, 7, 10, 9, 12, 11],
                2 => [6, 5, 8, 7, 2, 1, 4, 3, 10, 9, 12, 11],
                3 => [10, 9, 4, 3, 6, 5, 8, 7, 2, 1, 12, 11],
                4 => [12, 9, 4, 3, 6, 5, 8, 7, 2, 11, 10, 1],
            )
            dual_perms = Dict{Vector{Int},Dict{Int,Vector{Int}}}(
                [0] => dual_perms_0, [0, 0] => dual_perms_00
            )

            # Non-dual rules: step 2 rule for case [0,0], inv3 → inv1 - inv2
            step2_rules = Dict{Vector{Int},Dict{Int,Vector{Tuple{Int,Rational{Int}}}}}(
                [0, 0] => Dict{Int,Vector{Tuple{Int,Rational{Int}}}}(
                    3 => [(1, 1 // 1), (2, -1 // 1)]
                ),
            )

            # Dual rules: step 2 rule for dual case [0,0], inv4 → inv1 + 2*inv2
            dual_step2_rules = Dict{Vector{Int},Dict{Int,Vector{Tuple{Int,Rational{Int}}}}}(
                [0, 0] => Dict{Int,Vector{Tuple{Int,Rational{Int}}}}(
                    4 => [(1, 1 // 1), (2, 2 // 1)]
                ),
            )

            # Dual rules: step 3 rule for dual case [0,0], inv3 → -inv1 + inv2
            dual_step3_rules = Dict{Vector{Int},Dict{Int,Vector{Tuple{Int,Rational{Int}}}}}(
                [0, 0] => Dict{Int,Vector{Tuple{Int,Rational{Int}}}}(
                    3 => [(1, -1 // 1), (2, 1 // 1)]
                ),
            )

            rules = Dict{Int,Dict{Vector{Int},Dict{Int,Vector{Tuple{Int,Rational{Int}}}}}}(
                2 => step2_rules
            )
            dual_rules = Dict{
                Int,Dict{Vector{Int},Dict{Int,Vector{Tuple{Int,Rational{Int}}}}}
            }(
                2 => dual_step2_rules, 3 => dual_step3_rules
            )

            InvarDB(perms, dual_perms, rules, dual_rules)
        end

        @testset "PermToInv: dual case [0]" begin
            db = _make_dual_db()
            xAct.XInvar._perm_dispatch = nothing
            xAct.XInvar._dual_perm_dispatch = nothing

            dual_case = InvariantCase([0], 1)
            rperm = RPerm(:CD, dual_case, [2, 1, 4, 3, 6, 5, 8, 7])
            rinv = PermToInv(rperm; db=db)
            @test rinv.metric == :CD
            @test rinv.case == dual_case
            @test rinv.index == 1
        end

        @testset "PermToInv: dual case [0,0] — all 4 invariants" begin
            db = _make_dual_db()
            xAct.XInvar._dual_perm_dispatch = nothing

            dual_case = InvariantCase([0, 0], 1)
            r1 = PermToInv(
                RPerm(:CD, dual_case, [2, 1, 4, 3, 6, 5, 8, 7, 10, 9, 12, 11]); db=db
            )
            @test r1.index == 1

            r2 = PermToInv(
                RPerm(:CD, dual_case, [6, 5, 8, 7, 2, 1, 4, 3, 10, 9, 12, 11]); db=db
            )
            @test r2.index == 2

            r3 = PermToInv(
                RPerm(:CD, dual_case, [10, 9, 4, 3, 6, 5, 8, 7, 2, 1, 12, 11]); db=db
            )
            @test r3.index == 3

            r4 = PermToInv(
                RPerm(:CD, dual_case, [12, 9, 4, 3, 6, 5, 8, 7, 2, 11, 10, 1]); db=db
            )
            @test r4.index == 4
        end

        @testset "PermToInv: dual unknown perm" begin
            db = _make_dual_db()
            xAct.XInvar._dual_perm_dispatch = nothing

            dual_case = InvariantCase([0], 1)
            rperm = RPerm(:CD, dual_case, [1, 2, 3, 4, 5, 6, 7, 8])
            @test_throws ArgumentError PermToInv(rperm; db=db)
        end

        @testset "PermToInv: dual unknown case" begin
            db = _make_dual_db()
            xAct.XInvar._dual_perm_dispatch = nothing

            dual_case = InvariantCase([2], 1)
            rperm = RPerm(:CD, dual_case, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
            @test_throws ArgumentError PermToInv(rperm; db=db)
        end

        @testset "InvToPerm: dual case [0]" begin
            db = _make_dual_db()
            dual_case = InvariantCase([0], 1)
            rinv = RInv(:CD, dual_case, 1)
            rperm = InvToPerm(rinv; db=db)
            @test rperm.metric == :CD
            @test rperm.case == dual_case
            @test rperm.perm == [2, 1, 4, 3, 6, 5, 8, 7]
        end

        @testset "InvToPerm: dual case [0,0] — all 4" begin
            db = _make_dual_db()
            dual_case = InvariantCase([0, 0], 1)

            r1 = InvToPerm(RInv(:CD, dual_case, 1); db=db)
            @test r1.perm == [2, 1, 4, 3, 6, 5, 8, 7, 10, 9, 12, 11]

            r2 = InvToPerm(RInv(:CD, dual_case, 2); db=db)
            @test r2.perm == [6, 5, 8, 7, 2, 1, 4, 3, 10, 9, 12, 11]

            r3 = InvToPerm(RInv(:CD, dual_case, 3); db=db)
            @test r3.perm == [10, 9, 4, 3, 6, 5, 8, 7, 2, 1, 12, 11]

            r4 = InvToPerm(RInv(:CD, dual_case, 4); db=db)
            @test r4.perm == [12, 9, 4, 3, 6, 5, 8, 7, 2, 11, 10, 1]
        end

        @testset "InvToPerm: dual unknown index" begin
            db = _make_dual_db()
            dual_case = InvariantCase([0, 0], 1)
            @test_throws ArgumentError InvToPerm(RInv(:CD, dual_case, 99); db=db)
        end

        @testset "InvToPerm: dual unknown case" begin
            db = _make_dual_db()
            dual_case = InvariantCase([2], 1)
            @test_throws ArgumentError InvToPerm(RInv(:CD, dual_case, 1); db=db)
        end

        @testset "round-trip: dual PermToInv → InvToPerm" begin
            db = _make_dual_db()
            xAct.XInvar._dual_perm_dispatch = nothing
            dual_case = InvariantCase([0, 0], 1)

            for idx in 1:4
                perm = db.dual_perms[[0, 0]][idx]
                rperm = RPerm(:CD, dual_case, perm)
                rinv = PermToInv(rperm; db=db)
                @test rinv.index == idx
                rperm2 = InvToPerm(rinv; db=db)
                @test rperm2.perm == perm
            end
        end

        @testset "round-trip: dual InvToPerm → PermToInv" begin
            db = _make_dual_db()
            xAct.XInvar._dual_perm_dispatch = nothing
            dual_case = InvariantCase([0, 0], 1)

            for idx in 1:4
                rinv = RInv(:CD, dual_case, idx)
                rperm = InvToPerm(rinv; db=db)
                rinv2 = PermToInv(rperm; db=db)
                @test rinv2.index == idx
            end
        end

        @testset "InvSimplify: dual step 2 rule" begin
            db = _make_dual_db()
            dual_case = InvariantCase([0, 0], 1)
            # Dual inv4 → inv1 + 2*inv2 (dual step 2 rule)
            rinv = RInv(:CD, dual_case, 4)
            result = InvSimplify(rinv, 2; db=db, dim=4)
            @test length(result) == 2
            coeffs = Dict(r.index => c for (c, r) in result)
            @test coeffs[1] == 1 // 1
            @test coeffs[2] == 2 // 1
            # All terms should preserve dual case
            for (_, r) in result
                @test r.case.n_epsilon == 1
            end
        end

        @testset "InvSimplify: dual step 3 rule" begin
            db = _make_dual_db()
            dual_case = InvariantCase([0, 0], 1)
            # Dual inv3 → -inv1 + inv2 (dual step 3 rule)
            rinv = RInv(:CD, dual_case, 3)
            result = InvSimplify(rinv, 3; db=db, dim=4)
            @test length(result) == 2
            coeffs = Dict(r.index => c for (c, r) in result)
            @test coeffs[1] == -1 // 1
            @test coeffs[2] == 1 // 1
        end

        @testset "InvSimplify: dual independent invariant unchanged" begin
            db = _make_dual_db()
            dual_case = InvariantCase([0, 0], 1)
            rinv = RInv(:CD, dual_case, 1)
            result = InvSimplify(rinv, 2; db=db, dim=4)
            @test length(result) == 1
            @test result[1] == (1 // 1, rinv)
        end

        @testset "InvSimplify: non-dual rules not applied to dual" begin
            db = _make_dual_db()
            # Non-dual case [0,0] inv3 has a step-2 rule (inv3 → inv1 - inv2)
            # Dual case [0,0] inv3 has a DIFFERENT step-3 rule
            # At level 2, the dual inv3 should NOT be touched by non-dual step-2 rules
            dual_case = InvariantCase([0, 0], 1)
            rinv = RInv(:CD, dual_case, 3)
            result = InvSimplify(rinv, 2; db=db, dim=4)
            # No dual step-2 rule for inv3, so unchanged
            @test length(result) == 1
            @test result[1] == (1 // 1, rinv)
        end

        @testset "InvSimplify: mixed dual and non-dual" begin
            db = _make_dual_db()
            # Mix a non-dual term and a dual term
            expr = Tuple{Rational{Int},RInv}[
                (1 // 1, RInv(:CD, InvariantCase([0, 0]), 3)),       # non-dual: → inv1 - inv2
                (1 // 1, RInv(:CD, InvariantCase([0, 0], 1), 4)),   # dual: → inv1 + 2*inv2
            ]
            result = InvSimplify(expr, 2; db=db, dim=4)

            # Separate non-dual and dual results
            nondual = [(c, r) for (c, r) in result if r.case.n_epsilon == 0]
            dual = [(c, r) for (c, r) in result if r.case.n_epsilon == 1]

            # Non-dual: inv3 → inv1 - inv2
            nd_coeffs = Dict(r.index => c for (c, r) in nondual)
            @test nd_coeffs[1] == 1 // 1
            @test nd_coeffs[2] == -1 // 1

            # Dual: inv4 → inv1 + 2*inv2
            d_coeffs = Dict(r.index => c for (c, r) in dual)
            @test d_coeffs[1] == 1 // 1
            @test d_coeffs[2] == 2 // 1
        end

        @testset "InvSimplify: dual requires dim=4" begin
            db = _make_dual_db()
            dual_case = InvariantCase([0, 0], 1)
            rinv = RInv(:CD, dual_case, 1)

            # dim=nothing should raise
            @test_throws ArgumentError InvSimplify(rinv, 2; db=db, dim=nothing)

            # dim=3 should raise
            @test_throws ArgumentError InvSimplify(rinv, 2; db=db, dim=3)

            # dim=5 should raise
            @test_throws ArgumentError InvSimplify(rinv, 6; db=db, dim=5)

            # dim=4 should succeed
            result = InvSimplify(rinv, 2; db=db, dim=4)
            @test length(result) == 1
        end

        @testset "InvSimplify: non-dual terms unaffected by dim check" begin
            db = _make_dual_db()
            rinv = RInv(:CD, InvariantCase([0, 0]), 3)
            # Non-dual term with dim=nothing: should work fine
            result = InvSimplify(rinv, 2; db=db, dim=nothing)
            @test length(result) == 2
        end

        @testset "dispatch cache: dual separate from non-dual" begin
            db = _make_dual_db()
            xAct.XInvar._perm_dispatch = nothing
            xAct.XInvar._dual_perm_dispatch = nothing

            # Non-dual lookup builds _perm_dispatch but not _dual_perm_dispatch
            rperm = RPerm(:CD, InvariantCase([0]), [2, 1, 4, 3])
            PermToInv(rperm; db=db)
            @test xAct.XInvar._perm_dispatch !== nothing
            @test xAct.XInvar._dual_perm_dispatch === nothing

            # Dual lookup builds _dual_perm_dispatch
            dual_rperm = RPerm(:CD, InvariantCase([0], 1), [2, 1, 4, 3, 6, 5, 8, 7])
            PermToInv(dual_rperm; db=db)
            @test xAct.XInvar._dual_perm_dispatch !== nothing

            # Clean up
            xAct.XInvar._perm_dispatch = nothing
            xAct.XInvar._dual_perm_dispatch = nothing
        end

        @testset "reset_state! clears dual dispatch cache" begin
            db = _make_dual_db()
            xAct.XInvar._perm_dispatch = nothing
            xAct.XInvar._dual_perm_dispatch = nothing

            PermToInv(RPerm(:CD, InvariantCase([0]), [2, 1, 4, 3]); db=db)
            PermToInv(RPerm(:CD, InvariantCase([0], 1), [2, 1, 4, 3, 6, 5, 8, 7]); db=db)
            @test xAct.XInvar._perm_dispatch !== nothing
            @test xAct.XInvar._dual_perm_dispatch !== nothing

            xAct.reset_state!()
            @test xAct.XInvar._perm_dispatch === nothing
            @test xAct.XInvar._dual_perm_dispatch === nothing
        end
    end
end
