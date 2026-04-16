!!! tip "Run this notebook"
    - [Download the Jupyter notebook](https://github.com/sashakile/XAct.jl/blob/main/notebooks/julia/foundations_3d_coords.ipynb)
    - [Open in Google Colab](https://colab.research.google.com/github/sashakile/XAct.jl/blob/main/notebooks/julia/foundations_3d_coords.ipynb)

# Tutorial: 3D Geometry - Curvilinear Coordinates

!!! info "Project Profile for AI Agents (LLM TL;DR)"
    - **Goal**: Compare 3D coordinate systems and demonstrate tensor vector calculus.
    - **Key Symbols**: Manifold `:M`, Charts `:Cart`, `:Cyl`, `:Sph`.
    - **Calculus**: Gradient ($\nabla_a \Phi$), Divergence ($\nabla_a V^a$).
    - **Prerequisites**: `xAct.jl`, `Plots.jl`, `LinearAlgebra`.

This tutorial extends our foundational geometry exploration to 3D Euclidean
space ($R^3$). We will compare Cartesian, Cylindrical, and Spherical
coordinate systems and demonstrate how standard vector calculus operators
(Gradient, Divergence) are represented in the language of tensors.

## 1. Dependencies

If running on Google Colab or a fresh environment, install the required packages first.

```@example foundations_3d_coords_julia
# Uncomment the lines below if running on Google Colab:
# using Pkg
# Pkg.add(url="https://github.com/sashakile/XAct.jl.git")
# Pkg.add("Plots")
```

## 2. Setup

```@example foundations_3d_coords_julia
using xAct
using Plots
using LinearAlgebra
```

!!! tip "Common Pitfall: Global State"
    `xAct.jl` maintains a global registry. If you re-run definition cells
    without calling `reset_state!()`, you will encounter "Symbol already exists"
    errors.

## 3. Define the Manifold and Charts

We define a 3D manifold $R^3$ with abstract indices.

```@example foundations_3d_coords_julia
reset_state!()
M = def_manifold!(:M, 3, [:a, :b, :c, :d, :x, :y, :z, :r, :th, :ph])
@indices M a b c d x y z r th ph
```

Define three coordinate charts:
1. **Cartesian** ($x, y, z$)
2. **Cylindrical** ($\rho, \phi, z$) — using symbols $r, \phi, z$
3. **Spherical** ($r, \theta, \phi$) — using symbols $r, \theta, \phi$

```@example foundations_3d_coords_julia
def_chart!(:Cart, :M, [1, 2, 3], [:x, :y, :z])
def_chart!(:Cyl,  :M, [1, 2, 3], [:r, :ph, :z])
def_chart!(:Sph,  :M, [1, 2, 3], [:r, :th, :ph])
```

## 4. The Euclidean Metric

In Cartesian coordinates, the Euclidean metric is simply $\delta_{ij} = \text{diag}(1, 1, 1)$.

```@example foundations_3d_coords_julia
def_metric!(1, "g[-a,-b]", :CD)
set_components!(:g, [1 0 0; 0 1 0; 0 0 1], [:Cart, :Cart])
```

## 5. Visualization: Spherical Coordinate Surfaces

In 3D, each coordinate defines a family of surfaces:
- $r = \text{const}$ (Spheres)
- $\theta = \text{const}$ (Cones)
- $\phi = \text{const}$ (Half-planes)

Let's visualize a sphere of constant $r$.

```@example foundations_3d_coords_julia
function plot_spherical_surface(r_val)
    θs = range(0, π, length=30)
    φs = range(0, 2π, length=60)

    xs = [r_val * sin(θ) * cos(φ) for θ in θs, φ in φs]
    ys = [r_val * sin(θ) * sin(φ) for θ in θs, φ in φs]
    zs = [r_val * cos(θ) for θ in θs, φ in φs]

    surface(xs, ys, zs, alpha=0.6, title="Spherical Coordinate Surface (r=$r_val)",
            xlabel="x", ylabel="y", zlabel="z", aspect_ratio=:equal)
end

plot_spherical_surface(1.5)
```

## 6. Metric in Spherical Coordinates

For a point $(r, \theta, \phi)$, the metric is:
$ds^2 = dr^2 + r^2 d\theta^2 + r^2 \sin^2\theta d\phi^2$

```@example foundations_3d_coords_julia
function spherical_metric(r_val, th_val, ph_val)
    [1 0 0;
     0 r_val^2 0;
     0 0 r_val^2*sin(th_val)^2]
end

r_val, th_val, ph_val = 1.0, pi/4, pi/2
g_sph = spherical_metric(r_val, th_val, ph_val)

println("Metric in Spherical coordinates at (r=$r_val, θ=$th_val, φ=$ph_val):")
g_sph
```

## 7. Vector Calculus as Tensor Algebra

In abstract index notation, standard operators are elegantly expressed:

- **Gradient** of a scalar $\Phi$: $\nabla_a \Phi$
- **Divergence** of a vector $V^a$: $\nabla_a V^a$
- **Laplacian** of a scalar $\Phi$: $\nabla^a \nabla_a \Phi = g^{ab} \nabla_a \nabla_b \Phi$

```@example foundations_3d_coords_julia
# Define a vector and scalar field
def_tensor!(:V, ["a"], :M)
def_tensor!(:Phi, String[], :M)

V = tensor(:V)
Phi = tensor(:Phi)

# Gradient: CD[-a](Phi[])
# Divergence: Contract(CD[-a](V[a]))
# Laplacian: Contract(g[a,b] * CD[-a](CD[-b](Phi[])))
```
## 8. Volume Element

The 3D volume element in spherical coordinates is $dV = \sqrt{|g|} dr d\theta d\phi = r^2 \sin\theta dr d\theta d\phi$.

```@example foundations_3d_coords_julia
sqrt_det_g = sqrt(det(g_sph))
textbook_val = r_val^2 * sin(th_val)

println("Metric volume factor: ", sqrt_det_g)
println("Textbook value (r^2 sin θ): ", textbook_val)
```

## 9. Symbolic Identities: Ricci and Riemann

In 3 Dimensions, the Riemann tensor is entirely determined by the Ricci tensor.
While we can't show the full 3D-specific vanishing of the Weyl tensor here without
coordinate expansion, we can show how `xAct.jl` manages the abstract relations
between these tensors.

For example, let's verify that the trace of the Ricci tensor is indeed the Ricci Scalar.

```@example foundations_3d_coords_julia
Ric = tensor(:RicciCD)
RS  = tensor(:RicciScalarCD)
g   = tensor(:g)

# Verify the definition: g^{ab} R_{ab} - R = 0
identity = Simplify(Contract(g[a, b] * Ric[-a, -b]) - RS[])

println("Identity check (g^{ab} R_{ab} - R):")
identity
```

Using these abstract tools, we can manipulate high-rank tensor equations
(like the decomposition of the Riemann tensor into Ricci and Weyl parts)
with complete mathematical rigor.

## 10. Summary

## Key Takeaways: 3D Curvilinear Systems

This tutorial showed:
1. Defining 3D manifolds and multiple curvilinear charts.
2. Representing standard vector calculus operators as tensor contractions.
3. Verifying volume elements in non-Cartesian bases.

## Next Steps

- **Curvature**: Explore intrinsic curvature in [The 2-Sphere](foundations_sphere_julia.md).
- **Basics**: Review 2D transformations in [Polar vs. Cartesian](foundations_2d_polar_julia.md).
- **Core Guide**: See the [Typed Expressions (TExpr)](../guide/TExpr.md) guide.
