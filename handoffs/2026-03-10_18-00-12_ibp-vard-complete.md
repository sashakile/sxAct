---
date: 2026-03-10T18:00:12-03:00
git_commit: d4161e8
branch: main
directory: /var/home/sasha/para/areas/dev/gh/sk/sxAct
issue: sxAct-8oa, sxAct-8tf
status: handoff
---

# Handoff: IBP and VarD implementation complete

## Context

sxAct is a Julia/Python port of the Wolfram xAct suite for abstract tensor
algebra. All algebra lives in `src/julia/XTensor.jl`; the Python side
(`src/sxact/adapter/julia_stub.py`) translates TOML test actions into Julia
calls. This session implemented IBP (Integration By Parts) and VarD
(Variational Derivative) from the xTras sub-package — two of the last major
P2 milestones remaining.

The fundamental challenge: CovD expressions like `CD[-a][T[-b]]` use a
TWO-bracket syntax that the existing `_parse_monomial` parser cannot handle
(it stops at the first `]`). IBP and VarD therefore operate entirely at the
string level, with their own factor-splitting and CovD-detection logic, and
a `_safe_simplify` guard that skips `Simplify` on expressions containing CovD
factors.

## Current Status

### Completed this session
- [x] **sxAct-8oa** — `IBP(expr, covd)` in `XTensor.jl:2603`
  - Pure divergence `CD[-a][V[a]]` → 0
  - Product `A * CD[-a][B]` → `-(CD[-a][A]) * B` (sign flip, mod total deriv)
  - Unchanged terms pass through
- [x] **sxAct-8tf** — `VarD(expr, field, covd)` in `XTensor.jl:2744`
  - Case 1: direct field `phi[]` — contribution = kernel
  - Case 2: `CD[-a][phi[]]` — contribution = `-CD[-a][kernel]` via Leibniz
  - Case 3: `CD[-a][CD[-b][phi[]]]` — contribution = `+CD[-a][CD[-b][kernel]]`
- [x] `TotalDerivativeQ(expr, covd)` in `XTensor.jl:2636`
- [x] Python adapter: `IntegrateByParts`, `TotalDerivativeQ`, `VarD` actions
- [x] 22 Julia unit tests, 10 TOML integration tests — 154/154 Julia, 154/154 TOML, 544/544 Python all passing
- [x] Simplify review: extracted `_join_term_strings` helper (shared by IBP and VarD), replaced `_expr_has_covd_factors` full-parse with a fast regex in `_safe_simplify`, removed redundant `String()` conversion

### In Progress
- Nothing

### Planned (next priorities)
- [ ] **sxAct-1sn** — xCore Symbol Registry (ValidateSymbol, Namespace) — P2
- [ ] **sxAct-wom** — order>1 multinomial Leibniz in `perturb()` — P3
- [ ] **sxAct-amy** — `expect_error` field in test schema — P3
- [ ] Docs overhaul epic (sxAct-3et, sxAct-kx9, sxAct-bh8) — P2

## Critical Files

1. `src/julia/XTensor.jl:2263-2773` — entire IBP/VarD implementation (new)
2. `src/julia/XTensor.jl:2273` — `_safe_simplify`: skips `Simplify` on CovD-bearing expressions via regex; **do not remove** until `_parse_monomial` is extended
3. `src/sxact/adapter/julia_stub.py:466-502` — `_integrate_by_parts`, `_total_derivative_q`, `_vard` handlers
4. `tests/xtensor/ibp_vard.toml` — 10 integration tests with oracle snapshots
5. `src/julia/tests/test_xtensor.jl:537-609` — Julia unit tests for IBP/VarD

## Recent Changes

- `src/julia/XTensor.jl` — +510 lines: `_safe_simplify`, `_split_factor_strings`, `_parse_covd_application`, `_index_appears_in`, `_extract_leading_coeff`, `_fmt_pos_coeff`, `_term_string`, `_split_string_terms`, `_ibp_term_factors`, `_join_term_strings`, `IBP`, `TotalDerivativeQ`, `_leibniz_covd`, `_vard_term_contributions`, `VarD`
- `src/sxact/adapter/julia_stub.py` — added `IntegrateByParts`, `TotalDerivativeQ`, `VarD` to `_XTENSOR_ACTIONS` and handler methods
- `src/sxact/adapter/base.py` — added three new actions to `supported_actions()`
- `src/sxact/runner/schemas/test-schema.json` / `tests/schema/test-schema.json` — added `IntegrateByParts`, `TotalDerivativeQ`, `VarD`, `PerturbationOrder`, `PerturbationAtOrder` to action enums
- `tests/xtensor/ibp_vard.toml` — new test file (10 tests)
- `oracle/xtensor/ibp_vard/` — 20 oracle files (10 JSON + 10 WL)

## Key Learnings

1. **CovD factors break `_parse_monomial`**
   - `_parse_monomial` (line ~758) reads `Name[...]` expecting exactly one bracket group
   - `CD[-a][T[-b]]` has TWO bracket groups; after the first `]` the parser hits `[` which is not an identifier and breaks
   - This means `Simplify` → `ToCanonical` → `_parse_expression` silently corrupts CovD expressions (truncates them)
   - `_safe_simplify` guards against this using a fast regex: `Regex(covd_str * raw"\[-\w+\]\[")` (line 2274)
   - **Long-term fix**: extend `_parse_monomial` to consume multiple bracket groups for CovD factors

