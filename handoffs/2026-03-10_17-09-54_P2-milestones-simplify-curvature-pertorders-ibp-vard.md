---
date: 2026-03-10T17:09:54-03:00
git_commit: 5b75cfe
branch: main
directory: /var/home/sasha/para/areas/dev/gh/sk/sxAct
issue: sxAct-8oa, sxAct-8tf
status: handoff
---

# Handoff: P2 milestones — Simplify, PerturbCurvature, PerturbationOrders, IBP/VarD

## Context

This session worked through the P2/P3 ready queue one by one, each with a
subagent implementation followed by a Rule-of-5-Universal review and bug fixes
before committing. Three issues are now closed. sxAct-8oa (IBP) was claimed
(in_progress) but not yet started when the session paused.

The project is the Julia/Python port of the Wolfram xAct suite. All logic lives
in `src/julia/XTensor.jl` (core Julia algebra) and `src/sxact/adapter/julia_stub.py`
(Python → Julia dispatch). Tests are TOML files under `tests/xtensor/` with
snapshots in `oracle/xtensor/`.

## Current Status

### Completed this session
- [x] **sxAct-9ya** — `Simplify` now calls `Contract` then `ToCanonical` iteratively
  until convergence (max 20 iters). Also added `xAct.jl` bundle entry-point and
  `reset_core!()`. Fixed `_serialize` pure-scalar trailing-space bug.
  `src/julia/XTensor.jl:1840-1850`, `src/julia/xAct.jl`
- [x] **sxAct-sz5** — `PerturbCurvature` action: returns δΓ, δR_{abcd}, δR_{ab}, δR
  as formula strings. **RO5U found factor-of-2 bug in RicciScalar1** (was `2δR`,
  fixed to `δR`). `src/julia/XTensor.jl:1891-2291`
- [x] **sxAct-hyy** — `PerturbationOrder(name)→Int` and
  `PerturbationAtOrder(background,n)→Symbol`. **RO5U found missing guard**: added
  duplicate `(background,order)` check in `def_perturbation!`.
  `src/julia/XTensor.jl:1634-1754`

### In Progress
- [ ] **sxAct-8oa** — xTras IBP: symbolic integration by parts for discarding
  total derivatives in Lagrangians. Claimed, not yet started.

### Planned
- [ ] **sxAct-8tf** — xTras VarD: variational derivatives / Euler-Lagrange equations
- [ ] **sxAct-1sn** — xCore Symbol Registry (ValidateSymbol, Namespace)
- [ ] **sxAct-wom** — order>1 multinomial Leibniz in `perturb()`
- [ ] Docs overhaul epic (sxAct-3et, sxAct-kx9, sxAct-bh8)

## Critical Files

1. `src/julia/XTensor.jl` — entire algebra engine; ~2300 lines
2. `src/julia/xAct.jl` — new bundle entry-point (loads XCore + XTensor)
3. `src/sxact/adapter/julia_stub.py` — Python→Julia dispatch for all actions
4. `src/sxact/xcore/_runtime.py:42-58` — runtime now loads `xAct.jl` (not XCore.jl)
5. `src/julia/tests/test_xtensor.jl` — 132 Julia unit tests
6. `tests/xtensor/` — TOML integration tests (144 total)
7. `oracle/xtensor/` — snapshot oracles keyed by test id

## Recent Changes

- `src/julia/XTensor.jl` — Simplify convergence loop; PerturbCurvature;
  PerturbationOrder/AtOrder; def_perturbation! duplicate guard;
  _serialize pure-scalar fix
- `src/julia/xAct.jl` — new bundle file (46 lines)
- `src/julia/XCore.jl:607-628` — new `reset_core!()` function
- `src/sxact/adapter/julia_stub.py` — removed `_get_xtensor` lazy loader (now in
  runtime); added PerturbCurvature, PerturbationOrder, PerturbationAtOrder
- `src/sxact/xcore/_runtime.py:42-58` — loads `xAct.jl` / `using .xAct`
- `src/sxact/adapter/base.py` — new actions added to `supported_actions()`
- `oracle/xtensor/pert_curvature/` — 17 oracle files (new)
- `oracle/xtensor/pert_orders/` — 26 oracle files (new)
- `tests/xtensor/pert_curvature.toml`, `tests/xtensor/pert_orders.toml` — new

## Key Learnings

