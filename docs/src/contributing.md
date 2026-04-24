# Contributing

We welcome contributions to `XAct.jl` (the Julia core) and the `sxact` verification framework.

## Getting Started

Please see the root [CONTRIBUTING.md](https://github.com/sashakile/XAct.jl/blob/main/CONTRIBUTING.md) for full details on environment setup, code style, and workflow.

### Quick Setup

```bash
# 1. Clone the repository
git clone https://github.com/sashakile/XAct.jl.git
cd XAct.jl

# 2. Install Python dependencies
uv sync --extra dev

# 3. Run Julia tests
julia --project=. test/runtests.jl

# 4. Run Python tests
uv run pytest
```

## Contribution Areas

### 1. Mathematical Implementation (Julia)
- Adding new xAct-compatible functions (e.g., `LieD`, exterior calculus, spinors).
- Optimizing permutation group algorithms in `XPerm.jl`.
- Implementing the multi-term symmetry engine (Invar).
- Extending xCoba coordinate component support in `XTensor.jl`.

### 2. Verification & Tooling (Python)
- Adding new TOML test cases for existing operations.
- Improving the normalization pipeline (regex and AST-based).
- Expanding the property-based test catalog.
- Improving oracle snapshot tooling.

### 3. Documentation & Tutorials
- Writing new Literate.jl tutorials in `docs/examples/`.
- Improving the differential geometry primer.
- Adding worked examples for general relativity use-cases.

## Testing Your Changes

### Notebook Validation

Use the shared notebook smoke-test workflow before changing Quarto notebook sources:

```bash
just test-notebooks
```

That command executes every Julia `.qmd` notebook in `notebooks/julia/` by extracting its Julia code cells and running them in fresh Julia subprocesses. It is the repository's lightweight notebook regression path.

Python notebooks currently use a different validation strategy:
- `just docs` validates the rendered conversion path for `notebooks/python/*.qmd`.
- Runtime validation for Python notebooks remains manual/smoke-based for now because those notebooks depend on the packaged `xact-py` wrapper and Python/Julia environment setup rather than pure Documenter execution.

When a notebook ticket asks for verification, use `just test-notebooks` for Julia notebooks and document any extra Python-specific manual checks explicitly.

Before submitting a PR, please ensure:
1. `julia --project=. test/runtests.jl` passes.
2. `uv run pytest` passes.
3. `just docs` builds the documentation without errors.
4. `just test-notebooks` passes if you changed notebook sources or notebook-derived docs.
