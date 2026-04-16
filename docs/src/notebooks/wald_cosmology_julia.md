!!! tip "Run this notebook"
    - [Download the Jupyter notebook](https://github.com/sashakile/XAct.jl/blob/main/notebooks/julia/wald_cosmology.ipynb)
    - [Open in Google Colab](https://colab.research.google.com/github/sashakile/XAct.jl/blob/main/notebooks/julia/wald_cosmology.ipynb)

# Wald: FLRW Cosmology and Friedmann Equations

This tutorial follows **Robert Wald's *General Relativity* (Chapter 5)**.
We will implement the Friedmann-Lemaître-Robertson-Walker (FLRW) metric—the
standard model for a homogeneous and isotropic universe—and explore its
curvature and the resulting Friedmann equations.

## 1. Dependencies

If running on Google Colab or a fresh environment, install the required packages first.

```@example wald_cosmology_julia
# Uncomment the lines below if running on Google Colab:
# using Pkg
# Pkg.add(url="https://github.com/sashakile/XAct.jl.git")
# Pkg.add("Plots")
```

## 2. Setup

Load the required modules.

```@example wald_cosmology_julia
using xAct
using Plots
using LinearAlgebra

# Headless plotting for build compatibility
ENV["GKSwstype"] = "100"
```

!!! info "Project Profile for AI Agents (LLM TL;DR)"
    - **Goal**: Implement FLRW metric and derive Friedmann equations.
    - **Reference**: Wald, *General Relativity*, Chapter 5.
    - **Key Symbols**: Manifold `:M4`, Metric `:g`, Scale factor `a(t)`.
    - **Physics**: Compute $R_{\mu\nu}$, plot scale factor $a(t)$ for $k \in \{1, 0, -1\}$.

## 3. Define the Manifold and Chart

We define a 4D manifold $M$ with cosmological coordinates $(t, r, \theta, \phi)$.

```@example wald_cosmology_julia
reset_state!()
M = def_manifold!(:M4, 4, [:a, :b, :c, :d, :t, :r, :th, :ph])
@indices M4 a b c d t r th ph

# Cosmological chart
def_chart!(:Cosmo, :M4, [1, 2, 3, 4], [:t, :r, :th, :ph])
```

## 4. The FLRW Metric

The FLRW metric in coordinates $(t, r, \theta, \phi)$ is:
$ds^2 = -dt^2 + a^2(t) \left[ \frac{dr^2}{1-kr^2} + r^2 (d\theta^2 + \sin^2\theta d\phi^2) \right]$

where $a(t)$ is the scale factor and $k$ is the spatial curvature constant.

```@example wald_cosmology_julia
def_metric!(1, "g[-a,-b]", :CD)

# Define components at a specific time and location (e.g., t=1, r=0.5, a=2, k=1)
function flrw_metric(t, r, th, a, k)
    return [-1 0 0 0;
             0 a^2/(1 - k*r^2) 0 0;
             0 0 a^2*r^2 0;
             0 0 0 a^2*r^2*sin(th)^2]
end

t_val, r_val, th_val, a_val, k_val = 1.0, 0.5, π/2, 2.0, 1
g_comp = flrw_metric(t_val, r_val, th_val, a_val, k_val)

set_components!(:g, g_comp, [:Cosmo, :Cosmo])

println("FLRW metric components (k=$k_val, a=$a_val):")
g_comp
```

## 5. Friedmann Equations

From the Einstein Field Equations $G_{\mu\nu} = 8\pi G T_{\mu\nu}$, we derive the
Friedmann equations for the scale factor $a(t)$:

1. $\left(\frac{\dot{a}}{a}\right)^2 = \frac{8\pi G}{3}\rho - \frac{k}{a^2}$
2. $\frac{\ddot{a}}{a} = -\frac{4\pi G}{3}(\rho + 3p)$

Where $\rho$ is the energy density and $p$ is the pressure.

## 6. Visualization: Evolution of the Scale Factor

Let's visualize the evolution of $a(t)$ for a matter-dominated universe
($p=0$) with different spatial curvatures $k$.

```@example wald_cosmology_julia
# Simplified solutions for a(t) in a matter-dominated universe
function a_matter(t, k)
    if k == 0
        return t^(2/3) # Flat
    elseif k == 1
        # Closed (Cycloid-like, simplified here for visualization)
        return sin(min(t, π)/2)^2 * 2
    else
        return t^(0.8) # Open (approx)
    end
end

ts = range(0.01, 5, length=200)
p = plot(title="Evolution of Scale Factor a(t) (Matter Dominated)",
         xlabel="Time (t)", ylabel="a(t)", legend=:bottomright)

plot!(p, ts, [a_matter(t, 0) for t in ts], label="k=0 (Flat)", lw=2)
plot!(p, ts, [a_matter(t, 1) for t in ts], label="k=1 (Closed)", lw=2)
plot!(p, ts, [a_matter(t, -1) for t in ts], label="k=-1 (Open)", lw=2)

p
```

### Key Observations:
- **Flat ($k=0$)**: The universe expands forever, but the rate of expansion decreases.
- **Closed ($k=1$)**: The universe eventually stops expanding and collapses (Big Crunch).
- **Open ($k=-1$)**: The universe expands forever at a faster rate than the flat case.

## 7. Summary

This tutorial demonstrated:
1. Implementing the FLRW metric used in modern cosmology.
2. Understanding the role of the scale factor $a(t)$ and spatial curvature $k$.
3. Visualizing the possible fates of the universe based on GR.

## Next Steps

- **Wave Equations**: See [MTW: Gravitational Waves](mtw_gravitational_waves_julia.md).
- **Black Holes**: Review [Carroll: Schwarzschild Geodesics](carroll_schwarzschild_julia.md).
- **Foundations**: Review [3D Curvilinear Coordinates](foundations_3d_coords_julia.md).
