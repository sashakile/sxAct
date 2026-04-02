## Context

XTensor's expression parser was built for flat tensor products (`T[-a,-b] V[-c]`).
CovD support was added later via a separate regex-based string parser because the
existing `FactorAST(name, indices)` had no slot for an operand, and refactoring would
have touched every function in the canonicalization pipeline.

This created three CovD code paths:
1. `_parse_expression` / `FactorAST` — flat parser, silently drops CovD operands
2. `_extract_covd_chain` / `_split_expression_terms` — string-based CovD chain parser
3. `_preprocess_covd_reductions` — regex string rewrites for metric compatibility
   and second Bianchi identity (runs on raw string before `_parse_expression`)

## Terminology

- **CovD application**: `CD[-a][operand]` — a single covariant derivative acting on
  an operand expression. Represented as a `CovDFactor` node in the AST.
- **CovD chain**: Nested applications `CD[-a][CD[-b][...]]`. Represented as a
  `CovDFactor` whose operand contains another `CovDFactor`.
- **Mixed CovD+product**: `CD[-a][V[-b]] S[-c,-d]` — a CovD factor multiplied by
  plain tensor factors in the same term. The most common physics usage pattern.

## Goals / Non-Goals

- **Goal**: Single AST that represents flat products AND CovD application
- **Goal**: `ToCanonical("CD[-a][V[-b]]")` round-trips correctly (or errors explicitly)
- **Goal**: `SortCovDs`/`CommuteCovDs` use the same AST as `ToCanonical`
- **Goal**: Mixed CovD+product expressions like `CD[-a][V[-b]] S[-c,-d]` parse correctly
- **Non-Goal**: Full CovD canonicalization inside `ToCanonical` (that's a separate feature)
- **Non-Goal**: Changing the string syntax — `CD[-a][V[-b]]` remains the format
- **Non-Goal**: CovD of sums — `CD[-a][V[-b] + W[-b]]` should be expanded by the
  user to `CD[-a][V[-b]] + CD[-a][W[-b]]` (linearity). The parser rejects sums
  inside CovD brackets with an explicit error.

## Decisions

### AST node design

Extend `FactorAST` to a sum type:

```julia
# A factor is either a plain tensor or a CovD application
struct TensorFactor
    tensor_name::Symbol
    indices::Vector{String}
end

struct CovDFactor
    covd_name::Symbol
    deriv_index::String
    operand::Vector{FactorNode}  # the monomial being differentiated (no coefficient)
end

const FactorNode = Union{TensorFactor, CovDFactor}

struct TermAST
    coeff::Rational{Int}
    factors::Vector{FactorNode}
end
```

**Operand type**: `operand::Vector{FactorNode}` represents a monomial (product of
factors) without a coefficient. The coefficient lives at the outer `TermAST` level.
This matches physics: `3 CD[-a][V[-b]]` means "3 times the derivative of V", not
"derivative of 3V". If the parser encounters a coefficient inside CovD brackets
(e.g., `CD[-a][3 V[-b]]`), it factors it out: coeff becomes `3` on the TermAST,
operand becomes `[TensorFactor(:V, ["-b"])]`.

**Why Union over abstract type**: Julia's Union-splitting gives zero-overhead dispatch
for small unions. An abstract type hierarchy adds method table complexity for no benefit
with only 2 variants.

**Alternative considered**: Keep `FactorAST` flat and represent CovD as a special
tensor with a metadata field. Rejected because it would require every consumer of
`FactorAST` to check for the special case, which is what we're trying to eliminate.

### Parser changes

`_parse_monomial` currently stops when it sees `[` after `]` (not a letter). The fix:
after parsing `Name[indices]`, check if the next character is `[`. If so, AND the
`Name` is a registered CovD (checked via `CovDQ`), recursively parse the bracketed
content as the operand of a `CovDFactor`. If `Name` is not a registered CovD and `[`
follows `]`, raise a parse error.

### Migration strategy

Phase the change:

1. **Phase A** (guard): Add a check in `_parse_monomial` — if `]` is followed by `[`,
   raise an error: "CovD bracket syntax not supported in this context. Use SortCovDs."
   This eliminates silent data loss immediately.

2. **Phase B** (AST): Rename `FactorAST` to `TensorFactor` first. Then introduce
   `CovDFactor` and `FactorNode`. Update `_parse_monomial` to produce `FactorNode`.
   Update `_canonicalize_term`, `_serialize`, and `_term_key_str` to handle both
   variants. `ToCanonical` preserves CovD bracket structure and recursively
   canonicalizes the inner operand.

3. **Phase C** (unify): Rewrite `SortCovDs`/`CommuteCovDs` to parse via the unified
   AST instead of `_extract_covd_chain`. Migrate `_preprocess_covd_reductions` from
   string-regex to AST-level identity application. Retire the string-based parsers.

### Execution order

Phase B preserves the existing execution order in `ToCanonical`: `_preprocess_covd_reductions`
runs on the raw string BEFORE `_parse_expression`. This ensures metric compatibility and
second Bianchi reductions still work during the transition. Phase C migrates these to
AST-level operations, after which the preprocessing step is removed.

## Risks / Trade-offs

- **Risk**: Changing `FactorAST` breaks every function that pattern-matches on it.
  Mitigation: Phase A (error guard) ships first and is zero-risk. Phase B renames
  `FactorAST` to `TensorFactor` as the first step, so existing code needs only a rename
  before any new types are introduced.

- **Risk**: CovD operands create nested AST — serialization, key-hashing, and
  coefficient collection must handle recursive structure.
  Mitigation: `_term_key_str` already uses string serialization; extending it to
  serialize CovD brackets is straightforward.

- **Trade-off**: Phase B makes `ToCanonical` CovD-aware — it preserves the CovD bracket
  structure and recursively canonicalizes the inner operand. But it does not canonicalize
  CovD ordering (sorting derivatives) — that stays in `SortCovDs`. CovD ordering involves
  Riemann correction terms and is a distinct algorithm.

- **Rollback**: Phase A is independently revertable (one error check). Phase B should be
  a single commit or squashed PR so it can be reverted atomically if regressions appear.

## Known call sites affected by CovD bracket blindness

Audit performed 2026-04-02 after fixing SortCovDs term collection (69754a2).
Phase A (error guard) is deployed — these now throw instead of silently corrupting,
but callers still need to handle the error or gain bracket support.

### P1 — Reachable from TOML test runner today

| Caller | File | Issue |
|--------|------|-------|
| `Simplify()` | `Pert.jl:387` | Calls `Contract` → `ToCanonical` in loop; crashes on brackets |
| `Contract()` | `Canonical.jl` | Same flat parser as `ToCanonical`; crashes on brackets |
| `_contract()` adapter | `julia_stub.py:489` | Unprotected — same pattern as the `_to_canonical` bug fixed in 69754a2 |
| `_simplify()` adapter | `julia_stub.py:558` | Unprotected — same pattern |

**Interim mitigation (already deployed):** `_to_canonical` has try/catch + SortCovDs fallback.
`_contract` and `_simplify` do NOT have this fallback — they will crash if a TOML test
passes CovD bracket expressions to Contract or Simplify actions. No current TOML test
does this, but it's a latent bug.

### P2 — Reachable from user-facing API

| Caller | File | Issue |
|--------|------|-------|
| `SymmetryOf()` | `XTras.jl:117` | Calls `ToCanonical` directly |
| `AllContractions()` | `XTras.jl:62,73` | Calls `Simplify`/`Contract` |
| `MakeTraceFree()` | `XTras.jl:357` | Calls `Simplify` |
| `CollectTensors()` | `XTras.jl:15` | Delegates to `ToCanonical` |

These are higher-level functions that rarely receive CovD expressions in practice,
but they will crash if they do.

### Already safe

| Caller | Why safe |
|--------|----------|
| `_safe_simplify()` (Pert.jl:757) | Regex guard detects brackets, returns unchanged |
| `SortCovDs()` | Native bracket support, now with term collection |
| `CommuteCovDs()` | Native bracket support |
| `_to_canonical()` adapter | try/catch + SortCovDs fallback |

### Resolution

Phase B (unified AST) eliminates all of these — once `_parse_monomial` can produce
`CovDFactor` nodes, `ToCanonical`/`Contract`/`Simplify` handle brackets natively.
Until then, the P1 adapter handlers could get the same try/catch fallback as
`_to_canonical`, but this is piecemeal — prefer shipping Phase B instead.

## Open Questions

- Should `Contract` and `Simplify` attempt to contract through CovD brackets
  (e.g., `g^{ab} CD[-a][V[-b]]` → `CD^{a}[V[-a]]`)? Probably yes, but this
  can be deferred to a follow-up.
