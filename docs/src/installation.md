# Installation

This guide covers how to install the `XAct.jl` package for research use, as well as the optional verification framework for developers.

Canonical onboarding path: README → Installation → [Getting Started](getting-started.md) → [Typed Expressions (TExpr)](guide/TExpr.md).

## 1. Quick Install (Research Use)

If you just want to use `xAct` for tensor calculus in Julia, you only need the Julia package.

### Prerequisites
- [Julia 1.12+](https://julialang.org/downloads/)

### Installation
Open your Julia REPL and run:

```julia
using Pkg
Pkg.add(url="https://github.com/sashakile/XAct.jl.git")
```

Wait for the installation to finish, then you can start using it:
```julia
using XAct
```

Next: continue to [Getting Started](getting-started.md) for the first working examples.

## 2. Python Wrapper (xact-py)

The Python wrapper provides an idiomatic interface to the Julia core. For the full verification framework, see [Developer Install](#3-developerverification-install).

### Prerequisites
- [Julia 1.12+](https://julialang.org/downloads/)
- Python 3.10+
- [uv](https://docs.astral.sh/uv/) (recommended)

### Installation
`xact-py` is published on [PyPI](https://pypi.org/project/xact-py/). For normal use, install the latest release with:

```bash
pip install xact-py
```

On first import, `xact-py` resolves `XAct` from the Julia registries via `juliapkg`.

Only install from a repository checkout if you explicitly need unreleased changes from `main` or are contributing to the wrapper. In that case, install the Python package in editable mode and point `juliapkg` at a shared Julia project that develops the local repository checkout:

```bash
git clone https://github.com/sashakile/XAct.jl.git
cd XAct.jl
uv pip install -e packages/xact-py
export PYTHON_JULIAPKG_PROJECT="$PWD/.juliapkg-xact"
julia --project="$PYTHON_JULIAPKG_PROJECT" -e 'using Pkg; Pkg.develop(path=pwd()); Pkg.instantiate()'
```

*Note: The wrapper automatically manages its Julia dependencies using `juliapkg`.*

Next: continue to [Getting Started](getting-started.md#3-quick-start-python) for the first Python workflow.

---

## 3. Developer/Verification Install

The full suite includes a Python wrapper and a Dockerized Wolfram Oracle for proving implementation parity.

### Prerequisites
- [Julia 1.12+](https://julialang.org/downloads/)
- [uv](https://docs.astral.sh/uv/) (recommended) or Python 3.10+
- [Docker](https://www.docker.com/)

### Step A: Clone and Sync
```bash
git clone https://github.com/sashakile/XAct.jl.git
cd sxAct
uv sync
```

### Step B: Activate the Wolfram Oracle
The verification suite requires a Dockerized Wolfram Engine. You must activate it once using a free [Wolfram ID](https://account.wolfram.com/auth/create):

```bash
docker compose run --rm wolfram wolframscript -activate
```

### Step C: Start the Server
```bash
docker compose up -d oracle
```

### Step D: Run Tests
```bash
uv run pytest
```

Once the environment is ready, use [Getting Started](getting-started.md) for user-facing workflows and [Contributing](contributing.md) for development guidance.

---

## Troubleshooting

### "No valid license found" (Wolfram Engine)
The Docker container needs a one-time activation. Ensure you have run:
```bash
docker compose run --rm wolfram wolframscript -activate
```

### Docker: "Permission denied"
Ensure your user is in the `docker` group or prefix commands with `sudo`.

### Julia: "Package not found"
Ensure you are using the correct URL when adding via `Pkg.add(url=...)`.
