# Contributing

We welcome contributions to `xAct.jl` (the Julia core) and the `sxact` verification framework.

## Getting Started

Please see the root [CONTRIBUTING.md](https://github.com/sashakile/sxAct/blob/main/CONTRIBUTING.md) for full details on environment setup, code style, and workflow.

### Quick Setup

```bash
# 1. Clone the repository
git clone https://github.com/sashakile/sxAct.git
cd sxAct

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

Before submitting a PR, please ensure:
1. `julia --project=. test/runtests.jl` passes.
2. `uv run pytest` passes.
3. `just docs` builds the documentation without errors.
