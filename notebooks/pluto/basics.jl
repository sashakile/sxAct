### A Pluto.jl notebook ###
# v0.20.4

using Markdown
using InteractiveUtils

# ╔═╡ 8a1b2c3d-4e5f-6a7b-8c9d-0e1f2a3b4c5d
begin
    # If running outside the sxAct project, uncomment:
    # using Pkg; Pkg.add(url="https://github.com/sashakile/sxAct.git")
    using xAct
end

# ╔═╡ 1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d
md"""
# sxAct.jl — Interactive Tutorial

This Pluto notebook introduces the core workflow of `xAct.jl`:
manifolds, metrics, canonicalization, and curvature.

Each cell is **reactive** — editing a definition automatically re-evaluates
all dependent cells.
"""

# ╔═╡ 2a3b4c5d-6e7f-8a9b-0c1d-2e3f4a5b6c7d
md"## 1. Define a Manifold"

# ╔═╡ 3a4b5c6d-7e8f-9a0b-1c2d-3e4f5a6b7c8d
begin
    reset_state!()
    M = def_manifold!(:M, 4, [:a, :b, :c, :d, :e, :f])
end

# ╔═╡ 4a5b6c7d-8e9f-0a1b-2c3d-4e5f6a7b8c9d
md"""
## 2. Define a Metric

Lorentzian signature ``(-,+,+,+)``. This automatically creates
Riemann, Ricci, RicciScalar, Weyl, Einstein, and Christoffel tensors.
"""

# ╔═╡ 5a6b7c8d-9e0f-1a2b-3c4d-5e6f7a8b9c0d
g = def_metric!(-1, "g[-a,-b]", :CD)

# ╔═╡ 6a7b8c9d-0e1f-2a3b-4c5d-6e7f8a9b0c1d
md"""
## 3. Canonicalization

The Butler-Portugal algorithm brings tensor expressions to canonical form.
"""

# ╔═╡ 7a8b9c0d-1e2f-3a4b-5c6d-7e8f9a0b1c2d
ToCanonical("g[-b,-a] - g[-a,-b]")

# ╔═╡ 8b9c0d1e-2f3a-4b5c-6d7e-8f9a0b1c2d3e
begin
    def_tensor!(:T, ["-a", "-b"], :M; symmetry_str="Symmetric[{-a,-b}]")
    ToCanonical("T[-b,-a] - T[-a,-b]")
end

# ╔═╡ 9c0d1e2f-3a4b-5c6d-7e8f-9a0b1c2d3e4f
md"""
## 4. Contraction

Lower an index with the metric — ``V_b = V^a g_{ab}``:
"""

# ╔═╡ 0d1e2f3a-4b5c-6d7e-8f9a-0b1c2d3e4f5a
begin
    def_tensor!(:V, ["a"], :M)
    Contract("V[a] * g[-a,-b]")
end

# ╔═╡ 1e2f3a4b-5c6d-7e8f-9a0b-1c2d3e4f5a6b
md"""
## 5. Riemann Tensor Identities

First Bianchi identity — should vanish:
"""

# ╔═╡ 2f3a4b5c-6d7e-8f9a-0b1c-2d3e4f5a6b7c
ToCanonical("RiemannCD[-a,-b,-c,-d] + RiemannCD[-a,-c,-d,-b] + RiemannCD[-a,-d,-b,-c]")

# ╔═╡ 3a4b5c6d-7e8f-9a0b-1c2d-3e4f5a6b7c8d
md"""
## 6. Perturbation Theory

Perturb the metric to first order:
"""

# ╔═╡ 4b5c6d7e-8f9a-0b1c-2d3e-4f5a6b7c8d9e
begin
    def_tensor!(:h, ["-a", "-b"], :M; symmetry_str="Symmetric[{-a,-b}]")
    def_perturbation!(:h, :g, 1)
    perturb("g[-a,-b]", 1)
end

# ╔═╡ Cell order:
# ╟─1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d
# ╠═8a1b2c3d-4e5f-6a7b-8c9d-0e1f2a3b4c5d
# ╟─2a3b4c5d-6e7f-8a9b-0c1d-2e3f4a5b6c7d
# ╠═3a4b5c6d-7e8f-9a0b-1c2d-3e4f5a6b7c8d
# ╟─4a5b6c7d-8e9f-0a1b-2c3d-4e5f6a7b8c9d
# ╠═5a6b7c8d-9e0f-1a2b-3c4d-5e6f7a8b9c0d
# ╟─6a7b8c9d-0e1f-2a3b-4c5d-6e7f8a9b0c1d
# ╠═7a8b9c0d-1e2f-3a4b-5c6d-7e8f9a0b1c2d
# ╠═8b9c0d1e-2f3a-4b5c-6d7e-8f9a0b1c2d3e
# ╟─9c0d1e2f-3a4b-5c6d-7e8f-9a0b1c2d3e4f
# ╠═0d1e2f3a-4b5c-6d7e-8f9a-0b1c2d3e4f5a
# ╟─1e2f3a4b-5c6d-7e8f-9a0b-1c2d3e4f5a6b
# ╠═2f3a4b5c-6d7e-8f9a-0b1c-2d3e4f5a6b7c
# ╟─3a4b5c6d-7e8f-9a0b-1c2d-3e4f5a6b7c8d
# ╠═4b5c6d7e-8f9a-0b1c-2d3e-4f5a6b7c8d9e
