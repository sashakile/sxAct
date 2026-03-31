# Change: Unify the two XTensor expression parsers

## Why

XTensor has two independent parsers in `Canonical.jl`:

1. **`_parse_expression` / `FactorAST`** (lines 5-218) — flat `Name[indices]` products. Used by `ToCanonical`, `Contract`, `Simplify`.
2. **`_extract_covd_chain` / `_split_expression_terms`** (lines 545-730) — nested `CD[-a][CD[-b][T[-c]]]` brackets. Used by `SortCovDs`, `CommuteCovDs`.

The flat parser silently drops CovD operands: `ToCanonical("CD[-a][V[-b]]")` returns `"CD[-a]"`. This is a silent data corruption bug (sxAct-nl2r, P1). The two parsers share no code, have different error handling, and will diverge further as the system grows.

## What Changes

- Replace `FactorAST` with a new AST node type that can represent both flat tensor factors and CovD application (nested bracket syntax)
- Rewrite `_parse_monomial` to recognize `Name[indices][operand]` as CovD application rather than stopping at the first `]`
- Retire `_extract_covd_chain` and `_split_expression_terms` — rewrite `SortCovDs`/`CommuteCovDs` to use the unified AST
- Detect-and-error: if a CovD expression reaches a code path that doesn't support it yet, raise an error instead of silently dropping the operand

## Impact

- Affected specs: expression-parser (new capability)
- Affected code: `src/XTensor/Canonical.jl` (primary), callers of `_parse_expression` and `_extract_covd_chain`
- Three CovD code paths to unify:
  1. `_parse_expression` / `FactorAST` — flat parser, silently drops CovD operands
  2. `_extract_covd_chain` / `_split_expression_terms` — string-based CovD chain parser
  3. `_preprocess_covd_reductions` — regex string rewrites for metric compatibility and second Bianchi identity (runs before parsing)
- Risk: moderate — `ToCanonical`, `Contract`, `Simplify`, `SortCovDs`, `CommuteCovDs` all depend on the parser. Extensive existing tests provide a safety net.
