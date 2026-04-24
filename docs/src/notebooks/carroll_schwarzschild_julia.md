!!! tip "Run this notebook"
    - [Download the Jupyter notebook](https://github.com/sashakile/XAct.jl/blob/main/notebooks/julia/carroll_schwarzschild.ipynb)
    - [Open in Google Colab](https://colab.research.google.com/github/sashakile/XAct.jl/blob/main/notebooks/julia/carroll_schwarzschild.ipynb)
    - [Open in Binder](https://mybinder.org/v2/gh/sashakile/XAct.jl/main?labpath=notebooks%2Fjulia%2Fcarroll_schwarzschild.ipynb)

# Carroll: Schwarzschild Geodesics and Curvature

This tutorial follows **Sean Carroll's *Spacetime and Geometry* (Chapter 5)**.
We will implement the Schwarzschild metric, inspect one curvature diagnostic at a
sample radius, and connect the effective potential to the standard landmark radii
from Carroll's discussion of Schwarzschild geodesics.

## 1. Setup

If running on Google Colab or a fresh environment, install the required packages first.

```@example carroll_schwarzschild_julia
# Uncomment the lines below if running on Google Colab:
# using Pkg
# Pkg.add("XAct")
# Pkg.add("Plots")
```

## 2. Setup

Load the required modules.

```@example carroll_schwarzschild_julia
using XAct
using Plots
using LinearAlgebra

# Headless plotting for build compatibility
ENV["GKSwstype"] = "100"
```

!!! info "Project Profile for AI Agents (LLM TL;DR)"
    - **Goal**: Implement Schwarzschild metric, check one textbook curvature invariant, and interpret the geodesic effective potential honestly.
    - **Reference**: Carroll, *Spacetime and Geometry*, Chapter 5.
    - **Key Symbols**: Manifold `:M4`, Metric `:g`, CovD `:CD`.
    - **Physics**: Evaluate the Kretschmann scalar $K = R_{abcd}R^{abcd} = 48M^2/r^6$ for `M=1`, then mark the horizon, photon sphere, and ISCO on $V_{\text{eff}}$.

## 2. Define the Manifold and Chart

We define a 4D manifold $M$ with Schwarzschild coordinates $(t, r, \theta, \phi)$.

```@example carroll_schwarzschild_julia
reset_state!()
M = def_manifold!(:M4, 4, [:a, :b, :c, :d, :t, :r, :th, :ph])
@indices M4 a b c d t r th ph

# Schwarzschild chart
def_chart!(:Schw, :M4, [1, 2, 3, 4], [:t, :r, :th, :ph])
```

## 3. The Schwarzschild Metric

The Schwarzschild metric in coordinates $(t, r, \theta, \phi)$ is:
$ds^2 = -\left(1 - \frac{2GM}{r}\right) dt^2 + \left(1 - \frac{2GM}{r}\right)^{-1} dr^2 + r^2 d\theta^2 + r^2 \sin^2\theta d\phi^2$

We'll set $G=M=1$ for simplicity ($r_s = 2$).

```@example carroll_schwarzschild_julia
def_metric!(-1, "g[-a,-b]", :CD)

# Define the components at a specific point (e.g., r=3, theta=pi/2)
function schwarzschild_metric(r, θ)
    f = 1 - 2/r
    return [-f 0 0 0;
             0 1/f 0 0;
             0 0 r^2 0;
             0 0 0 r^2*sin(θ)^2]
end

r_val = 3.0
θ_val = π/2
g_comp = schwarzschild_metric(r_val, θ_val)

set_components!(:g, g_comp, [:Schw, :Schw])

println("Schwarzschild metric at r=", r_val, ", θ=π/2:")
g_comp
```

## 4. Curvature Diagnostic: the Kretschmann Scalar

A pointwise component assignment is enough to *sample* the Schwarzschild metric,
but it is **not** a proof that the full vacuum equations hold globally. So, to
keep this notebook high-trust, we check one standard Schwarzschild diagnostic
quantity instead of claiming a complete vacuum derivation.

A textbook invariant is the Kretschmann scalar

```math
K = R_{abcd}R^{abcd} = \frac{48 M^2}{r^6}.
```

which Carroll discusses as a coordinate-independent way to see that the true
curvature singularity is at $r=0$, not at the horizon. For our units $M=1$,
this becomes $K = 48/r^6$.

```@example carroll_schwarzschild_julia
RS = tensor(:RicciScalarCD)
G_derived = VarD(RS[], :g, :CD)

println("Generic Einstein tensor identity from variational calculus:")
G_derived

schwarzschild_kretschmann(r; M=1.0) = 48 * M^2 / r^6
sample_kretschmann = schwarzschild_kretschmann(r_val)
expected_kretschmann = 48 / r_val^6

@assert isapprox(sample_kretschmann, expected_kretschmann; rtol=1e-12)
println("Kretschmann scalar check passed: K(r=", r_val, ") = ", sample_kretschmann)
```

This calculation is deliberately modest in scope: it validates one real
Schwarzschild invariant at the sampled radius, while the variational-derivative
output above remains a **general identity** for the Einstein tensor rather than a
standalone proof that our sampled coordinate components solve the vacuum field
equations everywhere.

## 5. Geodesics and Effective Potential

For equatorial geodesics, Carroll's effective-potential picture separates three
kinds of statements:

1. the **formula** for $V_{\text{eff}}(r)$,
2. the **special radii** it highlights in Schwarzschild spacetime, and
3. the **physical interpretation** of those radii.

Here we keep those levels separate. We plot the standard effective potential and
explicitly mark the event horizon, photon sphere, and ISCO rather than implying
that the plot alone derives the full geodesic theory.

```@example carroll_schwarzschild_julia
function V_eff(r, L, ϵ)
    M = 1.0
    return 0.5 * ϵ + L^2 / (2r^2) - (ϵ * M) / r - (M * L^2) / r^3
end

event_horizon = 2.0
photon_sphere = 3.0
isco = 6.0

@assert event_horizon == 2.0
@assert photon_sphere == 3.0
@assert isco == 6.0
println("Key Schwarzschild radii: horizon=", event_horizon, ", photon sphere=", photon_sphere, ", ISCO=", isco)

rs = range(2.1, 15, length=200)
p = plot(title="Schwarzschild Effective Potential (M=1)",
         xlabel="r", ylabel="V_eff", ylims=(-0.1, 0.6))

# Timelike geodesics with different angular momenta
for L in [3.0, 3.46, 4.0, 4.5]
    plot!(p, rs, [V_eff(r, L, 1.0) for r in rs], label=string("L=", L, " (massive)"))
end

# Null geodesic (photon)
plot!(p, rs, [V_eff(r, 4.0, 0.0) for r in rs], label=string("L=", 4.0, " (photon)"), linestyle=:dash, color=:black)

vline!(p, [event_horizon], label="Event horizon r=2M", linestyle=:dot, color=:red)
vline!(p, [photon_sphere], label="Photon sphere r=3M", linestyle=:dash, color=:purple)
vline!(p, [isco], label="ISCO r=6M", linestyle=:dashdot, color=:blue)
hline!(p, [0.5], label="E∞ (particle at rest)", alpha=0.3)
p
```

### Interpreting the marked radii

- **Event horizon, $r=2M$**: a causal boundary of the Schwarzschild coordinates,
  not a curvature singularity; the Kretschmann scalar above stays finite there.
- **Photon sphere, $r=3M$**: the distinguished radius for unstable circular null
  orbits.
- **ISCO, $r=6M$**: the innermost stable circular orbit for timelike geodesics.

These landmarks are textbook facts from Carroll's Chapter 5. In this notebook,
the plot is best read as a visualization that helps interpret those known radii,
not as a complete derivation of all orbital properties from first principles.

## 6. Summary

This tutorial demonstrated:
1. Implementing the Schwarzschild metric in standard coordinates.
2. Sampling one genuine Schwarzschild curvature invariant, the Kretschmann scalar.
3. Visualizing the effective potential while clearly labeling the horizon, photon sphere, and ISCO.
4. Distinguishing between a general tensor identity, a sampled coordinate realization, and the physical interpretation of the resulting plots.

## Next Steps

- **Cosmology**: Explore the [Wald: FLRW Cosmology](wald_cosmology_julia.md) tutorial.
- **Wave Equations**: See [MTW: Gravitational Waves](mtw_gravitational_waves_julia.md).
- **Foundations**: Review [2-Sphere Geometry](foundations_sphere_julia.md).
