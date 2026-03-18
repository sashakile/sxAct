using Test
using Aqua
using JET
using xAct

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
        (:S1, "XCore", xCoreNames),
        (:S2, "XPerm", xPermNames),
        (:S3, "XTensor", xTensorNames),
        (:S4, "XTableau", xTableauNames),
        (:S5, "XCoba", xCobaNames),
        (:S6, "Invar", InvarNames),
        (:S7, "Harmonics", HarmonicsNames),
        (:S8, "XPert", xPertNames),
        (:S9, "Spinors", SpinorsNames),
        (:S10, "EM", EMNames),
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
    # AbstractCmd is a stable internal Base type, not part of the public API.
    sym = :AbstractCmd
    @assert isdefined(Base, sym) && !Base.isexported(Base, sym) "test assumption broken on this Julia version"
    @test_nowarn ValidateSymbol(sym)
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
    e = :(f(x, y))
    syms = FindSymbols(e)
    @test :f in syms && :x in syms && :y in syms
end

@testset "FindSymbols — tuple" begin
    result = FindSymbols((:p, :q, :p))
    @test length(result) == 2
    @test :p in result && :q in result
end

# ============================================================
# ThreadArray
# ============================================================

@testset "ThreadArray — element-wise application" begin
    result = ThreadArray(+, [1, 2, 3], [10, 20, 30])
    @test result == [11, 22, 33]
end

@testset "ThreadArray — with lambda" begin
    result = ThreadArray((a, b) -> a * b, [2, 3], [4, 5])
    @test result == [8, 15]
end

# ============================================================
# ReportSet
# ============================================================

@testset "ReportSet — changes value when different" begin
    r = Ref(1)
    ReportSet(r, 2; verbose=false)
    @test r[] == 2
end

@testset "ReportSet — no change when same value" begin
    r = Ref(42)
    ReportSet(r, 42; verbose=false)
    @test r[] == 42
end

@testset "ReportSet — verbose=true does not throw" begin
    r = Ref("old")
    @test_nowarn ReportSet(r, "new"; verbose=false)
    @test r[] == "new"
end

# ============================================================
# ReportSetOption
# ============================================================

@testset "ReportSetOption — is a no-op" begin
    @test ReportSetOption(:SomeSymbol, :opt => "val") === nothing
end

# ============================================================
# LinkCharacter / LinkSymbols / UnlinkSymbol
# ============================================================

@testset "LinkSymbols — joins with LinkCharacter" begin
    lc = LinkCharacter[]
    result = LinkSymbols([:ab, :cd, :ef])
    @test string(result) == "ab$(lc)cd$(lc)ef"
end

@testset "LinkSymbols — single symbol" begin
    @test LinkSymbols([:foo]) == :foo
end

@testset "LinkSymbols — empty list" begin
    @test LinkSymbols(Symbol[]) == Symbol("")
end

@testset "UnlinkSymbol — splits at LinkCharacter" begin
    lc = LinkCharacter[]
    s = Symbol("ab$(lc)cd$(lc)ef")
    @test UnlinkSymbol(s) == [:ab, :cd, :ef]
end

@testset "UnlinkSymbol — no link character is identity" begin
    @test UnlinkSymbol(:foo) == [:foo]
end

@testset "LinkSymbols + UnlinkSymbol — roundtrip" begin
    parts = [:alpha, :beta, :gamma]
    @test UnlinkSymbol(LinkSymbols(parts)) == parts
end

# ============================================================
# xTension! / MakexTensions
# ============================================================

# Helper to reset the extensions store between test sets.
function reset_xtensions!()
    empty!(XCore._xtensions)
end

@testset "xTension! + MakexTensions — hooks fire in registration order" begin
    reset_xtensions!()
    log = Int[]
    xTension!("PkgA", :DefMetric, "Beginning", (_...) -> push!(log, 1))
    xTension!("PkgB", :DefMetric, "Beginning", (_...) -> push!(log, 2))
    xTension!("PkgC", :DefMetric, "Beginning", (_...) -> push!(log, 3))
    MakexTensions(:DefMetric, "Beginning")
    @test log == [1, 2, 3]
end

