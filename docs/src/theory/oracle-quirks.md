# xAct Oracle Quirks

!!! info "Quick Reference"
    **Reserved names**: avoid `N`, `I`, `E`, `C`, `D`, `O` as symbol names.
    **Context isolation**: use `context_id` parameter to prevent symbol pollution.
    **Key gotcha**: `ToCanonical` only handles mono-term symmetries, not Bianchi identity.

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
- Proper normalization handles the majority of equality cases

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

### Integration Tests

37 integration tests across three suites verify Oracle behavior:

- `test_xact_basics.py` (12 tests) — manifold/metric/tensor definitions, canonicalization, contraction, curvature, numeric sampling
- `test_isolation.py` (6 tests) — kernel cleanup, state isolation between test files, dirty-kernel recovery
- `test_tensor_tier3.py` (19 tests) — tensor numeric sampling, tier-3 comparison fallback, context tracking

> **Note**: `ToCanonical` does not apply multi-term symmetries like the first Bianchi identity.
> Integration tests verify mono-term symmetries (antisymmetry, pair exchange) that `ToCanonical` supports.

## Performance Tips

1. Batch related operations into single expressions
2. Use simpler test manifolds (dim 2-3) for unit tests
3. Skip slow tests during development: `pytest -m "not slow"`
4. The Oracle uses a persistent kernel - xAct loads once (~2s) and stays loaded
5. Use unique symbol names per test to avoid protection errors

## Implementation Notes

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
