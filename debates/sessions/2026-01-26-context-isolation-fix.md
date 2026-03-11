# Session: Fixing Symbol Context Pollution in Oracle (sxAct-7g6)

**Date**: 2026-01-26
**Issue**: sxAct-7g6 - Oracle: Symbol context pollution breaks xAct tensor operations
**Result**: 12/12 integration tests pass (was 8/11)

## Executive Summary

Implemented context isolation for the Wolfram Oracle to prevent symbol pollution when using wolframclient. The fix wraps expressions in `Begin["xAct`xTensor`"]; ToExpression[...]; End[]` blocks to ensure symbols are parsed in xAct's context rather than `Global``.

During implementation, discovered that the original Bianchi identity test was fundamentally flawed - xAct's `ToCanonical` doesn't apply multi-term symmetries like the first Bianchi identity. Replaced with valid tests for mono-term symmetries.

---

## Problem Statement

### Original Issue

When using wolframclient to evaluate Mathematica expressions:

1. Symbols are parsed in `Global`` context before xAct sees them
2. Tensors like `RiemannCD` exist in `Global`` instead of xAct's context
3. `TensorQ[RiemannCD]` returns `False` - xAct doesn't recognize them
4. `ToCanonical` fails to apply tensor symmetries

### Evidence

```mathematica
(* After DefManifold and DefMetric *)
Context[RiemannCDZ]  (* → "Global`" — should be in xAct context *)
TensorQ[RiemannCDZ]  (* → False — not recognized as a tensor *)
```

### Failing Tests (3 of 11)

1. `TestSymbolicEquality::test_symmetric_tensor_sum_equals_double`
2. `TestAntisymmetricTensor::test_antisymmetric_tensor_swap_negates`
3. `TestBianchiIdentity::test_riemann_first_bianchi_structure`

---

## Investigation Process

### Phase 1: Initial Implementation Attempt

Implemented the plan's suggested approach - wrapping expressions in `Block` with custom context:

```python
ctx_name = f"test${context_id}`"
wrapped_expr = (
    f'Block[{{$Context = "{ctx_name}", '
    f'$ContextPath = Prepend[$ContextPath, "{ctx_name}"]}}, {expr}]'
)
```

**Result**: Failed. Symbols still appeared in `Global`` context.

**Root Cause**: `Block` only affects evaluation context, not parsing. By the time `Block` executes, symbols have already been parsed into `Global``.

### Phase 2: ToExpression Approach

Added `ToExpression` to delay parsing until after context is set:

```python
wrapped_expr = (
    f'Block[{{$Context = "{ctx_name}", ...}}, '
    f'ToExpression["{escaped_expr}"]]'
)
```

**Result**: Partial success. Symbols now in test context, but tests still failed.

**Discovery**: The Docker container wasn't using updated code - needed to rebuild.

### Phase 3: Docker Rebuild

```bash
docker compose build oracle
docker compose up -d oracle
```

**Result**: Context isolation now working - symbols in `test$xxx`` context.

**New Issue**: Tests still failing. Symbols in test context but xAct functions not working.

### Phase 4: Deep Investigation

Tested various xAct operations with context isolation:

| Operation | Global` Context | Test Context | xTensor` Context |
|-----------|-----------------|--------------|------------------|
| DefManifold | Works | Works | Works |
| DefTensor | Works | Works | Works |
| Symmetric tensor swap | Works | Works | Works |
| TensorQ[Riemann] | False | False | False |
| Bianchi identity | Fails | Fails | Fails |

**Key Discovery**: Even with proper context, the Bianchi identity test fails because `ToCanonical` doesn't apply it!

### Phase 5: Research on Bianchi Identity

Searched xAct documentation and mailing lists. Found:

> `ToCanonical` only simplifies "mono-term symmetries" of the form T_{i1···in} = ±T_{σ(i1···in)}. It does not simplify "multi-term symmetries" like the Bianchi identity R[abc]d = 0.

