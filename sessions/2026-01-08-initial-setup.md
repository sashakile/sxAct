# Session: 2026-01-08 - Initial Setup

## Current Progress

✅ **Completed:**
- Explored repository structure and understood project goals
- Extracted xAct 1.2.0 library from tarball
- Set up Docker-based Wolfram Engine (v14.3.0)
- Activated Wolfram Engine license with persistent Docker volume
- Created Python virtual environment with uv
- Installed Wolfram Client for Python (v1.4.0)
- Successfully tested xAct loading in Wolfram Engine container
- Created docker-compose configuration for reproducible setup
- Generated example scripts and documentation

## Learnings

### Wolfram Engine & xAct
- xAct requires adding `/opt` to `$Path` before loading packages
- Main packages: xCore (base), xPerm (permutations), xTensor (tensor algebra)
- xTensor automatically defines manifolds, metrics, and curvature tensors
- Some compatibility warnings with Wolfram Engine 14.3.0 but packages work

### Docker Setup
- Wolfram license activation in Docker requires persistent volumes
- Docker compose volumes preserve activation between container runs
- Volume name: `sxact_wolfram-config` stores license data
- Must run as root user in container for license access

### Python Environment
- Used `uv` package manager for modern Python dependency management
- Wolfram Client for Python installed with 19 dependencies
- Python 3.10.19 selected by uv for compatibility

## Issues & Solutions

**Issue 1: xAct not loading initially**
- Problem: `Needs["xAct\`xCore\`"]` failed to find package
- Solution: Add `/opt` (not `/opt/xAct`) to `$Path` before loading
- Root cause: Wolfram looks for `xAct/xCore/Kernel/init.m` from path entries

**Issue 2: Wolfram license not persisting**
- Problem: Activation lost when container stopped
- Solution: Created named Docker volume `wolfram-config` mounted at `/root/.WolframEngine`
- Alternative tried: Host directory mount had permission issues

**Issue 3: Homebrew cask macOS-only**
- Problem: `brew install --cask wolfram-engine` failed on Linux
- Solution: Used official Docker image `wolframresearch/wolframengine` instead

**Issue 4: Docker compose version warning**
- Problem: `version` field obsolete in docker-compose.yml
- Solution: Removed version field (now optional in modern compose)

## Code Examples

### Loading xAct in Wolfram
```wolfram
(* Add xAct to path *)
AppendTo[$Path, "/opt"];

(* Load main tensor package *)
Needs["xAct`xTensor`"];

(* Define a 4D manifold *)
DefManifold[M4, 4, {μ, ν, ρ, σ}];

(* Define metric *)
DefMetric[-1, g[-μ, -ν], CD, {";", "∇"}];
```

### Running Wolfram with Docker Compose
```bash
# Interactive session
docker compose run --rm wolfram wolframscript

# Run script
docker compose run --rm wolfram wolframscript -file /notebooks/test_xact.wls

# Execute code
docker compose run --rm wolfram wolframscript -code "AppendTo[\$Path, \"/opt\"]; Needs[\"xAct\`xCore\`\"]"
```

## Configuration Changes

**Files Created:**
- `docker-compose.yml` - Wolfram Engine service with volumes
- `pyproject.toml` - Python dependencies (uv managed)
- `.venv/` - Python virtual environment
- `wolfram.sh` - Helper script for Wolfram commands
- `SETUP.md` - Complete setup documentation
- `notebooks/test_xact.wls` - Working xAct example
- `notebooks/test_python_wolfram.py` - Python template
- `.gitignore` - Python, Wolfram, IDE files
- `sessions/` - Session notes directory

**Packages Installed:**
- Python: wolframclient==1.4.0 + dependencies
- Julia: v1.12.3 (pre-installed, MathLink pending)

**Docker Volumes:**
- `sxact_wolfram-config` - Persistent Wolfram license

## Migration Notes

### Current State
- xAct is a pure Wolfram Language library
- No direct Julia/Python equivalents exist
- Main functionality: symbolic tensor algebra and differential geometry

### Potential Approaches
1. **Wrapper approach**: Use MathLink/Wolfram Client to call xAct from Julia/Python
2. **Port approach**: Reimplement xAct algorithms in SymPy/TensorFlow/Julia
3. **Hybrid approach**: Core symbolic engine in Julia/Python, call Wolfram for complex operations

### Packages to Explore
- Julia: `TensorOperations.jl`, `AbstractTensors.jl`, `Manifolds.jl`
- Python: `SymPy`, `einsteinpy`, `diffeqpy`

## Next Steps

1. **Test MathLink.jl with Julia**
   - Install MathLink package in Julia
   - Test calling Wolfram Engine from Julia REPL
   - Try loading xAct from Julia

2. **Explore Python Wolfram Client**
   - Set up Wolfram Kernel server for network access
   - Test remote evaluation from Python
   - Try xAct operations via Python client

3. **Document xAct Functionality**
   - Create examples of common xAct operations
   - Document tensor algebra workflows
   - Identify core features needed in migration

4. **Research Existing Alternatives**
   - Survey Julia tensor packages
   - Test SymPy tensor capabilities
   - Compare feature sets with xAct

5. **Create Benchmarks**
   - Simple tensor calculations in xAct
   - Implement same in Julia/Python candidates
   - Compare syntax, performance, capabilities
