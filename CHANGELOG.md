# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.5.0] - 2026-03-18

### Highlights

- **TExpr typed expression layer** — every engine function returns typed `TTensor`, `Idx`, `TensorHead`, `CovDHead` values
- **Python public API** — `xact.api` with zero juliacall exposure; `Manifold`, `Metric`, `Tensor`, `Perturbation`, `CTensor`, `Basis`, `Chart` classes
- **xact CLI** — `xact translate` replaces `xact-test translate`; Wolfram Language → Julia/TOML/JSON/Python
- **xCoba completion** — `CTensor`, `Basis`/`Chart` handles, `SetComponents`/`GetComponents`/`ComponentValue`, `BasisChange`/`GetJacobian`
- **Docs overhaul** — Diátaxis structure, Quarto notebooks, TExpr guide, AI-readable architecture
- **819 Python tests passing**, 417 XTensor + 91 XPerm + 782 XInvar Julia tests passing

### Added

#### TExpr — Typed Expression Layer (Stage 1 + Stage 2)
- **`Idx`** — typed index with name, position (up/dn), and manifold binding
- **`TensorHead`** — tensor descriptor carrying symmetry, rank, and slot types
- **`TTensor`** — concrete typed tensor expression with index lists
- **`CovDHead` / `covd()`** — covariant derivative factory returning typed output
- **Round-tripping** — `ToCanonical`, `Contract`, `Simplify`, `CommuteCovDs`, `SortCovDs`, `RiemannSimplify` all return `TTensor`
- **xTras overloads** — `CollectTensors`, `AllContractions` return typed output
- **xCoba overloads** — `ToBasis`, `FromBasis`, `TraceBasisDummy` return typed output

#### Python Public API (`xact.api`)
- **`Manifold`**, **`Metric`**, **`Tensor`**, **`Perturbation`** handle classes
- **`CTensor`** — component tensor handle for xCoba workflows
- **`Basis`** / **`Chart`** — frame and coordinate chart handles
- Top-level functions: `canonicalize`, `contract`, `simplify`, `perturb`, `commute_covds`, `sort_covds`, `ibp`, `var_d`, `riemann_simplify`, `reset`, `dimension`
- Zero juliacall exposure; fully typed (mypy strict)

#### xact CLI
- `xact translate` subcommand (moved from `xact-test`)
- Interactive REPL with `--no-eval` mode and session export

#### xCoba Completion
- `SetComponents` / `GetComponents` / `ComponentValue`
- `CTensorQ`, `BasisChangeQ`
- `BasisChange`, `GetJacobian`

### Fixed
- juliacall `FromBasis` `AbstractString` overload using `invoke` to fix JET false positive
- `commute_covds` and `sort_covds` passing covd as Julia Symbol
- stale xAct pkgimage cache purged before JET test
- mypy strict mode enforced across all packages

### Infrastructure
- Self-hosted CI runners (no GitHub Actions minute limits)
- Pre-push hooks gate on relevant file changes only
- `bd export` snapshot committed to `.beads/issues.jsonl`

### Documentation
- Diátaxis-aligned structure (tutorials / how-tos / reference / explanation)
- Quarto notebooks with Pluto demos (`just lab` for local JupyterLab)
- TExpr guide and Getting Started updated for typed API
- Elegua integration guide and tensor domain specifications

---

## [0.4.0] - 2026-03-17

### Highlights

- **Complete Invar pipeline (Phases 1–11)** — Riemann invariant classification and simplification, matching Wolfram xAct's Invar module
- **Wolfram Expression Translator** — parse Wolfram Language surface syntax, translate to Julia/TOML/JSON/Python, interactive REPL
- **782 XInvar Julia tests passing** — invariant types, permutation conversion, database parser, multi-level simplification, validation benchmarks
- **709 Python tests passing** — full adapter, translator, and runner coverage
- **441 XTensor Julia tests passing** — including SortCovDs, multi-term identities, xTras utilities

### Added

#### XInvar — Riemann Invariant Engine (11 Phases)
- **Multi-term identity framework** — `RegisterIdentity!`, `_apply_identities!`, auto-Bianchi registration
- **RPerm/RInv types** — canonical permutation and invariant label representations
- **InvariantCase catalog** — 48 non-dual cases (order ≤14), 15 dual cases (order ≤10), `MaxIndex`/`MaxDualIndex` tables
- **RiemannToPerm** — tensor string → canonical permutation, with Ricci/RicciScalar expansion, CovD wrapping
- **PermToRiemann** — inverse conversion with optional `curvature_relations`
- **InvarDB parser** — Maple (cycle notation) and Mathematica (substitution rules) format parsers
- **PermToInv/InvToPerm** — database lookup with dispatch cache
- **InvSimplify** — 6-level pipeline: identity, cyclic, Bianchi, CovD commutation, dimension-dependent, dual
- **RiemannSimplify** — end-to-end `expr → RPerm → InvSimplify → tensor string` pipeline
- **SortCovDs** — canonical CovD chain ordering with Riemann correction generation
- **Dimension-dependent identities** — level 5 simplification for integer dimensions
- **Dual invariants** — level 6 simplification for 4D spacetimes
- **Backtracking canonicalization** — bounds-based pruning + block-perm dedup for n≥5 Riemann products

#### Wolfram Expression Translator
- `wl_to_action` — WL surface-syntax parser, serializer, and action recognizer
- Output renderers: JSON, Julia, TOML, Python
- `xact-test translate` CLI with `--to` format selection
- Interactive REPL with `--no-eval` mode and session export

#### xCoba Extensions
- `ToBasis`, `FromBasis`, `TraceBasisDummy`
- Christoffel symbols from metric CTensor components

#### xTras Utilities
- `CollectTensors`, `AllContractions`, `SymmetryOf`, `MakeTraceFree`

#### Infrastructure
- `juliapkg` — automated Julia/xAct dependency management
- Package split: `xact-py` (Julia wrapper) and `sxact` (validation framework)
- Live-reload docs server via LiveServer.jl
- Yachay identity context specification

### Fixed
- juliacall/PythonCall SIGSEGV on process teardown (os._exit workaround)
- Wolfram Invar permutation convention bridged with internal involution convention
- Invar tutorial gracefully handles missing database in CI
- Literate doc tests available in CI (`[deps]` not just `[extras]`)
- Benchmark test ID collisions resolved
- Wolfram adapter flaky tests
- Performance test threshold relaxed for CI stability

### Documentation
- Wolfram xAct migration guide with translator CLI walkthrough
- Polyglot tutorials (Julia + Python) for basics and Invar
- Architecture, API, and verification docs fully rewritten for current state
- Docs-as-Tests: Literate tutorials execute during test suite

---

## [0.3.0] - 2026-03-11

### Highlights

- **xCoba coordinate components & basis changes**
- **Perturbation theory (xPert)**
- **IBP, VarD, CommuteCovDs** for variational calculus

See [v0.3.0 release](https://github.com/sashakile/sxAct/releases/tag/v0.3.0) for details.

---

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
