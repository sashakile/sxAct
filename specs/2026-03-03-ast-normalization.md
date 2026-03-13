# Spec: AST-Based Normalization Engine

**Date:** 2026-03-03
**Status:** Proposed
**Priority:** High (Architectural)

## Problem Statement

The current normalization pipeline (`packages/sxact/src/sxact/normalize/pipeline.py`) relies on regular expressions. This approach is fragile because:
1. **Nesting:** Regex struggles with deeply nested expressions like `CD[-a][CD[-b][T[c]]]`.
2. **Formatting:** Minor whitespace or bracket variations in CAS output can break the regex match.
3. **Commutativity:** Sorting terms in a sum using string splits (`split(" + ")`) fails if the terms themselves contain additions (e.g., inside sub-expressions).

## Proposed Solution: Tree-Based Normalization

Transition to a formal Abstract Syntax Tree (AST) representation for all CAS outputs before performing comparison.

### 1. S-Expression Parser
Implement a recursive-descent parser that converts xAct's `FullForm` output into a Python tree.
- **Requirement:** The `OracleClient` must be configured to wrap expressions in `ToString[..., FullForm]` to ensure the parser only deals with prefix notation (e.g., `Plus[a, b]`) rather than ambiguous infix notation.
- `Head[Arg1, Arg2]` -> `Node(head="Head", args=[...])`
- `a` -> `Leaf(name="a")`
- `-1` -> `Leaf(value=-1)`

### 2. Normalization Passes
Operate on the tree rather than the string:
- **`CanonicalizeIndicesPass`:** Traverse the tree in Depth-First Search (DFS) order. The first index encountered is renamed to `$1`, the second to `$2`, etc.
- **`SortCommutativePass`:** For nodes with heads like `Plus` or `Times`, sort the `args` list using a **Strict Serialization Format** (whitespace-free, alphabetic key sorting).
- **`CoefficientFlatteningPass`:** Distribute or collect numeric coefficients to a standard position.

### 3. Serializer
A "strict" serializer that outputs a single, whitespace-free string from the normalized tree for Tier 1 comparison and as a key for sorting sub-trees.

## Interdependencies
- **Snapshot Stability:** This spec is a blocker for **Oracle Snapshots** (`specs/2026-03-03-oracle-snapshots.md`) to prevent trivial string changes from invalidating the snapshot database.

## Success Criteria
- `normalize("A[a] + B[b]") == normalize("B[a] + A[b]")` returns `True`.
- Successfully normalizes expressions with 3+ levels of nested brackets.
- Zero "false negative" failures in the `integration/` suite caused by index naming differences.
