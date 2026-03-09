# Spec: Julia-Centric Documentation Strategy

**Date**: 2026-03-09
**Status**: Active / Specification
**Project**: sxAct (Julia Implementation + Python Wrapper)

## 1. Executive Summary
To provide a "no-complication" onboarding experience, sxAct will adopt a **Julia-first documentation model** (similar to `diffeqpy` or `PySR`). This strategy consolidates all documentation into the Julia ecosystem using `Documenter.jl` and `Literate.jl`, eliminating the need for multi-language toolchains like MkDocs.

The documentation will serve as a **polyglot bridge**, showing users how to perform tensor calculus in both Julia and Python while referencing the original Wolfram xAct syntax.

---

## 2. Tooling & Architecture

### 2.1 Core Tools
- **Documenter.jl**: The primary engine for building the HTML documentation site. It handles cross-referencing, API generation from docstrings, and deployment.
- **Literate.jl**: Used to transform Julia scripts (`.jl`) into Markdown tutorials (`.md`). These scripts will serve as both documentation and executable regression tests.

### 2.2 Directory Structure
The `docs/` folder is a **standalone Julia project** with its own `Project.toml` and `Manifest.toml` to ensure reproducible builds.

```text
docs/
├── Project.toml        # Documentation-specific dependencies (Documenter, Literate, PythonCall)
├── Manifest.toml       # Pinned versions for doc build
├── make.jl             # Unified build script (XCore, XPerm, XTensor)
├── src/                # Markdown source files
│   ├── index.md        # Home: The "Migration Rosetta Stone"
│   ├── installation.md # Unified Install (Julia/Python/Docker)
│   ├── api-julia.md    # Auto-generated from Julia source
│   ├── api-python.md   # Reference for the sxact-py wrapper
│   └── theory/         # Mathematical foundations (Butler-Portugal, etc.)
└── examples/           # Literate Julia scripts (Symlinked to src/julia/examples/)
    └── canonicalization.jl
```

---

## 3. Content Strategy

### 3.1 The "Migration Rosetta Stone" (Landing Page)
The homepage (`index.md`) will feature a high-signal comparison table to immediately orient users arriving from the Wolfram ecosystem.

| Operation | Wolfram (xAct) | Julia (sxAct.jl) | Python (sxact-py) |
| :--- | :--- | :--- | :--- |
| **DefManifold** | `DefManifold[M, 4, {a,b}]` | `M = Manifold(:M, 4)` | `M = sxact.Manifold("M", 4)` |
| **DefTensor** | `DefTensor[T[-a,-b], M]` | `T = Tensor(:T, [-a, -b], M)` | `T = sxact.Tensor("T", [-a, -b], M)` |
| **ToCanonical** | `ToCanonical[expr]` | `to_canonical(expr)` | `sxact.to_canonical(expr)` |

### 3.2 Polyglot Literate Tutorials
Tutorials will be written in Julia using `Literate.jl` but will explicitly include Python code blocks.
- **Method**: Use `PythonCall.jl` inside the Literate script to **actually execute and validate** the Python side of the example. This ensures that the `sxact-py` wrapper is never out of sync with the Julia core.
- **Benefit**: A single source file ensures that both Julia and Python examples are mathematically consistent and verified.

### 3.3 Python Wrapper Documentation
Since the Python wrapper (`sxact-py`) is a thin layer over the Julia implementation, its documentation will be integrated directly into the `Documenter.jl` site.
- **api-python.md**: A hand-curated reference explaining the Pythonic names (snake_case) and how Julia objects are mapped to Python classes.
- **Interoperability**: Clear instructions on passing data between Julia's `Tensors.jl` and Python's `NumPy/SymPy`.

---

## 4. Maintenance & Quality Gates

### 4.1 "Docs as Tests"
All `Literate.jl` examples must be executable as part of the CI pipeline.
- **Performance**: To prevent long CI wait times for heavy tensor contractions, tutorials will support a "Fast Mode" (syntax check) for standard PRs and a "Full Mode" (total execution) for nightly builds.
- **Caching**: Documenter's caching mechanism will be leveraged to avoid redundant computation of stable examples.

### 4.2 Automated Capability Matrix
A script integrated into `docs/make.jl` will parse the `specs/XACT_LIBRARIES_MIGRATION_PLAN.md` and generate a "Status Dashboard" page in the documentation, providing transparency on which xAct features are currently verified.

### 4.3 Documentation Contribution Workflow
Python-centric developers can contribute to the documentation by editing the Literate `.jl` files in `docs/examples/`. These files use standard Markdown in comments, making them easy to edit even without deep Julia expertise.

---

## 5. Next Steps
1.  **Refactor `docs/`**: Delete `mkdocs.yml` and move relevant content from `docs/site/` to `docs/src/`.
2.  **Bootstrap `make.jl`**: Configure `Documenter.jl` to track `XCore`, `XPerm`, and `XTensor`.
3.  **Implement Rosetta Stone**: Build the foundational comparison table on the new landing page.
4.  **First Literate Tutorial**: Create `docs/examples/basics.jl` covering the core migration path using `PythonCall.jl`.
