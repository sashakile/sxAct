# Layer 2 Property Test Format and Runner Integration Design

**Date:** 2026-03-05
**Ticket:** sxAct-yue
**Status:** Decision
**Blocks:** sxAct-a2i (Layer 2 property catalog implementation)

---

## Summary

Five design decisions for Layer 2 property testing:

1. **Format**: Separate TOML format in `tests/properties/`, extending the spec schema
2. **Runner**: New `xact-test property` CLI subcommand
3. **Backend**: Custom sampling (existing `sampling.py`) as primary; Hypothesis deferred
4. **Cross-adapter**: Same random inputs executed on all adapters; results compared
5. **Scalar scope**: 10+ xCore properties tractable; real value is in xTensor invariants

---

## Q1: Property Spec Format

**Decision: Separate TOML file format, `layer = "property"`, in `tests/properties/`**

The Layer 1 TOML format (`tests/xcore/*.toml`) uses `[[tests]]` + `[[tests.operations]]`
with imperative `action` steps. This doesn't map naturally to declarative "for all X, P(X)".

The Layer 2 format defined in `specs/2026-01-09-three-layer-testing-architecture.md` is
already detailed and well-reasoned. Use it as-is:

```toml
# tests/properties/xcore_symbol_laws.toml
version = "1.0"
layer = "property"
description = "xCore symbol manipulation mathematical properties"

[[properties]]
id = "dagger_involution"
name = "MakeDaggerSymbol is an involution"

[properties.mathematical_basis]
statement = "For any symbol s, MakeDaggerSymbol(MakeDaggerSymbol(s)) == s"

[properties.forall]
[[properties.forall.generators]]
name = "s"
type = "Symbol"
strategy = "fresh_symbol"

[properties.law]
lhs = "MakeDaggerSymbol[MakeDaggerSymbol[$s]]"
rhs = "$s"
equivalence_type = "identical"

[properties.verification]
num_samples = 50
random_seed = 42
```

**Directory layout:**
```
tests/
├── xcore/        # Layer 1 (existing)
├── properties/   # Layer 2 (new)
│   ├── xcore_symbol_laws.toml
│   ├── tensor_algebra_laws.toml
│   └── riemann_symmetries.toml
```

The `layer = "property"` tag distinguishes files; the runner will refuse to load
Layer 1 files via `xact-test property` and vice versa.

---

## Q2: Runner Integration

**Decision: New `xact-test property` CLI subcommand**

The existing `xact-test run` subcommand operates on Layer 1 TOML with snapshot/live
oracle modes. Property tests have fundamentally different execution semantics (generate
inputs, execute forall, check law). Mixing them under `--layer=2` would complicate the
`run` path.

A new subcommand is clean, follows the existing CLI pattern, and makes usage explicit:

```
xact-test property tests/properties/          # run all property tests
xact-test property tests/properties/ --adapter=python  # test specific adapter
xact-test property tests/properties/ --samples=200     # override sample count
xact-test property tests/properties/ --seed=99         # reproducible run
xact-test property tests/properties/ --filter tag:critical
```

Rejected alternatives:
- `--layer=2` flag on `run`: pollutes existing subcommand, complicates loader
- pytest plugin: heavyweight, doesn't fit oracle-based architecture, breaks cross-adapter parity

---

## Q3: Hypothesis vs Custom Sampling

**Decision: Use existing `sampling.py` as primary backend; defer Hypothesis**

Hypothesis advantages (shrinking, stateful, seeds, rich strategies) are compelling but
create a hard dependency on Python-only execution. The core goal of Layer 2 is
**language-agnostic**: a property TOML should run against Wolfram, Julia, and Python.

Hypothesis is Python-specific and cannot drive the Wolfram or Julia adapters directly.
The existing `sampling.py` already supports:
- Scalar variable substitution with random values
- Tensor component array generation (`build_tensor_context`)
- Confidence scoring across N realizations
- Reproducible seeding

The property runner will use `sample_numeric` from `sampling.py` with the generator
types declared in `properties.forall.generators`. Hypothesis can be revisited later
as an optional enhancement for the Python adapter only (to get shrinking on failures).

