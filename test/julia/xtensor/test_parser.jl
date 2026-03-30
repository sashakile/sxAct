@testset "Parser / Serializer" begin
    PE = XTensor._parse_expression
    ST = XTensor._serialize_terms

    # --- _parse_expression basics ---
    @testset "parse zero / empty" begin
        @test PE("0") == []
        @test PE("") == []
    end

    @testset "parse single tensor" begin
        terms = PE("T[-a,-b]")
        @test length(terms) == 1
        @test terms[1].coeff == 1 // 1
        @test length(terms[1].factors) == 1
        @test terms[1].factors[1].tensor_name == :T
        @test terms[1].factors[1].indices == ["-a", "-b"]
    end

    @testset "parse scalar (empty indices)" begin
        terms = PE("phi[]")
        @test length(terms) == 1
        @test terms[1].factors[1].indices == String[]
    end

    @testset "parse integer coefficient" begin
        terms = PE("3 T[-a]")
        @test terms[1].coeff == 3 // 1
        @test terms[1].factors[1].tensor_name == :T
    end

    @testset "parse negative coefficient" begin
        terms = PE("-2 T[-a]")
        @test terms[1].coeff == -2 // 1
    end

    @testset "parse rational coefficient" begin
        terms = PE("(1/2) T[-a,-b]")
        @test terms[1].coeff == 1 // 2
    end

    @testset "parse negative rational" begin
        terms = PE("(-3/7) R[-a,-b,-c,-d]")
        @test terms[1].coeff == -3 // 7
    end

    @testset "parse product of two tensors" begin
        terms = PE("R[-a,-b,-c,-d] g[ia,ib]")
        @test length(terms) == 1
        @test length(terms[1].factors) == 2
        @test terms[1].factors[1].tensor_name == :R
        @test terms[1].factors[2].tensor_name == :g
    end

    @testset "parse sum" begin
        terms = PE("T[-a] + S[-b]")
        @test length(terms) == 2
        @test terms[1].coeff == 1 // 1
        @test terms[2].coeff == 1 // 1
    end

    @testset "parse difference" begin
        terms = PE("T[-a] - S[-b]")
        @test length(terms) == 2
        @test terms[1].coeff == 1 // 1
        @test terms[2].coeff == -1 // 1
    end

    @testset "parse three terms with mixed signs" begin
        terms = PE("2 A[-a] - 3 B[-a] + (1/4) C[-a]")
        @test length(terms) == 3
        @test terms[1].coeff == 2 // 1
        @test terms[2].coeff == -3 // 1
        @test terms[3].coeff == 1 // 4
    end

    @testset "parse parenthesized sub-expression" begin
        terms = PE("2*(R[] + S[])")
        @test length(terms) == 2
        @test terms[1].coeff == 2 // 1
        @test terms[2].coeff == 2 // 1
    end

    # --- _serialize_terms basics ---
    @testset "serialize empty → 0" begin
        @test ST(XTensor.TermAST[]) == "0"
    end

    @testset "serialize single tensor" begin
        terms = PE("T[-a,-b]")
        @test ST(terms) == "T[-a,-b]"
    end

    @testset "serialize with coefficient" begin
        terms = PE("3 T[-a]")
        @test ST(terms) == "3 T[-a]"
    end

    @testset "serialize rational coefficient" begin
        terms = PE("(1/2) R[-a,-b,-c,-d]")
        @test ST(terms) == "(1/2) R[-a,-b,-c,-d]"
    end

    @testset "serialize negative term" begin
        terms = PE("-T[-a]")
        @test ST(terms) == "-T[-a]"
    end

    @testset "serialize sum" begin
        terms = PE("T[-a] + S[-b]")
        @test ST(terms) == "T[-a] + S[-b]"
    end

    @testset "serialize difference" begin
        terms = PE("T[-a] - S[-b]")
        @test ST(terms) == "T[-a] - S[-b]"
    end

    # --- Round-trip fidelity ---
    @testset "round-trip" begin
        for expr in [
            "T[-a,-b]",
            "3 T[-a]",
            "(1/2) R[-a,-b,-c,-d]",
            "-T[-a] + 2 S[-b]",
            "R[-a,-b,-c,-d] g[ia,ib]",
        ]
            @test ST(PE(expr)) == expr
        end
    end
end
