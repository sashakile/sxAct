# Installation

This guide covers how to install the `xAct.jl` package for research use, as well as the optional verification framework for developers.

## 1. Quick Install (Research Use)

If you just want to use `xAct` for tensor calculus in Julia, you only need the Julia package.

### Prerequisites
- [Julia 1.12+](https://julialang.org/downloads/)

### Installation
Open your Julia REPL and run:

```julia
using Pkg
Pkg.add(url="https://github.com/sashakile/sxAct.git")
```

Wait for the installation to finish, then you can start using it:
```julia
using XAct
```

## 2. Python Wrapper (xact-py)

The Python wrapper provides an idiomatic interface to the Julia core. For the full verification framework, see [Developer Install](#3-developerverification-install).

### Prerequisites
- [Julia 1.12+](https://julialang.org/downloads/)
- Python 3.10+
- [uv](https://docs.astral.sh/uv/) (recommended)

### Installation
`xact-py` is published to PyPI. For most users, install the latest release with:

```bash
pip install xact-py
```

If you want the current unreleased `main` branch instead, install from a checkout of this repository:

```bash
git clone https://github.com/sashakile/sxAct.git
cd sxAct
uv pip install packages/xact-py
```

*Note: The wrapper automatically manages its Julia dependencies using `juliapkg`.*

---

## 3. Developer/Verification Install

The full suite includes a Python wrapper and a Dockerized Wolfram Oracle for proving implementation parity.

### Prerequisites
- [Julia 1.12+](https://julialang.org/downloads/)
- [uv](https://docs.astral.sh/uv/) (recommended) or Python 3.10+
- [Docker](https://www.docker.com/)

### Step A: Clone and Sync
```bash
git clone https://github.com/sashakile/sxAct.git
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