**New generator types to implement in `sampling.py`:**
- `"fresh_symbol"` → random fresh symbol name (for xCore symbol properties)
- `"symbol_list"` → list of N fresh symbols
- `"Tensor"` → random component array (already exists via `TensorContext`)
- `"Metric"` → random positive-definite metric (already exists)

---

## Q4: Cross-Adapter Property Validation

**Decision: Same random inputs executed on all adapters; compare outputs**

The property runner generates a fixed set of N input realizations (from the `forall`
generators), then for each realization:
1. Execute `properties.law.lhs` on adapter A
2. Execute `properties.law.rhs` on adapter A
3. Compare with `equivalence_type`

When running cross-adapter validation:
1. Generate inputs once (shared RNG seed)
2. Execute the same inputs on each enabled adapter
3. All adapters must produce equivalent results

This is cleaner than running adapters independently with separate random seeds (which
would sample different input spaces). The shared seed means failures are reproducible
and comparable across adapters.

```
xact-test property tests/properties/ --adapter=wolfram,python
```

---

## Q5: Tractable Scalar Properties for xCore

**xCore has no mathematical knowledge** (pure programming utilities). The meaningful
properties are programming invariants, not tensor mathematics. Still, 10+ are tractable:

| # | Property | Functions | Type |
|---|---|---|---|
| 1 | `MakeDaggerSymbol` is involution | `make_dagger_symbol` | identity |
| 2 | `HasDaggerCharacterQ(MakeDaggerSymbol(s))` always True | both | predicate |
| 3 | `UnlinkSymbol(LinkSymbols([s]))` == `[s]` | both | roundtrip |
| 4 | `UnlinkSymbol(LinkSymbols([a,b]))` == `[a,b]` | both | roundtrip |
| 5 | `len(UnlinkSymbol(LinkSymbols(syms))) == len(syms)` | both | length-pres |
| 6 | `DeleteDuplicates` is idempotent | `delete_duplicates` | idempotent |
| 7 | `DuplicateFreeQ(DeleteDuplicates(lst))` always True | both | invariant |
| 8 | `len(DeleteDuplicates(lst)) <= len(lst)` | both | monotone |
| 9 | `JustOne([x]) == x` | `just_one` | identity |
| 10 | `SymbolJoin(*syms)` returns a string | `symbol_join` | type |
| 11 | `HasDaggerCharacterQ(plain_sym)` is False (no dagger) | predicate | predicate |
| 12 | `FindSymbols(expr)` is subset of all symbols in expr | `find_symbols` | subset |

**These are low mathematical value but good for framework validation.**

The high-value Layer 2 properties are in **xTensor/xPerm**:
- Riemann tensor symmetries (R_{abcd} = -R_{bacd}, etc.)
- Bianchi identity
- Metric contraction idempotency
- ToCanonical idempotency
- Contraction with Kronecker delta

These require tensor generators and are the real research contribution. The xCore
scalar properties serve as framework smoke tests.

---

## Updated Decision for sxAct-a2i

The Layer 2 property catalog should include:
- 5+ xCore scalar properties (framework smoke tests)
- 10+ xTensor tensor invariants (research contribution)
- Split into separate TOML files by mathematical domain

Recommended first properties for catalog (implement in sxAct-a2i):
1. `MakeDaggerSymbol` involution
2. `LinkSymbols`/`UnlinkSymbol` roundtrip
3. `DeleteDuplicates` idempotency
4. Contraction with Kronecker delta: `T[a] * Delta[-a, b] == T[b]`
5. Metric symmetry: `g[a, b] == g[b, a]`
6. Riemann antisymmetry in first pair: `R[a,b,c,d] == -R[b,a,c,d]`
7. Riemann antisymmetry in second pair: `R[a,b,c,d] == -R[a,b,d,c]`
8. Riemann pair-exchange symmetry: `R[a,b,c,d] == R[c,d,a,b]`
9. First Bianchi identity: `R[a,b,c,d] + R[a,c,d,b] + R[a,d,b,c] == 0`
10. `ToCanonical` idempotency
