# XAct.jl

!!! info "Project Profile for AI Agents (LLM TL;DR)"
    - **Name**: XAct.jl (Repository: `XAct.jl`)
    - **Primary Language**: Julia (Computational Core)
    - **Function**: Symbolic tensor algebra and curvature calculus for General Relativity.
    - **Ecosystem**: Native Julia port of the Wolfram [xAct](http://xact.es/) suite by José M. Martín-García et al.
    - **Verification**: Parity verified against Wolfram Engine via `sxact` test framework.
    - **License**: GNU General Public License v3.0 (GPL-3.0)

A native Julia port of the [xAct](http://xact.es/) tensor algebra suite for general relativity, originally developed for Wolfram Mathematica. Rewrites xPerm, xTensor, xCoba, and Invar in pure Julia for performance, composability, and open access without a Mathematica license.

## Fast Track (Julia)

Get started in 60 seconds. Open your Julia REPL and run:

```julia
using XAct

reset_state!()
def_manifold!(:M, 4, [:a, :b, :c, :d])
def_tensor!(:T, ["-a", "-b"], :M; symmetry_str="Symmetric[{-a,-b}]")

@indices M a b c d     # typed index variables
T_h = tensor(:T)       # tensor handle

ToCanonical(T_h[-b,-a] - T_h[-a,-b])  # returns "0"
```

The `@indices` / `tensor()` syntax is the **typed API** — it validates slot counts
and manifold membership at construction time. See [Typed Expressions (TExpr)](guide/TExpr.md)
for the full guide. The string API (`ToCanonical("T[-b,-a] - T[-a,-b]")`) also works
everywhere and can be mixed freely.

## Project Overview

The `XAct.jl` project provides the native Julia implementation of the [xAct](http://xact.es/) tensor calculus suite originally created by José M. Martín-García and collaborators for Wolfram Mathematica. It is designed as the modern, open-source successor — a complete rewrite rather than a wrapper.

### Components
- **XAct.jl** (Core): The computational engine written in native Julia — covers canonicalization (Butler-Portugal/xPerm), contraction, covariant derivatives, perturbation theory, coordinate components (xCoba), Riemann invariants (Invar), and more.
- **sxact** (Verification): A Python framework for automated parity testing against the Wolfram Engine using TOML-defined test cases and oracle snapshots.

## Migration Rosetta Stone

For the full table, see [Getting Started](getting-started.md#4-reference-migration-rosetta-stone).

| Operation | Wolfram (xAct) | Julia (xAct.jl) | Status |
| :--- | :--- | :--- | :--- |
| **DefManifold** | `DefManifold[M, 4, {a,b}]` | `def_manifold!(:M, 4, [:a, :b])` | ✅ Verified |
| **DefMetric** | `DefMetric[-1, g[-a,-b], CD]` | `def_metric!(-1, "g[-a,-b]", :CD) ` | ✅ Verified |
| **ToCanonical** | `ToCanonical[expr]` | `ToCanonical(expr)` | ✅ Verified |
| **Contract** | `ContractMetric[expr]` | `Contract(expr)` | ✅ Verified |
| **RiemannSimplify** | `RiemannSimplify[expr, CD]` | `RiemannSimplify(expr, :CD)` | ✅ Verified |
| **RiemannToPerm** | `RiemannToPerm[expr]` | `RiemannToPerm(expr)` | ✅ Verified |

## Coming from Wolfram xAct?
Use the [Wolfram Migration Guide](wolfram-migration.md) to automatically translate your existing Wolfram code to Julia with the `xact-test translate` CLI.

## Installation
See the [Installation Guide](installation.md) for details on setting up the Julia package. Docker and the Wolfram Oracle are only required for running the verification suite.

## Architecture
The implementation follows a layered approach, described in the [Architecture](architecture.md) section.

## AI Attribution

The majority of this codebase was developed with AI assistance using [Claude Code](https://claude.ai/claude-code), [Gemini](https://gemini.google.com/), and [Amp Code](https://ampcode.com/). All code is human-reviewed and tested against the Wolfram Engine oracle for mathematical correctness. We believe AI-assisted development, when paired with rigorous verification, produces higher-quality scientific software.
