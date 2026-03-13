# xAct.jl - Command Runner

# Build the documentation using Documenter.jl
docs:
    julia --project=docs/ docs/make.jl

# Serve docs with live reload — watches docs/src/ and rebuilds on change
serve-docs:
    julia --project=docs/ -e 'using LiveServer; servedocs(literate_dir="docs/examples")'
