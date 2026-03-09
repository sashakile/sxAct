# Spec: xAct Migration Master Plan & Progress Tracker

**Date**: 2026-03-09
**Status**: Active / Specification
**Project**: sxAct Implementation Core

## 1. Executive Summary
This document tracks the functional completion of ported xAct libraries and the status of the implementation core. The migration is moving from Phase 1 (Prototyping) to Phase 2 (Production Parity).

The sxAct repository is the primary implementation layer for the Julia/Python ports.

---

## 2. Library Migration Status

### 2.1 Core Tier (The Foundation)
| Library | Status | Progress | Key Missing Features |
| :--- | :--- | :--- | :--- |
| **xCore** | In-Progress | 80% | AtomQ, SymbolName (Julia), Full symbol registry. |
| **xPerm** | In-Progress | 60% | Schreier-Sims optimization, full butler_examples validation. |
| **xTensor** | In-Progress | 40% | CovD (Covariant Derivative), ChristoffelCD, Simplify. |

### 2.2 Extension Tier (The Research Core)
| Library | Status | Progress | Priority |
| :--- | :--- | :--- | :--- |
| **xCoba** | Missing | 0% | High (Component calculations) |
| **xPert** | Missing | 0% | High (Perturbation theory) |
| **xTras** | Missing | 0% | Medium (Field theory utilities) |

---

## 3. Infrastructure Progress (Elegua - External Repository)
*Elegua development is handled in the elegua repository. This repo acts as a consumer.*

| Component | Status | Progress | Notes |
| :--- | :--- | :--- | :--- |
| **Adapters** | DONE | 90% | Operational (to be extracted). |
| **Runner** | DONE | 85% | Operational (to be extracted). |
| **Snapshots** | DONE | 100% | Operational. |

---

## 4. Language Progress (Chacana - External Repository)
*Chacana specification and parsing is handled in the chacana repository.*

| Component | Status | Progress | Notes |
| :--- | :--- | :--- | :--- |
| **Chacana Spec** | DRAFT | 0.2.2 | Formal specification. |
| **PEG Grammar** | DRAFT | 0.2.4 | See [chacana repo]. |

---

## 5. Detailed Roadmap & Milestones

### Phase 2: Production Parity (March 2026)
1.  [ ] xCore Parity: Complete SymbolName and AtomQ reflection.
2.  [ ] xPerm Parity: Achieve 100% pass rate on Butler examples.
3.  [ ] CovD Support: Implement covariant derivative commutation rules in XTensor.jl.

### Phase 3: Applied Physics (April 2026)
1.  [ ] xCoba Core: Implement coordinate-to-component mapping.
2.  [ ] xPert Core: Implement metric perturbation expansion engine.

---

## 6. Known Gaps & Blockers
- CovD (sxAct-3to): Lack of covariant derivative support blocks high-order GW benchmarks.
- Multi-Index Sets: Required for full ToCanonical parity in xPerm.
