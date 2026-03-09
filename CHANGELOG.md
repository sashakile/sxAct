# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-03-09

### Highlights

- **92/92 Butler permutation examples passing** — XPerm.jl fully implements Butler-Portugal canonicalization
- **40/40 xTensor Tier 1 TOML tests passing** — manifolds, tensors, metrics, curvature tensors
- **540 Python unit tests passing** — oracle, normalize, compare, adapter, runner
- **219 oracle snapshots** recorded from Wolfram Engine + xAct
- Multi-backend adapter: route the same TOML test to Julia or Python

### Added

#### Julia Implementation
- `XPerm.jl`: Butler-Portugal canonicalization with Schreier-Sims algorithm
  - StrongGenSet, SchreierVector, Dimino group enumeration
  - Niehoff shortcuts for Symmetric/Antisymmetric tensors (O(k log k))
  - Riemann group (8 elements) built-in
  - PermWord, DeleteRedundantGenerators, Timing wrappers
  - WL-compat layer: SchreierOrbit, SchreierOrbits, Stabilizer, Dimino, Apply `@@`
- `XTensor.jl`: Abstract tensor algebra
  - `def_manifold!`, `def_metric!`, `def_tensor!` with global state
  - Auto-creates Riemann, Ricci, RicciScalar, Einstein, Weyl from `def_metric!`
  - `ToCanonical`: parse → canonicalize → collect → serialize pipeline
  - Einstein expansion and Bianchi identity reduction rules
  - CovD reduction rules for metric compatibility
- `XCore.jl`: Type hierarchy, symbol registry, basic utilities
- Julia unit tests: 44 xPerm + 43 xTensor

#### Python Infrastructure
- Oracle client: HTTP client to Wolfram/xAct Docker service with snapshot support
- Normalization pipeline: AST parser, dummy index canonicalization ($1, $2, …), term ordering
- Comparator: expression equivalence assertion + N-sample numeric substitution
- TOML runner: lifecycle management, per-file isolation, hash verification
- CLI: `xact-test run/property/benchmark` commands
- Property runner: Layer 2 property catalog (27/29 pass), cross-adapter comparison (`--compare-adapter`)
- Benchmark harness: Layer 3 performance regression tracking with machine metadata

#### CI / Tooling
- GitHub Actions: pytest, Julia unit tests, TOML regression, benchmark regression check
- CI baseline JSON (`ci_baseline.json`) for performance thresholds
- Pre-commit hooks: ruff, mypy, julia-format, end-of-file, trailing whitespace

#### Specifications & Design
- `specs/`: 16 design documents covering architecture, roadmap, and ecosystem plans
- Eleguá orchestrator RFC and Chacana DSL specification (v0.2.4, grammar v0.1.1)
- xAct library migration master plan and roadmap

### Fixed

- Unique per-context Wolfram namespace in KernelManager
- Flask threaded mode with RLock serialization
- Multi-letter index support in `_INDEX_RE`
- Julia adapter: fresh property symbol bindings, ruff lint (26 auto-fixed, 19 manual)
- Butler suite: Apply `@@`, SchreierOrbit named-gen injection, timing destructuring

### Deferred (Tier 2+)

- `Contract` / `Simplify` actions (index contraction)
- Covariant derivatives, Christoffel symbols
- xCoba component calculations
- xPert perturbation theory
- Chacana PEG parser extraction (Eleguá package)

---

## [0.1.0] - 2026-01-22

Initial prototype: oracle client, Result envelope, normalization pipeline, Python xCore stub,
Layer 1 TOML runner, basic Julia adapter skeleton.
