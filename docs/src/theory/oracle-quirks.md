# xAct Oracle Quirks

This document captures quirks, edge cases, and gotchas discovered while working with xAct through the Oracle HTTP server.

## Symbol Context Pollution (RESOLVED)

> **Status**: Resolved (2026-01-26). Symbol isolation is now handled via the `context_id` parameter to ensure a clean evaluation environment.

### The Problem

When using wolframclient to evaluate expressions, **symbols are parsed in `Global`` context before xAct sees them**. This causes:

1. Tensors like `S[-a,-b]` become `Global`S[Times[-1, Global`a], ...]` instead of xAct tensor expressions
2. `ToCanonical` and other xAct functions don't recognize the expressions as tensors
3. Curvature tensors like `RiemannCD` are created in `Global`` context and not treated as proper xAct curvatures

### Solution Implemented

The Oracle now supports a `context_id` parameter for `/evaluate-with-init`. When provided:

1. Expression is wrapped in `Begin["xAct`xTensor`"]; ToExpression[...]; End[]`
2. `ToExpression` delays parsing until after context is set
3. All symbols are created in `xAct`xTensor`` context
4. xAct functions properly recognize tensors

### Usage

```python
# Python client
client.evaluate_with_xact(expr, context_id="unique_id")

# Or via HTTP
POST /evaluate-with-init
{"expr": "...", "context_id": "unique_id"}
```

### Test Fixture

```python
@pytest.fixture
def context_id() -> str:
    return uuid.uuid4().hex[:8]
```

## Loading & Initialization

### xAct Load Time

- Loading xAct (`Needs["xAct`xTensor`"]`) takes **~2-3 seconds** on first call (persistent kernel)
- xAct is loaded once and reused across all `/evaluate-with-init` calls
- Subsequent calls complete in **~5-10ms** (kernel already initialized)
- Mark integration tests with `@pytest.mark.slow` to skip during normal development

### Index Naming

- xAct requires indices to be defined with the manifold: `DefManifold[M, 4, {a,b,c,d}]`
- Using undefined indices causes cryptic errors
- Indices are case-sensitive
- **Do NOT use `N` as a manifold name** — it's Mathematica's built-in numeric conversion function

### Reserved Names to Avoid

- `N` — Mathematica's numeric conversion
- `I` — imaginary unit
- `E` — Euler's number
- `C` — used for constants in solutions
- `D` — derivative operator
- `O` — big-O notation

## Output Format

### Unicode Characters

- xAct may output Greek letters as Unicode: `μ`, `ν` instead of `\[Mu]`, `\[Nu]`
- Normalization pipeline should handle both forms
- Example: `T[-μ,-ν]` and `T[-\[Mu],-\[Nu]]` should normalize identically

### Dummy Index Naming

- xAct generates internal dummy indices like `$1234`
- These may appear in output even for simple expressions
- Normalization must canonicalize these to `$1, $2, ...`

### FullForm vs InputForm

- wolframclient returns expressions in Python object form, converted via `str()`
- This produces FullForm-like output: `Times[-1, a]` instead of `-a`
- Comparisons must account for these format differences

## Tensor Operations

### DefTensor Syntax

```mathematica
(* Correct: indices with positions *)
DefTensor[T[-a,-b], M, Symmetric[{-a,-b}]]

(* Wrong: missing index positions *)
DefTensor[T[a,b], M, Symmetric[{a,b}]]  (* May silently fail *)
```

### ToCanonical Behavior

- `ToCanonical` returns the canonical form but may not simplify to zero
- For testing equality, use `ToCanonical[expr1 - expr2]` and check for `0`
- Sometimes `Simplify` is needed after `ToCanonical`
- **ToCanonical only works if tensors are properly registered with xAct** (see Context Pollution issue)

### Metric Contraction

- Use `ContractMetric` explicitly; it's not automatic
- Order matters: `g[a,b] V[-b] // ContractMetric` ≠ `ContractMetric[g[a,b]] V[-b]`

### DefMetric Functions

- `SignDetOfMetric[g]` — returns the sign of the metric determinant (-1 for Lorentzian)
- `SignatureOfMetric[g]` — throws `Hold[Throw[None]]` in some cases (may require explicit signature spec)
- Use `SignDetOfMetric` for testing metric properties

