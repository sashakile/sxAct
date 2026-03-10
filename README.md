# sxAct — xAct Migration & Implementation

This repository is dedicated to the Julia implementation of the [xAct](http://xact.es/) suite and its Python wrapper. It provides the core tensor algebra engines and validation tooling to ensure mathematical parity with the Wolfram Language "Gold Standard."

## Project Scope

- Primary Goal: Migrate xAct's functionality (xCore, xPerm, xTensor, etc.) to Julia for high-performance, open-source tensor calculus.
- Python Access: Provide an idiomatic Python wrapper (sxact-py) around the Julia core.
- Validation: Use a Dockerized Wolfram Engine (the "Oracle") to prove implementation correctness.

### The Ecosystem Split

To maintain modularity and focus, this project is part of a three-pillar ecosystem:

1.  sxAct (This Repo): The Julia/Python implementations of xAct.
2.  [Elegua](https://github.com/sashakile/elegua) (External): The Orchestrator and multi-tier test harness.
3.  [Chacana](https://github.com/sashakile/chacana) (External): The language-agnostic Tensor DSL and specification.

---

## Quick Start

Prerequisites: Docker, Python >= 3.10, [uv](https://docs.astral.sh/uv/)

```bash
# Install Python dependencies
uv sync

# Start the Wolfram/xAct oracle server (for validation)
docker compose up -d

# Run tests
uv run pytest tests/
```

See [SETUP.md](SETUP.md) for first-time setup (Wolfram Engine activation, Docker configuration).

## Architecture

The implementation follows a layered approach:

1.  The [oracle](api/oracle.md) module communicates with a running Wolfram Engine.
2.  The [normalize](api/normalize.md) module canonicalizes xAct expressions.
3.  The [compare](api/compare.md) module asserts equivalence between implementations.

## License

`sxAct` is released under the **GNU General Public License v3.0 (GPL-3.0)**. See the [LICENSE](LICENSE) file for the full text.
