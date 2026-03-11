# Installation

This guide covers how to install the `xAct.jl` Julia package and the optional Python verification framework.

## 1. Julia Package Installation (xAct.jl)

`xAct.jl` is the primary high-performance tensor calculus engine.

### Prerequisites
- [Julia 1.10+](https://julialang.org/downloads/)

### Installation via GitHub (Development)
Since `xAct.jl` is currently in active migration, you can add it directly from the repository:

```julia
using Pkg
Pkg.add(url="https://github.com/sashakile/sxAct.git", subdir="src/julia")
```

## 2. Python Verification Framework (sxact-py)

The Python framework is used for cross-verifying `xAct.jl` against the Wolfram "Gold Standard" using the Oracle server.

### Prerequisites
- [uv](https://docs.astral.sh/uv/) (recommended) or Python 3.10+
- [Docker](https://www.docker.com/) (for the Oracle server)

### Setup with uv
```bash
git clone https://github.com/sashakile/sxAct.git
cd sxAct
uv sync
```

> **Note on Naming**: When defining manifolds or tensors, ensure you choose names that do not collide with built-in Julia or Base exports (e.g., avoid `:Base`, `:map`, or `:log`).

### Activation of the Wolfram Oracle
The verification suite requires a Dockerized Wolfram Engine. You must activate it once:

```bash
docker compose run --rm wolfram wolframscript -activate
```
*(Requires a free [Wolfram ID](https://account.wolfram.com/auth/create) for non-production use)*.

## 3. Starting the Oracle Server

To run the verification tests or compare your Julia results against xAct in Mathematica:

```bash
docker compose up -d oracle
```

Wait for the health check to pass (~30–60 seconds):
```bash
curl http://localhost:8765/health
```

## 4. Verification

To ensure your installation is working correctly, run the test suite:

```bash
# Run all tests (requires Docker oracle)
uv run pytest
```

## Troubleshooting

### Julia: "Package xAct not found"
Ensure you are using the correct environment. If you installed it globally, `using xAct` should work. If you are developing, use `julia --project=.` and ensure `xAct` is in your `Project.toml`.

### Python: "No valid license found"
This happens if the Wolfram Engine in Docker is not activated. Re-run Step 2 (Activation).

### Oracle: "Connection refused"
Ensure the Docker container is running: `docker compose ps`. If it is unhealthy, check the logs: `docker compose logs oracle`.
