# Verification API (`sxact`)

!!! info "Verification API TL;DR for AI Agents"
    - **OracleClient**: sxAct compatibility wrapper around `elegua.oracle.OracleClient` (`health`, `evaluate`, `evaluate_with_xact`, `cleanup`)
    - **Normalization**: `normalize()` (regex) and `ast_normalize()` (AST-based, preferred); also exposed as the sxAct L3 Elegua comparison layer
    - **Comparison**: Legacy three-tier `compare()` plus sxAct L3/L4 plugins for Elegua's `ComparisonPipeline`
    - **Snapshots**: `SnapshotComparator` for offline hash-based regression testing; snapshot artifacts remain sxAct-owned

The `sxact` Python package is a specialized framework for verifying the mathematical correctness of `XAct.jl` against the Wolfram Language implementation.

## 1. OracleClient

`sxact.oracle.client.OracleClient(base_url="http://localhost:8765")`

Manages the connection to the Dockerized Wolfram Engine. This class is a compatibility wrapper around `elegua.oracle.OracleClient`: Elegua owns the HTTP transport, while sxAct adapts responses to the historical `sxact.oracle.result.Result` dataclass used by existing adapters, comparators, and snapshot code.

| Method | Description |
| :--- | :--- |
| `health()` | Check if the server and Wolfram kernel are alive. Returns `bool`. |
| `evaluate(expr, timeout=30)` | Evaluate a plain Wolfram expression. Returns `Result`. |
| `evaluate_with_xact(expr, timeout=60, context_id=None)` | Evaluate with xAct pre-loaded and optional context isolation. Returns `Result`. |
| `cleanup()` | Clear Global context and reset xAct registries. Returns `bool`. |
| `restart()` | Hard-restart the Wolfram kernel (expensive fallback). Returns `bool`. |
| `check_clean_state()` | Query registry counts for leak detection. Returns `(is_clean, leaked_symbols)`. |

## 2. Normalization Functions

`sxact.normalize.pipeline`

Canonicalizes xAct output strings for comparison regardless of dummy index naming or whitespace.

### `normalize(expr)`

Regex-based pipeline, applies in order:

1. Whitespace normalization
2. Coefficient normalization (`2*x` → `2 x`, `-1*x` → `-x`)
3. Dummy index canonicalization (`a, b` → `$1, $2`)
4. Term ordering (lexicographic sort for sums)

### `ast_normalize(expr)`

AST-based normalizer (preferred for Tier 1 comparison). Handles arbitrarily nested brackets, sorts commutative operators before canonicalizing indices. Falls back to `normalize()` on parse failure.

## 3. Comparator API

`sxact.compare.comparator`

Implements the legacy sxAct multi-tier comparison strategy. New live-runner integration composes the same xAct-specific logic through Elegua's `ComparisonPipeline`, using `sxact.elegua_bridge.comparison_layers.compare_canonical` for L3 canonical comparison and `make_compare_numeric(oracle)` for L4 numeric sampling.

### `compare(lhs, rhs, oracle=None, mode=EqualityMode.SYMBOLIC, tensor_ctx=None)`

Compares two `Result` objects for equivalence:

- **Tier 1** (`NORMALIZED`): Normalized string equality. No oracle required.
- **Tier 2** (`SYMBOLIC`): Symbolic difference check (`Simplify[lhs - rhs] == 0`) using the Wolfram Oracle.
- **Tier 3** (`NUMERIC`): Numeric sampling fallback for identities the simplifier can't handle.

Returns a `CompareResult(equal, tier, confidence, diff)`.

### `EqualityMode`

| Value | Description |
| :--- | :--- |
| `NORMALIZED` | Stop at Tier 1 (string comparison only) |
| `SYMBOLIC` | Try up to Tier 2 (default) |
| `NUMERIC` | Try all three tiers |

## 4. Sampling API

`sxact.compare.sampling`

### `sample_numeric(lhs, rhs, oracle, n=10, seed=42, tensor_ctx=None, confidence_threshold=0.95)`

Evaluates symbolic expressions at random numeric points to check for equivalence. Supports both scalar and tensor expressions (via `TensorContext`).

Returns a `SamplingResult(equal, confidence, samples)`.

## 5. Snapshot API

`sxact.snapshot.compare`

Deterministic hash-based regression testing that allows verification without a live Wolfram Engine. Snapshot storage and comparison remain sxAct-specific because the JSON layout, content hashes, and CLI reporting are tied to XAct.jl oracle artifacts rather than Elegua's domain-agnostic runtime model.

### `SnapshotComparator`

Compares adapter results against pre-recorded oracle snapshots (stored as JSON with SHA-256 content hashes).

```python
from sxact.snapshot.compare import SnapshotComparator

comparator = SnapshotComparator(oracle_dir="oracle/")
result = comparator.compare(test_id, adapter_result)
# result.status: "match", "mismatch", or "missing"
```
