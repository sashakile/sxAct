# RFC: The Eleguá + Chacana Ecosystem
**Status**: Proposed / Architectural Pivot
**Date**: 2026-03-08
**Project**: sxAct Migration & Beyond

## 1. Executive Summary

This RFC proposes a fundamental architectural pivot for the `sxAct` project. We are decoupling the system into two primary pillars: **Eleguá** (The Orchestrator) and **Chacana** (The Language).

- **Eleguá** (Master of the Crossroads) is a domain-agnostic test harness designed for validating the migration of complex symbolic systems (xAct, Rubi, FeynCalc) from Wolfram Mathematica to open-source environments.
- **Chacana** (The Bridge) is a cross-language tensor calculus DSL that uses TOML for declarations and a compact micro-syntax for expressions, providing a machine-parseable "Penrose notation" for the 21st century.

The system will support a **Three-Tier Execution Strategy**, mathematically proving the equivalence between the Wolfram "Gold Standard," a literal Julia port (`xAct-jl`), and an idiomatic high-performance engine (`Chacana-jl`) powered by `Symbolics.jl`.

---

## PHASE 1: DESCRIBE (Symptoms)

### Observed Symptoms
- **Coupling**: The test harness is intertwined with tensor algebra logic, preventing its use for other symbolic domains (e.g., Rubi).
- **Language Lock**: Implementation is tightly coupled to Wolfram/Mathematica syntax, hindering native performance and portability.
- **Verification Gap**: No automated way to prove that a Julia/Python port is mathematically equivalent to the Wolfram "Gold Standard."
- **Performance "Wolfram Hangover"**: Current Julia code (`XCore.jl`) mimics Mathematica's global state and dynamic patterns, preventing AOT compilation and GPU optimization.
- **Late Error Detection**: Index mismatches and symmetry errors are caught at runtime by the backend, rather than at parse-time by a validator.

---

## PHASE 2: DIAGNOSE (Root Cause)

### Problem Statement

**Current behavior**:
The system operates as a monolithic "xAct-in-Python/Julia" clone where the test runner sends procedural commands (`action: "DefTensor"`) to an adapter that translates them into language-specific strings.

**Mechanism**:
The lack of a **Common Intermediate Representation (CIR)** forces the system to rely on string-to-string translation (`_wl_to_jl`). This couples the frontend (DSL) to the backend (Processors) and prevents static analysis. Furthermore, the Julia implementation follows "Wolfram Patterns" (global registries, `eval()`) instead of idiomatic Julia, creating a performance ceiling.

---

## PHASE 3: DELIMIT (Scope)

### In Scope
- **Eleguá Core**: A generalized, domain-agnostic test harness (The Gatekeeper).
- **Chacana Core**: A standalone cross-language tensor DSL (The Bridge).
- **xAct-jl**: A literal, feature-complete Julia port (The Mirror / Tier 2 Oracle).
- **Chacana-jl**: An idiomatic, AOT-ready Julia engine using `Symbolics.jl` (The Future).
- **CIR Protocol**: A JSON AST (MathJSON-inspired) for universal symbolic interchange.

### Out of Scope (Non-Goals)
- **Automatic Translation**: We are NOT building a tool to translate `.m` files to `.jl` files.
- **GUI**: Visual representation is deferred to future dashboard work.
- **Non-Tensor Domains**: While Eleguá is *designed* to be general, we only implement the `Chacana` plugin in this phase.

---

## PHASE 4: DIRECTION (Strategic Approach)

### The Three-Tier Processor Strategy

| Tier | Name | Nature | Symbolic Engine | Math Core | Role |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Tier 1** | **Wolfram xAct** | Original Engine | Mathematica | xperm.c | The "Gold Standard" / Ultimate Oracle. |
| **Tier 2** | **xAct-jl** | Literal Julia Port | Custom (Wolfram-like) | **XPerm.jl** | The "High-Speed Oracle" / 1:1 Parity. |
| **Tier 3** | **Chacana-jl** | Idiomatic Julia | **Symbolics.jl** | **XPerm.jl** | The Performance Future / AOT Compiled. |

### Decision
**Selected approach**: The **Crossroads (Eleguá) & Bridge (Chacana)** Model.

**Rationale**:
By separating the **DSL** from the **Processors**, we create a "Source of Truth" that can be verified across three tiers. **XPerm.jl** (the Butler-Portugal algorithm) is the "Shared Engine" used by both Julia tiers, ensuring mathematical consistency while allowing for different symbolic frontends.

---

## PHASE 5: DESIGN (Tactical Plan)

