---
date: 2026-03-06T23:39:51-03:00
git_commit: fdd517a
branch: main
directory: /var/home/sasha/para/areas/dev/gh/sk/sxAct
issue: sxAct-z1c
status: handoff
---

# Handoff: xPerm WL Compatibility Layer (sxAct-z1c)

## Context

We are implementing a WL-compatible API layer in `XPerm.jl` so that the Julia
adapter can evaluate Wolfram-style xPerm expressions extracted from
`ButlerExamples.nb`. The 92 butler tests are already extracted as TOML files in
`tests/xperm/butler_examples/`. The goal is >50 tests passing via oracle snapshots.

Two preconditions have been completed: (1) fixed `_is_tensor_expr` regex in
`julia_stub.py` to avoid false-positives on xPerm calls, and (2) added the WL
compat functions (`Cycles`, `GenSet`, `PermMemberQ`, etc.) to the end of
`XPerm.jl`. The blocker: those functions are defined inside `module XPerm` but
are **not visible in Julia's `Main` scope** when the adapter calls `jl.seval(...)`.

## Current Status

### Completed
- [x] Fixed `_TENSOR_EXPR_RE` in `julia_stub.py:554` — regex is now
  `r'-[a-z]|\w+\[[a-z]{2,}'` (was `r'\w+\[-?\w'`)
- [x] All 40 xTensor TOML tests still pass (regression-free)
- [x] Added WL compat layer to `XPerm.jl:677-820` — `Cycles`, `GenSet`,
  `StrongGenSet` outer constructor, `ID`, `PermMemberQ`, `OrderOfGroup`,
  `Orbit`, `Orbits`, `Permute`, `TranslatePerm`, `SchreierSims`

### Blocked
- [ ] **WL compat functions not in `Main` scope** — `jl.seval("Cycles(...)")`
  fails with `UndefVarError: Cycles not defined in Main`

### Planned
- [ ] Fix scoping: bring XPerm WL exports into `Main` (see Next Steps #1)
- [ ] Run `gen_butler_snapshots.py` → expect >50 "True" results
- [ ] Run `xact-test run` to verify >50 passing oracle comparisons
- [ ] Commit and close sxAct-z1c

## Critical Files

1. `src/julia/XPerm.jl:677-820` — WL compat layer (newly added, NOT committed)
2. `src/sxact/adapter/julia_stub.py:41-55` — `_get_xtensor()` loads XTensor via
   `include(path)` + `using .XTensor`; **this is where the scoping fix goes**
3. `src/sxact/adapter/julia_stub.py:551-557` — `_TENSOR_EXPR_RE` (already fixed)
4. `scripts/gen_butler_snapshots.py` — snapshot generator; counts "pass" only
   when last Assert returns `"True"`
5. `tests/xperm/butler_examples/example_0.toml` — canonical butler test format
6. `tests/xperm/butler_examples/example_1_symmetries_of_the_square.toml` —
   PermMemberQ-heavy (8/9 tests should pass once scoping fixed)

## Recent Changes

> Not yet committed

- `src/julia/XPerm.jl` — WL compat layer appended (lines ~677-820)
- `src/sxact/adapter/julia_stub.py:554` — `_TENSOR_EXPR_RE` regex fix
- `oracle/xperm/butler_examples/` — 92 stub snapshots written (all empty/failed,
  to be replaced once scoping is fixed)

## Key Learnings

### 1. WL compat functions are in `XPerm` module, not `Main`

The Julia adapter evaluates expressions in `Main` via `jl.seval(expr)`. After
`_get_xtensor()` runs, `XTensor` is loaded and its exports are in `Main`, but
`XPerm` (a submodule of `XTensor`) is not. So `Cycles(...)` fails.

**Fix: add one line to `_get_xtensor()` in `julia_stub.py:55`:**
```python
jl.seval("using .XTensor.XPerm")   # or: jl.seval("using .XPerm")
```
Or alternatively, re-export XPerm names from XTensor so `using .XTensor` brings
them in automatically. The quickest fix is the one-liner in `_get_xtensor()`.

> Verify first which qualified name works:
> ```python
> jl.seval("XTensor.XPerm.Cycles isa Function")
> ```
> If True, use `using .XTensor.XPerm`. Otherwise try the other path.

### 2. BFS orbit order, not sorted

`schreier_vector()` in `XPerm.jl:182` **sorts** `orbit_pts`. But xPerm (WL)
returns orbits in **BFS discovery order**. The WL compat `Orbit`/`Orbits`
functions implement their own BFS (`_orbit_bfs`) and do NOT sort. This matches
the expected butler test output exactly (verified for examples 0, 12, 13, 14).

### 3. `Permute(a, b)` = `compose(b, a)` (b applied after a)

In xPerm, `Permute[a, b]` applies `a` first then `b`. In XPerm.jl,
`compose(p, q)[i] = p[q[i]]` (apply `q` first). So `Permute(a, b) = compose(b, a)`.
Verified against example_6 test 2.

### 4. `Perm[list]` → `Vector{Int}(list)` works without special handling

`const Perm = Vector{Int}` in XPerm.jl makes `Perm([1,2,3,...])` call
`Vector{Int}([1,2,3,...])`, which is valid Julia (returns a copy). So
`TranslatePerm[Perm[{list}], Cycles]` → `TranslatePerm(Perm([list]), Cycles)`
→ `Vector{Int}(list)` works automatically — no `_wl_to_jl` special case needed.

### 5. Estimated test count (once scoping fixed)

Based on analysis of all 16 TOML files:
- example_0: 3 (Orbit, Orbits — BFS order)
- example_1: 8 (PermMemberQ True/False)
- example_2: 9 (OrderOfGroup ×5, PermMemberQ ×4)
- example_3: 1 (OrderOfGroup)
- example_4: 1 (OrderOfGroup)
- example_5: 2 (Orbits ×1, OrderOfGroup ×1)
- example_6: 2 (OrderOfGroup, Permute)
- example_7: 1 (OrderOfGroup)
- example_8: 1 (OrderOfGroup)
- example_9: 1 (OrderOfGroup)
- example_10: 1 (OrderOfGroup)
- example_11: 9 (PermMemberQ ×8, OrderOfGroup ×1 — signed perms but schreier_sims still works)
- example_12: 5 (Orbits ×1, OrderOfGroup ×2, PermMemberQ ×2)
- example_13: 3 (Orbits ×1, PermMemberQ ×2)
- example_14: 1 (Orbits)
- **Total estimate: ~48 tests** (just under 50 — close)

Tests that WON'T pass (complex WL constructs): `Dimino`, `SchreierOrbit`,
`SchreierOrbits`, `Timing`, `@@` (Apply), `//@` (Map), `PermWord`,
`StablePoints`, `Stabilizer`, `DeleteRedundantGenerators`, `PowerPermute`,
comparisons to `"g2"` (named perm strings).

### 6. gen_butler_snapshots.py counts "True" only

The script at `scripts/gen_butler_snapshots.py:127` counts a test as "pass"
only if `raw == "True"` (the Assert's repr). All other results (including
correct integer/vector results from intermediate Evaluate steps) show as "fail".
This is correct — the tests use Assert as the final step.

### 7. `_is_tensor_expr` regex summary

Current (fixed) regex: `r'-[a-z]|\w+\[[a-z]{2,}'`
- Matches covariant tensor index: `-spa`, `-a`
- Matches contravariant multi-letter index: `Conv[coa]`, `QGTorsion[qga,...]`
- Does NOT match xPerm: `Orbit[7,...]`, `GenSet[a,b]` (single letter), `Perm[ID]`

## Open Questions

- [ ] Does `using .XTensor.XPerm` work, or should it be `using .XPerm`?
  Quick test: `jl.seval("XTensor.XPerm.Cycles isa Function")` → True means use
  `.XTensor.XPerm`; otherwise check if XPerm is top-level after `include`.
- [ ] Will the signed permutation examples (11, 12) work correctly? The
  `StrongGenSet(base, genset)` constructor passes `n = max_element` which
  equals the perm degree (6 or 9), NOT the physical degree (4 or 7). The
  Schreier-Sims may still be correct since `signed = (deg == n+2)` would be
  false but the group elements are still correct degree-6/9 vectors.
- [ ] Does `OrderOfGroup` overflow for Rubik's cube (43252003274489856000 >
  Int64 max = 9.2e18)? If so, example_5's orderofgroup_07 will overflow. Check
  with `order_of_group` return type.

