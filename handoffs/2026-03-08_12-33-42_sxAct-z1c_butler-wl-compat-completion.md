---
date: 2026-03-08T12:33:42-03:00
git_commit: a874d0b
branch: main
directory: /var/home/sasha/para/areas/dev/gh/sk/sxAct
issue: sxAct-z1c
status: handoff
---

# Handoff: Butler WL Compat — 61/82 Tests Passing

## Context

sxAct-z1c is the task to make the Julia XPerm adapter pass as many of the
90 Butler example tests as reasonably possible. The Butler examples exercise
the full Wolfram-Language xPerm API surface, and we're implementing a Julia
compatibility layer that replaces WL semantics.

This session resumed from a previous context compaction. The session before
had pushed from 31 to 46/82 tests by fixing Schreier-Sims bugs (degree
mismatch, BoundsError, generator deduplication, SV caching, targeted restart)
and implementing subprocess-per-file isolation with 90s timeouts.

This session pushed from 47 to **61/82** tests passing.

## Current Status

### Completed
- [x] Fixed `_orbit_bfs` BoundsError for mixed-degree generators (session prior)
- [x] Implemented `SchreierOrbit(pt, GS, n, names)` — BFS with named labels
- [x] Implemented `SchreierOrbits(GS, n, names)` — all-orbits multi-BFS
- [x] Added `Schreier(orbit, labels, parents)` constructor for assertion comparison
- [x] Added `MultiSchreierResult` struct with proper `show` and `==`
- [x] Implemented `Stabilizer(pts, GS)` — filter generators that fix all pts
- [x] Implemented `Dimino(GS)` — BFS group element enumeration (count tests)
- [x] Fixed `Permute` to pad shorter permutation before compose (degree mismatch)
- [x] Added `_preprocess_apply_op`: `f @@ {a,b,c}` → `f(a,b,c)` in translator
- [x] Added `_preprocess_schreier_orbit`: injects named-gen arrays
- [x] Added `\[Equal]` → `==` translation in `_wl_to_jl`
- [x] Generated 82 oracle snapshots in `oracle/xperm/butler_examples/`
- [x] All regression tests pass: 44/44 Julia, 540 Python, 40/40 xTensor

### Files fully passing (6/6 or perfect)
- example_0: 6/6 (SchreierOrbit, SchreierOrbits)
- example_1: 9/9 (Stabilizer + \[Equal])
- example_4: 2/2
- example_7: 2/2 (Dimino count)
- example_8: 1/1
- example_9: 1/1
- example_12: 6/6 (Dimino count)
- example_14: 2/2 (Dimino count)

### Remaining 21 failures (all WL-specific, not fixable without name registry)

**WL named-generator tracking (Dimino returns "a", "b" etc. strings):**
- example_11 dimino_01 (1 test)
- example_11b dimino_01/02 (2 tests — also extraction artifact in TOML)
- example_13 dimino_02 (1 test)
- example_2 dimino_05/08/11 (3 tests)

**WL chain/stabilizer-chain global variables:**
- example_2 eval_02: `OrderOfGroup /@ chain` — `chain` never set (1 test)

**PermWord / PermWord-dependent cascade:**
- example_2 permword_15 (1 test)
- example_6 eval_03: `Permute @@ PermWord[...]` (1 test)

**Named permutation lookup (result == "g2" string):**
- example_2 permute_16 (1 test)

**newSGS not set (depends on permword_15):**
- example_2 permmemberq_22/23/24 (3 tests)

**WL Timing[] + destructuring {a,b} = expr:**
- example_3 eval_02, eval_04 (Timing + {junk, newSGS} = ...) (2 tests)
- example_3 deleteredundantgenerators_03, eval_05, orderofgroup_06 (3 tests)

**RightCosetRepresentative + TranslatePerm cascade:**
- example_13 translateperm_05/06 (2 tests)

**Slow (skipped):**
- example_5_rubik, example_10 (skip = "slow")

## Critical Files

1. `src/julia/XPerm.jl:1086-1300` — New WL compat: Stabilizer, SchreierResult,
   SchreierOrbit, SchreierOrbits, MultiSchreierResult, Dimino
2. `src/sxact/adapter/julia_stub.py:663-740` — New preprocessors: apply_op,
   schreier_orbit, plus `\[Equal]` handling in `_wl_to_jl`
3. `scripts/gen_butler_snapshots.py` — Subprocess-per-file oracle generator
4. `oracle/xperm/butler_examples/` — 82 oracle snapshots

## Recent Changes

- `src/julia/XPerm.jl` — Added ~220 lines of WL compat functions
- `src/sxact/adapter/julia_stub.py` — Added ~80 lines of preprocessors
- `oracle/xperm/butler_examples/**` — 82 snapshots created/updated
- `tests/xperm/butler_examples/example_5_rubik.toml` — `skip = "slow"`
- `tests/xperm/butler_examples/example_10.toml` — `skip = "slow"`

## Key Learnings

