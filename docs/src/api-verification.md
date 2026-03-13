# Verification API (`sxact`)

The `sxact` Python package is a specialized framework for verifying the mathematical correctness of `xAct.jl` against the Wolfram Language implementation.

## 1. Oracle Client

`sxact.oracle.client.OracleClient(base_url="http://localhost:8765")`

Manages the connection to the Dockerized Wolfram Engine.

| Method | Description |
| :--- | :--- |
| `health()` | Check if the server and Wolfram kernel are alive. Returns `bool`. |
| `evaluate(expr, timeout=30)` | Evaluate a plain Wolfram expression. Returns `Result`. |
| `evaluate_with_xact(expr, timeout=60, context_id=None)` | Evaluate with xAct pre-loaded and optional context isolation. Returns `Result`. |
| `cleanup()` | Clear Global context and reset xAct registries. Returns `bool`. |
| `restart()` | Hard-restart the Wolfram kernel (expensive fallback). Returns `bool`. |
| `check_clean_state()` | Query registry counts for leak detection. Returns `(is_clean, leaked_symbols)`. |

## 2. Normalization Pipeline

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

## 3. Comparison Engine

`sxact.compare.comparator`

Implements a multi-tier comparison strategy.

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

## 4. Numeric Sampling

`sxact.compare.sampling`

### `sample_numeric(lhs, rhs, oracle, n=10, seed=42, tensor_ctx=None, confidence_threshold=0.95)`

Evaluates symbolic expressions at random numeric points to check for equivalence. Supports both scalar and tensor expressions (via `TensorContext`).

Returns a `SamplingResult(equal, confidence, samples)`.

## 5. Snapshot Comparator

`sxact.snapshot.compare`

Deterministic hash-based regression testing that allows verification without a live Wolfram Engine.

### `SnapshotComparator`

Compares adapter results against pre-recorded oracle snapshots (stored as JSON with SHA-256 content hashes).

```python
from sxact.snapshot.compare import SnapshotComparator

comparator = SnapshotComparator(oracle_dir="oracle/")
result = comparator.compare(test_id, adapter_result)
# result.status: "match", "mismatch", or "missing"
```
