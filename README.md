# sxAct - xAct Migration Experiments

Repositorio para experimentar la migración de la librería xAct de Wolfram a otro lenguaje abierto.

**xAct** is a tensor algebra and differential geometry package for Wolfram Language. This repository explores porting its functionality to open-source ecosystems (Julia, Python).

## Quick Start

**Prerequisites:** Docker

```bash
# Clone and enter repository
cd sxAct

# Activate Wolfram Engine (first time only)
docker compose run --rm wolfram wolframscript -activate

# Run the test example
docker compose run --rm wolfram wolframscript -file /notebooks/test_xact.wls
```

See [SETUP.md](SETUP.md) for complete installation and usage guide.

## What's Included

- ✅ Wolfram Engine 14.3.0 (Docker-based, persistent license)
- ✅ xAct 1.2.0 library (fully extracted)
- ✅ Python environment with Wolfram Client
- ✅ Julia 1.12.3 (MathLink setup pending)
- ✅ Example scripts and documentation

## Project Goals

1. **Explore xAct capabilities** - Document tensor algebra workflows
2. **Test interoperability** - Julia/Python calling Wolfram/xAct via MathLink
3. **Identify migration paths** - Evaluate Julia/Python tensor packages
4. **Build prototypes** - Implement xAct functionality in open-source languages

## Repository Structure

```
sxAct/
├── docker-compose.yml          # Wolfram Engine setup
├── SETUP.md                    # Complete setup guide
├── dump-session.md             # Session notes template
├── notebooks/                  # Example scripts
│   ├── test_xact.wls          # xAct demo
│   └── test_python_wolfram.py # Python example
├── sessions/                   # Session notes
│   └── 2026-01-08-initial-setup.md
└── resources/
    └── xAct/                   # xAct 1.2.0 library
```

## Resources

- [xAct Homepage](http://xact.es/) - Official documentation
- [Wolfram Engine](https://www.wolfram.com/engine/) - Free for non-production use
- [MathLink.jl](https://github.com/JuliaInterop/MathLink.jl) - Julia ↔ Wolfram
- [Wolfram Client for Python](https://reference.wolfram.com/language/WolframClientForPython/) - Python ↔ Wolfram

## Next Steps

See `sessions/2026-01-08-initial-setup.md` for current progress and planned experiments.