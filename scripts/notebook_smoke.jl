# Run with: julia --project=. scripts/notebook_smoke.jl

const NOTEBOOK_ROOT = joinpath(@__DIR__, "..", "notebooks")
const NOTEBOOK_PROJECT = joinpath(@__DIR__, "..", "docs")

"""Return sorted Quarto notebook source paths for a notebook subdirectory."""
function notebook_sources(kind::AbstractString)
    dir = joinpath(NOTEBOOK_ROOT, kind)
    isdir(dir) || throw(ArgumentError("Notebook directory not found: $dir"))
    return sort(filter(path -> endswith(path, ".qmd"), readdir(dir; join=true)))
end

"""Extract all code blocks for a Quarto language fence like ```{julia}."""
function extract_qmd_code_blocks(path::AbstractString, lang::AbstractString="julia")
    blocks = String[]
    current = String[]
    in_block = false
    fence = "```{$lang}"

    for line in eachline(path)
        if !in_block
            if startswith(line, fence)
                in_block = true
                empty!(current)
            end
            continue
        end

        if startswith(line, "```")
            push!(blocks, join(current, "\n"))
            in_block = false
            continue
        end

        if startswith(strip(line), "# |")
            continue
        end

        push!(current, line)
    end

    return join(blocks, "\n\n")
end

"""Execute one Julia Quarto notebook in a fresh Julia subprocess."""
function run_julia_notebook(path::AbstractString; stdout::IO=Base.stdout, stderr::IO=Base.stderr)
    code = extract_qmd_code_blocks(path, "julia")
    isempty(strip(code)) && throw(ArgumentError("No Julia code blocks found in $path"))

    wrapper = """
    ENV[\"GKSwstype\"] = \"100\"
    m = Module(:NotebookSmoke)
    try
        Base.include_string(m, $(repr(code)), $(repr(String(path))))
    catch e
        @error "Notebook failed: $(basename(path))" exception=(e, catch_backtrace())
        exit(1)
    end
    """

    mktemp() do tmppath, io
        write(io, wrapper)
        close(io)
        cmd = `$(Base.julia_cmd()) --project=$(NOTEBOOK_PROJECT) --startup-file=no --history-file=no $tmppath`
        run(pipeline(cmd; stdout=stdout, stderr=stderr))
    end
    return nothing
end

"""Run all Julia notebook smoke tests and throw on the first failure."""
function run_notebook_smoke_tests(; io::IO=stdout, notebook_stdout::IO=stdout, notebook_stderr::IO=stderr)
    paths = notebook_sources("julia")
    println(io, "Notebook smoke tests ($(length(paths)) Julia notebooks)")
    for path in paths
        print(io, "  • ", basename(path), " ... ")
        flush(io)
        run_julia_notebook(path; stdout=notebook_stdout, stderr=notebook_stderr)
        println(io, "ok")
    end
    println(io, "Python notebook strategy: docs build validates rendering; notebook-specific runtime checks remain documented/manual for now.")
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_notebook_smoke_tests()
end
