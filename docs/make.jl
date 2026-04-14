# Documenter.jl build script
# Run with: julia --project=docs/ docs/make.jl

using Documenter
using Literate
using XAct
using Plots

# Headless plotting for CI/builds
ENV["GKSwstype"] = "100"

# Transform Literate examples into Markdown
example_dir = joinpath(@__DIR__, "examples")
output_dir = joinpath(@__DIR__, "src/examples")
isdir(output_dir) || mkdir(output_dir)

for file in readdir(example_dir)
    if endswith(file, ".jl")
        Literate.markdown(joinpath(example_dir, file), output_dir; documenter=true)
    end
end

# Export Pluto notebooks as Documenter-compatible Markdown
pluto_dir = joinpath(@__DIR__, "..", "notebooks", "pluto")
pluto_output = joinpath(@__DIR__, "src", "notebooks")
isdir(pluto_output) || mkdir(pluto_output)

if isdir(pluto_dir) && !isempty(filter(f -> endswith(f, ".jl"), readdir(pluto_dir)))
    using PlutoStaticHTML
    pluto_files = filter(f -> endswith(f, ".jl"), readdir(pluto_dir))
    bopts = BuildOptions(pluto_dir; write_files=false, output_format=documenter_output)
    results = build_notebooks(bopts, pluto_files)
    for file in pluto_files
        name = replace(file, ".jl" => "")
        outpath = joinpath(pluto_output, "$name.md")
        content = join(results[file], "\n")
        @info "Writing Pluto output: $outpath ($(length(content)) bytes)"
        write(outpath, content)
    end
end

# Convert Quarto (.qmd) notebooks to Documenter-compatible Markdown
# Strips YAML frontmatter and converts ```{lang} fences to ```lang
for (subdir, lang_label) in [("julia", "Julia"), ("python", "Python")]
    qmd_dir = joinpath(@__DIR__, "..", "notebooks", subdir)
    isdir(qmd_dir) || continue
    for file in filter(f -> endswith(f, ".qmd"), readdir(qmd_dir))
        name = replace(file, ".qmd" => "")
        src = read(joinpath(qmd_dir, file), String)
        # Strip YAML frontmatter
        md = replace(src, r"^---\n.*?^---\n*"ms => "")
        # Use @example blocks for Julia so Documenter executes them and shows plots
        if subdir == "julia"
            label = "$(name)_julia"
            md = replace(md, r"```\{julia\}" => "```@example $label")
        else
            # Convert ```{python} to plain fenced blocks (Documenter doesn't run Python)
            md = replace(md, r"```\{(\w+)\}" => s"```\1")
        end
        # Rewrite deployed-docs URLs to relative Documenter paths
        md = replace(md, "https://sashakile.github.io/sxAct/" => "../")
        # Rewrite .ipynb cross-links: name.ipynb -> name_julia.md (or python)
        md = replace(
            md,
            r"([\w\d_-]+)\.ipynb" => SubstitutionString("\\1_$(lowercase(lang_label)).md"),
        )
        # Add a note linking to the .ipynb and Colab
        header = """
!!! tip "Run this notebook"
    - [Download the Jupyter notebook](https://github.com/sashakile/sxAct/blob/main/notebooks/$subdir/$name.ipynb)
    - [Open in Google Colab](https://colab.research.google.com/github/sashakile/sxAct/blob/main/notebooks/$subdir/$name.ipynb)

"""
        outpath = joinpath(pluto_output, "$(name)_$(lowercase(lang_label)).md")
        @info "Writing Quarto notebook: $outpath"
        write(outpath, header * md)
    end
end

makedocs(;
    sitename="XAct.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", nothing) == "true",
        canonical="https://saxa.xyz/sxAct/",
        edit_link="main",
        assets=String[],
        size_threshold=300 * 1024, # Increase to 300KiB for large API page
        inventory_version="0.7.0",
    ),
    warnonly=[
        :cross_references, :example_block, :docs_block, :missing_docs, :autodocs_block
    ],
    modules=[XAct, XAct.XCore, XAct.XPerm, XAct.XTensor, XAct.XInvar],
    pages=[
        "Home" => "index.md",
        "Status" => "status.md",
        "Installation" => "installation.md",
        "Getting Started" => "getting-started.md",
        "Guide" => ["Typed Expressions (TExpr)" => "guide/TExpr.md"],
        "Key Concepts" => "concepts.md",
        "Migrating from Wolfram" => "wolfram-migration.md",
        "Tutorials" =>
            ["Basics" => "examples/basics.md", "Riemann Invariants" => "examples/invar.md"],
        "Notebooks" => [
            "Julia (Jupyter)" => "notebooks/basics_julia.md",
            "Python (Jupyter)" => "notebooks/basics_python.md",
            "Interactive (Pluto)" => "notebooks/basics.md",
            "Foundations: 2D Polar" => "notebooks/foundations_2d_polar_julia.md",
            "Foundations: 3D Coords" => "notebooks/foundations_3d_coords_julia.md",
            "Foundations: 2-Sphere" => "notebooks/foundations_sphere_julia.md",
            "Carroll: Schwarzschild" => "notebooks/carroll_schwarzschild_julia.md",
            "Wald: FLRW Cosmology" => "notebooks/wald_cosmology_julia.md",
            "MTW: Gravitational Waves" => "notebooks/mtw_gravitational_waves_julia.md",
        ],
        "Physics" => [
            "Electromagnetism" => "notebooks/physics_em_julia.md",
            "Fluid Dynamics" => "notebooks/physics_fluids_julia.md",
        ],
        "Theory" => ["Differential Geometry Primer" => "differential-geometry-primer.md"],
        "Advanced" => ["Oracle Quirks" => "theory/oracle-quirks.md"],
        "Architecture" => "architecture.md",
        "Reference" => [
            "Julia API" => "api-julia.md",
            "Python API" => "api-python.md",
            "Verification API" => "api-verification.md",
            "Verification Tools" => "verification-tools.md",
        ],
        "Contributing" => "contributing.md",
    ],
)

# Deployment is handled by the GitHub Actions workflow (upload-pages-artifact
# + deploy-pages), so no deploydocs() call is needed here.
