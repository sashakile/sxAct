# TensorDSL: Decoupled Architecture & Integration

**Status:** Proposed / Architectural Pivot
**Date:** 2026-03-07
**Spec Version:** v0.1.0
**Implementation Strategy:** Thin Parser + Fat Backends (Strategy 4)

## 1. Architectural Vision
The goal is to provide a language-agnostic way to define tensor calculus problems that can be used across Python and Julia without heavy interop dependencies (like `juliacall`).

### The "Thin Parser" Principle
The `tensordsl` library is a lightweight utility that performs two tasks:
1.  **Parse TOML declarations** (manifolds, tensors, indices).
2.  **Parse string expressions** into a standardized **JSON AST**.

It **does not** contain mathematical logic like Butler-Portugal canonicalization or Schreier-Sims algorithms. These are offloaded to **Backends**.

## 2. Implementation Strategy

### Native Python (`tensordsl-py`)
*   **Goal:** A zero-dependency Python package (available via `pip`).
*   **Dependencies:** `tomli` (TOML parsing) and a lightweight recursive-descent parser.
*   **Output:** A JSON-serializable dictionary following the TensorDSL AST spec.
*   **Zero Interop:** Does not require a Julia runtime to be installed.

### Native Julia (`TensorDSL.jl`)
*   **Goal:** A lightweight Julia package (available via `Pkg`).
*   **Dependencies:** `TOML.jl` and `StructTypes.jl`.
*   **Output:** A native Julia `Expr` or `Dict` that matches the JSON spec.

## 3. The Backend Interface (The Interop Bridge)
Since the Parser is "thin," the math is performed by plugging in a Backend.

| Backend Type | Description |
| :--- | :--- |
| **Local Backend** | (e.g., SymPy in Python, XCore.jl in Julia). Logic stays within the same language. |
| **AOT Backend (1.12+)** | A pre-compiled Julia shared library (`libtensordsl_backend.so`) created with `juliac`. The Python parser calls this via `ctypes` for high-performance math without a full Julia environment. |
| **Oracle Backend** | The JSON AST is sent to an external server (like the `sxact` oracle) for processing. |

## 4. Implementation Roadmap (Decoupled)

### Phase 1: Standardized AST (The Contract)
*   Define the JSON schema for the TensorDSL AST. This is the "Source of Truth" that ensures `tensordsl-py` and `TensorDSL.jl` produce identical output for the same input.

### Phase 2: Dual Native Parsers
*   **Python:** Implement `tensordsl-py`. Focus on the EBNF string parser (`R{^a _b}`).
*   **Julia:** Implement `TensorDSL.jl`.
*   **Validation:** Create a test suite of `.tensor.toml` files that must produce bit-identical JSON ASTs in both implementations.

### Phase 3: Julia 1.12 AOT (Future)
*   Once Julia 1.12 is stable, compile the mathematical core of `XCore.jl` (Symmetry expansion, Canonicalization) into a standalone C-library using `juliac`.
*   Provide an optional high-performance "plugin" for the Python library that uses this binary.

## 5. Synergy with sxAct
Within this repository, the existing `sxact` framework becomes a **user** of the `tensordsl` parser.

1.  **Loader**: `sxact.runner.loader` will use `tensordsl-py` to parse test files.
2.  **Execution**: The resulting AST is sent to the `WolframAdapter` or `JuliaAdapter` (Backends).
3.  **Decoupling**: The DSL logic is moved out of `sxact` and into a standalone library, allowing other projects (e.g., General Relativity simulations in JAX) to use TensorDSL without the `sxact` test harness.

## 6. Proposed New File Structure
```text
/var/home/sasha/para/areas/dev/gh/sk/sxAct/
├── docs/tensordsl-integration.md
├── specs/TENSOR_DSL_SPEC_V0.1.0.md
├── packages/
│   ├── tensordsl-py/           # Standalone Python Parser
│   │   ├── pyproject.toml
│   │   └── src/tensordsl/
│   └── TensorDSL.jl/           # Standalone Julia Parser
│       ├── Project.toml
│       └── src/TensorDSL.jl
└── src/sxact/
    └── dsl/
        └── adapter.py          # Bridge between tensordsl-py and sxact adapters
```
