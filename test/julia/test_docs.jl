using Test
using Literate
using xAct

@testset "Documentation Tests" begin
    # 1. Verify build script exists
    make_jl = joinpath(@__DIR__, "..", "..", "docs", "make.jl")
    @test isfile(make_jl)

    # 2. Execute Literate tutorials as tests
    # This ensures that code snippets in tutorials don't throw errors.
    example_dir = joinpath(@__DIR__, "..", "..", "docs", "examples")

    # We run them in a separate module to avoid polluting the test namespace
    # and to simulate a clean user session.
    for tutorial in ["basics.jl", "invar.jl"]
        path = joinpath(example_dir, tutorial)
        @testset "Tutorial: $tutorial" begin
            # Literate.script generates a plain Julia file from the commented source
            # We then include it to execute the code.
            m = Module(gensym())
            # Inject xAct into the anonymous module
            Core.eval(m, :(using xAct))

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
