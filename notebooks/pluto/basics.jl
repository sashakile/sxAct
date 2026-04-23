### A Pluto.jl notebook ###
# v0.20.4

using Markdown
using InteractiveUtils

# ╔═╡ a1000001-0000-0000-0000-000000000001
begin
    import Pkg
    Pkg.activate(joinpath(@__DIR__, "..", ".."))
    using XAct
end

# ╔═╡ a1000002-0000-0000-0000-000000000002
md"""
# XAct.jl — Interactive Tutorial

This Pluto notebook introduces the core workflow of `XAct.jl`:
manifolds, metrics, canonicalization, and curvature.

Expressions are written using the **typed API** — `@indices` declares index
objects, `tensor()` looks up handles, and `T[-a,-b]` builds expressions with
slot-count and manifold validation at construction time.

Each cell is **reactive** — editing a definition automatically re-evaluates
all dependent cells.
"""

# ╔═╡ a1000003-0000-0000-0000-000000000003
md"## 1. Define a Manifold"

# ╔═╡ a1000004-0000-0000-0000-000000000004
begin
    reset_state!()
    M = def_manifold!(:M, 4, [:a, :b, :c, :d, :e, :f])
    @indices M a b c d e f
end

# ╔═╡ a1000005-0000-0000-0000-000000000005
md"""
## 2. Define a Metric

Lorentzian signature ``(-,+,+,+)``. This automatically creates
Riemann, Ricci, RicciScalar, Weyl, Einstein, and Christoffel tensors.
"""

# ╔═╡ a1000006-0000-0000-0000-000000000006
begin
    g = def_metric!(-1, "g[-a,-b]", :CD)
    Riem = tensor(:RiemannCD)
    Ric  = tensor(:RicciCD)
    g_h  = tensor(:g)
end

# ╔═╡ a1000007-0000-0000-0000-000000000007
md"""
## 3. Canonicalization

The Butler-Portugal algorithm brings tensor expressions to canonical form.
Expressions are built with `[]` — wrong slot count or manifold raises an error
immediately, before reaching the engine.
"""

# ╔═╡ a1000008-0000-0000-0000-000000000008
ToCanonical(g_h[-b,-a] - g_h[-a,-b])

# ╔═╡ a1000009-0000-0000-0000-000000000009
begin
    def_tensor!(:T, ["-a", "-b"], :M; symmetry_str="Symmetric[{-a,-b}]")
    T_h = tensor(:T)
    ToCanonical(T_h[-b,-a] - T_h[-a,-b])
end

# ╔═╡ a100000a-0000-0000-0000-000000000001
md"""
## 4. Contraction

Lower an index with the metric — ``V_b = V^a g_{ab}``:
"""

# ╔═╡ a100000b-0000-0000-0000-000000000001
begin
    def_tensor!(:V, ["a"], :M)
    V_h = tensor(:V)
    Contract(V_h[a] * g_h[-a,-b])
end

# ╔═╡ a100000c-0000-0000-0000-000000000001
md"""
## 5. Riemann Tensor Identities

The Riemann tensor satisfies well-known symmetries that the canonicalizer
automatically recognizes.
"""

# ╔═╡ a100000d-0000-0000-0000-000000000001
# First Bianchi identity — R_{abcd} + R_{acdb} + R_{adbc} = 0
ToCanonical(Riem[-a,-b,-c,-d] + Riem[-a,-c,-d,-b] + Riem[-a,-d,-b,-c])

# ╔═╡ a100000e-0000-0000-0000-000000000001
# Antisymmetry in the first pair — R_{abcd} + R_{bacd} = 0
ToCanonical(Riem[-a,-b,-c,-d] + Riem[-b,-a,-c,-d])

# ╔═╡ a100000f-0000-0000-0000-000000000001
# Pair symmetry — R_{abcd} = R_{cdab}
ToCanonical(Riem[-a,-b,-c,-d] - Riem[-c,-d,-a,-b])

# ╔═╡ a1000010-0000-0000-0000-000000000001
md"""
## 6. Perturbation Theory

Perturb the metric to first order:
"""

# ╔═╡ a1000011-0000-0000-0000-000000000001
begin
    def_tensor!(:h, ["-a", "-b"], :M; symmetry_str="Symmetric[{-a,-b}]")
    def_perturbation!(:h, :g, 1)
    perturb(g_h[-a,-b], 1)
end

# ╔═╡ a1000012-0000-0000-0000-000000000001
md"""
## 7. Validation

The typed API raises errors at construction time — before the expression
reaches the engine:
"""

# ╔═╡ a1000013-0000-0000-0000-000000000001
try
    Riem[-a,-b]     # ERROR: RiemannCD has 4 slots, got 2
catch e
    e
end

# ╔═╡ Cell order:
# ╟─a1000002-0000-0000-0000-000000000002
# ╠═a1000001-0000-0000-0000-000000000001
# ╟─a1000003-0000-0000-0000-000000000003
# ╠═a1000004-0000-0000-0000-000000000004
# ╟─a1000005-0000-0000-0000-000000000005
# ╠═a1000006-0000-0000-0000-000000000006
# ╟─a1000007-0000-0000-0000-000000000007
# ╠═a1000008-0000-0000-0000-000000000008
# ╠═a1000009-0000-0000-0000-000000000009
# ╟─a100000a-0000-0000-0000-000000000001
# ╠═a100000b-0000-0000-0000-000000000001
# ╟─a100000c-0000-0000-0000-000000000001
# ╠═a100000d-0000-0000-0000-000000000001
# ╠═a100000e-0000-0000-0000-000000000001
# ╠═a100000f-0000-0000-0000-000000000001
# ╟─a1000010-0000-0000-0000-000000000001
# ╠═a1000011-0000-0000-0000-000000000001
# ╟─a1000012-0000-0000-0000-000000000001
# ╠═a1000013-0000-0000-0000-000000000001
