!!! tip "Run this notebook"
    - [Download the Jupyter notebook](https://github.com/sashakile/XAct.jl/blob/main/notebooks/julia/physics_fluids.ipynb)
    - [Open in Google Colab](https://colab.research.google.com/github/sashakile/XAct.jl/blob/main/notebooks/julia/physics_fluids.ipynb)
    - [Open in Binder](https://mybinder.org/v2/gh/sashakile/XAct.jl/main?urlpath=lab/tree/notebooks/julia/physics_fluids.ipynb)

# Physics: Relativistic Fluid Dynamics

This tutorial explores **Relativistic Fluid Dynamics** using `XAct.jl`.
We will define the energy-momentum tensor for a **perfect fluid**, verify its
conservation laws, and derive the relativistic Euler equations.

## 1. Setup

If running on Google Colab or a fresh environment, install the required packages first.

```@example physics_fluids_julia
# Uncomment the lines below if running on Google Colab:
# using Pkg
# Pkg.add("XAct")
# Pkg.add("Plots")
```

## 2. Setup

Load the required modules.

```@example physics_fluids_julia
using XAct
using Plots
using LinearAlgebra

# Headless plotting for build compatibility
ENV["GKSwstype"] = "100"
```

!!! info "Project Profile for AI Agents (LLM TL;DR)"
    - **Goal**: Implement perfect fluid $T_{ab}$ and verify conservation laws.
    - **Key Symbols**: Velocity $u^a$, Density $\rho$, Pressure $p$.
    - **Physics**: $T_{ab} = (\rho + p)u_a u_b + p g_{ab}$, verify $\nabla_a T^{ab} = 0$.

## 2. Define the Manifold and Metric

```@example physics_fluids_julia
reset_state!()
M = def_manifold!(:M4, 4, [:alpha, :beta, :gamma, :delta, :mu, :nu])
@indices M4 alpha beta gamma delta mu nu

# General metric g_ab
g = def_metric!(-1, "g[-mu,-nu]", :CD)
```

## 3. The Perfect Fluid Energy-Momentum Tensor

A perfect fluid is characterized by its **energy density** $\rho$,
**pressure** $p$, and **4-velocity** $u^\mu$. The energy-momentum tensor is:
$T_{\mu\nu} = (\rho + p) u_\mu u_\nu + p g_{\mu\nu}$

```@example physics_fluids_julia
# Define scalar fields rho and p
def_tensor!(:rho, String[], :M4)
def_tensor!(:p, String[], :M4)
rho = tensor(:rho)
p_tensor = tensor(:p)

# Define 4-velocity vector u^mu
def_tensor!(:u, ["mu"], :M4)
u = tensor(:u)

# Define T_mu_nu
# T_mu_nu = (rho + p) u_mu u_nu + p g_mu_nu
T_expr = ToCanonical((rho[] + p_tensor[]) * u[-mu] * u[-nu] + p_tensor[] * tensor(:g)[-mu, -nu])

println("Energy-Momentum Tensor T_{μν}:")
T_expr
```

## 4. Conservation Laws

The physical evolution of the fluid is governed by the conservation of
energy and momentum:
$\nabla_\mu T^{\mu\nu} = 0$

```julia
# Compute the divergence: g^{αμ} ∇_α T_{μν}
div_T = ToCanonical(
    Contract(tensor(:g)[alpha, mu] * covd(:CD)[-alpha](rho[] * u[-mu] * u[-nu]))
    + Contract(tensor(:g)[alpha, mu] * covd(:CD)[-alpha](p_tensor[] * u[-mu] * u[-nu]))
    + Contract(tensor(:g)[alpha, mu] * covd(:CD)[-alpha](p_tensor[] * tensor(:g)[-mu, -nu]))
)
```

## 5. Deriving Continuity and Euler Equations

The conservation equations $\nabla_\mu T^{\mu\nu} = 0$ contain both the energy
conservation (continuity) and momentum conservation (Euler) equations.

### Energy Conservation
Projecting along the 4-velocity ($u_\nu \nabla_\mu T^{\mu\nu} = 0$) yields the
continuity equation:
$u^\mu \nabla_\mu \rho + (\rho + p) \nabla_\mu u^\mu = 0$

```julia
# Project divergence onto u^nu
energy_cons = ToCanonical(Contract(u[nu] * div_T))
```
## 6. Summary

This tutorial demonstrated:
1. Constructing complex physical tensors from fundamental fields.
2. Symbolically deriving conservation laws in curved spacetime.
3. Projecting tensor equations to extract specific physical components (like energy conservation).

## Next Steps

- **Electromagnetism**: See [Maxwell's Equations in Curved Spacetime](physics_em_julia.md).
- **Black Holes**: Review [Carroll: Schwarzschild Geodesics](carroll_schwarzschild_julia.md).
- **Cosmology**: Review [Wald: FLRW Cosmology](wald_cosmology_julia.md).