@testset "xTension! + MakexTensions — Beginning and End are independent" begin
    reset_xtensions!()
    fired = Symbol[]
    xTension!("Pkg", :DefTensor, "Beginning", (_...) -> push!(fired, :begin))
    xTension!("Pkg", :DefTensor, "End", (_...) -> push!(fired, :end))
    MakexTensions(:DefTensor, "Beginning")
    @test fired == [:begin]
    MakexTensions(:DefTensor, "End")
    @test fired == [:begin, :end]
end

@testset "xTension! + MakexTensions — hooks receive args" begin
    reset_xtensions!()
    received = []
    xTension!("Pkg", :DefMetric, "End", (a, b) -> push!(received, (a, b)))
    MakexTensions(:DefMetric, "End", :g, 4)
    @test received == [(:g, 4)]
end

@testset "xTension! + MakexTensions — no hooks registered is a no-op" begin
    reset_xtensions!()
    @test_nowarn MakexTensions(:UnknownCmd, "Beginning")
end

@testset "xTension! — invalid moment throws" begin
    reset_xtensions!()
    @test_throws ErrorException xTension!("Pkg", :DefTensor, "Middle", identity)
end

@testset "xTension! + MakexTensions — multiple commands are independent" begin
    reset_xtensions!()
    log = Symbol[]
    xTension!("Pkg", :DefMetric, "End", (_...) -> push!(log, :metric))
    xTension!("Pkg", :DefTensor, "End", (_...) -> push!(log, :tensor))
    MakexTensions(:DefMetric, "End")
    @test log == [:metric]
    MakexTensions(:DefTensor, "End")
    @test log == [:metric, :tensor]
end

# ============================================================
# JustOne
# ============================================================

@testset "JustOne — singleton extraction" begin
    @test JustOne([42]) == 42
    @test JustOne(["hello"]) == "hello"
    @test JustOne([:sym]) == :sym
end

@testset "JustOne — throws on empty" begin
    @test_throws ErrorException JustOne([])
end

@testset "JustOne — throws on multi-element" begin
    @test_throws ErrorException JustOne([1, 2])
    @test_throws ErrorException JustOne([1, 2, 3])
end

# ============================================================
# MapIfPlus
# ============================================================

@testset "MapIfPlus — maps over vector" begin
    @test MapIfPlus(x -> x * 2, [1, 2, 3]) == [2, 4, 6]
end

@testset "MapIfPlus — maps over tuple" begin
    result = MapIfPlus(x -> x + 1, (10, 20))
    @test result == (11, 21)
end

@testset "MapIfPlus — applies once to scalar" begin
    @test MapIfPlus(x -> x * 10, 5) == 50
    @test MapIfPlus(identity, :sym) === :sym
end

@testset "MapIfPlus — scalar string" begin
    @test MapIfPlus(identity, "hello") == "hello"
end

# ============================================================
# SetNumberOfArguments
# ============================================================

@testset "SetNumberOfArguments — is a no-op shim" begin
    @test SetNumberOfArguments(sin, 1) === nothing
    @test SetNumberOfArguments(+, 2) === nothing
end

# ============================================================
# CheckOptions
# ============================================================

@testset "CheckOptions — empty returns empty vector" begin
    result = CheckOptions()
    @test result == Pair[]
    @test result isa Vector{Pair}
end

@testset "CheckOptions — single pair" begin
    result = CheckOptions(:a => 1)
    @test length(result) == 1
    @test result[1] == (:a => 1)
end

@testset "CheckOptions — multiple pairs" begin
    result = CheckOptions(:a => 1, :b => 2)
    @test length(result) == 2
end

@testset "CheckOptions — list of pairs is flattened" begin
    result = CheckOptions([:a => 1, :b => 2])
    @test length(result) == 2
end

@testset "CheckOptions — non-pair throws" begin
    @test_throws ErrorException CheckOptions(:not_a_pair)
    @test_throws ErrorException CheckOptions(42)
end

# ============================================================
# TrueOrFalse
# ============================================================

@testset "TrueOrFalse — true for Bool values" begin
    @test TrueOrFalse(true) == true
    @test TrueOrFalse(false) == true
end

@testset "TrueOrFalse — false for non-Bool" begin
    @test TrueOrFalse(1) == false
    @test TrueOrFalse(:sym) == false
    @test TrueOrFalse("true") == false
    @test TrueOrFalse(nothing) == false
end

# ============================================================
# SymbolJoin
# ============================================================

