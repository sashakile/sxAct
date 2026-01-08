# sxAct Setup Guide

This repository contains tools for experimenting with the xAct library (Wolfram Language tensor algebra package) and exploring migration to open-source languages.

## ✅ Completed Setup

### 1. Wolfram Engine (via Docker)
- **Image**: wolframresearch/wolframengine:latest (v14.3.0)
- **Status**: Activated and ready to use
- **xAct**: v1.2.0 mounted at `/opt/xAct` in container

### 2. Python Environment
- **Python**: 3.10.19 (managed by uv)
- **Wolfram Client**: v1.4.0 installed
- **Virtual env**: `.venv/` (created by uv)

### 3. Julia
- **Version**: 1.12.3
- **MathLink**: Not yet configured (optional)

## Usage

### Running Wolfram with xAct

**Option 1: Using docker compose directly**
```bash
# Interactive session
docker compose run --rm wolfram wolframscript

# Run a script
docker compose run --rm wolfram wolframscript -file notebooks/test_xact.wls

# Execute code directly
docker compose run --rm wolfram wolframscript -code "AppendTo[\$Path, \"/opt\"]; Needs[\"xAct\`xTensor\`\"]; Print[\"Hello xAct!\"]"
```

**Option 2: Using the helper script** (coming soon)
```bash
./wolfram.sh -file notebooks/test_xact.wls
```

### Python with Wolfram Client

Activate the virtual environment:
```bash
source .venv/bin/activate
# or with uv
uv run python notebooks/test_python_wolfram.py
```

### Loading xAct packages

In any Wolfram script, add xAct to the path first:
```wolfram
AppendTo[$Path, "/opt"];
Needs["xAct`xTensor`"];  (* Main tensor package *)
Needs["xAct`xCoba`"];    (* Coordinate-based calculations *)
Needs["xAct`xPert`"];    (* Perturbation theory *)
```

## Available xAct Packages

Located in `resources/xAct/`:
- **xCore**: Core functionality
- **xPerm**: Permutation handling
- **xTensor**: Tensor algebra (main package)
- **xCoba**: Coordinate-based tensor calculations
- **xPert**: Perturbation theory
- **Spinors**: Spinor calculus
- **Invar**: Invariant computations
- **Harmonics**: Harmonic analysis
- **xTras**: Additional utilities
- And more...

## Project Structure

```
sxAct/
├── docker-compose.yml          # Docker setup with Wolfram Engine
├── pyproject.toml              # Python dependencies (uv)
├── .venv/                      # Python virtual environment
├── wolfram.sh                  # Helper script for Wolfram
├── notebooks/                  # Example scripts
│   ├── test_xact.wls          # xAct test script
│   └── test_python_wolfram.py # Python example
└── resources/
    └── xAct/                   # xAct library v1.2.0
```

## Next Steps

### Optional: Julia with MathLink
To enable Julia interoperability:
```bash
julia
] add MathLink
```

### Optional: Direct Wolfram Engine Installation
If you prefer not to use Docker, download and install Wolfram Engine directly:
- https://www.wolfram.com/engine/
- Free license available for non-production use

## Troubleshooting

### Wolfram Engine not activated
If you see activation errors, run:
```bash
docker compose run --rm wolfram wolframscript -activate
```

### xAct not loading
Ensure you add `/opt` to the path before loading xAct:
```wolfram
AppendTo[$Path, "/opt"];
```

### Permission issues
The docker-compose setup runs as root inside the container. Files created in mounted volumes may have root ownership.

## Resources

- xAct homepage: http://xact.es/
- Wolfram Engine docs: https://www.wolfram.com/engine/
- Wolfram Client for Python: https://reference.wolfram.com/language/WolframClientForPython/
- MathLink.jl: https://github.com/JuliaInterop/MathLink.jl
