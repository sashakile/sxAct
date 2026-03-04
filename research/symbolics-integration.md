# Research Report: Integrating sxAct with Symbolics.jl

Deep research into the `sxAct` codebase and the Julia `Symbolics.jl` ecosystem reveals a clear path for integration. `sxAct` is currently a port of the Wolfram `xAct` suite, with its foundation in `XCore.jl`. Integrating this with `Symbolics.jl` (the native Julia CAS) would transform `sxAct` into a high-performance, native Julia tensor calculus engine.

## 1. Architectural Strategy: The Three-Layer Bridge
To achieve `xAct`-level functionality within `Symbolics.jl`, the integration follows a layered approach:

### Layer 1: The Port (XCore / XPerm / XTensor)
*   **Status**: `XCore.jl` is already a functional port of the `xAct/xCore` utility layer (symbol registry, upvalues, options).
*   **Strategy**: Port the ~2,000 lines of `xperm.c` (the Butler-Portugal algorithm) to Julia. To manage complexity and ensure immediate functionality, this will be done in two phases:
    1.  **Bootstrap Phase**: Implement a `ccall` wrapper to the existing `xperm.c` library.
    2.  **Native Phase**: Iteratively port the C logic to a pure Julia `XPerm.jl` for maximum compiler optimization.
*   **Role**: This layer handles the "heavy lifting" algorithms and mathematical ground truth (Schreier-Sims, Strong Generating Sets), independent of the symbolic representation.

### Layer 2: The SymbolicUtils Mapping
*   **Implementation**: Use `SymbolicUtils.jl` to represent tensors as `Term` objects.
*   **Metadata Isolation**: To prevent collisions with scalar variables, indices will be represented by a dedicated `AbstractIndex` type wrapping `Sym` objects, each carrying its own metadata (e.g., `IndexType`, `Variance`, `Parity/Grade`).
*   **Non-Commutativity**: Unlike scalars, tensor products are non-commutative at this level. The integration will use a non-commutative product head for tensor strings, ensuring that ordering is preserved until the canonicalizer proves equivalence.
*   **Metadata**: Store `xAct` properties (symmetries, manifold associations) in `SymbolicUtils` metadata for each tensor head.

### Layer 3: The Symbolics UI & Rewriter
*   **User Interface**: An `@tensor` macro will act as a specialized version of `@variables`, registering symbols in the `XCore` registry and attaching the necessary `Symbolics` metadata automatically.
*   **Abstract Operators**: Implement a dedicated `CD` (Covariant Derivative) operator. This operator remains symbolic and does not expand into Christoffel symbols unless a metric/connection is explicitly defined on the manifold.
*   **Canonicalization Pass**: A custom `SymbolicUtils` rewriter that:
    1.  Identifies **Dummy Indices** (contracted indices that appear once as upper and once as lower).
    2.  Renames these to a standard sequence (e.g., `$1, $2, ...`) to allow for structural comparison of mathematically identical expressions (e.g., $A_i B^i$ vs $A_j B^j$).
    3.  Invokes `XPerm.canonicalize` to sort free indices according to tensor symmetries.
    4.  Sorts terms in a sum (`Plus` head) using a deterministic "strict serialization" to ensure a unique representation for the CAS.

## 2. Technical Feasibility & Comparison
| Feature | current `SymbolicTensors.jl` | Proposed `sxAct` + `Symbolics.jl` |
| :--- | :--- | :--- |
| **Backend** | `SymPy` (Python) | Native Julia (`SymbolicUtils`) |
| **Performance** | High latency (PyCall) | Near-C speeds (Pure Julia/ccall) |
| **Canonicalization** | Butler-Portugal (via SymPy) | Butler-Portugal (via `XPerm.jl`) |
| **Integration** | Wrapper-based | Deeply integrated via Metadata |
| **Validation** | Manual | Automated via existing `sxact` Oracle |

## 3. Implementation Roadmap
1.  **Phase 1: XPerm Bootstrap**: Create the `ccall` bridge to `xperm.c` and verify every function against the Wolfram `xAct` Oracle using the existing Python `sxact` testing harness.
2.  **Phase 2: Metadata & Type System**: Define the `AbstractIndex` and `TensorProperties` metadata structures in `XCore.jl`.
3.  **Phase 3: The Rewriter**: Implement the `SymbolicUtils` rewriter pass for index renaming and symmetry-aware sorting.
4.  **Phase 4: Abstract Operators**: Implement `CD` (Covariant Derivative) and `Lie` derivative logic as symbolic rewriters.
5.  **Phase 5: Equivalence Validation**: Run the full `integration/` suite to ensure that `Symbolics.jl` expressions are correctly canonicalized to match the Wolfram ground truth.

## 4. Edge Cases & Special Considerations
*   **Non-Metric Manifolds**: The design explicitly supports abstract differentiation without requiring a metric, mirroring `xTensor`'s ability to work with generic connections.
*   **Supergeometry**: Metadata will include a `Parity` field to support anti-commuting (Grassmann) variables, essential for supergravity and particle physics applications.
*   **Index Collisions**: The dedicated `Index` type ensures that a symbol `μ` used as an index will not be confused with a scalar variable `μ` used elsewhere in the same symbolic expression.