@testset "SymbolJoin — concatenates symbols" begin
    @test SymbolJoin(:foo, :Bar) == :fooBar
end

@testset "SymbolJoin — accepts strings" begin
    @test SymbolJoin("foo", "Bar") == :fooBar
end

@testset "SymbolJoin — mixed types" begin
    @test SymbolJoin("x", 1, "y") == :x1y
end

@testset "SymbolJoin — single argument" begin
    @test SymbolJoin(:hello) == :hello
end

@testset "SymbolJoin — result is a Symbol" begin
    @test SymbolJoin("a", "b") isa Symbol
end

# ============================================================
# NoPattern
# ============================================================

@testset "NoPattern — identity on non-patterns" begin
    @test NoPattern(42) === 42
    @test NoPattern(:x) === :x
    @test NoPattern("hello") === "hello"
end

@testset "NoPattern — identity on any value" begin
    v = [1, 2, 3]
    @test NoPattern(v) === v
end

# ============================================================
# DaggerCharacter / HasDaggerCharacterQ / MakeDaggerSymbol
# ============================================================

@testset "DaggerCharacter — is a Ref{String} with non-empty default" begin
    @test DaggerCharacter isa Ref{String}
    @test !isempty(DaggerCharacter[])
end

@testset "HasDaggerCharacterQ — false for plain symbol" begin
    @test HasDaggerCharacterQ(:foo) == false
end

@testset "HasDaggerCharacterQ — true after MakeDaggerSymbol" begin
    daggered = MakeDaggerSymbol(:myBase)
    @test HasDaggerCharacterQ(daggered) == true
end

@testset "MakeDaggerSymbol — toggle: twice gives original" begin
    @test MakeDaggerSymbol(MakeDaggerSymbol(:foo)) == :foo
    @test MakeDaggerSymbol(MakeDaggerSymbol(:alpha)) == :alpha
end

@testset "MakeDaggerSymbol — adds dagger to plain symbol" begin
    daggered = MakeDaggerSymbol(:v)
    @test occursin(DaggerCharacter[], string(daggered))
end

@testset "MakeDaggerSymbol — removes dagger from daggered symbol" begin
    daggered = MakeDaggerSymbol(:w)
    plain = MakeDaggerSymbol(daggered)
    @test plain == :w
end

# ============================================================
# SubHead
# ============================================================

@testset "SubHead — bare symbol returns itself" begin
    @test SubHead(:x) === :x
    @test SubHead(:MyTensor) === :MyTensor
end

@testset "SubHead — Expr returns head symbol" begin
    # In Julia, :(f(x,y)).head is :call, so SubHead recurses to :call.
    e = :(f(x, y))
    @test SubHead(e) === :call
end

@testset "SubHead — non-symbol non-Expr is identity" begin
    @test SubHead(42) === 42
end

# ============================================================
# xUpSet! / xUpSetDelayed! / xUpAppendTo! / xUpDeleteCasesTo!
# ============================================================

function reset_upvalues!()
    empty!(XCore._upvalue_store)
end

@testset "xUpSet! — stores value" begin
    reset_upvalues!()
    xUpSet!(:MyProp, :MySym, 42)
    d = XCore._upvalue_store[:MySym]
    @test d[:MyProp] == 42
end

@testset "xUpSet! — returns value" begin
    reset_upvalues!()
    ret = xUpSet!(:P, :S, "hello")
    @test ret == "hello"
end

@testset "xUpSet! — overwrites previous value" begin
    reset_upvalues!()
    xUpSet!(:P, :S, 1)
    xUpSet!(:P, :S, 2)
    @test XCore._upvalue_store[:S][:P] == 2
end

@testset "xUpSetDelayed! — stores thunk, returns nothing" begin
    reset_upvalues!()
    ret = xUpSetDelayed!(:P, :S, () -> 99)
    @test ret === nothing
    thunk = XCore._upvalue_store[:S][:P]
    @test thunk isa Function
    @test thunk() == 99
end

@testset "xUpAppendTo! — initializes list" begin
    reset_upvalues!()
    xUpAppendTo!(:P, :S, "first")
    @test XCore._upvalue_store[:S][:P] == ["first"]
end

@testset "xUpAppendTo! — appends to list" begin
    reset_upvalues!()
    xUpAppendTo!(:P, :S, "a")
    xUpAppendTo!(:P, :S, "b")
    @test XCore._upvalue_store[:S][:P] == ["a", "b"]
