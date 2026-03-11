# xAct.jl

Julia and Python implementations of xAct — a powerful tensor algebra library for general relativity.

## Project Overview

The `xAct.jl` project (hosted in the `sxAct` repository) contains the core high-performance Julia implementation of xAct's tensor calculus engines, along with a comprehensive Python wrapper. It is designed to bridge the gap between the Wolfram Language "Gold Standard" and the modern, open-source scientific computing ecosystem.

### Three Pillars of the Migration

To maintain focus and scalability, the migration effort is divided into three distinct, interoperable projects:

1.  **xAct.jl** (This Repo): The native Julia core and Python wrapper implementations.
2.  **[Elegua](https://github.com/sashakile/elegua)** (External): The orchestration layer used to verify implementation parity against the **Wolfram Oracle** (a Dockerized Wolfram Engine).
3.  **[Chacana](https://github.com/sashakile/chacana)** (External): The language-agnostic tensor DSL and specification.

## Key Features

- **XCore.jl / XPerm.jl / XTensor.jl**: Native Julia ports of the foundational xAct packages.
- **Verification-First**: Integrated tools to compare results against the Wolfram Oracle.
- **High Performance**: Leverages Julia's JIT compilation for fast tensor operations.

## Migration Rosetta Stone

| Operation | Wolfram (xAct) | Julia (xAct.jl) |
| :--- | :--- | :--- |
| **DefManifold** | `DefManifold[M, 4, {a,b}]` | `def_manifold!(:M, 4, [:a, :b])` |
| **DefTensor** | `DefTensor[T[-a,-b], M]` | `def_tensor!(:T, ["-a", "-b"], :M)` |
| **DefMetric** | `DefMetric[-1, g[-a,-b], CD]` | `def_metric!(-1, "g[-a,-b]", :CD)` |
| **ToCanonical** | `ToCanonical[expr]` | `ToCanonical(expr)` |
| **Contract** | `ContractMetric[expr]` | `Contract(expr)` |

## Quick Start

```julia
using xAct
M = def_manifold!(:M, 4, [:a, :b])
T = def_tensor!(:T, ["-a", "-b"], :M, symmetry_str="Symmetric[{-a,-b}]")
ToCanonical("T[-b,-a] - T[-a,-b]") # returns "0"
```

For more detailed examples, see our [Getting Started Guide](getting-started.md) and [Basics Tutorial](examples/basics.md).

## Installation

See the [Installation Guide](installation.md) for details on setting up the Julia package and the Python verification environment.

## Architecture

The implementation follows a layered approach, described in the [Architecture](architecture.md) section.
