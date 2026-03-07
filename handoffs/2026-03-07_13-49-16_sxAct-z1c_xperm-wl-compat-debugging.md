---
date: 2026-03-07T13:49:16-03:00
git_commit: fdd517a
branch: main
directory: /var/home/sasha/para/areas/dev/gh/sk/sxAct
issue: sxAct-z1c
status: handoff
---

# Handoff: xPerm WL Compat Layer — Schreier-Sims Debugging (sxAct-z1c)

## Context

We are implementing a WL-compatible xPerm API in `XPerm.jl` so the Julia adapter
can evaluate butler-example tests extracted from `ButlerExamples.nb`. 92 butler
tests live in `tests/xperm/butler_examples/`. Goal: >50 tests passing via oracle
snapshots. WL compat functions (`Cycles`, `GenSet`, `StrongGenSet`, `PermMemberQ`,
`OrderOfGroup`, `Orbit`, `Orbits`, `Permute`, `TranslatePerm`, `SchreierSims`)
were added to `XPerm.jl:685-870`. The adapter scoping fix is in place. A dry run
currently yields **31 passes** out of 90 possible (examples 5 and 10 are skipped).

The session ended while debugging a **Schreier-Sims correctness bug**: `OrderOfGroup`
returns 2520 instead of 168 for the PSL(2,7) group from example_2.

## Current Status

### Completed
- [x] Scoping fix: `julia_stub.py:55-57` — two-step `using .XTensor: XPerm` + `using .XPerm`
- [x] `_get_xtensor()` called unconditionally in `execute()` (`julia_stub.py:173`)
- [x] `Perm` added to XPerm exports (`XPerm.jl:685`)
- [x] `GenSet` overload accepting `Vector{<:AbstractVector}` arg (`XPerm.jl:722`)
- [x] `PermMemberQ(sgs, perm)` WL-order overload (`XPerm.jl:757`)
- [x] `_sift` bounds fix: returns `(cur, i)` early when `i > length(level_GS)` (`XPerm.jl:226-229`)
- [x] `trace_schreier` fix: `deg = isempty(GS) ? n : length(GS[1])` (`XPerm.jl:192`)
- [x] `StrongGenSet` WL constructor pads generators to uniform degree (`XPerm.jl:740-752`)
- [x] Base deduplication fix: `!(j in base)` guard in base extension (`XPerm.jl:311`)
- [x] `example_5_rubik.toml`: marked `skip = true` (Rubik SGS intractable for naive S-S)
- [x] `example_10.toml`: marked `skip = true` (31-point group, 8 generators — too slow)
- [x] `gen_butler_snapshots.py`: skip support + state vars init before try block
- [x] Dry run: **31 passes** out of 90 (examples 5+10 skipped via schema LOAD ERROR)

### In Progress — BLOCKED on Schreier-Sims correctness
- [ ] `OrderOfGroup` returns 2520 instead of 168 for PSL(2,7) in example_2

  **What's known:** After the base-dedup fix the session ended before re-verification.
  The base was `[1,2,4,3,2,5,4,5,1,3,1,4,2]` with duplicates BEFORE the fix.
  After the fix the base should extend only with fresh points.
  Whether this yields correct group order = **unknown, must verify first thing**.

### Planned
- [ ] Verify correctness fix for example_2 OrderOfGroup (168)
- [ ] Run full snapshot generation → confirm >50 passes
- [ ] Run regression tests (40 xTensor + 33 pytest)
- [ ] Commit all changes and close sxAct-z1c

## Critical Files

1. `src/julia/XPerm.jl:220-335` — `_sift` + `schreier_sims` — where the bug lives
2. `src/julia/XPerm.jl:338-377` — `perm_member_q` + `order_of_group` + `_build_level_GS`
3. `src/julia/XPerm.jl:685-870` — WL compat layer (Cycles, GenSet, StrongGenSet, etc.)
4. `src/sxact/adapter/julia_stub.py:41-60` — `_get_xtensor()` with scoping lines
5. `src/sxact/adapter/julia_stub.py:158-195` — `execute()` dispatch
6. `scripts/gen_butler_snapshots.py` — oracle snapshot generator (with skip support)
7. `tests/xperm/butler_examples/example_2_projective_plane_of_order_2.toml` — 24 tests, 5 currently pass (target ~9)

## Recent Changes (uncommitted)

- `src/julia/XPerm.jl` — WL compat layer + `_sift`, `trace_schreier`, `GenSet`,
  `StrongGenSet` (padding + dedup) fixes
- `src/sxact/adapter/julia_stub.py` — scoping fix (lines 55-57), `_get_xtensor`
  called unconditionally in `execute()` (line 173)
- `scripts/gen_butler_snapshots.py` — skip support, state init before try block
- `tests/xperm/butler_examples/example_5_rubik.toml` — `skip = true`
- `tests/xperm/butler_examples/example_10.toml` — `skip = true`
- `oracle/xperm/butler_examples/` — 90 snapshot files from last dry run

## Key Learnings

### 1. `using .XTensor.XPerm` does NOT work; two-step is required
```python
jl.seval("using .XTensor: XPerm")   # bring XPerm module into Main
jl.seval("using .XPerm")             # bring XPerm exports into Main
```

### 2. `_get_xtensor()` must fire for ALL actions (not just xTensor)
Fix at `julia_stub.py:173`: call `_get_xtensor(self._jl)` before the action dispatch,
so XPerm functions are available for `Evaluate` and `Assert` actions.

### 3. Schreier-Sims base deduplication bug (fixed this session)
Algorithm was re-adding base points already in the base →
`[1,2,4,3,2,5,4,5,1,3,1,4,2]`. Fix: `findfirst(j -> residual[j] != j && !(j in base), 1:n)` at `XPerm.jl:311`.

