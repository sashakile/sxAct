# Plan: xAct Libraries Migration & Progress Tracker

This document provides a detailed, component-level breakdown of the Wolfram **xAct** suite's migration to Julia (`.jl`). Progress is tracked against **Validation Milestones** (e.g., passing documentation notebooks) rather than subjective percentages.

---

## 1. Library Dependency Mapping
*Infrastructure required before higher-level physics packages can be implemented.*

| Package | Immediate Dependencies | Blocked By |
| :--- | :--- | :--- |
| **xCore** | None | — |
| **xPerm** | xCore | — |
| **xTensor** | xPerm | `CovD` (for advanced GR) |
| **xCoba** | xTensor | Basis/Frame support |
| **xPert** | xTensor | `CovD`, Perturbation expansion logic |
| **xTras** | xTensor | Young Projectors, `CovD` |
| **Invar** | xTras, xTensor | Bianchi identity engine |
| **Spinors** | xTensor | Spinor index types |

---

## 2. xCore: Foundation Utilities
*Status: Foundation layer; mostly operational.*

| Component | Status | Details | Milestone |
| :--- | :--- | :--- | :--- |
| **Symbol Registry** | **In-Progress** | Namespace management and `ValidateSymbol`. | `xCoreDoc.nb` partial |
| **Upvalues System** | **DONE** | Julia-side emulation of Wolfram `UpValues`. | `xCoreDoc.nb` partial |
| **Dagger Logic** | **DONE** | `DaggerCharacter` and `MakeDaggerSymbol`. | `xCoreDoc.nb` partial |
| **Option Handling** | **DONE** | `CheckOptions` validation logic. | `xCoreDoc.nb` partial |
| **Symbolic Atoms** | **MISSING** | `AtomQ`, `SymbolName` reflection. | **BLOCKER** |

---

## 3. xPerm: Permutation Group Engine
*Status: Core algorithms implemented; parity with xperm.c pending.*

| Component | Status | Details | Milestone |
| :--- | :--- | :--- | :--- |
| **Group Theory Base** | **DONE** | Permutations, composition, and inverse. | `xPermDoc.nb` partial |
| **Schreier-Sims** | **DONE** | BSGS construction. | `xPermDoc.nb` partial |
| **Butler-Portugal** | **In-Progress** | The `double_coset_rep` algorithm. | `butler_examples` partial |
| **Niehoff Shortcuts** | **DONE** | O(k log k) Sym/Asym optimization. | `butler_examples` partial |
| **Multi-Index Sets** | **MISSING** | **BLOCKER** for full `ToCanonical` parity. | `butler_examples` full |
| **Signed Perms** | **DONE** | Degree-n+2 representation for parity. | `xPermDoc.nb` partial |

---

## 4. xTensor: Abstract Tensor Algebra
*Status: Basic algebra operational; differential geometry blocked.*

| Component | Status | Details | Milestone |
| :--- | :--- | :--- | :--- |
| **Manifold/Metric** | **DONE** | `DefManifold`, `DefMetric`, and index variance. | `xTensorDoc.nb` partial |
| **Covariant D** | **MISSING** | **HIGH PRIORITY BLOCKER** (Commutation rules). | `xTensorDoc.nb` (CovD) |
| **Curvature Core** | **DONE** | Riemann, Ricci, Einstein definitions. | `curvature_invariants.toml` |
| **Simplification** | **In-Progress** | Mono-term (DONE), Algebraic/Simplify (MISSING). | `xTensorDoc.nb` full |
| **Basis/Frame** | **MISSING** | Tetrads and non-coordinate bases. | `xCobaDoc.nb` (pre-req) |

---

## 5. xCoba: Coordinate & Component Calculus
*Status: Planned; bridges abstract algebra to numerical arrays.*

| Component | Status | Details | Milestone |
| :--- | :--- | :--- | :--- |
| **Component Maps** | **MISSING** | `CTensor` mapping to Julia `Array`. | `xCobaDoc.nb` partial |
| **Coord. Transforms** | **MISSING** | Automatic Jacobian generation. | `xCobaDoc.nb` partial |
| **ODE Integration** | **MISSING** | **EXTENSION**: Hooking into `DifferentialEquations.jl`. | New Benchmark |

---

## 6. xPert: Perturbation Theory
*Status: Planned; combinatorial engine for GW/Cosmology.*

| Component | Status | Details | Milestone |
| :--- | :--- | :--- | :--- |
| **Perturb. Orders** | **MISSING** | `h@1`, `h@2` expansion levels. | `xPertDoc.nb` partial |
| **Curvature Exp.** | **MISSING** | Combinatorial formulas for perturbed Riemann. | `xPertDoc.nb` partial |
| **Metric Validation**| **MISSING** | **CRITICAL**: Background metric consistency checks. | `xPertDoc.nb` partial |

---

## 7. xTras: Field Theory & Lagrangian Utils
*Status: Planned; high-level research tools.*

| Component | Status | Details | Milestone |
| :--- | :--- | :--- | :--- |
| **Var. Derivatives** | **MISSING** | `VarD` for Euler-Lagrange equations. | `xTras.pdf` examples |
| **Symbolic IBP** | **MISSING** | Integration By Parts (Total Derivative Removal). | `xTras.pdf` examples |
| **Young Projectors** | **MISSING** | Multi-term symmetry via Young tableaux. | **BLOCKER** for Invar |

---

## 8. Specialized Packages (In-Depth Roadmap)

### **Spinors** (2-Spinor Calculus)
*   **Status**: MISSING
*   **Milestone**: Newman-Penrose and GHP equations from `SpinorsDoc.nb`.

### **Invar** (Curvature Invariants)
*   **Status**: MISSING
*   **Requirement**: Needs Multi-term symmetry engine.
*   **Milestone**: Full simplification of Riemann invariants through 12 derivatives.

### **FieldsX** (Fermions & Graded Algebra)
*   **Status**: MISSING
*   **Requirement**: Extends `xPerm` signed permutations to handle **Graded Symmetry** (Grassmann-odd indices).

---

## 9. Overall Progress Summary

| Tier | Status | Validation Baseline |
| :--- | :--- | :--- |
| **Foundational** (xCore, xPerm) | **STABLE** | ~70% of Documentation Notebooks passing. |
| **Structural** (xTensor) | **IN-PROGRESS** | Basic algebra passing; CovD is primary blocker. |
| **Applied** (xCoba, xPert, xTras) | **PLANNED** | Awaiting xTensor/CovD completion. |
| **Advanced** (Invar, Spinors) | **RESEARCH** | Awaiting Multi-term symmetry engine. |
