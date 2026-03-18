# Getting Started with xAct.jl

!!! info "LLM TL;DR"
    - Install: `Pkg.add(url="https://github.com/sashakile/sxAct")`
    - Julia entry point: `using xAct`, then `def_manifold!`, `def_metric!`, `@indices`, `tensor()`
    - Typed API recommended; string API (`ToCanonical("expr")`) works everywhere
    - Python: `import xact`, snake_case wrappers, same semantics as Julia

This guide covers installation, quick-start usage for Julia and Python, and a
Wolfram-to-Julia migration reference.

---

## 1. Installation (Julia)

Open the Julia REPL and run:

```julia
using Pkg
Pkg.add(url="https://github.com/sashakile/sxAct")
```

!!! note "Julia General Registry"
    `xAct.jl` is not yet registered in the Julia General Registry (planned for a future release).
    Until then, install via the GitHub URL above.


For Python installation, see [Installation Guide](installation.md).

---

## 2. Quick Start (Julia)

The primary interface is the REPL or a Jupyter notebook.
The **typed API** is the recommended workflow: it validates your expressions at
construction time and integrates with standard Julia operator syntax.

```julia
using xAct

reset_state!()
def_manifold!(:M, 4, [:a, :b, :c, :d])
def_tensor!(:T, ["-a", "-b"], :M; symmetry_str="Symmetric[{-a,-b}]")

@indices M a b c d       # declare typed index variables
T_h = tensor(:T)         # look up registered tensor handle

# T is symmetric — T_{ba} - T_{ab} = 0
ToCanonical(T_h[-b,-a] - T_h[-a,-b])   # "0"
```

### Typed API vs. String API

Both APIs are fully supported and can be mixed freely:

| | Typed API | String API |
|---|---|---|
| **Syntax** | `T_h[-b,-a] - T_h[-a,-b]` | `"T[-b,-a] - T[-a,-b]"` |
| **Slot validation** | Error at construction | Error inside engine |
| **Manifold check** | Error at index creation | Not checked |
| **IDE support** | Tab-completion on tensor heads | None |
| **Composability** | `expr1 + expr2` with operators | String concatenation |

The typed API serializes to strings internally — the same engine runs either way.

!!! tip "When to use which"
    Use the **typed API** for interactive work and new code.
    The **string API** is convenient for short one-liners and when pasting
    expressions from the Wolfram documentation.

For a detailed guide including covariant derivatives and Python, see
[Typed Expressions (TExpr)](guide/TExpr.md).

### With a Metric

Defining a metric automatically creates the associated curvature tensors
(Riemann, Ricci, RicciScalar, Weyl, Einstein, Christoffel).

```julia
reset_state!()
def_manifold!(:M, 4, [:a, :b, :c, :d, :e, :f])
def_metric!(-1, "g[-a,-b]", :CD)

@indices M a b c d e f
Riem = tensor(:RiemannCD)

# First Bianchi identity
ToCanonical(Riem[-a,-b,-c,-d] + Riem[-a,-c,-d,-b] + Riem[-a,-d,-b,-c])   # "0"

# Pair symmetry
ToCanonical(Riem[-a,-b,-c,-d] - Riem[-c,-d,-a,-b])   # "0"
```

---

## 3. Quick Start (Python)

The `xact` Python package provides a snake-case API that wraps the Julia core.
All the same concepts apply: define a manifold and tensor, then use operator syntax.

```python
import xact

xact.reset()
M = xact.Manifold("M", 4, ["a", "b", "c", "d"])
T = xact.Tensor("T", ["-a", "-b"], M, symmetry="Symmetric[{-a,-b}]")

# xact.indices(M) returns one Idx object per label registered on M
a, b, c, d = xact.indices(M)    # typed index objects
T_h = xact.tensor("T")          # tensor handle (same role as Julia tensor(:T))

xact.canonicalize(T_h[-b,-a] - T_h[-a,-b])   # "0"
```

For a full walkthrough, see the [Python notebook](https://github.com/sashakile/sxAct/blob/main/notebooks/python/basics.ipynb).

---

## 4. Reference: Migration Rosetta Stone

For experienced `xAct` users, this table shows direct mappings from Wolfram Language to Julia.

| Operation | Wolfram (xAct) | Julia (xAct.jl) | Status |
| :--- | :--- | :--- | :--- |
| **DefManifold** | `DefManifold[M, 4, {a,b}]` | `def_manifold!(:M, 4, [:a, :b])` | ✅ Verified |
| **DefTensor** | `DefTensor[T[-a,-b], M]` | `def_tensor!(:T, ["-a", "-b"], :M)` | ✅ Verified |
| **DefMetric** | `DefMetric[-1, g[-a,-b], CD]` | `def_metric!(-1, "g[-a,-b]", :CD)` | ✅ Verified |
| **ToCanonical** | `ToCanonical[expr]` | `ToCanonical(expr)` | ✅ Verified |
| **Contract** | `ContractMetric[expr]` | `Contract(expr)` | ✅ Verified |
| **Simplify** | `Simplification[expr]` | `Simplify(expr)` | ✅ Verified |
| **RiemannSimplify** | `RiemannSimplify[expr, CD]` | `RiemannSimplify(expr, :CD)` | ✅ Verified |
| **RiemannToPerm** | `RiemannToPerm[expr]` | `RiemannToPerm(expr)` | ✅ Verified |
| **CommuteCovDs** | `SortCovDs[expr]` | `CommuteCovDs(expr)` | ✅ Verified |
| **IBP** | `IBP[expr, v]` | `IBP(expr, :CD)` | ✅ Verified |
| **VarD** | `VarD[field][CD]expr` | `VarD(expr, :field, :CD)` | ✅ Verified |
| **Perturbation** | `Perturbation[expr]` | `Perturb(expr)` | ✅ Verified |

---

## Next Steps

- **Typed API deep dive**: See [Typed Expressions (TExpr)](guide/TExpr.md) for validation rules, covariant derivatives, and the Python typed API.
- **Core Concepts**: See [Key Concepts](concepts.md) for details on the symbol registry.
- **Migrating from Wolfram?**: See the [Wolfram Migration Guide](wolfram-migration.md) for the expression translator and REPL.
- **Verification**: Learn how we ensure mathematical correctness in the [Verification Framework Guide](verification-tools.md).
- **Status Dashboard**: Check the [Feature Matrix](theory/STATUS.md) to see which functions are ready for production use.
