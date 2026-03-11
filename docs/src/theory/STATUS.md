# xAct.jl Feature Completion Matrix

This page tracks the implementation status of xAct features in the Julia core (`xAct.jl`) and their verification status against the Wolfram Language implementation.

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
| Predefined Groups (Riemann, etc.) | DONE | |
| Butler-Portugal Test Suite (92 examples) | DONE | 100% verified parity |

---

## 2. XTensor.jl — Tensor Algebra

Foundational tensor algebra and curvature operators.

| Action / Feature | Status | Notes |
|--------|--------|-------|
| `DefManifold` / `DefVBundle` | DONE | |
| `DefMetric` | DONE | |
| `DefTensor` (with symmetry) | DONE | |
| `ToCanonical` | DONE | Full parse → canonicalize → serialize pipeline |
| `Contract` | DONE | Metric-aware index contraction |
| `Evaluate` | DONE | Expression evaluation and binding |
| `Assert` | DONE | Symbolic condition checking |
| Curvature Tensors (Riemann, Ricci, Weyl, etc.) | DONE | Auto-created by `DefMetric` |
| `reset_state!()` | DONE | Clean session state for testing |
| `Simplify` | DEFERRED | Planned for Tier 2 implementation |
| `CovD` (Covariant Derivative) | MISSING | In progress |
| `ChristoffelCD` | MISSING | Required for component calculus |

---

## 3. Python Wrapper & Verification Layer

The `sxact` Python package provides interoperability and a multi-tier verification suite.

| Feature | Status | Notes |
|---------|--------|-------|
| `JuliaAdapter` | DONE | Routes actions to XTensor.jl |
| `PythonAdapter` | DONE | Wraps Julia via `PythonCall.jl` |
| `WolframAdapter` (Oracle) | DONE | Connects to Dockerized Wolfram Engine |
| Normalization Pipeline | DONE | Whitespace and dummy index canonicalization |
| Three-tier Comparison Engine | DONE | String, Symbolic, and Numeric verification |
| Property-based Testing | PARTIAL | 10+ core identities verified; tensor sampling in progress |
| Performance Benchmarking | PARTIAL | Baseline tracking for core operations |

---

## 4. Test Suites

| Suite | Count | Status | Notes |
|-------|-------|--------|-------|
| xCore Utilities | ~20 | PASS | Basic symbol and list operations |
| xPerm Basic Symmetries | 6 | PASS | |
| Butler-Portugal Examples | 92 | PASS | Complex permutation groups |
| xTensor Fundamentals | ~40 | PASS | Manifolds, metrics, and curvature |
| Curvature Invariants | 8 | PASS | Quadratic gravity and Bianchi identities |
| Quadratic Gravity | 8 | PASS | |
| xCore Laws (Property Tests) | 12 | PASS | 10/12 pass; 2 pending missing Julia shims |

---

## Roadmap & Known Gaps

- **Covariant Derivatives**: Full support for `CovD` and its commutation rules is the next major milestone.
- **xCoba (Components)**: Initial support for coordinate charts is present; component calculations are planned.
- **Tier 2 Simplification**: Integration of more advanced symbolic simplification rules.
- **Notebook Extraction**: Automatic extraction of regression tests from existing xAct notebooks.
