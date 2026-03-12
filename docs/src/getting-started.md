# Getting Started with xAct.jl

This tutorial walks through the basic usage of `xAct.jl` in Julia and provides a reference "Rosetta Stone" for users migrating from the original Wolfram implementation.

!!! info "Prerequisites"
    Ensure you have installed `xAct.jl` according to the [Installation Guide](installation.md) before starting this tutorial.

---

## 1. Interactive Tutorial (Julia)

The primary interface for tensor calculus is the Julia REPL or a Jupyter notebook.

```julia
using xAct

# 1. Define a manifold
# In Julia, we use symbols (e.g., :M) for object names.
M = def_manifold!(:M, 4, [:a, :b, :c, :d])

# 2. Define a symmetric tensor
# Syntax: def_tensor!(name, indices, manifold; options...)
T = def_tensor!(:T, ["-a", "-b"], :M; symmetry_str="Symmetric[{-a,-b}]")

# 3. Canonicalize an expression
# Since T is symmetric, T_{ba} - T_{ab} should be zero.
result = ToCanonical("T[-b, -a] - T[-a, -b]")
println(result)  # "0"
```

For a more detailed, step-by-step walkthrough, see the [Basics Tutorial](examples/basics.md).

---

## 2. Reference: Migration Rosetta Stone

For experienced `xAct` users, this table shows the direct mappings from Wolfram Language to Julia.

| Operation | Wolfram (xAct) | Julia (xAct.jl) | Status |
| :--- | :--- | :--- | :--- |
| **DefManifold** | `DefManifold[M, 4, {a,b}]` | `def_manifold!(:M, 4, [:a, :b])` | ✅ Verified |
| **DefTensor** | `DefTensor[T[-a,-b], M]` | `def_tensor!(:T, ["-a", "-b"], :M)` | ✅ Verified |
| **DefMetric** | `DefMetric[-1, g[-a,-b], CD]` | `def_metric!(-1, "g[-a,-b]", :CD)` | ✅ Verified |
| **ToCanonical** | `ToCanonical[expr]` | `ToCanonical(expr)` | ✅ Verified |
| **Contract** | `ContractMetric[expr]` | `Contract(expr)` | 🏗️ Beta |
| **IBP** | `IBP[expr, CD]` | `IBP(expr, :CD)` | 🗓️ Planned |

---

## 3. Core Concepts

- **Symbol Registry**: `xAct.jl` maintains a global registry of manifolds, bundles, and tensors. Functions that modify this state end in `!` (e.g., `def_tensor!`).
- **Indices**: We follow the standard xAct notation: `-a` for covariant (lower) and `a` for contravariant (upper) indices.
- **Parity Verification**: Every operation in `xAct.jl` is mathematically proven to be identical to the Wolfram implementation through automated Docker-based tests.

## 4. Using Python for Verification

*Note: The high-level Python API is currently in development. For now, the Python framework is used primarily for verification. See the [Python API Reference](api-python.md) for details.*

```python
from sxact.adapter.julia_stub import JuliaAdapter

# Connect to the Julia engine
adapter = JuliaAdapter()
adapter.initialize()

# Define a manifold and tensor
adapter.execute("def_manifold", {"name": "M", "dim": 4, "index_labels": ["a", "b"]})
result = adapter.execute("ToCanonical", {"expr": "T[-b, -a] - T[-a, -b]"})
```

## Next Steps

- **Installation**: See the [Installation Guide](installation.md) for local setup.
- **Status Dashboard**: Check the [Feature Matrix](theory/STATUS.md) to see which functions are ready for production use.
