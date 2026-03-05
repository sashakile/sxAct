# Research Report: MetaMigration Harness (sxBench)
## Decoupling Symbolic Validation for Cross-Library Migration

**Date:** 2026-03-05  
**Status:** Research / Architectural Proposal  
**Target:** Rubi.jl, sxAct, and Generic Symbolic CAS Ports

---

## 1. Glossary of Terms

| Term | Definition |
| :--- | :--- |
| **IUT** | **Implementation Under Test**: The new library (e.g., `Rubi.jl` or `sxAct`) being validated against the ground truth. |
| **CIR** | **Canonical Intermediate Representation**: A standardized, serialized format (usually a nested JSON/AST) that all adapters must emit to enable cross-language comparison. |
| **Manifest** | A declarative configuration file specifying the required environment (packages, context settings, and path variables) for a test session. |
| **Oracle** | The "Ground Truth" engine (Wolfram Mathematica) used to generate expected results and verify mathematical properties. |

---

## 2. Introduction: The Validation Gap
When migrating mature symbolic systems (like **xAct** or **Rubi**) from Mathematica to open-source environments (Julia/Python), the primary challenge is not just the porting of logic, but the **verification of mathematical equivalence**. 

The current `sxAct` project has built a robust "Three-Layer" validation system. This research explores how to extract this system into a standalone **MetaMigration Harness** (internal name: `sxBench`) that can be reused for any symbolic library, starting with **Rubi.jl**.

---

## 3. Analysis of the current `sxAct` Coupling
The `sxAct` codebase currently serves two masters: the tensor algebra implementation and the test harness. To achieve a reusable framework, we must decouple several key areas:

### 3.1 The Oracle Logic (Isolation & Manifests)
Currently, the Wolfram Oracle is hardcoded to load `xAct` via an `init.wl` script.
- **Problem:** It cannot easily switch to `Rubi` or `FeynCalc` without manual configuration.
- **Solution:** Implement **Manifest-based Initialization**. The client sends a list of required packages (e.g., `{"packages": ["Rubi`"]}`).
- **Technical Note (Context Isolation):** To prevent symbol shadowing or rule collisions when loading multiple packages (e.g., `xAct` + `Rubi`), the `KernelManager` must utilize Mathematica `Contexts` (`BeginPackage["sxBench`Scope`"]`) for every evaluation session. This ensures absolute namespace isolation between different manifests.

### 3.2 The Test Schema (Generic & Resource-Aware)
The `sxact/runner/loader.py` uses a TOML schema that includes tensor-specific fields.
- **Problem:** Fields like `rank`, `manifold`, and `symmetry` are baked into the `ExpectedProperties` model.
- **Solution:** Generalize `ExpectedProperties` into a generic `MetadataDict`.
- **Resource Management:** Add support for `timeout_multiplier` and `resource_limit` at the test level. For large suites like Rubi (72k tests), complex edge cases may require 10x the standard timeout, while "smoke" tests should fail fast.

### 3.3 Normalization and Canonicalization
Normalization is currently a monolith in `src/sxact/normalize/`.
- **Problem:** It is hardcoded for tensor index permutation and dummy variable renaming.
- **Solution:** Introduce a **Normalization Plugin Architecture**. 
    - `sxBench` provides the framework.
    - `sxAct` provides the `TensorNormalizer` (index-aware).
    - `Rubi` provides the `AlgebraicNormalizer` (polynomial/rule-aware).

---

## 4. Proposed Architecture: `sxBench`

### 4.1 The "Zero-Knowledge" Harness
The core harness operates on an opaque **Action-Result** loop:
1.  **Action:** A high-level operation (e.g., `Integrate`, `Contract`, `Simplify`).
2.  **Execution:** The harness executes the action on both the Oracle and the IUT.
3.  **CIR Emission:** Both engines must emit a **Canonical Intermediate Representation (CIR)**. This is a serialized format (JSON/AST) that strips implementation-specific memory addresses and metadata.
4.  **Comparator:** The harness performs a structural comparison of the CIRs. For numeric tasks, it falls back to numeric sampling.

### 4.2 The Universal Adapter Interface
Every library port must implement a standardized adapter to bridge the language gap:
- `initialize(manifest)`: Setup the local environment.
- `execute(action, args)`: Run the math.
- `serialize_to_cir()`: Convert the native object into a **CIR** for the harness to compare.

---

## 5. Case Study: Migrating Rubi.jl
**Rubi** is a Rule-Based Integrator with ~7,000 rules and ~72,000 test cases. Using the `sxBench` harness, the migration would follow this workflow:

1.  **Snapshot Generation:** Run the 72,000 integration tests through the `WolframOracle` with `Rubi` loaded and store the CIR snapshots.
2.  **Equivalence Testing (Layer 1):** Run the same expressions through `Rubi.jl` and verify the CIR matches the snapshot.
3.  **Linearity Invariants (Layer 2):** Define a property test: `Integrate[a*f + b*g] == a*Integrate[f] + b*Integrate[g]`.
4.  **Differentiation Check (Layer 3):** If `F = Integrate[f]`, then the harness verifies $F'(x) - f(x) \approx 0$ via numeric sampling.

---

## 6. Implementation Roadmap for Separation

### Phase 1: Universal Oracle Service
- Extract `oracle/` into a standalone microservice.
- Implement session manifests and `Context` isolation.

### Phase 2: Core Harness (sxBench)
- Move `sxact/runner` to `sxbench/runner`.
- Replace tensor-specific models with the generic `MetadataDict` and `CIR` protocol.
- Implement the `NormalizationRegistry`.

### Phase 3: Library Plugins
- `sxbench-tensor`: Adds tensor index canonicalization.
- `sxbench-integral`: Adds integral form verification.

---

## 7. Conclusion
Decoupling the `sxAct` testing framework into `sxBench` creates a foundational piece of **symbolic migration infrastructure**. It allows developers to port complex Mathematica packages with the rigorous verification required for scientific computing. 