### Phase 1: Eleguá Core (The Gatekeeper)
**Goal**: Generalize the harness into a "Zero-Knowledge" orchestrator (sxBench).
- **Action**: Extract `runner`, `compare`, `snapshot`, and `oracle` logic into `packages/elegua-core`.
- **Manifests**: Implement **Manifest-based Initialization** to load domain-specific environments (e.g., `{"packages": ["xAct"]}`).
- **CIR Protocol**: Define the JSON AST protocol, including depth limits and flat-serialization strategies for large GR expressions.
- **Context Isolation**: Use Wolfram `Contexts` (`Elegua`Scope`) to ensure namespace safety.
- **Workspace Setup**: Configure monorepo tooling (e.g., `pyproject.toml` with editable installs) to manage inter-dependent local packages.
- **Snapshot-Only Mode**: Implement a fallback in the runner to compare Tier 2/3 against cached Tier 1 snapshots if the Wolfram Oracle is unreachable (enabling CI/CD).

### Phase 2: Chacana-Spec (The Bridge)
**Goal**: Implement the standalone DSL and Static Type System.
- **Action**: Build the recursive-descent parser for the `R{^a _b _c _d}` micro-syntax in `packages/chacana-spec-py`.
- **Static Analysis**: Implement the **Index Well-Formedness** check (variance, type, and contraction validation).
- **Normalizer**: Provide the `TensorNormalizer` (index-permutation aware) as a plugin for Eleguá.

### Phase 3: xAct-jl (The Mirror)
**Goal**: Complete the literal functional port.
- **Action**: Move `XPerm.jl` and `XTensor.jl` to `packages/xact-jl`.
- **Parity Baseline**: Explicitly target `xTensor` and `xPerm` core functionality (monoterm symmetries, canonicalization, basic calculus) for this phase.
- **Isolation**: Replace global registries with a `ChacanaSession` context object.
- **Verification**: Use Eleguá to prove `Wolfram-xAct == xAct-jl`.

### Phase 4: Chacana-jl (The Awakening)
**Goal**: Build the idiomatic, high-performance future using `Symbolics.jl`.
- **Action**: Implement `Chacana-jl` in `packages/chacana-jl` using typed structs (`Manifold{4}`) and `SymbolicUtils.jl` rewriters.
- **Namespace Isolation**: Implement robust metadata isolation using `Symbolics.AbstractVariableMetadata` to prevent collisions between scalar and tensor symbols (e.g., Ricci scalar `R` vs Riemann head `R`).
- **AOT**: Ensure zero use of `eval()` to allow compilation to standalone binaries via Julia 1.12 `juliac`.
- **SciML**: Integrate with `ModelingToolkit.jl` for abstract-to-concrete PDE expansion.
- **Verification**: Use Eleguá to prove `xAct-jl == Chacana-jl`.

---

## PHASE 6: DEVELOP (Execution Roadmap)

### Movement I: Scaffolding (Weeks 1-2)
- [ ] Create `packages/elegua-core` and `packages/chacana-spec-py`.
- [ ] Define CIR JSON Schema and Manifest protocol.
- [ ] Configure monorepo workspace for Python/Julia.
- [ ] Move existing `sxact` runners and comparators into Eleguá.

### Movement II: The DSL Bridge (Weeks 3-4)
- [ ] Implement Chacana micro-syntax parser in Python.
- [ ] Implement static validator for index consistency.
- [ ] Refactor `WolframAdapter` to consume Chacana AST.

### Movement III: The Oracle Mirror (Weeks 5-6)
- [ ] Complete `xAct-jl` parity (Tier 2) for the defined baseline.
- [ ] Implement `XactJLAdapter` in Eleguá.
- [ ] Run full Schwarzschild/Kerr regression suite across Tiers 1 & 2.

### Movement IV: The Native Future (Weeks 7-8)
- [ ] Implement `Chacana-jl` prototype using `Symbolics.jl`.
- [ ] Implement `ChacanaJLAdapter` in Eleguá.
- [ ] Verify Tier 3 against Tier 2.

---

## Scientific Impact

Eleguá and Chacana represent a shift from "porting code" to "verifying mathematics."
1. **Infrastructure of Trust**: Eleguá provides a mathematically rigorous way to prove the correctness of any future tensor engine.
2. **Machine-Parseable Notation**: Chacana provides a language-agnostic way for physicists to express their problems, usable in Python, Julia, Rust, and beyond.
3. **Bridge to SciML**: By integrating with `Symbolics.jl`, tensor calculus becomes a first-class citizen in the world of Scientific Machine Learning and PINNs.

---
**END OF DOCUMENT**
