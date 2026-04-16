# XAct.jl Feature Completion Matrix

!!! info "Status TL;DR for AI Agents"
    All core xAct modules ported: XPerm (canonicalization), XTensor (algebra, CovD, perturbation, IBP, VarD, Session isolation, TExpr typed expressions Stage 2), xCoba (coordinates, Christoffel), xTras (utilities), XInvar (Riemann invariant engine, all 11 phases). 1200+ Julia unit tests + 900+ Python tests passing. Architecture note: engine operates on strings (not typed AST); TExpr layer adds typed input/output but serializes internally. Gaps: spinors, exterior calculus, LaTeX rendering.

This page tracks the implementation status of features ported from the Wolfram [xAct](http://xact.es/) suite to `XAct.jl`, and their verification status against the Wolfram Language implementation.

---

## 1. XPerm.jl — Permutation Group Engine

High-performance implementation of the Butler-Portugal tensor index canonicalization algorithm.

| Feature | Status | Notes |
|---------|--------|-------|
| Signed permutation representation (n+2 degree) | DONE | Matches `xperm.c` exactly |
| `StrongGenSet` & `SchreierVector` structures | DONE | Core group theory primitives |
| Schreier-Sims algorithm | DONE | |
| `canonicalize_slots()` API | DONE | High-level entry point |
| Niehoff shortcut: `Symmetric` / `Antisymmetric` | DONE | O(k log k) optimization |
| Predefined Groups (Riemann, Young, etc.) | DONE | |
| `double_coset_rep` | DONE | Full implementation replacing stub |
| Young Tableaux | DONE | `YoungTableau` struct + 6 functions |
| WL Compatibility Layer | DONE | CamelCase aliases for Wolfram parity |

---

## 2. XTensor.jl — Tensor Algebra

Foundational tensor algebra and curvature operators.

| Action / Feature | Status | Notes |
|--------|--------|-------|
| `DefManifold` / `DefVBundle` | DONE | |
| `DefMetric` | DONE | Auto-creates Riemann/Ricci/RicciScalar/Einstein/Weyl/Christoffel |
| `DefTensor` (with symmetry) | DONE | Symmetric, Antisymmetric, GradedSymmetric, Riemann, Young |
| `ToCanonical` | DONE | Full parse → canonicalize → serialize pipeline |
| `Contract` | DONE | Metric-aware index contraction |
| `Simplify` | DONE | Iterative Contract → ToCanonical loop |
| `CommuteCovDs` / `SortCovDs` | DONE | Covariant derivative commutation and canonical ordering with Riemann corrections |
| `DefPerturbation` / `Perturb` | DONE | Multinomial Leibniz expansion |
| `PerturbCurvature` | DONE | Curvature tensor perturbation rules |
| `PerturbationOrder` / `PerturbationAtOrder` | DONE | Order extraction and filtering |
| `IBP` (Integration by Parts) | DONE | |
| `TotalDerivativeQ` | DONE | Total derivative detection |
| `VarD` (Euler-Lagrange) | DONE | Variational derivative |
| `Evaluate` | DONE | Expression evaluation and binding |
| `Assert` | DONE | Symbolic condition checking |
| Curvature Tensors (Riemann, Ricci, Weyl, etc.) | DONE | Auto-created by `DefMetric` |
| `RegisterIdentity!` / Multi-term identities | DONE | Bianchi identities, custom identity framework |
| `Session` struct & `reset_session!` | DONE | Isolated mutable state; all `def_*!` / accessors accept `session` kwarg |
| `reset_state!()` | DONE | Clean session state for testing |
| `ValidateSymbolInSession` | DONE | Checks all registries for name collisions |
| **TExpr typed expression layer (Stage 2)** | **DONE** | `@indices`, `tensor()`, `T[-a,-b]` syntax; Typed input AND output. |

---

## 3. xCoba — Coordinate Components

Coordinate bases, component arrays, and Christoffel symbols.

| Feature | Status | Notes |
|---------|--------|-------|
| `DefBasis` / `DefChart` | DONE | Basis and chart definitions |
| `SetBasisChange` / `ChangeBasis` | DONE | Coordinate transforms with Jacobians |
| `CTensor` / `SetComponents` / `GetComponents` | DONE | Component arrays with auto-transform |
| `ToBasis` / `FromBasis` / `TraceBasisDummy` | DONE | Abstract ↔ component conversion |
| `Christoffel` | DONE | Γ^a_{bc} from metric + derivatives |

---

## 4. XInvar.jl — Riemann Invariant Engine

Classification and simplification of Riemann invariants using the Invar database. All 11 phases complete.

| Feature | Status | Notes |
|---------|--------|-------|
| `RPerm` / `RInv` / `DualRInv` types | DONE | Core invariant representations |
| `InvarCases()` / `InvarDualCases()` | DONE | 48 non-dual + 15 dual cases through order 10-14 |
| `MaxIndex` / `MaxDualIndex` | DONE | 50 + 17 entries |
| `RiemannToPerm` / `PermToRiemann` | DONE | Conversion with optional curvature relations |
| `PermToInv` / `InvToPerm` | DONE | DB lookup with dispatch cache |
| Database parser (`InvarDB.jl`) | DONE | Maple + Mathematica format parsing |
| `InvSimplify` | DONE | 6-level pipeline: cyclic, Bianchi, CovD, dim-dep, dual |
| `RiemannSimplify` | DONE | End-to-end user-facing simplification |
| `SortCovDs` | DONE | Canonical CovD chain ordering with Riemann corrections |
| Dimension-dependent identities | DONE | Phase 9 |
| Dual invariants / Levi-Civita | DONE | Phase 10 |

---

## 5. xTras — Utilities

Extended tensor manipulation utilities.

| Feature | Status | Notes |
|---------|--------|-------|
| `CollectTensors` | DONE | Group like tensor terms |
| `AllContractions` | DONE | Enumerate all possible contractions |
| `SymmetryOf` | DONE | Extract symmetry of expression |
| `MakeTraceFree` | DONE | Trace-free projection |

---

## 6. Verification Layer

The `sxact` Python package provides a multi-tier verification suite.

| Feature | Status | Notes |
|---------|--------|-------|
| `JuliaAdapter` | DONE | Routes actions to XTensor.jl |
| `WolframAdapter` (Oracle) | DONE | Connects to Dockerized Wolfram Engine |
| Normalization Pipeline | DONE | Whitespace and dummy index canonicalization |
| Three-tier Comparison Engine | DONE | String, Symbolic, and Numeric verification |
| Oracle Snapshot Mode | DONE | Deterministic hash-based regression testing |
| Property-based Testing | DONE | 29 properties across 3 suites; 27/29 pass Julia, 2 skip (not exposed) |
| Performance Benchmarking | PARTIAL | Baseline tracking for core operations |

---

## 7. Test Suites

| Suite | Count | Status | Notes |
|-------|-------|--------|-------|
| XPerm Julia Unit Tests | 156 | PASS | Permutation group, Schreier-Sims, Young tableaux |
| XTensor Julia Unit Tests | 567 | PASS | Tensor algebra, xCoba, xTras, perturbation, Session |
| TExpr Julia Unit Tests | 238 | PASS | Typed expression layer |
| XInvar Julia Unit Tests | 648,825 | PASS | Riemann invariant phases 2-11 |
| Python Runner Tests | 909 | PASS | Adapter, normalization, CLI, TExpr |
| Property Tests (Layer 2) | 29 | PASS | Riemann symmetries, tensor algebra, xCore laws (27 pass, 2 skip) |

---

## Maturity & Known Limitations

!!! warning "Early adopter stage"
    XAct.jl has been developed and tested by a single author. It has not yet
    been used in production research by the broader community. We encourage
    early adopters to **try it on real problems and report issues** — that is
    the most valuable contribution at this stage.

### Architecture: string-based engine

The current engine (`ToCanonical`, `Contract`, `Simplify`, etc.) operates on
**string representations** of tensor expressions. Every call parses the input
string into an internal coefficient map, performs the operation, and serializes
back to a string. This mirrors the original Wolfram xAct design but is not
idiomatic Julia — it prevents type dispatch, compiler optimizations, and
zero-allocation workflows.

The **TExpr typed expression layer** (Stage 2, complete) provides a typed
front-end (`@indices`, `tensor()`, `T[-a,-b]` syntax) that validates at
construction time, but currently serializes to string before calling the engine.
A future refactor will make TExpr the native representation throughout the
pipeline, eliminating the parse/serialize round-trips.

### Python wrapper

The [`xact-py`](https://pypi.org/project/xact-py/) package provides a Pythonic
API backed by the Julia engine via
[juliacall](https://github.com/JuliaPy/PythonCall.jl). It makes XAct.jl
accessible to researchers who prefer Python without sacrificing the Julia
engine's performance.

---

## Roadmap

### Coverage of the original xAct suite

The table below maps the original Wolfram [xAct](http://xact.es/) packages
(by José M. Martín-García et al.) to their XAct.jl status.

| Wolfram xAct package | XAct.jl module | Status | Notes |
|:---------------------|:---------------|:-------|:------|
| **xCore** | `XCore.jl` | **Ported** | Symbol registry, utility layer |
| **xPerm** | `XPerm.jl` | **Ported** | Butler-Portugal canonicalization, Schreier-Sims, Young tableaux |
| **xTensor** | `XTensor.jl` | **Ported** | Abstract tensor algebra, CovD, perturbation, IBP, VarD |
| **xCoba** | `XTensor/Coba.jl` | **Ported** | Coordinate bases, Christoffel, component arrays |
| **Invar** | `XInvar.jl` | **Ported** | All 11 phases — Riemann invariant classification and simplification |
| **xPert** | (in `XTensor.jl`) | **Partial** | `perturb()`, `PerturbCurvature` done; high-order gauge not yet |
| **xTras** | (in `XTensor.jl`) | **Partial** | `CollectTensors`, `AllContractions`, `SymmetryOf`, `MakeTraceFree` |
| **Spinors** / **SpinFrames** | — | Not started | Requires spinor index type |
| **xTerior** | — | Not started | Exterior calculus (forms, wedge, Hodge, d) |
| **Harmonics** | — | Not started | Tensor spherical harmonics |
| **TexAct** | — | Not started | LaTeX rendering |
| **xPrint** | — | Not started | Formatted input interface |
| **SymManipulator** | — | Not started | Symmetrized expressions |
| Other packages (xPand, FieldsX, xPPN, etc.) | — | Not planned | Domain-specific; community contributions welcome |

### Planned work (prioritized)

**Near-term — internal quality**

1. **TExpr as native engine representation**: Eliminate the string
   parse/serialize round-trip. Make `TExpr` the internal representation that
   `ToCanonical`, `Contract`, and `Simplify` operate on directly. This is the
   single most impactful architectural improvement.
2. **Session isolation completion**: Reader functions (`ToCanonical`, `Contract`,
   `Simplify`) still access some global state; migrate remaining references to
   the `Session` struct.
3. **Rich display (TExpr Stage 3)**: Unicode REPL output and LaTeX rendering
   for Jupyter/Pluto notebooks.

**Medium-term — new capabilities**

4. **Spinors / NP / GHP**: Spinor index type, Newman-Penrose and
   Geroch-Held-Penrose formalisms.
5. **xTerior**: Exterior calculus — differential forms, wedge product, Hodge
   star, exterior derivative.
6. **DifferentialEquations.jl integration**: Geodesic equations, numerical
   integration of component ODEs from xCoba output.

**Long-term — ecosystem**

7. **Harmonics**: Tensor spherical harmonic decomposition for cosmological
   perturbation theory.
8. **TexAct**: Publication-quality LaTeX output.
9. **TExpr Stage 4**: Introspection API — `free_indices()`, `rank()`,
   `terms()`, pattern matching.

### How to contribute

The most impactful contributions right now:

- **Use it and file issues.** The library has parity-level test coverage against
  the Wolfram engine, but edge cases in real research workflows are the best way
  to find gaps.
- **Report confusing APIs.** If something feels un-Julian or the error messages
  are unhelpful, that's a bug.
- **Benchmark against Wolfram.** Performance comparisons on real-world
  expressions help prioritize optimization work.