1. **xAct.jl is now the runtime entry-point** (architectural shift)
   - `_runtime.py` loads `xAct.jl` which `include()`s XCore.jl then XTensor.jl
   - The old `_get_xtensor` lazy loader in `julia_stub.py` was deleted
   - See `src/sxact/xcore/_runtime.py:42-58` and `src/julia/xAct.jl`

2. **RicciScalar1 had a factor-of-2 bug**
   - The inline content of `ricci_scalar1` duplicated `ricci1`'s 4 terms without
     the `(1/2)` prefix → formula was `2δR` instead of `δR`
   - Fixed by reusing `ricci1` string directly (which carries `(1/2)`) and
     changing coefficient from `-2` to `-1`
   - `src/julia/XTensor.jl:2150-2200`; oracle `oracle/xtensor/pert_curvature/perturb_curvature_ricci_scalar.json`

3. **def_perturbation! allowed duplicate (background, order) pairs**
   - `PerturbationAtOrder` does a linear scan of `_perturbations` dict; with
     duplicate pairs, it would non-deterministically return one of them
   - Fixed with an O(n) pre-check loop in `def_perturbation!`
   - `src/julia/XTensor.jl:1643-1654`

4. **Simplify convergence check semantics**
   - Compares `ToCanonical(Contract(current))` against `current` (pre-Contract)
   - Slightly imprecise but correct: if full pass produces no change, stop
   - Max 20 iterations; in practice converges in 1-2 for well-formed expressions

5. **oracle_is_axiom tests snapshot the formula strings directly**
   - For PerturbCurvature, snapshots capture the CovD notation strings
   - After fixing RicciScalar1, oracles were manually updated (JSON + WL files)
   - Hash field = `sha256:hashlib.sha256(json.dumps({"normalized_output":..., "properties":...}, sort_keys=True).encode()).hexdigest()[:12]`

## Open Questions

- [ ] IBP (sxAct-8oa): what is the right granularity? Full CovD IBP on a
  Lagrangian expression, or just a `TotalDerivativeQ` predicate?
- [ ] VarD (sxAct-8tf): is full Euler-Lagrange in scope, or just the
  functional derivative `δL/δφ` for scalar fields?
- [ ] `PerturbCurvature` formulas are returned as unevaluated CovD strings — should
  they be simplified via `Simplify` before returning?

## Next Steps

1. **Implement IBP** `sxAct-8oa` [Priority: P2, IN_PROGRESS]
   - Pattern: add `IntegrateByParts(expr)` to XTensor.jl + adapter
   - Key: identify total-derivative terms (∇_a V^a) and drop them
   - Reference: xTras paper / xAct manual §IBP

2. **Implement VarD** `sxAct-8tf` [Priority: P2]
   - Functional derivative of a Lagrangian density w.r.t. a field
   - Depends on IBP being available

3. **Symbol Registry** `sxAct-1sn` [Priority: P2]
   - `ValidateSymbol`, `Namespace` — xCore-level feature
   - Independent of xTras

4. **Update MEMORY.md** with new test counts and architecture
   - Test counts: 132 Julia unit tests, 144 TOML xtensor tests
   - xAct.jl bundle now the runtime entry-point

## Artifacts

**New files:**
- `src/julia/xAct.jl`
- `tests/xtensor/pert_curvature.toml`
- `tests/xtensor/pert_orders.toml`
- `oracle/xtensor/pert_curvature/` (17 files)
- `oracle/xtensor/pert_orders/` (26 files)

**Modified files:**
- `src/julia/XTensor.jl`
- `src/julia/XCore.jl`
- `src/julia/tests/test_xtensor.jl`
- `src/sxact/adapter/julia_stub.py`
- `src/sxact/adapter/base.py`
- `src/sxact/xcore/_runtime.py`
- `src/sxact/runner/schemas/test-schema.json`
- `tests/schema/test-schema.json`

## Test Commands

```bash
# Julia unit tests
julia --project=src/julia src/julia/tests/test_xtensor.jl

# Python unit tests
uv run pytest tests/ -q --ignore=tests/integration --ignore=tests/properties --ignore=tests/xperm --ignore=tests/xtensor

# TOML integration tests (snapshot mode)
uv run xact-test run --adapter julia --oracle-mode snapshot --oracle-dir oracle tests/xtensor/<file>.toml

# All TOML at once
uv run xact-test run --adapter julia --oracle-mode snapshot --oracle-dir oracle tests/xtensor/
```
