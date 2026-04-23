!!! tip "Run this notebook"
    - [Download the Jupyter notebook](https://github.com/sashakile/XAct.jl/blob/main/notebooks/julia/carroll_schwarzschild.ipynb)
    - [Open in Google Colab](https://colab.research.google.com/github/sashakile/XAct.jl/blob/main/notebooks/julia/carroll_schwarzschild.ipynb)
    - [Open in Binder](https://mybinder.org/v2/gh/sashakile/XAct.jl/main?urlpath=lab/tree/notebooks/julia/carroll_schwarzschild.ipynb)

# Carroll: Schwarzschild Geodesics and Curvature

This tutorial follows **Sean Carroll's *Spacetime and Geometry* (Chapter 5)**.
We will implement the Schwarzschild metric—the unique spherically symmetric
vacuum solution to Einstein's field equations—and explore its curvature and
geodesic structure.

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
    - **Goal**: Implement Schwarzschild metric and verify vacuum field equations.
    - **Reference**: Carroll, *Spacetime and Geometry*, Chapter 5.
    - **Key Symbols**: Manifold `:M4`, Metric `:g`, CovD `:CD`.
    - **Physics**: Verify $R_{\mu\nu} = 0$, plot effective potential $V_{\text{eff}}$.

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

println("Schwarzschild metric at r=$r_val, θ=π/2:")
g_comp
```

## 4. Curvature and Field Equations

The Schwarzschild metric is a vacuum solution, meaning the Ricci tensor $R_{ab}$
must vanish everywhere outside the source ($r > r_s$).

In General Relativity, the vacuum field equations $G_{ab} = 0$ can be derived
from the Einstein-Hilbert action:
$S = \int d^4x \sqrt{-g} R$

Using `XAct.jl`, we can derive the Einstein tensor by taking the **variational
derivative** of the Ricci Scalar with respect to the metric.

```@example carroll_schwarzschild_julia
RS = tensor(:RicciScalarCD)

# Variational derivative of R w.r.t metric g:
# G_ab = VarD(R, g)
# (Note: In sxAct, we use the abstract tensor names)
G_derived = VarD(RS[], :g, :CD)

println("Derived Einstein tensor formula:")
G_derived
```

The output shows the derived expression for $G_{ab}$ in terms of the Ricci
tensor and scalar, exactly matching the definition $G_{ab} = R_{ab} - \frac{1}{2}g_{ab}R$.

## 5. Geodesics and Effective Potential


Geodesics in Schwarzschild spacetime are governed by the effective potential:
$V_{\text{eff}}(r) = \frac{1}{2}\epsilon + \frac{L^2}{2r^2} - \frac{\epsilon M}{r} - \frac{ML^2}{r^3}$

where $\epsilon=1$ for timelike geodesics (massive particles) and $\epsilon=0$
for null geodesics (photons).

```@example carroll_schwarzschild_julia
function V_eff(r, L, ϵ)
    M = 1.0
    return 0.5*ϵ + L^2/(2r^2) - (ϵ*M)/r - (M*L^2)/r^3
end

rs = range(2.1, 15, length=200)
p = plot(title="Schwarzschild Effective Potential (M=1)",
         xlabel="r", ylabel="V_eff", ylims=(-0.1, 0.6))

# Timelike geodesics with different angular momenta
for L in [3.0, 3.46, 4.0, 4.5]
    plot!(p, rs, [V_eff(r, L, 1.0) for r in rs], label="L=$L (Massive)")
end

# Null geodesic (Photon)
plot!(p, rs, [V_eff(r, 4.0, 0.0) for r in rs], label="L=4 (Photon)", linestyle=:dash, color=:black)

hline!(p, [0.5], label="E_inf (at rest)", alpha=0.3)
p
```

### Key Features:
- **Innermost Stable Circular Orbit (ISCO)**: Located at $r = 6M$.
- **Photon Sphere**: Located at $r = 3M$ (the peak of the null potential).
- **Event Horizon**: Located at $r = 2M$.

## 6. Summary

This tutorial demonstrated:
1. Implementing a complex 4D metric from a standard textbook.
2. Setting coordinate-basis components for a specific spacetime geometry.
3. Visualizing the effective potential that dictates orbital mechanics in GR.

## Next Steps

- **Cosmology**: Explore the [Wald: FLRW Cosmology](wald_cosmology_julia.md) tutorial.
- **Wave Equations**: See [MTW: Gravitational Waves](mtw_gravitational_waves_julia.md).
- **Foundations**: Review [2-Sphere Geometry](foundations_sphere_julia.md).