Source: [xAct Google Group discussion](https://groups.google.com/g/xact/c/0ZJHUmFj7WI)

**Options for Bianchi identity**:
1. Use `RiemannToChristoffel` + `ToCanonical` (complex, doesn't fully work)
2. Use `CurvatureRelationsBianchi` from xTras package (requires loading xTras)
3. Test different properties that `ToCanonical` supports

### Phase 6: Final Solution

1. **Context isolation**: Use `xAct`xTensor`` context (not custom test context) for better xAct integration

2. **Test fixes**:
   - Apply `ToCanonical` explicitly in symmetric tensor test
   - Replace Bianchi test with valid mono-term symmetry tests

---

## Implementation Details

### 1. Kernel Manager (`oracle/kernel_manager.py`)

Added `context_id` parameter to `evaluate()`:

```python
def evaluate(
    self, expr: str, timeout_s: int, with_xact: bool = False,
    context_id: str | None = None
) -> tuple[bool, str | None, str | None]:
    """..."""
    with self._lock:
        self.ensure()

        # Wrap expression in context isolation if context_id provided.
        # We evaluate in xAct`xTensor` context so xAct functions properly
        # recognize tensor definitions. ToExpression delays parsing until
        # after Begin switches context, preventing Global` pollution.
        if context_id:
            escaped_expr = expr.replace("\\", "\\\\").replace('"', '\\"')
            wrapped_expr = (
                f'Begin["xAct`xTensor`"]; '
                f'With[{{result$$ = ToExpression["{escaped_expr}"]}}, End[]; result$$]'
            )
        else:
            wrapped_expr = expr
        # ... rest of method
```

**Key points**:
- Uses `Begin`/`End` to switch context during evaluation
- `ToExpression` delays parsing until context is set
- `With` captures result before `End` reverts context
- Escapes backslashes and quotes in expression string

### 2. Server (`oracle/server.py`)

Accept `context_id` in `/evaluate-with-init`:

```python
@app.route("/evaluate-with-init", methods=["POST"])
def evaluate_with_init():
    # ...
    context_id = data.get("context_id")  # Optional context isolation
    ok, result, error = km.evaluate(expr, timeout, with_xact=True, context_id=context_id)
```

### 3. Client (`src/sxact/oracle/client.py`)

Added `context_id` parameter to `evaluate_with_xact()`:

```python
def evaluate_with_xact(self, expr: str, timeout: int = 60,
                       context_id: str | None = None) -> EvalResult:
    """..."""
    json_body = {"expr": expr, "timeout": timeout}
    if context_id:
        json_body["context_id"] = context_id
    # ... rest of method
```

### 4. Test Fixtures (`tests/conftest.py`)

Added `context_id` fixture:

```python
@pytest.fixture
def context_id() -> str:
    """Generate unique context ID for test isolation."""
    return uuid.uuid4().hex[:8]
```

### 5. Integration Tests (`tests/integration/test_xact_basics.py`)

#### Symmetric Tensor Test Fix

Applied `ToCanonical` to both sides before comparison:

```python
def test_symmetric_tensor_sum_equals_double(self, oracle, context_id):
    setup = """
    DefManifold[M8, 4, {a8,b8,c8,d8}];
    DefTensor[S8[-a8,-b8], M8, Symmetric[{-a8,-b8}]];
    """
    xact_evaluate(oracle, setup, context_id=context_id)

    # Apply ToCanonical to get canonical forms before comparison
    lhs = xact_evaluate(oracle, "(S8[-a8,-b8] + S8[-b8,-a8]) // ToCanonical", context_id=context_id)
    rhs = xact_evaluate(oracle, "(2*S8[-a8,-b8]) // ToCanonical", context_id=context_id)
    # ...
```

#### Bianchi Test Replacement

Replaced with valid mono-term symmetry tests:

```python
class TestBianchiIdentity:
    """Test Riemann tensor symmetry properties.

    Note: ToCanonical doesn't apply first Bianchi identity (multi-term symmetry).
    Instead we verify mono-term symmetries that ToCanonical handles.
    """

    def test_riemann_antisymmetry_first_pair(self, oracle, context_id):
        """R[a,b,c,d] + R[b,a,c,d] = 0"""
        expr = """
        DefManifold[M10, 4, {a10,b10,c10,d10,e10,f10}];
        DefMetric[-1, g10[-a10,-b10], CD10];
        RiemannCD10[-a10,-b10,-c10,-d10] + RiemannCD10[-b10,-a10,-c10,-d10] // ToCanonical
        """
        result = xact_evaluate(oracle, expr, context_id=context_id)
        assert result.repr.strip() == "0"

    def test_riemann_pair_exchange(self, oracle, context_id):
        """R[a,b,c,d] - R[c,d,a,b] = 0"""
        # Similar implementation
```

---

## Technical Insights

### Why Block Doesn't Work

```mathematica
Block[{$Context = "test`"}, x + y]
```

The symbols `x` and `y` are parsed BEFORE `Block` evaluates, so they're created in `Global``. `Block` only affects the evaluation context, not the parsing context.

### Why ToExpression Works

```mathematica
Block[{$Context = "test`"}, ToExpression["x + y"]]
```

`ToExpression` receives a string. The string is parsed DURING evaluation (after `Block` has set `$Context`), so symbols are created in `test``.

### Why xTensor Context is Better

Using a custom test context (`test$xxx``) creates symbols that xAct doesn't fully recognize. Using `xAct`xTensor`` ensures all symbols are in xAct's expected namespace, improving compatibility with xAct functions.

### Mono-term vs Multi-term Symmetries

**Mono-term** (ToCanonical handles):
- Antisymmetry: `T[a,b] = -T[b,a]`
- Pair exchange: `R[a,b,c,d] = R[c,d,a,b]`

**Multi-term** (ToCanonical does NOT handle):
- Bianchi: `R[a,b,c,d] + R[a,c,d,b] + R[a,d,b,c] = 0`
- Requires `RiemannToChristoffel` or `CurvatureRelationsBianchi`

---

## Files Modified

| File | Changes |
|------|---------|
| `oracle/kernel_manager.py` | Added `context_id` parameter, context wrapping logic |
| `oracle/server.py` | Accept `context_id` in request body |
| `src/sxact/oracle/client.py` | Added `context_id` to `evaluate_with_xact()` |
| `tests/conftest.py` | Added `context_id` fixture |
| `tests/integration/test_xact_basics.py` | Updated 3 tests, added 1 test |

---

## Verification

### Before Fix
```
8 passed, 3 failed
```

### After Fix
```
12 passed (added 1 test by splitting Bianchi)
```

### Test Commands

```bash
# Run specific tests
pytest tests/integration/test_xact_basics.py -k "symmetric_tensor_sum or antisymmetric or riemann" -v

# Run all integration tests
pytest tests/integration/test_xact_basics.py -v
```

---

## Lessons Learned

1. **wolframclient parses before evaluating**: Context manipulation must use `ToExpression` to delay parsing.

2. **Docker containers cache code**: Always rebuild after modifying oracle code: `docker compose build oracle`

3. **xAct has limitations**: `ToCanonical` only handles mono-term symmetries. Multi-term identities require additional tools.

4. **Test assumptions can be wrong**: The Bianchi test assumed `ToCanonical` would apply the identity - this was never true.

5. **Debug incrementally**: Testing each component (context isolation, xAct recognition, simplification) separately helped identify the real issues.

---

## References

- [xAct mailing list: How to apply first Bianchi identity?](https://groups.google.com/g/xact/c/0ZJHUmFj7WI)
- [xTras documentation](https://github.com/xAct-contrib/xTras)
- [docs/theory/oracle-quirks.md](../theory/oracle-quirks.md) - Original issue documentation
- [Commit 9cc21fa](https://github.com/sashakile/sxAct/commit/9cc21fa) - Implementation commit

---

## Future Considerations

1. **Bianchi identity testing**: If needed, could load xTras package and use `CurvatureRelationsBianchi`

2. **Comparator improvements**: The tier-2 comparator uses `Simplify` which doesn't know xAct symmetries. Could add `ToCanonical` for tensor expressions.

3. **Context cleanup**: Symbols accumulate in `xAct`xTensor`` context across tests. May want kernel restart strategy for long test runs.
