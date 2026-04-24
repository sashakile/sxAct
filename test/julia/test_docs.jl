using Test
using XAct

# Literate is a test-extra; skip doc tests when unavailable (e.g. direct julia invocation)
_has_literate = try
    @eval using Literate
    true
catch
    false
end

@testset "Documentation Tests" begin
    # 1. Verify build script exists
    make_jl = joinpath(@__DIR__, "..", "..", "docs", "make.jl")
    @test isfile(make_jl)

    # 2. Notebook smoke-test workflow exists and can enumerate notebook sources.
    notebook_smoke_script = joinpath(@__DIR__, "..", "..", "scripts", "notebook_smoke.jl")
    @test isfile(notebook_smoke_script)
    include(notebook_smoke_script)
    @testset "Notebook smoke workflow" begin
        julia_notebooks = notebook_sources("julia")
        python_notebooks = notebook_sources("python")

        @test !isempty(julia_notebooks)
        @test basename.(julia_notebooks) == sort(basename.(julia_notebooks))
        @test all(endswith.(julia_notebooks, ".qmd"))
        @test basename.(python_notebooks) == ["basics.qmd"]

        basics_code = extract_qmd_code_blocks(first(filter(p -> basename(p) == "basics.qmd", julia_notebooks)))
        @test occursin("using XAct", basics_code)
        @test occursin("reset_state!()", basics_code)
        @test isnothing(run_notebook_smoke_tests(io=devnull, notebook_stdout=devnull, notebook_stderr=devnull))
    end

    # 3. Execute Literate tutorials as tests when Literate is available.
    # This ensures that code snippets in tutorials don't throw errors.
    example_dir = joinpath(@__DIR__, "..", "..", "docs", "examples")
    if !_has_literate
        @info "Skipping documentation tutorial execution: Literate package not available"
        @test_skip true
    else
        # We run them in a separate module to avoid polluting the test namespace
        # and to simulate a clean user session.
        for tutorial in ["basics.jl", "invar.jl"]
            path = joinpath(example_dir, tutorial)
            @testset "Tutorial: $tutorial" begin
                # Literate.script generates a plain Julia file from the commented source
                # We then include it to execute the code.
                m = Module(gensym())
                # Inject xAct into the anonymous module
                Core.eval(m, :(using XAct))

                # Use mktemp to avoid leaving artifacts
                mktempdir() do tmp
                    script_path = Literate.script(path, tmp)
                    @test isfile(script_path)
                    try
                        # include() in the context of our anonymous module
                        Base.include(m, script_path)
                        @test true # Reached end without error
                    catch e
                        @error "Documentation tutorial failed: $tutorial" exception=e
                        rethrow(e)
                    end
                end
            end
        end
    end
end
