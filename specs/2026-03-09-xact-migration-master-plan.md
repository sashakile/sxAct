# Spec: xAct Migration Master Plan & Progress Tracker

**Date**: 2026-03-09
**Status**: Active / Specification
**Project**: sxAct → Eleguá + Chacana Ecosystem

## 1. Executive Summary
This document serves as the master record for the migration of the Wolfram **xAct** suite to the **Eleguá + Chacana** ecosystem. It tracks the functional completion of ported libraries, the status of the orchestration infrastructure, and the roadmap for untranslated components.

The migration is moving from **Phase 1 (Prototyping/Verification)** to **Phase 2 (Ecosystem Decoupling)**.

---

## 2. Library Migration Status

### 2.1 Core Tier (The Foundation)
| Library | Status | Progress | Key Missing Features |
| :--- | :--- | :--- | :--- |
| **xCore** | **In-Progress** | 80% | `AtomQ`, `Cases` (Julia), Full symbol registry. |
| **xPerm** | **In-Progress** | 60% | Schreier-Sims optimization, full `butler_examples` validation. |
| **xTensor** | **In-Progress** | 40% | `CovD` (Covariant Derivative), `ChristoffelCD`, `Simplify` (Tier 2). |

### 2.2 Extension Tier (The Research Core)
| Library | Status | Progress | Priority |
| :--- | :--- | :--- | :--- |
| **xCoba** | **Missing** | 0% | High (Component calculations) |
| **xPert** | **Missing** | 0% | High (Perturbation theory) |
| **xTras** | **Missing** | 0% | Medium (Field theory utilities) |
| **Invar** | **Missing** | 0% | Low (Curvature invariants database) |
| **Spinors** | **Missing** | 0% | Medium (2-Spinor calculus) |

### 2.3 Utility Tier
| Library | Status | Progress | Priority |
| :--- | :--- | :--- | :--- |
| **Harmonics** | **Missing** | 0% | Low |
| **xPand** | **Missing** | 0% | Medium (Cosmology) |
| **TexAct** | **Missing** | 0% | Low (Formatting) |
| **AVF / xTerior**| **Missing** | 0% | Low (Exterior calculus) |

---

## 3. Infrastructure Progress (Eleguá)

| Component | Status | Progress | Notes |
| :--- | :--- | :--- | :--- |
| **Adapters** | DONE | 90% | Wolfram, Julia, Python adapters operational. |
| **Runner** | DONE | 85% | TOML execution, lifecycle management. |
| **Snapshots** | DONE | 100% | Record/Replay operational via `oracle/`. |
| **Normalization**| DONE | 95% | AST-based parser & commutative sorting. |
| **Eleguá Core** | **PLANNED** | 0% | Refactor `sxact.runner` -> `elegua-core`. |
| **ValidationToken**| **PLANNED** | 0% | MathJSON AST implementation. |
| **Isolation** | **PLANNED** | 10% | Need per-task Wolfram `Context` scoping. |

---

## 4. Language Progress (Chacana)

| Component | Status | Progress | Notes |
| :--- | :--- | :--- | :--- |
| **Chacana Spec** | **DRAFT** | 0.2.2 | Formal specification for TOML + Micro-syntax. |
| **PEG Grammar** | **DRAFT** | 0.2.4 | Formal PEG for the micro-syntax. |
| **Tree-sitter** | **DRAFT** | 0.1.1 | Grammar for IDE/LSP support. |
| **Static Checker**| **PLANNED** | 0% | Type-safe index validation (Phase 2). |
| **Chacana-jl** | **PLANNED** | 0% | Performance engine using `Symbolics.jl`. |

---

## 5. Detailed Roadmap & Milestones

### Phase 2: The Ecosystem Split (March 2026)
1.  **[ ] Eleguá Extraction**: Refactor `src/sxact/runner` into `packages/elegua-core`.
2.  **[ ] Chacana-Spec-Py**: Implement the PEG parser and Static Type Checker in Python.
3.  **[ ] ValidationToken**: Transition from string-based `Result` to MathJSON-compatible AST.
4.  **[ ] Wolfram Isolation**: Implement `BeginPackage["EleguaTask123`"]` wrapper for the Oracle.

### Phase 3: The Physics Expansion (April 2026)
1.  **[ ] xCoba Port**: Implement coordinate-to-component mapping in Julia.
2.  **[ ] xPert Implementation**: Combinatorial expansion engine for perturbations.
3.  **[ ] CovD Support**: Full covariant derivative commutation rules in `XTensor.jl`.

### Phase 4: Performance & Publication (May 2026)
1.  **[ ] Chacana-jl**: High-performance engine powered by `Symbolics.jl` rewriters.
2.  **[ ] Publication Drafts**: Finalize "Chacana: The Language" and "Eleguá: The Orchestrator" papers.
3.  **[ ] 100% Butler Validation**: Pass all 100% of xPerm Butler examples with zero discrepancies.

---

## 6. Known Gaps & Blockers
*   **CovD (sxAct-3to)**: Lack of covariant derivative support blocks high-order GW benchmarks (`gw_memory_3p5pn.toml`).
*   **Property Runner Tensors**: Property tests for tensors are currently failing because they lack the N-sample numeric substitution loop.
*   **Symbol Registry**: `XCore.jl` needs a more robust global symbol registry to mirror Wolfram's `$ContextPath` behavior.
