# # Riemann Invariant Simplification (Invar)
#
# This tutorial covers the use of the `Invar` module for simplifying scalar
# polynomial invariants of the Riemann tensor. This is essential for proving
# the equivalence of different spacetime metrics.

# ## 1. Setup
# We'll need a manifold and a metric to work with.

# **Julia**
using xAct
reset_state!()
def_manifold!(:M, 4, [:a, :b, :c, :d, :e, :f, :g, :h])
def_metric!(-1, "g[-a,-b]", :CD)

# **Python**
# ```python
# from xact.xcore import get_julia
# jl = get_julia()
# jl.xAct.reset_state_b()
# jl.xAct.def_manifold_b("M", 4, ["a", "b", "c", "d", "e", "f", "g", "h"])
# jl.xAct.def_metric_b(-1, "g[-a,-b]", "CD")
# ```

# ## 2. RiemannToPerm
# The core of the `Invar` pipeline is converting tensor expressions into a
# canonical permutation representation.

# **Julia**
expr = "RiemannCD[-a, -b, b, a]"
rperm = RiemannToPerm(expr, :CD)
println("Permutation form: ", rperm.perm)

# **Python**
# ```python
# rperm = jl.xAct.RiemannToPerm("RiemannCD[-a, -b, b, a]", "CD")
# print(f"Permutation: {rperm.perm}")
# ```

# ## 3. RiemannSimplify
# `RiemannSimplify` is the high-level entry point for simplifying Riemann
# invariants. It uses a pre-computed database of multi-term identities.

# **Julia**
# Consider the Kretschmann scalar. Different dummy index labelings should
# simplify to the same canonical form.
expr1 = "RiemannCD[-a,-b,-c,-d] RiemannCD[a,b,c,d]"
expr2 = "RiemannCD[-c,-d,-a,-b] RiemannCD[c,d,a,b]"
diff = "$expr1 - $expr2"

result = RiemannSimplify(diff, :CD)
println("Difference simplified: ", result)  # "0"

# **Python**
# ```python
# diff = "RiemannCD[-a,-b,-c,-d] RiemannCD[a,b,c,d] - RiemannCD[-c,-d,-a,-b] RiemannCD[c,d,a,b]"
# result = jl.xAct.RiemannSimplify(diff, "CD")
# print(f"Result: {result}")
# ```

# **Wolfram (xAct)**
# ```wolfram
# RiemannSimplify[RiemannCD[-a,-b,-c,-d] RiemannCD[a,b,c,d] - RiemannCD[-c,-d,-a,-b] RiemannCD[c,d,a,b], CD]
# (* returns 0 *)
# ```

# ## 4. Simplification Levels
# You can control the depth of simplification using the `level` parameter:
# 1. Identity only
# 2. Monoterm (cyclic)
# 3. Bianchi identities
# 4. Covariant derivative commutation
# 5. Dimension-dependent identities
# 6. Dual invariants (4D only)

# **Julia**
expr = "RiemannCD[-a,-b,-c,-d] RiemannCD[a,c,b,d] + 1/2 RiemannCD[-a,-b,-c,-d] RiemannCD[a,b,c,d]"
# Level 2 (Cyclic)
s2 = RiemannSimplify(expr, :CD; level=2)
println("Level 2: ", s2)

# Level 3 (Bianchi)
s3 = RiemannSimplify(expr, :CD; level=3)
println("Level 3: ", s3)

# ## 5. Dual Invariants (4D)
# In 4 dimensions, we can simplify invariants involving the Levi-Civita
# epsilon tensor (represented as `DualRiemann` in Wolfram, or via
# `n_epsilon=1` cases in `Invar`).

# **Julia**
# Dual invariants are only supported if dim=4.
result = RiemannSimplify("RiemannCD[-a, -b, b, a]", :CD; level=6, dim=4)
println("Level 6 (4D) result: ", result)

# ## 6. Summary
# The `Invar` module provides:
# - `RiemannToPerm`: Tensor string → Canonical Permutation
# - `PermToRiemann`: Canonical Permutation → Tensor string
# - `RiemannSimplify`: End-to-end multi-term simplification
# - `InvSimplify`: Low-level simplification of invariant lists