## Comparator Implications

### Tier 1: Normalized Comparison

- Most xAct outputs differ only in dummy index naming
- Proper normalization catches ~80% of equality cases

### Tier 2: Symbolic Simplify

- `Simplify[(expr1) - (expr2)]` works for most algebraic expressions
- May timeout for complex tensor expressions
- xAct-specific simplification rules require xAct context

### Tier 3: Numeric Sampling

- Tensor expressions with free indices cannot be directly sampled
- Need to substitute concrete index values or use trace operations
- Fallback for expressions Simplify cannot handle
- Works for scalar expressions (Sin[x]^2 + Cos[x]^2 == 1)

## Known Issues

### Session State

- The Oracle uses a **persistent Wolfram kernel** via WSTP (wolframclient)
- Tensor definitions persist across API calls within the same kernel session
- The kernel restarts automatically on timeout or error (xAct is reloaded)
- **Symbol pollution**: once a symbol is created in `Global``, it stays there

### Error Messages

- xAct errors are often unhelpful: `"Syntax error"`
- `Hold[Throw[None]]` indicates an internal xAct exception was caught
- Check that all indices are defined before use
- Verify manifold dimensions match tensor rank

### Tests Status (12/12 Pass)

All integration tests now pass after implementing context isolation:

1. ✅ TestDefineManifold::test_define_manifold_returns_manifold_info
2. ✅ TestDefineManifold::test_manifold_dimension
3. ✅ TestDefineMetric::test_define_metric_with_signature
4. ✅ TestSymmetricTensor::test_symmetric_tensor_swap_indices
5. ✅ TestToCanonical::test_tocanonical_reorders_indices
6. ✅ TestMetricContraction::test_metric_contraction_raises_index
7. ✅ TestRiemannTensor::test_riemann_exists_after_metric_definition
8. ✅ TestSymbolicEquality::test_symmetric_tensor_sum_equals_double (uses context_id)
9. ✅ TestNumericSampling::test_numeric_evaluation_of_scalar_expression
10. ✅ TestAntisymmetricTensor::test_antisymmetric_tensor_swap_negates (uses context_id)
11. ✅ TestBianchiIdentity::test_riemann_antisymmetry_first_pair (uses context_id)
12. ✅ TestBianchiIdentity::test_riemann_pair_exchange (uses context_id)

> **Note**: The original Bianchi identity test was replaced. ToCanonical doesn't apply
> multi-term symmetries like the first Bianchi identity. Tests now verify mono-term
> symmetries (antisymmetry, pair exchange) that ToCanonical does support.

## Performance Tips

1. Batch related operations into single expressions
2. Use simpler test manifolds (dim 2-3) for unit tests
3. Skip slow tests during development: `pytest -m "not slow"`
4. The Oracle uses a persistent kernel - xAct loads once (~2s) and stays loaded
5. Use unique symbol names per test to avoid protection errors

## Implementation Notes

### Context Isolation (Completed)

The context isolation feature was implemented in commit 9cc21fa:

1. ✅ Added `context_id` parameter to `/evaluate-with-init` endpoint
2. ✅ Server wraps evaluation in `Begin["xAct`xTensor`"]; ToExpression[...]; End[]`
3. ✅ Pytest fixture generates unique context ID per test
4. ✅ All evaluations within a test use the same context ID

### Why Begin/ToExpression Instead of Block

The original plan suggested `Block[{$Context = ...}, expr]`, but this doesn't work because:
- `Block` only affects evaluation context, not parsing context
- Symbols are parsed BEFORE `Block` executes
- All symbols end up in `Global`` anyway

The solution uses `ToExpression` to delay parsing:
```mathematica
Begin["xAct`xTensor`"];
With[{result$$ = ToExpression["expr"]}, End[]; result$$]
```

### Future Improvements

1. **Comparator**: Could add `ToCanonical` for tensor expressions in tier-2 comparison
2. **Bianchi identity**: Could load xTras and use `CurvatureRelationsBianchi` if needed
3. **Context cleanup**: May want kernel restart strategy for very long test runs