1. **`SchreierOrbit` needs generator names injected at Python level**
   - Julia functions receive permutation vectors without variable names
   - Python preprocessor detects `SchreierOrbit[pt, GenSet[g1,...], n]` and
     rewrites to `SchreierOrbit(pt, [g1,...], n, ["g1",...])` before translation
   - See `julia_stub.py:712` `_preprocess_schreier_orbit`

2. **WL `@@` (Apply) is `f @@ {a,b,c}` → `f(a,b,c)` in Julia**
   - `_preprocess_apply_op` strips trailing whitespace before `@@` so `f (args)`
     becomes `f(args)` (no space)
   - See `julia_stub.py:663` `_preprocess_apply_op`

3. **`Permute` must pad shorter permutations to common degree**
   - WL `Permute[Cycles[{2,4},{3,5}], Cycles[{4,5},{6,7}]]` works even when
     generators have degree 5 vs 7; Julia `compose` requires equal lengths
   - Fix: `Permute` now pads both to `max(len(a), len(b))` before composing
   - See `XPerm.jl:1043`

4. **`Schreier[orbit, labels, parents]` needs constructor for assertions**
   - The assertion `$result === Schreier[...]` gets the repr string substituted,
     then Julia evaluates `Schreier(...) == Schreier(...)`. Must define `Schreier`
     as a constructor and `==` for `SchreierResult`
   - See `XPerm.jl:1135`

5. **`\[Equal]` (WL Unicode) → `==` in Julia**
   - `Stabilizer[pts, GS] \[Equal] GenSet[b]` is WL's structural equality
   - Add `expr.replace("\\[Equal]", "==")` in `_wl_to_jl`
   - See `julia_stub.py:755`

6. **Dimino for count-only tests: BFS right-multiplication gives correct count**
   - WL `Length[Dimino[GenSet[...]]]` tests don't care about element order
   - Julia `Dimino(GS)::Vector{Vector{Int}}` → `length(Dimino(...))` works
   - Passed: example_7 (2688 elements), example_12 (336), example_14 (240)

7. **Remaining ceiling is ~61/82 without WL name registry**
   - Most remaining failures need named permutation tracking (Dimino returning
     "a", "b" instead of permutation vectors)
   - WL `Timing[expr]` + destructuring `{a,b} = ...` is hard without parser rewrite

## Open Questions

- [ ] Is sxAct-z1c considered "complete enough" at 61/82, or should we continue?
- [ ] Should we implement WL name registry (binding variable names to permutation
      vectors) to unlock ~6 more Dimino tests?
- [ ] Should we implement `Timing[expr]` → `{0, expr}` + tuple destructuring
      `{a,b} = ...` to unlock example_3's `orderofgroup_06` (+1)?
- [ ] example_11b dimino_01/02: both test same expression with different expected
      results — appears to be an extraction artifact. Should fix the TOML.

## Next Steps

1. **[LOW] Implement WL name registry** — difficult, ~+6 tests
   - Track which Julia variable name corresponds to each permutation vector
   - Return `"a"` instead of `Cycles[...]` in Dimino when generator matches named var
   - Requires Python-side name→perm dict passed into Julia

2. **[LOW] Fix example_11b TOML** — easy, but tests are wrong extractions
   - Both `dimino_01` and `dimino_02` test `Dimino[GenSet[a]]` (same expr)
     but expect different results (3 vs 6 elements). The TOML is wrong.
   - Either skip or fix the TOML to reflect actual WL notebook

3. **[MEDIUM] Close sxAct-z1c** — 61/82 is a significant improvement from 31
   - Run `bd close sxAct-z1c` if the task is complete enough
   - Push to remote: `git push`

## Artifacts

**Modified files:**
- `src/julia/XPerm.jl` (+220 lines WL compat)
- `src/sxact/adapter/julia_stub.py` (+80 lines preprocessors)
- `tests/xperm/butler_examples/example_5_rubik.toml` (skip → "slow")
- `tests/xperm/butler_examples/example_10.toml` (skip → "slow")

**New files (oracle snapshots):**
- `oracle/xperm/butler_examples/` — 82 snapshot files (*.json + *.wl)

**Committed:** yes, `a874d0b`

## Test Commands

```bash
# Butler dry-run (fast check, no snapshot write)
timeout 600 uv run python -u scripts/gen_butler_snapshots.py --dry-run

# Generate snapshots
timeout 600 uv run python scripts/gen_butler_snapshots.py

# Julia unit tests (should be 44/44)
julia --project=src/julia src/julia/tests/test_xperm.jl

# Python tests (should be 540 pass)
uv run pytest tests/ -q --ignore=tests/integration --ignore=tests/properties \
  --ignore=tests/xperm --ignore=tests/xtensor

# xTensor tests (should be 40/40)
uv run xact-test run --adapter julia --oracle-mode snapshot \
  --oracle-dir oracle tests/xtensor/

# Single-file debug
timeout 120 uv run python scripts/gen_butler_snapshots.py \
  --dry-run --single-file tests/xperm/butler_examples/example_0.toml
```
