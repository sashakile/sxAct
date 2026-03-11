```@meta
EditURL = "../../examples/basics.jl"
```

# Getting Started with xAct.jl

This tutorial introduces the core concepts of `xAct.jl` and shows how to perform
basic tensor algebra operations. We also demonstrate how the same operations
look in Python using the `sxact` wrapper.

## 1. Setup
First, we load the `xAct` module (the Julia port of the xAct suite).

````@example basics
using xAct
````

We also load `PythonCall` to demonstrate the polyglot nature of the project.

````@example basics
using PythonCall
````

## 2. Defining a Manifold
In the original Wolfram xAct, you would use:
`DefManifold[M, 4, {a, b, c, d, e, f}]`

In `xAct.jl`, we use `def_manifold!`. The `!` indicates that this function
modifies the global session state.

````@example basics
M = def_manifold!(:M, 4, [:a, :b, :c, :d, :e, :f])
````

Let's check the dimension:

````@example basics
println("Manifold M dimension: ", Dimension(:M))
````

## 3. Defining Tensors
Now we define a symmetric rank-2 tensor $T_{ab}$.
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

## 5. The Python Bridge
`xAct.jl` is designed to be accessible from Python. Using `PythonCall.jl`,
we can see how a Python user would interact with the same core.

```python
import sxact
M = sxact.Manifold("M", 4)
T = sxact.Tensor("T", ["-a", "-b"], M, symmetry="Symmetric")
print(sxact.to_canonical("T[-b,-a] - T[-a,-b]"))
```

Note: The high-level Python API shown above is a goal for the next
development phase. Currently, the Python side is primarily used for
verification and testing.

## 6. Summary Table

| **DefManifold** | `DefManifold[M, 4, {a,b}]` | `def_manifold!(:M, 4, [:a, :b])` |
| **DefTensor** | `DefTensor[T[-a,-b], M]` | `def_tensor!(:T, ["-a", "-b"], :M)` |
| **ToCanonical** | `ToCanonical[expr]` | `ToCanonical(expr)` |

---

*This page was generated using [Literate.jl](https://github.com/fredrikekre/Literate.jl).*
