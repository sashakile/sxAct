# XAct.jl - Command Runner

# Build the documentation using Documenter.jl
docs:
    julia --project=docs/ docs/make.jl

# Serve docs with live reload — watches docs/src/ and rebuilds on change
serve-docs:
    julia --project=docs/ -e 'using LiveServer; servedocs(literate_dir="docs/examples", skip_dirs=["docs/src/examples", "docs/src/notebooks"])'

# Run all Julia unit tests and quality checks
test-julia:
    julia --project=. test/runtests.jl

# Run Python unit tests (excluding slow/oracle tests)
test-python:
    uv run pytest tests/ -q --ignore=tests/integration --ignore=tests/properties --ignore=tests/xperm --ignore=tests/xtensor

# Run TOML regression tests using the Julia adapter and snapshot mode
test-regression:
    uv run xact-test run tests/xperm --adapter julia --oracle-mode snapshot --oracle-dir oracle
    uv run xact-test run tests/xtensor --adapter julia --oracle-mode snapshot --oracle-dir oracle

# Run all quality gates (unit, quality, regression)
test: test-julia test-python test-regression

# Smoke-test Julia Quarto notebook sources by executing their code cells
test-notebooks:
    julia --project=. scripts/notebook_smoke.jl

# Launch JupyterLab with Julia + Python kernels, opening the notebooks directory
lab:
    uv run jupyter lab --notebook-dir=notebooks

# Build the Docker image locally (tag defaults to "dev")
docker-build tag="dev":
    docker build -t ghcr.io/sashakile/xact.jl:{{tag}} .

# Build and load the Docker image locally without pushing
docker-build-load tag="dev":
    docker buildx build --load -t ghcr.io/sashakile/xact.jl:{{tag}} .

# Run the Docker image locally, exposing JupyterLab on port 8888
docker-run tag="dev":
    docker run --rm -p 8888:8888 ghcr.io/sashakile/xact.jl:{{tag}}
