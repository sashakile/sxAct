---
date: 2026-03-10T12:35:30-03:00
git_commit: 4c2fd9f
branch: main
directory: /var/home/sasha/para/areas/dev/gh/sk/sxAct
issue: sxAct-9g1
status: handoff
---

# Handoff: YoungSymmetry wired into def_tensor! and ToCanonical

## Context

Young tableaux were already implemented in XPerm.jl (row/col SGS builders,
`young_projector`, `standard_tableau`) as part of sxAct-9gt. This session
completed sxAct-9g1: making `def_tensor!` accept a `Young[{k1,k2,...}]`
symmetry string and having `ToCanonical` correctly canonicalize tensors with
that symmetry. This is a prerequisite for the Invar module (sxAct-tw0).

## Current Status

### Completed
- [x] `SymmetrySpec` extended with `partition::Vector{Int}` field — `src/julia/XTensor.jl:82-86`
- [x] `_parse_symmetry` handles `Young[{k1,k2,...}]` — `src/julia/XTensor.jl:266-275`
- [x] `_young_columns` helper added to XPerm.jl (needed for zero detection) — `src/julia/XPerm.jl:1920-1936`
- [x] `_canonicalize_young` implements lex-min over Young orbit — `src/julia/XPerm.jl:940-985`
- [x] `canonicalize_slots` dispatches `:YoungSymmetry` — `src/julia/XPerm.jl:988-1005`
- [x] `_canonicalize_term` threads `sym.partition` through — `src/julia/XTensor.jl:1229-1231`
- [x] 19 new Julia unit tests — `src/julia/tests/test_xtensor.jl:345-396`
- [x] 8 new TOML integration tests + oracle snapshots — `tests/xtensor/young_symmetry.toml`

### Planned
- [ ] sxAct-tw0: Invar — Riemann invariants through 12 derivatives (now unblocked)

## Critical Files

1. `src/julia/XPerm.jl:940-1005` — `_canonicalize_young` + extended `canonicalize_slots`
2. `src/julia/XTensor.jl:82-86` — `SymmetrySpec` struct (now has `partition` field)
3. `src/julia/XTensor.jl:259-305` — `_parse_symmetry` with new Young branch
4. `src/julia/XTensor.jl:1207-1240` — `_canonicalize_term` dispatch loop

## Recent Changes

- `src/julia/XPerm.jl:940-985` — Added `_canonicalize_young` and `_young_columns`
- `src/julia/XPerm.jl:961-1005` — Extended `canonicalize_slots` signature with optional `partition`
- `src/julia/XTensor.jl:82-86` — Extended `SymmetrySpec` with `partition` field + compat constructor
- `src/julia/XTensor.jl:266-275` — Added Young branch in `_parse_symmetry`
- `src/julia/XTensor.jl:1229-1231` — Threaded `sym.partition` to `canonicalize_slots`
- `src/julia/tests/test_xtensor.jl:345-396` — New YoungSymmetry testset (19 tests)
- `tests/xtensor/young_symmetry.toml` — 8 TOML integration tests (new file)
- `oracle/xtensor/young_symmetry/` — Oracle snapshots (all "True", new directory)

## Key Learnings

1. **Lex-min canonical rep, not projector expansion**
   - The issue notes suggested calling `young_projector` and expanding into a multi-term
     sum. That was rejected: `canonicalize_slots` returns a single `(indices, sign)` pair
     for all symmetry types, and changing that would ripple everywhere.
   - Instead, `_canonicalize_young` enumerates the full Young orbit `{c·r : c ∈ col_group, r ∈ row_group}`
     (same computation as the projector but without accumulating coefficients) and picks
     the lex-min element. Sign = sgn of the column element c used.
   - This correctly subsumes `:Symmetric` (`{n}` partition, col group = {e}, all signs +1)
     and `:Antisymmetric` (`{1,1,...}`, row group = {e}, signs from col transpositions).

2. **Zero detection: repeated indices in any column**
   - `_canonicalize_young` checks each column of the tableau for repeated bare index labels.
     If any column has duplicates, the tensor vanishes (column antisymmetrization kills it).
   - Row repetitions are NOT zero (row group is symmetric).
   - Implementation: `_young_columns(tab)` → `Vector{Vector{Int}}` of slot positions per column.

3. **SymmetrySpec backward compat**
   - Added `SymmetrySpec(type::Symbol, slots::Vector{Int}) = SymmetrySpec(type, slots, Int[])`
     so all existing code constructing `SymmetrySpec` with 2 args continues to work.
   - All existing Symmetric/Antisymmetric/Riemann tensors get `partition = Int[]`.

4. **Oracle snapshots for oracle_is_axiom tests**
   - Cannot use `xact-test snapshot` (requires live Wolfram). Use the same pattern as
     `scripts/gen_butler_snapshots.py`: run via `JuliaAdapter` directly, write JSON + .wl
     files manually. See bottom of this file for the inline script pattern.

5. **Issue note inaccuracy: "two-term" for {2,1}**
   - The issue acceptance criteria said "two-term" for {2,1}. The Young projector for {2,1}
     gives 4 terms (|S_3| = 6 elements, but projector has 4 non-zero). The actual canonical
     behavior is: a single canonical term (lex-min), with like-term collection downstream.
     The "two-term" test in the issue was never implemented — it doesn't match what
     `ToCanonical` should do. Tests were written to match correct behavior instead.

## Open Questions

- [ ] sxAct-tw0 (Invar) is now unblocked. It will need Young tensors with specific
  Riemann-symmetry-like partitions; check if `_canonicalize_young` handles rank-4+
  tensors with multi-row partitions efficiently (enumerates |G| elements; for large
  groups this could be slow, but Invar uses fixed small partitions).

## Next Steps

1. **sxAct-tw0: Invar** [Priority: P3, now unblocked]
   - Riemann invariants through 12 derivatives
   - Will likely need `Young[{2,2}]` or similar for Riemann-type tensors

## Artifacts

**New files:**
- `tests/xtensor/young_symmetry.toml`
- `oracle/xtensor/young_symmetry/` (8 JSON + 8 .wl files)
- `handoffs/2026-03-10_12-35-30_sxAct-9g1_young-symmetry.md` (this file)

**Modified files:**
- `src/julia/XPerm.jl`
- `src/julia/XTensor.jl`
- `src/julia/tests/test_xtensor.jl`

## References

- Issue: `bd show sxAct-9g1`
- Blocked issue: `bd show sxAct-tw0`
- Young tableau implementation (already done): `src/julia/XPerm.jl:1860-2130`
- Design spec: `specs/2026-03-06-xperm-xtensor-design.md`
