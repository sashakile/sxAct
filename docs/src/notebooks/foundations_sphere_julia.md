!!! tip "Run this notebook"
    - [Download the Jupyter notebook](https://github.com/sashakile/XAct.jl/blob/main/notebooks/julia/foundations_sphere.ipynb)
    - [Open in Google Colab](https://colab.research.google.com/github/sashakile/XAct.jl/blob/main/notebooks/julia/foundations_sphere.ipynb)

# Tutorial: Surface Geometry - The 2-Sphere

!!! info "Project Profile for AI Agents (LLM TL;DR)"
    - **Goal**: Demonstrate intrinsic curvature on a 2-sphere embedded in $R^3$.
    - **Key Symbols**: Manifold `:S2`, Chart `:Sph`.
    - **Curvature**: Ricci Scalar $R = 2/R^2$.
    - **Prerequisites**: `xAct.jl`, `Plots.jl`, `LinearAlgebra`.

This tutorial explores **intrinsic curvature** using the 2-sphere ($S^2$)
embedded in 3D Euclidean space. We will calculate the induced metric on the
sphere and compute its Riemann curvature tensor and Ricci scalar to show that
the surface is curved even though the ambient space is flat.

## 1. Dependencies

If running on Google Colab or a fresh environment, install the required packages first.

```@example foundations_sphere_julia
# Uncomment the lines below if running on Google Colab:
# using Pkg
# Pkg.add(url="https://github.com/sashakile/XAct.jl.git")
# Pkg.add("Plots")
```

## 2. Setup

Load the required modules.

```@example foundations_sphere_julia
using xAct
using Plots
using LinearAlgebra
```

!!! tip "Common Pitfall: Global State"
    Always call `reset_state!()` before defining a manifold to avoid "Symbol
    already exists" errors when re-running cells.

## 3. Define the Manifold and Chart

We define a 2D manifold $S^2$ with abstract indices.

```@example foundations_sphere_julia
reset_state!()
M = def_manifold!(:S2, 2, [:a, :b, :c, :d, :th, :ph])
@indices S2 a b c d th ph

# Coordinate chart (theta, phi)
def_chart!(:Sph, :S2, [1, 2], [:th, :ph])
```

## 4. Induced Metric on the 2-Sphere

For a sphere of radius $R$ embedded in $R^3$, the induced metric in spherical
coordinates is:
$ds^2 = R^2 d\theta^2 + R^2 \sin^2\theta d\phi^2$

```@example foundations_sphere_julia
def_metric!(1, "g[-a,-b]", :CD)

function sphere_metric(R, θ)
    [R^2 0;
     0 R^2*sin(θ)^2]
end

R_val = 1.0
θ_val = pi/4
g_comp = sphere_metric(R_val, θ_val)

set_components!(:g, g_comp, [:Sph, :Sph])

println("Induced metric components at θ = π/4 (R=1):")
g_comp
```

## 5. Visualization: The 2-Sphere

Let's visualize the surface we are analyzing.

```@example foundations_sphere_julia
function plot_sphere(R)
    θs = range(0, π, length=30)
    φs = range(0, 2π, length=60)

    xs = [R * sin(θ) * cos(φ) for θ in θs, φ in φs]
    ys = [R * sin(θ) * sin(φ) for θ in θs, φ in φs]
    zs = [R * cos(θ) for θ in θs, φ in φs]

    surface(xs, ys, zs, alpha=0.8, color=:viridis,
            title="The 2-Sphere (R=$R)", aspect_ratio=:equal)
end

plot_sphere(R_val)
```
## 6. Intrinsic Curvature

The Riemann tensor $R^a{}_{bcd}$ measures the intrinsic curvature of the
manifold. For a sphere of radius $R$, the Ricci scalar $R = g^{ab} R_{ab}$
should be a constant: $R = 2/R^2$.

```@example foundations_sphere_julia
# Riemann, Ricci, and RicciScalar are auto-created by def_metric!
Riem = tensor(:RiemannCD)
Ric  = tensor(:RicciCD)
RS   = tensor(:RicciScalarCD)

# For a sphere of R=1, the Ricci Scalar should be exactly 2.
# We use Contract to evaluate the scalar expression.
val = Contract(RS[])
println("Ricci Scalar (expected 2.0): ", val)
```

## 7. Symbolic Algebra: Leveraging the Engine

The real power of `xAct.jl` lies in its ability to manipulate tensor expressions
abstractly. Instead of just calculating numbers, we can verify geometric identities
that must hold for *any* metric.

For example, the **Einstein tensor** $G_{ab}$ is defined as:
$G_{ab} = R_{ab} - \frac{1}{2} g_{ab} R$

Let's use the engine to verify that the trace of the Einstein tensor in 2D
is exactly $-R$ (which implies $R_{aa} = 0$ in 2D, a unique property of surface geometry).

```@example foundations_sphere_julia
G = tensor(:EinsteinCD)
g = tensor(:g)

# Compute the trace: g^{ab} G_{ab}
# In 2D, this should simplify based on the definition.
trace_G = Contract(g[a, b] * G[-a, -b])

println("Trace of Einstein tensor (g^{ab} G_{ab}):")
trace_G
```

By leveraging `ToCanonical` and `Contract`, we can prove complex identities
without ever choosing a coordinate system.

## 8. Summary

## Key Takeaways: Intrinsic Geometry

This tutorial demonstrated:
1. Defining a manifold for a curved surface.
2. Calculating the induced metric from an embedding.
3. Visualizing the surface.
4. Verifying intrinsic curvature by computing the Ricci Scalar ($R = 2$).

## Next Steps

- **Schwarzschild**: Move to 4D Spacetime in the [Schwarzschild Geodesics](../examples/basics.md) tutorial.
- **3D Geometry**: Review 3D coordinate systems in [Curvilinear Coordinates](foundations_3d_coords_julia.md).
- **Core Guide**: See the [Typed Expressions (TExpr)](../guide/TExpr.md) guide.
