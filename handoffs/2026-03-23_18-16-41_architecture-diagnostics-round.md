---
date: 2026-03-23T18:38:55-03:00
git_commit: f7010e1
branch: main
directory: /var/home/sasha/para/areas/dev/gh/sk/sxAct
status: handoff
---

# Handoff: Full Architecture Diagnostics Round

## Context

Ran five diagnostic analyses across the entire sxAct codebase (8 Julia source files, ~12k LOC + 5 Python adapter/API files, ~5k LOC):

1. **Performance** — Julia type instabilities, allocation hot spots, untyped globals
2. **Rigidity** — coupling, OCP violations, God files, shotgun surgery
3. **Composability** — pipeline type mismatches, missed endomorphisms, algebraic properties
4. **Mutability** — shared mutable state, side effect entanglement, temporal coupling
5. **Test friction** — setup bloat, private function testing, missing seams
6. **Test abstraction mining** — lazy test clusters, parameterization, property test candidates

Each analysis was reviewed with Rule of 5, corrected for false positives, and translated into beads tickets. All findings cross-referenced against existing tickets to avoid duplicates.

## Current Status

### Completed
- [x] Performance diagnostic — all 8 Julia files analyzed, 20/24 findings verified, 4 false positives removed
- [x] Rigidity diagnostic — 12 initial findings, revised to 9 after removing premature abstractions (R6 symmetry dispatch, R11 InvSimplify levels, R12 parser duplication)
- [x] Composability diagnostic — 7 findings, 3 actionable, 4 no-action/ceiling
- [x] Mutability diagnostic — 6 findings, all map to existing tickets
- [x] Test friction diagnostic — 6 signals, root cause is shared mutable state (F1/F3 → sxAct-mbzz)
- [x] Test abstraction mining — 6 lazy clusters (45+ parameterizable tests, ~260 lines saveable), 6 property candidates (idempotency, round-trip, metamorphic)
- [x] Rule of 5 reviews applied to performance, rigidity, composability, and test abstraction diagnostics
- [x] Issue tracker reviews applied to both batches of new tickets
- [x] All tickets created, duplicates closed, dependencies set

### In Progress
- Nothing — session is complete

## Tickets Created This Session

### Performance (11 active after closing 1 duplicate)

| ID | Title | P | Status |
|---|---|---|---|
| sxAct-j2bm | const XInvar globals | P2 | open |
| sxAct-4t8y | pre-compile Regex in loops (XInvar/XTensor) | P2 | open |
| sxAct-a0qp | pre-allocate compose() in XPerm | P2 | open |
| sxAct-kldq | hashed coeff_map key in XTensor | P2 | open |
| sxAct-li8t | pre-compute sort keys in ToCanonical | P3 | blocked by kldq |
| sxAct-dv4u | reverse index for _factor_as_metric | P3 | open |
| sxAct-045b | IOBuffer in InvarDB parser | P3 | open |
| sxAct-st77 | Union{TermAST,Nothing} → endomorphism | P3 | open |
| sxAct-7mm6 | pre-alloc backtrack buffer in XInvar | P3 | open |
| sxAct-49y9 | TExpr Vector{TExpr} abstract fields | P4 | open |
| sxAct-ae73 | XPerm Vector{Any} fields | P4 | open |
| ~~sxAct-vmlm~~ | ~~sv_cache typing~~ | — | closed (dup of sxAct-5tka) |

### Rigidity (9 tickets)

| ID | Title | P | Status |
|---|---|---|---|
| sxAct-jqzm | action dispatch dict in julia_stub.py | P2 | open |
| sxAct-xvav | data-driven trace-rule dispatch | P2 | open |
| sxAct-nc07 | extract strip_variance to XCore | P3 | open |
| sxAct-y5f1 | extract WL→Julia translator (gated on TExpr) | P3 | open |
| sxAct-5hpg | centralize Julia name registry (gated on TExpr) | P3 | blocked by jqzm |
| sxAct-u59j | api.py decorator extraction | P4 | open |
| sxAct-k8wd | split XTensor.jl into submodules (gated) | P3 | blocked by mbzz |
| sxAct-nhty | split XInvar.jl into layers (deferred) | P4 | open |
| sxAct-vpgi | investigate parser overlap | P4 | open |

### Composability (1 new ticket, 2 existing updated)

| ID | Title | P | Status |
|---|---|---|---|
| sxAct-2vnp | normalize RiemannToPerm return type | P4 | open (new) |
| sxAct-op6e | TExpr round-trip for commute_covds/sort_covds | P2 | open (updated with composability framing) |
| sxAct-st77 | Union{TermAST,Nothing} refactor | P3 | open (updated with composability framing) |

### Mutability & Test Friction
No new tickets — all findings map to existing sxAct-mbzz (Session struct), sxAct-dduy (thread safety epic), sxAct-ew7y (partial init), sxAct-nhty (XInvar split).

### Test Abstraction Mining (5 new tickets, 1 existing updated)