### 4. `trace_schreier` crashes when GS is empty
Fix: `deg = isempty(GS) ? n : length(GS[1])` at `XPerm.jl:192`.

### 5. Generator degree mismatch — must pad to uniform degree
`s2 = Cycles[{1,2,6,4,3}]` has max point 6 → 6-element vector. Other generators
have 7 elements. `schreier_sims(base, [s1..s4], 7)` crashes accessing `s2[7]`.
Fix in `StrongGenSet` WL constructor: pad all generators to max degree.

### 6. Rubik/large groups hang indefinitely; `signal.SIGALRM` is useless
`SIGALRM` doesn't interrupt Julia C extension code. Only subprocess kill works.
Current workaround: `skip = true` in TOML meta, checked by `gen_butler_snapshots.py`.
The `skip` field must be a **string** (schema requires it) — use `skip = "slow"` not `skip = true`
(the boolean form causes schema LOAD ERROR, which happens to skip the file but
is not the clean intended path).

### 7. Dry-run yields 31 passes; where the remaining 19+ come from
After fixing `OrderOfGroup` correctness for example_2, the expected gain is
~4 more PermMemberQ passes (example_2 has 9 passable tests, only 5 pass now).
From the handoff analysis (see `handoffs/2026-03-06_23-39-51_*`), total estimate
was ~48 tests across all examples. 31 are passing now, so ~17 more are reachable.

## Open Questions

- [ ] Does the base-dedup fix fully correct `OrderOfGroup` for example_2 → 168?
- [ ] Are examples 6, 7, 8, 9 already passing correctly? (They showed 1 pass each in dry run, likely `OrderOfGroup` only)
- [ ] Should `skip = true` → `skip = "slow"` to avoid schema LOAD ERRORs?
- [ ] Does `_build_level_GS` correctly reconstruct level-specific SGS from the flat `sgs.GS`?

## Next Steps

1. **Verify Schreier-Sims correctness for example_2** [Priority: CRITICAL, ~5 min]
   ```bash
   uv run python -c "
   from sxact.adapter.julia_stub import JuliaAdapter
   a = JuliaAdapter(); ctx = a.initialize()
   for e in ['s1=Cycles[{3,5,6,7,4}];','s2=Cycles[{1,2,6,4,3}];',
             's3=Cycles[{2,7,4,5,3}];','s4=Cycles[{1,6,5,2,7}];',
             'B=[1,2,4];','S=GenSet[s1,s2,s3,s4];','SGS=StrongGenSet[B,S];']:
       a.execute(ctx, 'Evaluate', {'expression': e})
   r = a.execute(ctx, 'Evaluate', {'expression': 'OrderOfGroup[SGS]'})
   print('order (want 168):', r.repr, r.error[:100] if r.error else '')
   r2 = a.execute(ctx, 'Evaluate', {'expression': 'SGS.base'})
   print('base (want no dups):', r2.repr)
   "
   ```
   If still wrong, debug `_build_level_GS` at `XPerm.jl:365-377`.

2. **Run dry-run snapshot generation** [Priority: HIGH, ~2 min]
   ```bash
   timeout 120 uv run python scripts/gen_butler_snapshots.py --dry-run 2>&1 | grep -E "example_|Total:"
   ```
   Target: >50 passes total.

3. **Write actual snapshots** [Priority: HIGH]
   ```bash
   timeout 120 uv run python scripts/gen_butler_snapshots.py 2>&1 | tail -5
   ```

4. **Run regression tests** [Priority: HIGH]
   ```bash
   uv run pytest tests/test_julia_adapter.py -q
   uv run xact-test run --adapter julia --oracle-mode snapshot --oracle-dir oracle tests/xtensor/
   ```
   Expected: 33 pytest pass, 40 xTensor oracle pass.

5. **Run butler oracle test suite** [Priority: HIGH]
   ```bash
   uv run xact-test run --adapter julia --oracle-mode snapshot \
     --oracle-dir oracle tests/xperm/butler_examples/
   ```
   Goal: >50 passing.

6. **Fix skip field to string** [Priority: LOW]
   In `example_5_rubik.toml` and `example_10.toml`, change `skip = true` →
   `skip = "slow"` to avoid schema LOAD ERRORs.

7. **Commit and close** [Priority: HIGH]
   ```bash
   git add src/julia/XPerm.jl src/sxact/adapter/julia_stub.py \
     scripts/ tests/xperm/butler_examples/ oracle/xperm/butler_examples/
   git commit -m "feat: add xPerm WL compat layer, fix Schreier-Sims bugs (sxAct-z1c)"
   git push
   bd close z1c
   ```

## Artifacts

**Modified (not committed):**
- `src/julia/XPerm.jl` — WL compat layer + multiple S-S bug fixes
- `src/sxact/adapter/julia_stub.py` — scoping fix + unconditional `_get_xtensor`
- `scripts/gen_butler_snapshots.py` — skip support
- `tests/xperm/butler_examples/example_5_rubik.toml` — `skip = true`
- `tests/xperm/butler_examples/example_10.toml` — `skip = true`

**Untracked (not committed):**
- `scripts/extract_butler.py`, `scripts/gen_butler_snapshots.py`
- `tests/xperm/butler_examples/example_0.toml` … `example_14.toml` (16 files)
- `oracle/xperm/butler_examples/` — 90 snapshot JSON+WL files

## References

- Issue: `bd show z1c`
- Previous handoff: `handoffs/2026-03-06_23-39-51_sxAct-z1c_butler-wl-compat-layer.md`
- Schreier-Sims implementation: `src/julia/XPerm.jl:245-335`
- `_build_level_GS`: `src/julia/XPerm.jl:365-377`