## Next Steps

1. **Fix scoping in `_get_xtensor()`** [Priority: CRITICAL, ~5 min]
   ```python
   # src/sxact/adapter/julia_stub.py, in _get_xtensor() after line 55:
   jl.seval("using .XTensor.XPerm")  # or "using .XPerm"
   ```
   Verify: `uv run python -c "from sxact.adapter.julia_stub import JuliaAdapter; a=JuliaAdapter(); ctx=a.initialize(); r=a.execute(ctx,'Evaluate',{'expression':'Cycles([1,2,3,4])'}); print(r.status, r.repr)"`

2. **Run existing tests to confirm no regression** [Priority: HIGH, ~1 min]
   ```bash
   uv run pytest tests/test_julia_adapter.py -q
   uv run xact-test run --adapter julia --oracle-mode snapshot --oracle-dir oracle tests/xtensor/
   ```

3. **Run snapshot generation** [Priority: HIGH, ~5-10 min]
   ```bash
   uv run python scripts/gen_butler_snapshots.py
   ```
   Expect ~48 "True" results across examples 0-14.

4. **If count is <50, check what's failing** [Priority: HIGH]
   - Signed perm examples (11, 12): test PermMemberQ with degree-6 vectors
   - Orbits ordering: compare expected vs actual for example_12
   - OrderOfGroup overflow: test example_5 orderofgroup_07

5. **Run final verification** [Priority: HIGH]
   ```bash
   uv run xact-test run --adapter julia --oracle-mode snapshot \
     tests/xperm/butler_examples/ --oracle-dir oracle
   ```
   Goal: >50 passing.

6. **Commit and close** [Priority: HIGH]
   ```bash
   git add src/julia/XPerm.jl src/sxact/adapter/julia_stub.py \
     scripts/ tests/xperm/butler_examples/ oracle/xperm/butler_examples/
   git commit -m "feat: add xPerm WL compat layer, extract 92 butler tests (sxAct-z1c)"
   git push
   bd close z1c
   ```

## Artifacts

**Modified (not committed):**
- `src/julia/XPerm.jl` — WL compat layer appended (~145 lines)
- `src/sxact/adapter/julia_stub.py` — `_TENSOR_EXPR_RE` regex fix at line 554
- `oracle/xperm/butler_examples/` — 92 stub snapshot files (will be replaced)

**Existing (not committed, from previous session):**
- `scripts/extract_butler.py` — notebook parser
- `scripts/gen_butler_snapshots.py` — oracle snapshot generator
- `tests/xperm/butler_examples/example_0.toml` … `example_14.toml` — 16 TOML files

## References

- Issue: `bd show z1c`
- Previous handoff: `handoffs/2026-03-06_23-06-04_sxAct-z1c_butler-examples-extraction.md`
- XPerm WL layer: `src/julia/XPerm.jl:677+`
- Adapter scoping fix target: `src/sxact/adapter/julia_stub.py:41-55`
