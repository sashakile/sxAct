# Getting Started with xAct.jl

This guide walks through the basic usage of the `xAct.jl` library in Julia and the `sxact-py` verification suite in Python.

## Quick Start (Julia)

The primary interface for tensor calculus is the Julia package.

```julia
using xAct

# 1. Define a manifold
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

The Python wrapper allows researchers in the Python ecosystem to leverage the `xAct.jl` engines.

```python
from sxact import xAct

# Create a manifold and tensor
m = xAct.def_manifold("M", 4, ["a", "b"])
t = xAct.def_tensor("T", ["-a", "-b"], "M", symmetry="Symmetric")

# Perform canonicalization
result = xAct.to_canonical("T[-b, -a] - T[-a, -b]")
print(result)  # "0"
```

*Note: The Python high-level API is a current development focus. See the [Verification Guide](verification-tools.md) for low-level oracle comparison tools.*

## Key Concepts

-   **Symbol Registry**: `xAct.jl` maintains a global registry of manifolds, bundles, and tensors. Functions that modify this state end in `!` (e.g., `def_tensor!`).
-   **Indices**: We follow the standard xAct notation: `-a` for covariant (lower) and `a` for contravariant (upper) indices.
-   **Parity**: All operations in `xAct.jl` are verified against the Wolfram Language implementation to ensure mathematical correctness.

## Next Steps

-   **Installation**: See the [Installation Guide](installation.md) for local setup.
-   **Roadmap**: Check the [Feature Matrix](theory/STATUS.md) to see which xAct functions are currently supported.
-   **Architecture**: Learn about the multi-tier verification strategy in the [Architecture Guide](architecture.md).
