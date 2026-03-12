---
date: 2026-03-12T18:06:34-03:00
git_commit: 047be00
branch: main
directory: /var/home/sasha/para/areas/dev/gh/sk/sxAct
issue: sxAct-ki0
status: complete
---

# Handoff: Christoffel symbols from metric CTensor components

## Context

Implemented the Christoffel symbol computation for the xCoba (coordinate-based) layer of sxAct. This is a key building block for coordinate-based GR calculations: geodesic equations, covariant derivatives in components, and Riemann tensor evaluation all need Christoffel symbols. The feature computes the second kind Christoffel Γ^a_{bc} from stored metric components and user-provided metric derivatives.

## Current Status

### Completed
- [x] Auto-creation of `ChristoffelCovD` tensor in `def_metric!` via `_auto_create_curvature!` (`src/julia/src/XTensor.jl:903-913`)
- [x] `christoffel!` function computing Γ^a_{bc} = (1/2) g^{ad} (∂_b g_{dc} + ∂_c g_{bd} - ∂_d g_{bc}) (`src/julia/src/XTensor.jl:3621-3686`)
- [x] Adapter action `Christoffel` in Python layer (`src/sxact/adapter/julia_stub.py:721-756`)
- [x] Schema update for TOML test runner (`src/sxact/runner/schemas/test-schema.json`)
- [x] 31 Julia unit tests including Schwarzschild verification (`src/julia/tests/test_xtensor.jl:1604+`)
- [x] 5 TOML integration tests with oracle snapshots (`tests/xtensor/christoffel.toml`)
- [x] Issue sxAct-ki0 closed, code committed and pushed

## Critical Files

> These are the MOST IMPORTANT files to understand for continuation

1. `src/julia/src/XTensor.jl:3621-3686` - Core `christoffel!` implementation
2. `src/julia/src/XTensor.jl:903-913` - Auto-creation in `_auto_create_curvature!`
3. `src/julia/tests/test_xtensor.jl:1604-1770` - Unit tests including Schwarzschild verification
4. `src/sxact/adapter/julia_stub.py:721-756` - Python adapter `_christoffel` method
5. `tests/xtensor/christoffel.toml` - TOML integration tests

## Recent Changes

> Files modified in this session

- `src/julia/src/XTensor.jl:903-913` - Christoffel auto-creation in `_auto_create_curvature!`
- `src/julia/src/XTensor.jl:3609-3686` - New `christoffel!` function + string overload
- `src/julia/src/XTensor.jl:79-80` - Export `christoffel!`
- `src/julia/tests/test_xtensor.jl:1604-1770` - 31 new unit tests (new section)
- `src/sxact/adapter/julia_stub.py:139,333,721-756` - Adapter action + dispatch
- `src/sxact/adapter/base.py:274` - Added to `supported_actions`
- `src/sxact/runner/schemas/test-schema.json` - Schema for `Christoffel` action
- `tests/xtensor/christoffel.toml` - 5 TOML integration tests (new file)
- `oracle/xtensor/christoffel/*.json` - 4 oracle snapshots (new files)

## Key Learnings

> Important discoveries that affect future work

1. **Symmetry slot lookup requires distinct labels across all slots**
   - `_parse_symmetry` uses `findfirst` by label name, so if two slots share the same base label (e.g., slot 1 = `a` up, slot 2 = `-a` down), it finds the wrong position
   - Fix: Christoffel uses 3 distinct labels: `[idxs[1], -idxs[2], -idxs[3]]` not `[idxs[1], -idxs[1], -idxs[2]]`
   - See `src/julia/src/XTensor.jl:908-910`

2. **n >= 3 index label requirement limits 2D manifolds**
   - Christoffel is only auto-created when the manifold has >= 3 index labels
   - This means 2D manifolds (e.g., sphere surface) don't get Christoffel auto-creation
   - Root cause is the distinct-label requirement above; fixing `_parse_symmetry` to be variance-aware would remove this limitation

3. **CTensor stores numerical arrays only — no symbolic differentiation**
   - `metric_derivs` must be provided by the user as a numerical rank-3 array
   - For constant metrics (Minkowski), omitting `metric_derivs` gives all-zero Christoffels
   - Future symbolic support would require Symbolics.jl (not currently a dependency)

4. **Metric derivative sign convention**
   - `dg[c, a, b]` = ∂_c g_{ab} (derivative index is the FIRST dimension)
   - Schwarzschild: ∂_r g_{tt} and ∂_r g_{rr} are both NEGATIVE (easily mistaken for positive)
   - ∂_r g_{tt} = -2M/r² (g_{tt} becomes more negative as r increases)
   - ∂_r g_{rr} = -2M/(r²f²) (g_{rr} decreases as r increases past horizon)

## Open Questions

> Unresolved decisions or uncertainties

- [ ] Should `christoffel!` support symbolic metric components via Symbolics.jl?
- [ ] Should we add `christoffel_first_kind!` (all-covariant Γ_{abc}), or is metric contraction sufficient?
- [ ] How to handle 2D manifolds — fix `_parse_symmetry` to be variance-aware, or allow > dim index labels?

## Next Steps

> Prioritized actions for next session

1. **sxAct-3yn: Geodesic equations** [Priority: P3, now unblocked]
   - Generate d²x^a/dτ² + Γ^a_{bc} dx^b/dτ dx^c/dτ = 0 from Christoffel
   - Implement parallel transport ∇_v T = 0 in components
   - Verify Schwarzschild geodesics match textbook

2. **sxAct-4f5: xTras CollectTensors/AllContractions** [Priority: P2]
   - Higher-level tensor manipulation utilities

3. **sxAct-yrk: xTras MakeTraceFree** [Priority: P2]
   - Trace decomposition of tensors

4. **sxAct-x8q: Invar multi-term symmetry engine** [Priority: P2, major effort]
   - Required for Riemann invariant computation
   - Estimated 5-8 weeks

## Artifacts

> Complete list of files created/modified

**New files:**
- `tests/xtensor/christoffel.toml`
- `oracle/xtensor/christoffel/christoffel_minkowski.json`
- `oracle/xtensor/christoffel/christoffel_nontrivial.json`
- `oracle/xtensor/christoffel/christoffel_stored.json`
- `oracle/xtensor/christoffel/christoffel_symmetry.json`

**Modified files:**
- `src/julia/src/XTensor.jl` (+91 lines)
- `src/julia/tests/test_xtensor.jl` (+178 lines)
- `src/sxact/adapter/base.py` (+1 line)
- `src/sxact/adapter/julia_stub.py` (+35 lines)
- `src/sxact/runner/schemas/test-schema.json` (+22 lines)

## Test Results

| Suite | Count | Status |
|-------|-------|--------|
| Julia XTensor unit tests | 372/372 | PASS |
| TOML integration (xTensor) | 201/201 | PASS |
| Python runner tests | 550/550 | PASS |

## Notes

- The `christoffel!` API intentionally separates metric components from derivatives — this matches how numerical GR codes work (metric and its derivatives are independent inputs at each grid point)
- The Schwarzschild test evaluates at r=3M, θ=π/2 with M=1, which gives clean rational Christoffel values (1/3, 1/27, etc.) good for numerical verification
- Pre-commit hook `julia-format` will reformat Julia code; always `git add -u` after first failed commit attempt
