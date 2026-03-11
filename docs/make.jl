# Documenter.jl build script
# Run with: julia --project=docs/ docs/make.jl

using Documenter
using Literate
using xAct

# Transform Literate examples into Markdown
example_dir = joinpath(@__DIR__, "examples")
output_dir = joinpath(@__DIR__, "src/examples")
isdir(output_dir) || mkdir(output_dir)

for file in readdir(example_dir)
    if endswith(file, ".jl")
        Literate.markdown(joinpath(example_dir, file), output_dir; documenter=true)
    end
end

makedocs(;
    sitename="xAct.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", nothing) == "true",
        canonical="https://sashakile.github.io/sxAct/",
        edit_link="main",
        assets=String[],
    ),
    modules=[xAct, xAct.XCore, xAct.XPerm, xAct.XTensor],
    pages=[
        "Home" => "index.md",
        "Getting Started" => "getting-started.md",
        "Installation" => "installation.md",
        "Tutorials" => [
            "Basics" => "examples/basics.md",
            "Differential Geometry Primer" => "differential-geometry-primer.md",
        ],
        "Theory" => [
            "Feature Status" => "theory/STATUS.md",
            "Oracle Quirks" => "theory/oracle-quirks.md",
            "Tensor DSL Integration" => "theory/tensordsl-integration.md",
        ],
        "Architecture" => "architecture.md",
        "Reference" => [
            "Julia API" => "api.md",
            "Verification API" => "api-verification.md",
            "Verification Tools" => "verification-tools.md",
        ],
        "Contributing" => "contributing.md",
    ],
)

deploydocs(; repo="github.com/sashakile/sxAct.git", devbranch="main")
