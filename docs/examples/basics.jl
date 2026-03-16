# # Basics Tutorial
#
# This tutorial introduces the core concepts of `xAct.jl` and shows how to perform
# basic tensor algebra operations. We provide examples in **Julia**, **Python**,
# and the original **Wolfram Language (xAct)** to help with migration.

# ## 1. Setup
# First, we load the `xAct` module. In Julia, this is the native port. In Python,
# we use the `xact-py` wrapper which manages the Julia runtime transparently.

# **Julia**
using xAct
reset_state!()

# **Python**
# ```python
# from xact.xcore import reset_state
# # Note: xTensor/xCoba Python wrappers are coming soon.
# # For now, use juliacall to access Julia functions directly:
# from xact.xcore import get_julia
# jl = get_julia()
# jl.xAct.reset_state_b()
# ```

# ## 2. Defining a Manifold
# In General Relativity, our spacetime is represented as a manifold.
# In `xAct.jl`, we use `def_manifold!`. The `!` indicates that this function
# modifies the global session state.

# **Julia**
M = def_manifold!(:M, 4, [:a, :b, :c, :d, :e, :f])

# **Python**
# ```python
# # Using juliacall bridge:
# M = jl.xAct.def_manifold_b("M", 4, ["a", "b", "c", "d", "e", "f"])
# ```

# **Wolfram (xAct)**
# ```wolfram
# DefManifold[M, 4, {a, b, c, d, e, f}]
# ```

# Let's check the dimension of the manifold:
# **Julia**
println("Manifold M dimension: ", Dimension(:M))

# **Python**
# ```python
# print("Manifold M dimension:", jl.xAct.Dimension("M"))
# ```

# **Wolfram (xAct)**
# ```wolfram
# Dimension[M]
# ```

# ## 3. Defining Tensors
# Now we define a symmetric rank-2 tensor $T_{ab}$.
#
# **Julia**
T = def_tensor!(:T, ["-a", "-b"], :M; symmetry_str="Symmetric[{-a,-b}]")

# **Python**
# ```python
# T = jl.xAct.def_tensor_b("T", ["-a", "-b"], "M", symmetry_str="Symmetric[{-a,-b}]")
# ```

# **Wolfram (xAct)**
# ```wolfram
# DefTensor[T[-a, -b], M, Symmetric[{-a, -b}]]
# ```

# ## 4. Canonicalization
# One of the most powerful features of xAct is its ability to canonicalize
# tensor expressions using the Butler-Portugal algorithm.
#
# Consider the expression $T_{ba} - T_{ab}$. Since $T$ is symmetric, this
# should be zero.

# **Julia**
expr = "T[-b, -a] - T[-a, -b]"
canonical = ToCanonical(expr)
println("Canonical form of '$expr': ", canonical)

# **Python**
# ```python
# canonical = jl.xAct.ToCanonical("T[-b, -a] - T[-a, -b]")
# print(f"Canonical form: {canonical}")
# ```

# **Wolfram (xAct)**
# ```wolfram
# ToCanonical[T[-b, -a] - T[-a, -b]]
# (* returns 0 *)
# ```

# ## 5. Defining a Metric
# The metric tensor $g_{ab}$ is fundamental to defining geometry and curvature.
# In `xAct.jl`, defining a metric automatically creates its associated
# covariant derivative (`CD`), Riemann, Ricci, and Weyl tensors.

# **Julia**
g = def_metric!(-1, "g[-a,-b]", :CD)

# **Python**
# ```python
# g = jl.xAct.def_metric_b(-1, "g[-a,-b]", "CD")
# ```

# **Wolfram (xAct)**
# ```wolfram
# DefMetric[-1, g[-a, -b], CD]
# ```

# ## 6. Common Pitfalls & Fail-States
# - **Name Collisions**: If you try to define a manifold or tensor with a name
#   that already exists, `xAct.jl` will throw an error.
# - **Index Mismatch**: Ensure your tensor indices match the dimension of the
#   manifold.
# - **Global State**: The `!` in `def_manifold!` and `def_tensor!` means they
#   modify the global session. If you are in a notebook, re-running a cell
#   containing these might trigger a "Symbol already exists" error.

# ## 7. Next Steps
# Now that you've mastered the basics, check out:
# - [Differential Geometry Primer](../differential-geometry-primer.md)
# - [Feature Status](../theory/STATUS.md)
