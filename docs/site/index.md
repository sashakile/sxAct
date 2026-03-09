# sxAct

Julia and Python implementations of xAct — a powerful tensor algebra library for general relativity.

## Project Overview

The sxAct repository contains the core high-performance Julia implementation of xAct's tensor calculus engines, along with a comprehensive Python wrapper. It is designed to bridge the gap between the Wolfram Language "Gold Standard" and the modern, open-source scientific computing ecosystem.

### Three Pillars of the Migration

To maintain focus and scalability, the migration effort is divided into three distinct, interoperable projects:

1.  [sxAct](https://github.com/sashakile/sxAct) (This Repo): The native Julia core and Python wrapper implementations.
2.  [Elegua](https://github.com/sashakile/elegua) (External): The orchestration layer and multi-tier test harness used to verify implementation parity against the Wolfram Oracle.
3.  [Chacana](https://github.com/sashakile/chacana) (External): The language-agnostic tensor DSL and specification that connects the different tools.

## Key Features

- XCore.jl / XPerm.jl / XTensor.jl: Native Julia ports of the foundational xAct packages.
- sxact-py: A high-level Python API for research and simulation.
- Verification-First: Integrated tools to compare results against a Dockerized Wolfram Engine (Oracle) to ensure mathematical correctness.

## Quick Start

```bash
# Install dependencies
uv sync

# Start the oracle server (for validation)
docker compose up -d

# Run tests
uv run pytest tests/
```

See [Installation](installation.md) for full setup, or [Getting Started](getting-started.md) for your first computation.

## Architecture

The implementation follows a layered approach:

1.  The [oracle](api/oracle.md) module communicates with a running Wolfram Engine.
2.  The [normalize](api/normalize.md) module canonicalizes xAct expressions.
3.  The [compare](api/compare.md) module asserts equivalence between implementations.
