# Getting Started with xAct.jl

This guide walks through the basic usage of the `xAct.jl` library in Julia and the `sxact-py` verification suite in Python.

## Quick Start (Julia)

The primary interface for tensor calculus is the Julia package.

```julia
using xAct

# 1. Define a manifold
# Note: index labels must be symbols
M = def_manifold!(:M, 4, [:a, :b, :c, :d])

# 2. Define a symmetric tensor
T = def_tensor!(:T, ["-a", "-b"], :M; symmetry_str="Symmetric[{-a,-b}]")

# 3. Canonicalize an expression
# Since T is symmetric, T_{ba} - T_{ab} should be zero.
result = ToCanonical("T[-b, -a] - T[-a, -b]")
println(result)  # "0"
```

For a more detailed tutorial, see the [Basics Tutorial](examples/basics.md).

## Quick Start (Python)

*Note: The high-level Python user API is currently in development. For now, researchers can access the Julia engine via the `JuliaAdapter` in the `sxact` framework.*

```python
from sxact.adapter.julia_stub import JuliaAdapter

# Initialize the Julia engine
adapter = JuliaAdapter()
adapter.initialize()

# Define a manifold and tensor
adapter.execute("def_manifold", {"name": "M", "dim": 4, "index_labels": ["a", "b"]})
adapter.execute("def_tensor", {"name": "T", "index_specs": ["-a", "-b"], "manifold": "M", "symmetry_str": "Symmetric[{-a,-b}]"})

# Perform canonicalization
result = adapter.execute("ToCanonical", {"expr": "T[-b, -a] - T[-a, -b]"})
print(result.result)  # "0"
```

See the [Verification Guide](verification-tools.md) for details on comparing these results against the Wolfram Oracle.

## Key Concepts

-   **Symbol Registry**: `xAct.jl` maintains a global registry of manifolds, bundles, and tensors. Functions that modify this state end in `!` (e.g., `def_tensor!`).
-   **Indices**: We follow the standard xAct notation: `-a` for covariant (lower) and `a` for contravariant (upper) indices.
-   **Parity**: All operations in `xAct.jl` are verified against the Wolfram Language implementation to ensure mathematical correctness.

## Next Steps

-   **Installation**: See the [Installation Guide](installation.md) for local setup.
-   **Roadmap**: Check the [Feature Matrix](theory/STATUS.md) to see which xAct functions are currently supported.
-   **Architecture**: Learn about the multi-tier verification strategy in the [Architecture Guide](architecture.md).
