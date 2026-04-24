!!! tip "Run this notebook"
    - [Download the Jupyter notebook](https://github.com/sashakile/XAct.jl/blob/main/notebooks/julia/foundations_sphere.ipynb)
    - [Open in Google Colab](https://colab.research.google.com/github/sashakile/XAct.jl/blob/main/notebooks/julia/foundations_sphere.ipynb)
    - [Open in Binder](https://mybinder.org/v2/gh/sashakile/XAct.jl/main?labpath=notebooks%2Fjulia%2Ffoundations_sphere.ipynb)

# Tutorial: Surface Geometry - The 2-Sphere

!!! info "Project Profile for AI Agents (LLM TL;DR)"
    - **Goal**: Demonstrate intrinsic curvature on a 2-sphere embedded in $R^3$.
    - **Key Symbols**: Manifold `:S2`, Chart `:Sph`.
    - **Curvature**: Ricci Scalar $R = 2/R^2$.
    - **Prerequisites**: `XAct.jl`, `Plots.jl`, `LinearAlgebra`.

This tutorial explores **intrinsic curvature** using the 2-sphere ($S^2$)
embedded in 3D Euclidean space. We will calculate the induced metric on the
sphere and compute its Riemann curvature tensor and Ricci scalar to show that
the surface is curved even though the ambient space is flat.

## 1. Setup

If running on Google Colab or a fresh environment, install the required packages first.

```@example foundations_sphere_julia
# Uncomment the lines below if running on Google Colab:
# using Pkg
# Pkg.add("XAct")
# Pkg.add("Plots")
```

## 2. Setup

Load the required modules.

```@example foundations_sphere_julia
using XAct
using Plots
using LinearAlgebra
```

!!! tip "Common Pitfall: Global State"
    Always call `reset_state!()` before defining a manifold to avoid "Symbol
    already exists" errors when re-running cells.

## 2. Define the Manifold and Chart

We define a 2D manifold $S^2$ with abstract indices.

```@example foundations_sphere_julia
reset_state!()
M = def_manifold!(:S2, 2, [:a, :b, :c, :d, :th, :ph])
@indices S2 a b c d th ph

# Coordinate chart (theta, phi)
def_chart!(:Sph, :S2, [1, 2], [:th, :ph])
```

## 3. Induced Metric on the 2-Sphere

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

## 4. Visualization: The 2-Sphere

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
## 5. Intrinsic Curvature

The Riemann tensor $R^a{}_{bcd}$ measures the intrinsic curvature of the
manifold. For a sphere of radius $R$, the Ricci scalar $R = g^{ab} R_{ab}$
should be a constant: $R = 2/R^2$.

At the abstract-tensor level, `XAct.jl` keeps the scalar curvature symbolic:

```@example foundations_sphere_julia
# Riemann, Ricci, and RicciScalar are auto-created by def_metric!
Riem = tensor(:RiemannCD)
Ric  = tensor(:RicciCD)
RS   = tensor(:RicciScalarCD)

abstract_scalar = Contract(RS[])
println("Abstract Ricci scalar expression:")
abstract_scalar
```

To make the textbook claim explicit, we now do a component-level check using the
metric coefficients of the sphere. For the diagonal line element
$ds^2 = R^2 d\theta^2 + R^2 \sin^2\theta d\phi^2$, the only non-zero Christoffel
symbols are $\Gamma^\theta_{\phi\phi} = -\sin\theta\cos\theta$ and
$\Gamma^\phi_{\theta\phi} = \cot\theta$. From them we can compute the Gaussian
curvature $K = 1/R^2$, hence the scalar curvature $R = 2K = 2/R^2$.

```@example foundations_sphere_julia
function sphere_christoffels(θ)
    Γθ_φφ = -sin(θ) * cos(θ)
    Γφ_θφ = cos(θ) / sin(θ)
    return (; Γθ_φφ, Γφ_θφ)
end

function sphere_gaussian_curvature(R, θ)
    Γ = sphere_christoffels(θ)
    dθ_Γθ_φφ = sin(θ)^2 - cos(θ)^2
    rθ_φθφ = dθ_Γθ_φφ - Γ.Γθ_φφ * Γ.Γφ_θφ
    rθφθφ = R^2 * rθ_φθφ
    det_g = R^4 * sin(θ)^2
    return rθφθφ / det_g
end

sphere_ricci_scalar(R, θ) = 2 * sphere_gaussian_curvature(R, θ)

K_val = sphere_gaussian_curvature(R_val, θ_val)
sphere_ricci = sphere_ricci_scalar(R_val, θ_val)

@assert isapprox(K_val, 1 / R_val^2; atol=1e-12)
@assert isapprox(sphere_ricci_scalar(R_val, θ_val), 2 / R_val^2; atol=1e-12)

println("Gaussian curvature check passed: K = ", K_val)
println("Ricci scalar check passed: R = ", sphere_ricci)
```

## 6. Symbolic Algebra: What the Engine Proves Abstractly

The real power of `XAct.jl` lies in its ability to manipulate tensor expressions
abstractly. Here we use it for a dimension-dependent identity: in 2D, the trace
of the Einstein tensor satisfies
$g^{ab} G_{ab} = (1 - d/2) R = 0$.

```@example foundations_sphere_julia
G = tensor(:EinsteinCD)
g = tensor(:g)

trace_G = Contract(g[a, b] * G[-a, -b])
@assert string(trace_G) == "0"

println("Trace of Einstein tensor in 2D (expected 0):")
trace_G
```

A stronger geometric fact is that the full Einstein tensor vanishes identically
in 2D because $R_{ab} = \tfrac{1}{2} g_{ab} R$. This notebook explicitly checks
its trace symbolically and the scalar curvature numerically/components-wise.

## 7. Summary

## Key Takeaways: Intrinsic Geometry

This tutorial demonstrated:
1. Defining a manifold for a curved surface.
2. Calculating the induced metric from an embedding.
3. Visualizing the surface.
4. Verifying intrinsic curvature by computing the Ricci Scalar ($R = 2$).

## Next Steps

- **Schwarzschild**: Move to 4D Spacetime in the [Schwarzschild Geodesics](../getting-started.md) tutorial.
- **3D Geometry**: Review 3D coordinate systems in [Curvilinear Coordinates](foundations_3d_coords_julia.md).
- **Core Guide**: See the [Typed Expressions (TExpr)](../guide/TExpr.md) guide.
