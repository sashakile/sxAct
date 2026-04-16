!!! tip "Run this notebook"
    Download the [Jupyter notebook](https://github.com/sashakile/XAct.jl/blob/main/notebooks/julia/basics.ipynb) or open it in Google Colab.

# sxAct.jl — Getting Started

> **Note:** Auto-generated from `notebooks/julia/basics.qmd` via Quarto.
> Edit the source `.qmd` file, not the `.ipynb`.

## Overview

This notebook walks through the core workflow of `xAct.jl`:
defining a spacetime manifold, adding a metric, computing curvature tensors,
and simplifying expressions using the Butler-Portugal canonicalization algorithm.

**Google Colab:** select *Runtime → Change runtime type → Julia*.

## 1. Setup

If running on Google Colab or a fresh environment, install the package first.
In the Docker image or a local dev checkout this cell is a no-op.

```julia
# Uncomment the lines below if running on Google Colab:
# using Pkg
# Pkg.add(url="https://github.com/sashakile/XAct.jl.git")

using xAct
```

## 2. Define a Manifold

A 4-dimensional spacetime manifold $M$ with abstract indices $a, b, c, d, e, f$.

```julia
reset_state!()
M = def_manifold!(:M, 4, [:a, :b, :c, :d, :e, :f])
```

## 3. Define a Metric

The metric $g_{ab}$ with Lorentzian signature $(-,+,+,+)$ and covariant
derivative $\nabla$ (called `CD` internally).
This automatically creates Riemann, Ricci, RicciScalar, Weyl, Einstein, and
Christoffel tensors.

```julia
g = def_metric!(-1, "g[-a,-b]", :CD)
```

## 4. Canonicalization

The Butler-Portugal algorithm brings tensor expressions into a canonical form.
For a symmetric metric, $g_{ba} - g_{ab} = 0$:

```julia
ToCanonical("g[-b,-a] - g[-a,-b]")
```

Define a symmetric rank-2 tensor $T_{ab}$ (e.g. the energy-momentum tensor):

```julia
def_tensor!(:T, ["-a", "-b"], :M; symmetry_str="Symmetric[{-a,-b}]")
ToCanonical("T[-b,-a] - T[-a,-b]")
```

## 5. Contraction

`Contract` lowers/raises indices via the metric. Define a vector $V^a$
and contract with the metric to get $V_b$:

```julia
def_tensor!(:V, ["a"], :M)
Contract("V[a] * g[-a,-b]")
```

## 6. Riemann Tensor Identities

The Riemann tensor has well-known symmetries that the canonicalizer
automatically recognizes:

First Bianchi identity — $R_{abcd} + R_{acdb} + R_{adbc} = 0$:

```julia
ToCanonical("RiemannCD[-a,-b,-c,-d] + RiemannCD[-a,-c,-d,-b] + RiemannCD[-a,-d,-b,-c]")
```

Antisymmetry in the first pair — $R_{abcd} + R_{bacd} = 0$:

```julia
ToCanonical("RiemannCD[-a,-b,-c,-d] + RiemannCD[-b,-a,-c,-d]")
```

Pair symmetry — $R_{abcd} = R_{cdab}$:

```julia
ToCanonical("RiemannCD[-a,-b,-c,-d] - RiemannCD[-c,-d,-a,-b]")
```

## 7. Perturbation Theory

Define a perturbation tensor $h_{ab}$ (symmetric, same slots as the metric)
and perturb the metric to first order:

```julia
def_tensor!(:h, ["-a", "-b"], :M; symmetry_str="Symmetric[{-a,-b}]")
def_perturbation!(:h, :g, 1)
perturb("g[-a,-b]", 1)
```

## 8. Typed Expression API

The string API works well but mistakes — wrong index count, wrong manifold — only
surface inside the engine. The `TExprLayer` module adds typed index objects and
operator overloading that catch these errors at construction time.

### Index declarations

```julia
# @indices binds typed Idx variables to manifold M.
@indices M a b c d e f
# a = Idx(:a, :M), -a = DnIdx(:a, :M)
```

### Tensor handles

```julia
# tensor() looks up a registered name and returns a TensorHead.
Riem = tensor(:RiemannCD)
gT   = tensor(:g)
T_h  = tensor(:T)
```

### Building expressions

```julia
# Riemann first Bianchi identity — three ways to write the same thing:

# 1. String API (original)
ToCanonical("RiemannCD[-a,-b,-c,-d] + RiemannCD[-a,-c,-d,-b] + RiemannCD[-a,-d,-b,-c]")

# 2. Typed API — equivalent, validated at construction
expr = Riem[-a,-b,-c,-d] + Riem[-a,-c,-d,-b] + Riem[-a,-d,-b,-c]
ToCanonical(expr)

# 3. Arithmetic — scalar multiplication, subtraction
pair_sym = Riem[-a,-b,-c,-d] - Riem[-c,-d,-a,-b]
ToCanonical(pair_sym)
```

### Validation errors

```julia
# Wrong slot count — raised immediately, not inside the engine
try
    Riem[-a,-b]     # ERROR: RiemannCD has 4 slots, got 2
catch e
    println(e)
end
```

### Covariant derivatives

```julia
CD_h = covd(:CD)
phi  = tensor(:phi)    # assuming phi is a registered scalar

# CD[-a](phi[]) builds a TCovD node
deriv = CD_h[-a](phi[])
println(deriv)   # "CD[-a][phi[]]"
```

## Next Steps

- **Coordinate components (xCoba):** assign a basis, compute Christoffel symbols numerically
- **Covariant derivatives:** commute CovDs, integration by parts
- **Invariant simplification:** `RiemannSimplify` for scalar polynomial identities
- Full documentation: [sashakile.github.io/sxAct](https://sashakile.github.io/sxAct/)