2. **IBP sign convention**
   - Product rule: `A ∇_a B = ∇_a(AB) - (∇_a A)B`
   - IBP drops the total derivative ∇_a(AB) and flips sign: `A ∇_a B → -(∇_a A) B`
   - Implemented in `_ibp_term_factors:2526` — `(-coeff, new_body)` return

3. **VarD Leibniz expansion produces nested CovD strings**
   - For kernel `K = A B` and Case 2 (`CD[-a][phi]`): contribution is `-CD[-a][K]`
   - Expanded via `_leibniz_covd` → produces `"-CD[-a][A] B - A CD[-a][B]"`
   - These individual CovD-on-single-factor strings ARE valid and pass through `_safe_simplify` unchanged (correct)
   - Metric compat `CD[-a][g[-b,-c]] = 0` is handled by `_preprocess_covd_reductions` inside `ToCanonical`, which is called by `Simplify` when the output has no CovD factors

4. **`_split_string_terms` vs `_parse_sum!`**
   - `_parse_sum!` (line 629) parses into `TermAST` objects — cannot hold CovD factors
   - `_split_string_terms` (line 2476) returns raw `(sign, body_string)` pairs — needed for CovD-aware operations
   - They are parallel implementations by design; don't consolidate (different return types serve different needs)

5. **`_extract_leading_coeff` difference from `_parse_term`**
   - `_parse_term` (line 718) accepts `N * body` (with `*`) and also handles `outer_sign`
   - `_extract_leading_coeff` (line 2429) only handles `(N/D) body` and `N body` (no `*`)
   - The difference is intentional: IBP/VarD inputs come from user-written Lagrangians, not from serialize round-trips, so `*` notation doesn't appear

6. **`_join_term_strings` sign handling**
   - Parts formatted by `_term_string` may start with `"-"` (negative terms)
   - Join loop detects leading `"-"` and emits ` - rest` instead of ` + -rest`
   - This produces `"A - B"` not `"A + -B"`, which `_parse_sum!` handles correctly either way but looks better

7. **Oracle snapshot for TotalDerivativeQ**
   - Returns `"True"` or `"False"` (capital T/F) as a `Bool` type result
   - The oracle `normalized_output` is `"True"` or `"False"` accordingly
   - Assert tests check `$result == True` using the Bool string value

## Open Questions

- [ ] Should VarD handle fields with non-empty index slots? Currently only tested for `phi[]` (scalar). A rank-2 field `T[-a,-b]` should work (`startswith` matching), but not tested.
- [ ] `_safe_simplify` skips ALL simplification when CovD factors are present. Could apply `Contract` alone (which uses `_parse_expression` safely) before returning.
- [ ] VarD Case 3 (double CovD) produces `CD[-a][CD[-b][K]]` where K contains a metric factor. Metric compat (`CD[-x][g] = 0`) won't trigger automatically in the output. Is this a problem in practice? (Tests pass; only arises for specific Lagrangian forms.)
- [ ] `perturb()` (line 1804) and VarD both work on tensor expressions. Could they be composed (`VarD` on perturbed Lagrangians)? No tests for this yet.

## Next Steps

1. **Symbol Registry** `sxAct-1sn` [Priority: P2]
   - `ValidateSymbol`, `Namespace` in xCore
   - Independent of xTras; safe to start immediately

2. **Order>1 Leibniz in `perturb()`** `sxAct-wom` [Priority: P3]
   - `perturb(expr, 2)` currently errors for products (only order-1 implemented)
   - Multinomial Leibniz expansion for higher orders
   - See `XTensor.jl:1804` for current implementation

3. **`expect_error` in test schema** `sxAct-amy` [Priority: P3]
   - Add `expect_error: true` field so TOML tests can verify error paths
   - Schema at `tests/schema/test-schema.json`

4. **Update MEMORY.md**
   - Add IBP/VarD to "What's Implemented"
   - Update test counts: 154 Julia unit tests, 154 TOML xtensor tests

## Artifacts

**New files:**
- `tests/xtensor/ibp_vard.toml`
- `oracle/xtensor/ibp_vard/` (20 files)

**Modified files:**
- `src/julia/XTensor.jl` (+510 lines)
- `src/julia/tests/test_xtensor.jl` (+72 lines)
- `src/sxact/adapter/julia_stub.py` (+40 lines)
- `src/sxact/adapter/base.py` (+3 lines)
- `src/sxact/runner/schemas/test-schema.json` (+62 lines)
- `tests/schema/test-schema.json` (+95 lines)

## Test Commands

```bash
# Julia unit tests (154 total)
julia --project=src/julia src/julia/tests/test_xtensor.jl

# IBP/VarD TOML tests
uv run xact-test run --adapter julia --oracle-mode snapshot --oracle-dir oracle tests/xtensor/ibp_vard.toml

# All TOML tests (154 total)
uv run xact-test run --adapter julia --oracle-mode snapshot --oracle-dir oracle tests/xtensor/

# Python unit tests
uv run pytest tests/ -q --ignore=tests/integration --ignore=tests/properties --ignore=tests/xperm --ignore=tests/xtensor
```
