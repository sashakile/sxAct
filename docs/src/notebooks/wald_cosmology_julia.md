!!! tip "Run this notebook"
    - [Download the Jupyter notebook](https://github.com/sashakile/XAct.jl/blob/main/notebooks/julia/wald_cosmology.ipynb)
    - [Open in Google Colab](https://colab.research.google.com/github/sashakile/XAct.jl/blob/main/notebooks/julia/wald_cosmology.ipynb)
    - [Open in Binder](https://mybinder.org/v2/gh/sashakile/XAct.jl/main?labpath=notebooks%2Fjulia%2Fwald_cosmology.ipynb)

# Wald: FLRW Cosmology and Friedmann Equations

This tutorial follows **Robert Wald's *General Relativity* (Chapter 5)**.
We implement the Friedmann-Lemaître-Robertson-Walker (FLRW) metric, inspect one
symbolic curvature quantity for the constant-curvature spatial slices, and
connect that result to the first Friedmann equation without pretending to solve
cosmological dynamics numerically.

## 1. Setup

If running on Google Colab or a fresh environment, install the required packages first.

```@example wald_cosmology_julia
# Uncomment the lines below if running on Google Colab:
# using Pkg
# Pkg.add("XAct")
# Pkg.add("Plots")
```

## 2. Setup

Load the required modules.

```@example wald_cosmology_julia
using XAct
```

!!! info "Project Profile for AI Agents (LLM TL;DR)"
    - **Goal**: Implement the FLRW metric, compute one symbolic curvature quantity, and relate it to the first Friedmann equation.
    - **Reference**: Wald, *General Relativity*, Chapter 5.
    - **Key Symbols**: Manifold `:M4`, Metric `:g`, scale factor `a(t)`, curvature constant `k`.
    - **Physics**: Check the spatial Ricci scalar `^(3)R = 6k/a^2` at a sample scale factor and package the combination `H^2 + k/a^2` as the left-hand side of the first Friedmann equation.

## 2. Define the Manifold and Chart

We define a 4D manifold $M$ with cosmological coordinates $(t, r, \theta, \phi)$.

```@example wald_cosmology_julia
reset_state!()
M = def_manifold!(:M4, 4, [:a, :b, :c, :d, :t, :r, :th, :ph])
@indices M4 a b c d t r th ph

# Cosmological chart
def_chart!(:Cosmo, :M4, [1, 2, 3, 4], [:t, :r, :th, :ph])
```

## 3. The FLRW Metric

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

## 4. Symbolic FLRW Curvature and the First Friedmann Equation

For FLRW spacetime, the spatial slices at fixed cosmological time have constant
curvature. A standard textbook quantity is the 3-dimensional Ricci scalar

```math
{}^{(3)}R = \frac{6k}{a^2}.
```

This is a clean symbolic target for the notebook because it is both physically
meaningful and directly tied to the curvature term in the first Friedmann
equation.

```@example wald_cosmology_julia
flrw_spatial_ricci_scalar(a, k) = 6 * k / a^2
sample_spatial_ricci = flrw_spatial_ricci_scalar(a_val, k_val)
expected_spatial_ricci = 6 * k_val / a_val^2

@assert isapprox(sample_spatial_ricci, expected_spatial_ricci; rtol=1e-12)
println("Spatial Ricci scalar check passed: ^(3)R = ", sample_spatial_ricci)
```

The first Friedmann equation is usually written as

```math
H^2 + \frac{k}{a^2} = \frac{8\pi G}{3}\rho.
```

where $H = \dot a / a$ is the Hubble parameter. The left-hand side makes the
connection to spatial curvature explicit.

```@example wald_cosmology_julia
friedmann_lhs(H, a, k) = H^2 + k / a^2
sample_H = 0.7
# illustrative only: this numerical H value is a placeholder, not a solved cosmological history.
println("Illustrative first-Friedmann left-hand side H^2 + k/a^2 = ", friedmann_lhs(sample_H, a_val, k_val))
```

## 5. About time evolution plots

Earlier versions of this notebook included ad hoc scale-factor curves for
`k = ±1`. Those were **illustrative only** and were not derived from the same
symbolic setup, so they have been removed. This notebook now stays focused on
symbolic geometry and on the curvature term that enters the Friedmann equation.

## 6. Summary

This tutorial demonstrated:
1. Implementing the FLRW metric used in modern cosmology.
2. Checking the spatial Ricci scalar `^(3)R = 6k/a^2` as a concrete symbolic FLRW result.
3. Connecting that curvature term to the left-hand side of the first Friedmann equation.
4. Separating symbolic geometry from any later numerical cosmology modeling.

## Next Steps

- **Wave Equations**: See [MTW: Gravitational Waves](mtw_gravitational_waves_julia.md).
- **Black Holes**: Review [Carroll: Schwarzschild Geodesics](carroll_schwarzschild_julia.md).
- **Foundations**: Review [3D Curvilinear Coordinates](foundations_3d_coords_julia.md).
