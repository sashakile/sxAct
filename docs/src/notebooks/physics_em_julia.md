!!! tip "Run this notebook"
    - [Download the Jupyter notebook](https://github.com/sashakile/XAct.jl/blob/main/notebooks/julia/physics_em.ipynb)
    - [Open in Google Colab](https://colab.research.google.com/github/sashakile/XAct.jl/blob/main/notebooks/julia/physics_em.ipynb)

# Electromagnetism: Maxwell's Equations in Curved Spacetime

This tutorial demonstrates how to use `xAct.jl` to study classical field theories,
specifically **Electromagnetism**. We will define the electromagnetic
vector potential, construct the Faraday tensor, and verify Maxwell's equations
in an arbitrary curved background.

## 1. Dependencies

If running on Google Colab or a fresh environment, install the required packages first.

```@example physics_em_julia
# Uncomment the lines below if running on Google Colab:
# using Pkg
# Pkg.add(url="https://github.com/sashakile/XAct.jl.git")
# Pkg.add("Plots")
```

## 2. Setup

Load the required modules.

```@example physics_em_julia
using xAct
using Plots
using LinearAlgebra

# Headless plotting for build compatibility
ENV["GKSwstype"] = "100"
```

!!! info "Project Profile for AI Agents (LLM TL;DR)"
    - **Goal**: Verify Maxwell's equations and derive the wave equation for $A_a$.
    - **Key Symbols**: Potential $A_a$, Faraday Tensor $F_{ab}$, Current $J^a$.
    - **Physics**: $F_{ab} = \nabla_a A_b - \nabla_b A_a$, verify $\nabla_a F^{ab} = J^b$.

## 3. Define the Manifold and Metric

We start with a general 4D manifold and metric.

```@example physics_em_julia
reset_state!()
M = def_manifold!(:M4, 4, [:alpha, :beta, :gamma, :delta, :mu, :nu])
@indices M4 alpha beta gamma delta mu nu

# General metric g_ab
g = def_metric!(-1, "g[-mu,-nu]", :CD)
```

## 4. The Faraday Tensor

The electromagnetic field is described by the **vector potential** $A_\mu$.
The **Faraday tensor** (or field strength tensor) $F_{\mu\nu}$ is defined as the
exterior derivative of the potential:
$F_{\mu\nu} = \nabla_\mu A_\nu - \nabla_\nu A_\mu$

```@example physics_em_julia
# Define the vector potential A_mu
def_tensor!(:A, ["-mu"], :M4)
A = tensor(:A)

# Define the Faraday tensor F_mu_nu abstractly
# F_mu_nu = CD_mu A_nu - CD_nu A_mu
F_expr = ToCanonical(covd(:CD)[-mu](A[-nu]) - covd(:CD)[-nu](A[-mu]))

println("Faraday tensor F_{μν}:")
F_expr
```

## 5. Maxwell's Equations

In vacuum (or with a source current $J^\mu$), the inhomogeneous Maxwell equations are:
$\nabla_\mu F^{\mu\nu} = J^\nu$

Let's compute the divergence of the Faraday tensor symbolically.

```@example physics_em_julia
# Compute the divergence: g^{αμ} \nabla_α F_{μν}
div_F = ToCanonical(Contract(tensor(:g)[alpha, mu] * covd(:CD)[-alpha](F_expr)))

println("Divergence of F_{μν}:")
div_F
```

## 6. Wave Equation in the Lorenz Gauge

In the **Lorenz gauge** ($\nabla_\mu A^\mu = 0$), the Maxwell equations reduce to a
wave equation for the potential. However, in curved spacetime, a coupling
term to the Ricci tensor appears:
$\square A_\mu - R_\mu{}^\nu A_\nu = -J_\mu$

Let's see if we can derive this relation.

```@example physics_em_julia
# Maxwell equation: \nabla^\alpha (\nabla_\alpha A_\mu - \nabla_\mu A_\alpha)
# Let's expand this and use the Lorenz gauge condition.
maxwell_lhs = ToCanonical(Contract(tensor(:g)[alpha, beta] * covd(:CD)[-alpha](covd(:CD)[-beta](A[-mu]) - covd(:CD)[-mu](A[-beta]))))

println("Maxwell Equation LHS (expanded):")
maxwell_lhs
```
Notice the term involving the commutation of covariant derivatives, which
results in the curvature coupling.

## 7. Summary

This tutorial demonstrated:
1. Defining vector fields and higher-rank tensors for field theory.
2. Constructing field strength tensors using covariant derivatives.
3. Symbolically verifying the structure of Maxwell's equations in curved spacetime.

## Next Steps

- **Fluids**: Explore [Relativistic Fluid Dynamics](physics_fluids_julia.md).
- **Black Holes**: Review [Carroll: Schwarzschild Geodesics](carroll_schwarzschild_julia.md).
- **Foundations**: Review [3D Curvilinear Coordinates](foundations_3d_coords_julia.md).