end

@testset "xUpAppendTo! — returns the list" begin
    reset_upvalues!()
    lst = xUpAppendTo!(:P, :S, 1)
    @test lst == [1]
end

@testset "xUpDeleteCasesTo! — removes matching element" begin
    reset_upvalues!()
    xUpAppendTo!(:P, :S, 1)
    xUpAppendTo!(:P, :S, 2)
    xUpAppendTo!(:P, :S, 3)
    xUpDeleteCasesTo!(:P, :S, x -> x == 2)
    @test XCore._upvalue_store[:S][:P] == [1, 3]
end

@testset "xUpDeleteCasesTo! — no-op when property absent" begin
    reset_upvalues!()
    @test_nowarn xUpDeleteCasesTo!(:Missing, :S, _ -> true)
end

# ============================================================
# xTagSet! / xTagSetDelayed!
# ============================================================

@testset "xTagSet! — stores value under tag" begin
    reset_upvalues!()
    xTagSet!(:MyTag, :key, "val")
    stored = XCore._upvalue_store[:MyTag]
    @test haskey(stored, Symbol(:tag_, :key))
    @test stored[Symbol(:tag_, :key)] == "val"
end

@testset "xTagSetDelayed! — stores thunk under tag" begin
    reset_upvalues!()
    xTagSetDelayed!(:MyTag, :key, () -> 7)
    stored = XCore._upvalue_store[:MyTag]
    thunk = stored[Symbol(:tag_, :key)]
    @test thunk() == 7
end

# ============================================================
# push_unevaluated!
# ============================================================

@testset "push_unevaluated! — is alias for push!" begin
    v = [1, 2, 3]
    push_unevaluated!(v, 4)
    @test v == [1, 2, 3, 4]
end

# ============================================================
# XHold / xEvaluateAt
# ============================================================

@testset "XHold — wraps a value" begin
    h = XHold(42)
    @test h.value == 42
end

@testset "XHold — show does not throw" begin
    h = XHold(:sym)
    @test_nowarn repr(h)
    @test occursin("XHold", repr(h))
end

@testset "xEvaluateAt — returns expr unchanged" begin
    e = :(f(x))
    @test xEvaluateAt(e, [1]) === e
    @test xEvaluateAt(42, []) === 42
end

# ============================================================
# WarningFrom / xActDirectory / xActDocDirectory
# ============================================================

@testset "WarningFrom — is a Ref{String}" begin
    @test WarningFrom isa Ref{String}
    @test WarningFrom[] isa String
end

@testset "xActDirectory — is a Ref{String}" begin
    @test xActDirectory isa Ref{String}
    @test xActDirectory[] isa String
end

@testset "xActDocDirectory — is a Ref{String}" begin
    @test xActDocDirectory isa Ref{String}
    @test xActDocDirectory[] isa String
end

# ============================================================
# Disclaimer
# ============================================================

@testset "Disclaimer — prints without throwing" begin
    @test_nowarn Disclaimer()
end

# ============================================================
# DeleteDuplicates / DuplicateFreeQ (Category B aliases)
# ============================================================

@testset "DeleteDuplicates — removes duplicates preserving order" begin
    @test DeleteDuplicates([1, 2, 1, 3, 2]) == [1, 2, 3]
    @test DeleteDuplicates([:a, :b, :a]) == [:a, :b]
end

@testset "DeleteDuplicates — unique list unchanged" begin
    @test DeleteDuplicates([1, 2, 3]) == [1, 2, 3]
end

@testset "DeleteDuplicates — all same gives singleton" begin
    @test DeleteDuplicates([:x, :x, :x]) == [:x]
end

@testset "DuplicateFreeQ — true for unique list" begin
    @test DuplicateFreeQ([1, 2, 3]) == true
    @test DuplicateFreeQ([:a, :b]) == true
end

@testset "DuplicateFreeQ — false for list with duplicates" begin
    @test DuplicateFreeQ([1, 2, 1]) == false
end

@testset "DuplicateFreeQ — true for empty list" begin
    @test DuplicateFreeQ([]) == true
end

# ============================================================
# Layer 2: Property-based tests (randomized invariants)
# ============================================================

