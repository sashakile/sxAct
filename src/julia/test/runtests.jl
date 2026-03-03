using Test
include("../XCore.jl")
using .XCore

# Helper: reset shared state between tests that modify the registry.
function reset_registry!()
    empty!(XCore._symbol_registry)
    empty!(xCoreNames)
    empty!(xPermNames)
    empty!(xTensorNames)
    empty!(xTableauNames)
    empty!(xCobaNames)
    empty!(InvarNames)
    empty!(HarmonicsNames)
    empty!(xPertNames)
    empty!(SpinorsNames)
    empty!(EMNames)
end

# ============================================================
# register_symbol
# ============================================================

@testset "register_symbol — basic registration" begin
    reset_registry!()
    register_symbol(:MyTensor, "XTensor")
    @test "MyTensor" in xTensorNames
    @test XCore._symbol_registry["MyTensor"] == "XTensor"
end

@testset "register_symbol — idempotent re-registration" begin
    reset_registry!()
    register_symbol("Foo", "XPerm")
    @test_nowarn register_symbol(:Foo, "XPerm")   # same package → no-op
    @test count(==("Foo"), xPermNames) == 1        # not duplicated
end

@testset "register_symbol — collision with different package" begin
    reset_registry!()
    register_symbol(:Bar, "XCore")
    @test_throws ErrorException register_symbol(:Bar, "XTensor")
end

@testset "register_symbol — unknown package skips per-package list" begin
    reset_registry!()
    register_symbol(:Baz, "ThirdParty")
    @test XCore._symbol_registry["Baz"] == "ThirdParty"
    # No per-package list to check, but no error either
end

@testset "register_symbol — all known package lists populated" begin
    reset_registry!()
    pairs = [
        (:S1, "XCore",    xCoreNames),
        (:S2, "XPerm",    xPermNames),
        (:S3, "XTensor",  xTensorNames),
        (:S4, "XTableau", xTableauNames),
        (:S5, "XCoba",    xCobaNames),
        (:S6, "Invar",    InvarNames),
        (:S7, "Harmonics",HarmonicsNames),
        (:S8, "XPert",    xPertNames),
        (:S9, "Spinors",  SpinorsNames),
        (:S10,"EM",       EMNames),
    ]
    for (sym, pkg, lst) in pairs
        register_symbol(sym, pkg)
        @test string(sym) in lst
    end
end

# ============================================================
# ValidateSymbol
# ============================================================

@testset "ValidateSymbol — passes for fresh symbol" begin
    reset_registry!()
    @test_nowarn ValidateSymbol(:UnusedSymbolXYZ123)
end

@testset "ValidateSymbol — collision with registered symbol" begin
    reset_registry!()
    register_symbol(:AlreadyTaken, "XCoba")
    err = @test_throws ErrorException ValidateSymbol(:AlreadyTaken)
    @test occursin("XCoba", err.value.msg)
end

@testset "ValidateSymbol — collision with Base export" begin
    reset_registry!()
    # :map is a well-known Base export
    err = @test_throws ErrorException ValidateSymbol(:map)
    @test occursin("Base", err.value.msg)
end

@testset "ValidateSymbol — Base non-export does not block" begin
    reset_registry!()
    # Base internals that are not exported should not trigger the check.
    # Use a name that is defined in Base but not exported.
    # (We verify it is not exported first so the test is self-consistent.)
    sym = :_setindex_once!   # internal Base helper, not exported
    if isdefined(Base, sym) && !Base.isexported(Base, sym)
        @test_nowarn ValidateSymbol(sym)
    else
        @test_skip "symbol not suitable for this test on this Julia version"
    end
end

@testset "ValidateSymbol — collision message contains symbol name" begin
    reset_registry!()
    register_symbol(:NamedThing, "XTensor")
    err = @test_throws ErrorException ValidateSymbol(:NamedThing)
    @test occursin("NamedThing", err.value.msg)
end

# ============================================================
# FindSymbols
# ============================================================

@testset "FindSymbols — bare symbol" begin
    @test FindSymbols(:x) == [:x]
end

@testset "FindSymbols — non-symbol scalar" begin
    @test FindSymbols(42) == Symbol[]
    @test FindSymbols("hello") == Symbol[]
end

@testset "FindSymbols — vector" begin
    result = FindSymbols([:a, :b, :a, 1])
    @test :a in result && :b in result
    @test length(result) == 2   # deduplicated
end

@testset "FindSymbols — Expr" begin
    e = :( f(x, y) )
    syms = FindSymbols(e)
    @test :f in syms && :x in syms && :y in syms
end

@testset "FindSymbols — tuple" begin
    result = FindSymbols((:p, :q, :p))
    @test length(result) == 2
    @test :p in result && :q in result
end
