```@meta
EditURL = "../../examples/basics.jl"
```

# Basics Tutorial

This tutorial introduces the core concepts of `xAct.jl` and shows how to perform
basic tensor algebra operations.

## 1. Setup
First, we load the `xAct` module (the Julia port of the xAct suite).

````@example basics
using xAct
````

Reset global state so the example is safe to re-run.

````@example basics
reset_state!()
````

## 2. Defining a Manifold
In General Relativity, our spacetime is represented as a manifold.
In the original Wolfram xAct, you would use:
`DefManifold[M, 4, {a, b, c, d, e, f}]`

In `xAct.jl`, we use `def_manifold!`. The `!` indicates that this function
modifies the global session state.

````@example basics
M = def_manifold!(:M, 4, [:a, :b, :c, :d, :e, :f])
````

Let's check the dimension of the manifold:

````@example basics
println("Manifold M dimension: ", Dimension(:M))
````

## 3. Defining Tensors
Now we define a symmetric rank-2 tensor $T_{ab}$. This could represent
the energy-momentum tensor $T_{\mu\nu}$.
In Wolfram: `DefTensor[T[-a, -b], M, Symmetric[{-a, -b}]]`

````@example basics
T = def_tensor!(:T, ["-a", "-b"], :M; symmetry_str="Symmetric[{-a,-b}]")
````

## 4. Canonicalization
One of the most powerful features of xAct is its ability to canonicalize
tensor expressions using the Butler-Portugal algorithm.

Consider the expression $T_{ba} - T_{ab}$. Since $T$ is symmetric, this
should be zero.

````@example basics
expr = "T[-b, -a] - T[-a, -b]"
canonical = ToCanonical(expr)
println("Canonical form of '$expr': ", canonical)
````

## 5. Defining a Metric
The metric tensor $g_{ab}$ is fundamental to defining geometry and curvature.
In Wolfram: `DefMetric[-1, g[-a, -b], CD]`

````@example basics
g = def_metric!(-1, "g[-a,-b]", :CD)
println("Metric g defined with signature -1.")
````

## 6. Common Pitfalls & Fail-States
- **Name Collisions**: If you try to define a manifold or tensor with a name
  that already exists, `xAct.jl` will throw an error. Use `ValidateSymbolInSession(:Name)`
  to check before defining.
- **Index Mismatch**: Ensure your tensor indices match the dimension of the
  manifold. Defining a rank-3 tensor on a 2D manifold is allowed, but
  contracting them incorrectly will fail.
- **Global State**: The `!` in `def_manifold!` and `def_tensor!` means they
  modify the global session. If you are in a notebook, re-running a cell
  containing these might trigger a "Symbol already exists" error.

## 7. Next Steps
Now that you've mastered the basics, check out:
- [Differential Geometry Primer](../differential-geometry-primer.md)
- [Feature Status](../theory/STATUS.md)

---

*This page was generated using [Literate.jl](https://github.com/fredrikekre/Literate.jl).*