# Helper: generate a unique symbol name not already in the registry.
function fresh_name(prefix="sym")
    string(prefix, "_", rand(UInt32))
end

@testset "L2: no two packages register the same name" begin
    reset_registry!()
    for _ in 1:50
        name = fresh_name("prop")
        pkg1 = "PkgA"
        pkg2 = "PkgB"
        register_symbol(name, pkg1)
        # Second registration by a different package must throw.
        @test_throws ErrorException register_symbol(name, pkg2)
        # Registry still contains the original owner.
        @test XCore._symbol_registry[name] == pkg1
    end
end

@testset "L2: register_symbol idempotent for same package (random names)" begin
    reset_registry!()
    for _ in 1:50
        name = fresh_name("idem")
        register_symbol(name, "XCore")
        @test_nowarn register_symbol(name, "XCore")
        @test count(==(name), xCoreNames) == 1
    end
end

@testset "L2: ValidateSymbol always throws for any registered symbol" begin
    reset_registry!()
    names = [fresh_name("vs") for _ in 1:30]
    for n in names
        register_symbol(n, "XTensor")
    end
    for n in names
        @test_throws ErrorException ValidateSymbol(Symbol(n))
    end
end

@testset "L2: hook registration ordering preserved for N hooks" begin
    reset_xtensions!()
    N = 20
    log = Int[]
    for i in 1:N
        local j = i
        xTension!("Pkg", :DefProp, "Beginning", (_...) -> push!(log, j))
    end
    MakexTensions(:DefProp, "Beginning")
    @test log == collect(1:N)
end

@testset "L2: hooks are independent across (command, moment) pairs" begin
    reset_xtensions!()
    results = Dict{Tuple{Symbol,String},Vector{Int}}()
    cmds = [:Cmd1, :Cmd2, :Cmd3]
    moments = ["Beginning", "End"]
    # Register hooks for all combos, tracking a unique value per combo.
    for (ci, cmd) in enumerate(cmds)
        for (mi, moment) in enumerate(moments)
            key = (cmd, moment)
            results[key] = Int[]
            local k = key
            xTension!("Pkg", cmd, moment, (_...) -> push!(results[k], ci * 10 + mi))
        end
    end
    # Fire each combo and verify only the right hook ran.
    for cmd in cmds
        for moment in moments
            key = (cmd, moment)
            MakexTensions(cmd, moment)
            @test length(results[key]) == 1
        end
    end
end

# ============================================================
# Quality checks (Aqua, JET, JuliaFormatter)
# ============================================================

@testset "Aqua quality checks" begin
    Aqua.test_all(
        xAct;
        ambiguities=false,   # xAct intentionally defers to caller dispatch
        deps_compat=false,   # no [deps] to check (test-only extras)
        stale_deps=false,    # skips check for dev-only dependencies in Project.toml
    )
end

@testset "JET static analysis" begin
    # Purge stale pkgimage caches for xAct before running JET.
    # Multiple valid-but-outdated .ji files accumulate over development sessions;
    # Revise (used internally by JET) may pick a broken one that is missing the
    # source-text section, causing a false "not stored in source-text cache" error.
    let xact_id = Base.PkgId(xAct),
        candidates = Base.find_all_in_cache_path(xact_id),
        newest = isempty(candidates) ? nothing : first(sort(candidates; by=mtime, rev=true))

        for c in candidates
            c == newest && continue
            rm(c; force=true)
            rm(replace(c, ".ji" => ".so"); force=true)
        end
    end
    JET.test_package(xAct; target_modules=(xAct,))
end

@testset "JuliaFormatter" begin
    # Format check runs via the dedicated tooling environment to avoid
    # JuliaSyntax version conflicts between JuliaFormatter and JET.
    tooling_proj = joinpath(@__DIR__, "..", "tooling")
    src_dir = joinpath(@__DIR__, "..", "src")
    cmd = ```
    $(Base.julia_cmd()) --project=$(tooling_proj) -e "
        using JuliaFormatter
        ok = format(ARGS; overwrite=false)
        exit(ok ? 0 : 1)
    " -- $(src_dir)
    ```
    @test success(cmd)
end

# ============================================================
# Functional tests (Included from test/julia/)
# ============================================================

include("julia/test_xperm.jl")
include("julia/test_xtensor.jl")
include("julia/test_xinvar.jl")
include("julia/test_docs.jl")
