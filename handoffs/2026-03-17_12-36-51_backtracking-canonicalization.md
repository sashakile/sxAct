---
date: 2026-03-17T12:36:51-03:00
git_commit: 5a71c05
branch: main
directory: /var/home/sasha/para/areas/dev/gh/sk/sxAct
issue: sxAct-d7qy
status: handoff
---

# Handoff: Backtracking canonicalization for contraction perms

## Context

`_canonicalize_contraction_perm` in XInvar.jl finds the lexicographic minimum of a contraction permutation under the Riemann symmetry group (8 symmetries per factor x n! block permutations). The original brute-force O(8^n x n!) algorithm was infeasible for n>=5 (orders 10-14 in the Invar pipeline). This session added a backtracking algorithm with frozen-position pruning that makes n=5 and n=6 practical and n=7 possible (though still slow).

## Current Status

### Completed
- [x] `_backtrack_riemann_syms!` function (`src/XInvar.jl:1068-1147`) — recursive backtracking with frozen-position pruning
- [x] Modified `_canonicalize_contraction_perm` (`src/XInvar.jl:1181-1273`) — n<=4 brute force, n>=5 backtracking
- [x] Initial bound seeding from identity-symmetry block perms
- [x] Block perm lexicographic sorting for tighter early pruning
- [x] Cross-validation tests: backtracking matches brute force at n=4
- [x] Property tests: n=5 deterministic, symmetry-consistent
- [x] Feasibility tests: n=5 performance, n=6 completion
- [x] All 648,781 XInvar tests pass, 91 XPerm, 417+ XTensor, 709 Python

### Planned (follow-up optimization for n=7)
- [ ] Combined block-perm + Riemann-symmetry backtracking to avoid O(n!) outer loop
- [ ] Or: canonical augmentation approach (build canonical form position-by-position)

## Critical Files

1. `src/XInvar.jl:1068-1147` — `_backtrack_riemann_syms!`: the core recursive backtracking function
2. `src/XInvar.jl:1149-1273` — `_canonicalize_contraction_perm`: dispatch between brute-force (n<=4) and backtracking (n>=5)
3. `src/XInvar.jl:933-944` — `_swap_slots!`: conjugation primitive used by both paths
4. `test/julia/test_xinvar.jl:1073-1178` — New backtracking test suite

## Recent Changes

- `src/XInvar.jl:1068-1147` — Added `_backtrack_riemann_syms!` (new function, 80 lines)
- `src/XInvar.jl:1181-1273` — Rewrote `_canonicalize_contraction_perm` with dual-path dispatch
- `test/julia/test_xinvar.jl:1073-1178` — Added 4 new test sets (n=4 cross-validation, n=5 properties, n=5 perf, n=6 feasibility)

## Key Learnings

1. **Frozen-position pruning is sound but structure-dependent**
   - A position j is frozen after factor k iff `slot_to_factor[j] <= k AND slot_to_factor[perm[j]] <= k`
   - Pruning is weakest for cross-contracting perms (early positions map to late factors)
   - Self-contracting perms prune better but real-world improvement is modest

2. **Block permutations dominate at n>=7**
   - n=7 has 7!=5040 block perms; each requires a full backtracking traversal
   - The init seeding and sorting barely help (~3% improvement)
   - The real fix requires incorporating block perm choice INTO the backtracking tree

3. **Performance profile**
   - n=5: ~15ms/perm (204 perms at order 10 -> 3s total)
   - n=6: ~100ms/perm (1613 perms at order 12 -> 2.7min total)
   - n=7: ~16s/perm (16532 perms at order 14 -> 73hr total, still impractical)

4. **Brute-force refactoring: `riemann_starts` is block-perm-independent**
   - The old code computed `target_riemann_starts` per block perm, but since block perms only swap factors with the same derivative order, `riemann_starts[i] = first(slot_ranges[i]) + case.deriv_orders[i]` is constant
   - This was simplified in the refactored brute-force path

## Open Questions

- [ ] Can a combined block-perm + Riemann backtracking reduce n=7 to practical levels?
- [ ] Would canonical augmentation (constructing the canonical form greedily) be faster than search?
- [ ] For Invar pipeline phases 4-7, is n<=6 sufficient or is n=7 (order 14) required?

## Next Steps

1. **Phases 4 + 6: PermToInv + InvSimplify pipeline** [Priority: HIGH]
   - Orders 10-12 are now unblocked by this optimization
   - See `plans/2026-03-11-multi-term-symmetry-engine.md` for pipeline phases
   - Issues: sxAct-w50 (Phase 4), sxAct-23p (Phase 6)

2. **n=7 optimization (if needed)** [Priority: LOW]
   - Combined backtracking over block perms and Riemann symmetries
   - Would interleave "which factor goes at position k" with "which symmetry to apply"
   - Challenge: `_apply_block_perm_to_contraction` couples all positions via value remapping

## Artifacts

**Modified files:**
- `src/XInvar.jl` — Added `_backtrack_riemann_syms!`, refactored `_canonicalize_contraction_perm`
- `test/julia/test_xinvar.jl` — Added backtracking test suite

## References

- Plan: `plans/2026-03-11-multi-term-symmetry-engine.md` (Invar pipeline phases)
- Invar pipeline status in MEMORY.md (phases 1-11)
- Butler-Portugal canonicalization: `src/XPerm.jl`
