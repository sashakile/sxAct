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

# Export Pluto notebooks to HTML fragments for inclusion in docs
pluto_dir = joinpath(@__DIR__, "..", "notebooks", "pluto")
pluto_output = joinpath(@__DIR__, "src", "notebooks")
isdir(pluto_output) || mkdir(pluto_output)

if isdir(pluto_dir) && !isempty(readdir(pluto_dir))
    using PlutoStaticHTML
    pluto_files = filter(f -> endswith(f, ".jl"), readdir(pluto_dir))
    for file in pluto_files
        name = replace(file, ".jl" => "")
        @info "Exporting Pluto notebook: $file"
        html = PlutoStaticHTML.notebook_to_html(joinpath(pluto_dir, file))
        # Wrap in Documenter-compatible Markdown with raw HTML
        open(joinpath(pluto_output, "$name.md"), "w") do io
            println(io, "# $(titlecase(name)) (Pluto Notebook)")
            println(io)
            println(io, "```@raw html")
            println(io, html)
            println(io, "```")
        end
    end
end

makedocs(;
    sitename="xAct.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", nothing) == "true",
        canonical="https://sashakile.github.io/sxAct/",
        edit_link="main",
        assets=String[],
        size_threshold=300 * 1024, # Increase to 300KiB for large API page
        inventory_version="0.4.0",
    ),
    modules=[xAct, xAct.XCore, xAct.XPerm, xAct.XTensor, xAct.XInvar],
    pages=[
        "Home" => "index.md",
        "Status" => "theory/STATUS.md",
        "Installation" => "installation.md",
        "Getting Started" => "getting-started.md",
        "Migrating from Wolfram" => "wolfram-migration.md",
        "Tutorials" =>
            ["Basics" => "examples/basics.md", "Riemann Invariants" => "examples/invar.md"],
        "Notebooks" => ["Interactive Basics (Pluto)" => "notebooks/basics.md"],
        "Theory" => ["Differential Geometry Primer" => "differential-geometry-primer.md"],
        "Advanced" => ["Oracle Quirks" => "theory/oracle-quirks.md"],
        "Architecture" => "architecture.md",
        "Reference" => [
            "Julia API" => "api.md",
            "Python API" => "api-python.md",
            "Verification API" => "api-verification.md",
            "Verification Tools" => "verification-tools.md",
        ],
        "Contributing" => "contributing.md",
    ],
)

deploydocs(; repo="github.com/sashakile/sxAct.git", devbranch="main")