| ID | Title | P | Status |
|---|---|---|---|
| sxAct-8hwa | parameterize MaxIndex/MaxDualIndex spot-checks | P3 | open |
| sxAct-lm3q | parameterize Python export existence checks | P3 | open |
| sxAct-9bi7 | round-trip property tests (TExpr + XInvar) | P3 | open |
| sxAct-7ngd | parameterize XInvar parser spot-checks | P3 | blocked by nhty |
| sxAct-2bik | move shared Python fixtures to conftest.py | P4 | open |
| sxAct-96ry | property-based tests for XTensor invariants | P2 | open (updated: Contract NOT idempotent, added round-trip properties, PBT library notes) |

## Key Learnings

1. **The codebase has a natural FC/IS boundary that was never formalized**
   - All engine operations (ToCanonical, Contract, Simplify, etc.) are pure Calculations
   - All mutations are confined to `def_*!` functions (Actions)
   - Session struct (sxAct-mbzz) will formalize this
   - See mutability diagnostic, Step 3

2. **~30% of initial rigidity findings were premature abstraction**
   - Symmetry dispatch (R6): closed mathematical set, if/elif is correct
   - InvSimplify levels (R11): mathematically fixed pipeline
   - Parser duplication (R12): may be intentional specialization
   - Lesson: always check change frequency before recommending abstractions

3. **XTensor.jl split (R1/sxAct-k8wd) must use Julia submodules, not just file splitting**
   - `include()` shares parent module namespace — no coupling reduction
   - Must use `module Registry ... end` with explicit import/export
   - Gated on sxAct-mbzz landing first (Session struct changes the globals)

4. **TExpr round-trip serialization is an architectural ceiling, not a defect**
   - Every TExpr engine call does TExpr→String→engine→String→TExpr
   - Works correctly but performs 2N serialize/parse round-trips for N chained operations
   - Native TExpr engine (sxAct-lxc1) is the long-term fix

5. **Test setup bloat is the most visible symptom of the global-state problem**
   - 100+ Julia test blocks and 130+ Python tests repeat reset+rebuild
   - Session struct (sxAct-mbzz) is the single highest-leverage fix: eliminates reset cycle entirely

6. **Python double-checked locking is technically safe under GIL but has partial-init risk**
   - sxAct-ew7y tracks the real bug: _jl set but _xcore None after partial failure
   - Thread safety itself is less critical than init atomicity

## Key Learnings (continued)

7. **Contract is NOT idempotent** — Contract can require multiple passes with multiple metrics; Simplify exists for this reason. Remove Contract from idempotency property test candidates. Only ToCanonical and Simplify are idempotent.

8. **~100 lines saveable from XInvar parser spot-checks alone** — but defer parameterization until sxAct-nhty (XInvar split) decides which `_private` parsers become public APIs.

9. **No PBT library installed** — install PropCheck.jl (Julia) and hypothesis (Python) before implementing sxAct-96ry. Table-driven parameterized tests capture 80% of the value without framework overhead.

## Dependencies Set

```
sxAct-li8t → sxAct-kldq    (sort keys after coeff_map key change)
sxAct-k8wd → sxAct-mbzz    (XTensor split after Session struct)
sxAct-5hpg → sxAct-jqzm    (name registry after dispatch dict)
sxAct-7ngd → sxAct-nhty    (parser parameterization after XInvar split)
```

## Recommended Work Order

### Quick wins (do first, <1hr each):
1. sxAct-j2bm — add `const` to 3 XInvar globals (5 min)
2. sxAct-nc07 — extract strip_variance to XCore (30 min)
3. sxAct-op6e — add TExpr round-trip to commute_covds/sort_covds (10 min)
4. sxAct-045b — IOBuffer in InvarDB parser (15 min)
5. sxAct-lm3q — parameterize Python export checks (15 min)
6. sxAct-2bik — move shared fixtures to conftest.py (15 min)

### Medium effort (next):
5. sxAct-jqzm — action dispatch dict (1-2 hr)
6. sxAct-a0qp — pre-allocate compose() (1 hr, needs @btime baseline)
7. sxAct-4t8y — pre-compile Regex (1-2 hr)
8. sxAct-xvav — trace-rule data-driven dispatch (1-2 hr)

### Medium-effort test improvements (after quick wins):
9. sxAct-8hwa — parameterize MaxIndex/MaxDualIndex spot-checks (30 min)
10. sxAct-9bi7 — round-trip property tests for TExpr + XInvar (1-2 hr)

### Gated / deferred:
- sxAct-k8wd, sxAct-nhty — structural splits, wait for sxAct-mbzz
- sxAct-y5f1, sxAct-5hpg — Python adapter, wait for TExpr migration decision
- sxAct-49y9, sxAct-ae73 — parametric types, profile before committing
- sxAct-7ngd — parser parameterization, wait for sxAct-nhty

## Artifacts

**No source files created or modified** — all diagnostics were advisory only (read-only analysis). The only artifacts are the 26 beads tickets documented above (21 from first 5 diagnostics + 5 from test abstraction mining) plus 3 existing tickets updated with new framing.
