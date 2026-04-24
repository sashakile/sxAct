# Contributing to XAct.jl

This repository contains both the `XAct.jl` Julia package and the `sxact` verification framework.

## 1. Julia Development (XAct.jl)

The Julia source code is located in `src/`.

### Setup
- [Julia 1.10+](https://julialang.org/downloads/)
- Optional: [JuliaExtension](https://marketplace.visualstudio.com/items?itemName=julialang.language-julia) for VS Code.

### Running Julia Tests
```bash
julia --project=. test/runtests.jl
```

### Code Style
- Use `JuliaFormatter.jl`. A `.JuliaFormatter.toml` is provided in the root.
- Follow the [Blue Style](https://github.com/invenia/BlueStyle) where possible.
- Use `JET.jl` and `Aqua.jl` for static analysis and quality checks (run as part of `runtests.jl`).

---

## 2. Python & Verification Development (`xact-py`)

The Python source is located in the `packages/` directory:
- `packages/xact-py`: The computational wrapper.
- `packages/sxact`: The validation framework.

### Setup
**Prerequisites:** Docker, Python ≥ 3.10, [uv](https://docs.astral.sh/uv/)

```bash
# Install all dependencies for the workspace
uv sync --extra dev

# Point juliapkg at a shared Julia project that uses the local checkout
export PYTHON_JULIAPKG_PROJECT="$PWD/.juliapkg-xact"
julia --project="$PYTHON_JULIAPKG_PROJECT" -e 'using Pkg; Pkg.develop(path=pwd()); Pkg.instantiate()'

# Start the oracle server (needed for integration tests)
docker compose up -d
```

See [SETUP.md](SETUP.md) for first-time Wolfram Engine activation.

### Running Python Tests
```bash
# Unit tests only (fast, no Docker required)
uv run pytest tests/unit

# Integration tests (oracle must be running)
uv run pytest tests/integration/

# All tests
uv run pytest

# Type checking
uv run mypy packages/xact-py/src packages/sxact/src
```

Test markers:
- `oracle` — requires the Docker oracle server (`docker compose up -d`)
- `slow` — these take longer due to xAct initialization time.

---

## 3. Documentation

`XAct.jl` uses [Documenter.jl](https://juliadocs.github.io/Documenter.jl/stable/) for documentation.

### Building
```bash
# Build the documentation
just docs

# Smoke-test Julia Quarto notebooks
just test-notebooks

# Build and serve locally on http://localhost:8000
just serve-docs
```

Notebook validation policy:
- `just test-notebooks` is the shared Julia notebook smoke-test workflow. It extracts all Julia code cells from `notebooks/julia/*.qmd` and executes them in fresh Julia subprocesses.
- `just docs` remains the shared rendering/Markdown conversion check for notebook-derived documentation, including Python notebooks.
- Python notebook runtime validation is still manual/smoke-based for now because those notebooks depend on the `xact-py` wrapper and mixed Python/Julia environment setup.

## 4. Project Structure

| Path | Purpose |
|------|---------|
| `src/` | Native Julia implementation of xAct engines. |
| `test/` | Julia unit tests and quality checks. |
| `packages/xact-py/` | Python computational wrapper (`import xact`). |
| `packages/sxact/` | Python validation logic (`import sxact`). |
| `tests/` | Multi-tier test suite (Julia, Python, Oracle). |
| `docs/` | Documentation (Julia-centric, built with Documenter.jl). |

## 5. Workflow

Changes are tracked via [beads](https://github.com/sk/beads) for issue management.

```bash
# Check available work
bd ready

# Claim an issue
bd update <id> --status=in_progress

# Close when done
bd close <id>
```
