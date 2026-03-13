# Architecture

!!! info "Architecture TL;DR for AI Agents"
    Three Julia modules (XCore → XPerm → XTensor) bundled as `xAct.jl`. Verified via Python `sxact` framework against Dockerized Wolfram Oracle using TOML test cases and snapshot comparison.

`xAct.jl` is the native Julia core of the xAct tensor algebra suite. It is designed to be a high-performance, standalone library for symbolic tensor algebra, with a companion verification framework to ensure parity with the original Wolfram implementation.

## Related Projects

- **xAct.jl** (This Repo): The native computational engine and verification suite.
- [Chacana](https://github.com/sashakile/chacana) (External): A language-agnostic Tensor DSL and specification.

## Julia Core

The native library follows the original xAct design, split into three modules bundled by `xAct.jl`:

- **XCore.jl**: Foundational symbol registry, expression validator, and session state manager.
- **XPerm.jl**: Group theory engine implementing the Butler-Portugal algorithm for tensor index canonicalization. Includes Schreier-Sims, Niehoff shortcuts, and Young tableaux.
- **XTensor.jl**: Tensor algebra layer providing manifolds, bundles, metrics, curvature operators, covariant derivatives, perturbation theory, variational calculus, coordinate components (xCoba), and extended utilities (xTras).

## Verification Layer

To ensure mathematical correctness, `xAct.jl` is verified against the original Wolfram implementation:

- **Wolfram Oracle**: A Dockerized Wolfram Engine running xAct. Provides reference results for parity testing.
- **Test Runner (`sxact`)**: A Python framework that drives TOML-defined test cases through the Julia and Wolfram adapters, comparing results via normalization, symbolic simplification, and numeric sampling.
- **Oracle Snapshots**: Deterministic hash-based regression testing that allows verification without a live Wolfram Engine.

## Data Flow

```text
Julia REPL / Notebook
  └── using xAct
        ├── XCore.jl    (symbol registry, session state)
        ├── XPerm.jl    (Butler-Portugal canonicalization)
        └── XTensor.jl  (tensor algebra, xCoba, xTras)

Verification Pipeline
  TOML test file
    → xact-test CLI
      → JuliaAdapter (or WolframAdapter)
        → Normalize + Compare against oracle snapshot
```
