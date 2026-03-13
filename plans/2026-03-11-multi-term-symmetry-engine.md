# Multi-Term Symmetry Engine (Invar) Implementation Plan

**Date**: 2026-03-11
**Issue**: sxAct-x8q (multi-term symmetry engine)
**Enables**: sxAct-22s (Riemann invariant database), sxAct-tw0 (Riemann invariants through 12 derivatives)

## Scope Mapping

This plan covers TWO related but distinct deliverables:

| Phase | Issue | Deliverable |
|-------|-------|-------------|
| **Phase 1** | **sxAct-x8q** | Multi-term identity framework (the ENGINE) |
| Phases 2-11 | sxAct-22s | Invar port: invariant types, database, RiemannSimplify pipeline |

**Phase 1 is the MVP milestone**: it generalizes the hardcoded Bianchi patterns into a reusable identity framework, completing sxAct-x8q. Phases 2-11 build the Invar APPLICATION on top of that engine and should be tracked under sxAct-22s (or broken into sub-issues).

## Overview

Implement a multi-term symmetry engine that extends sxAct's canonicalization beyond mono-term symmetries (Butler-Portugal) to handle multi-term identities: cyclic, Bianchi, covariant derivative commutation, and dimension-dependent relations. Then build the Invar pipeline on top: convert Riemann scalar expressions to canonical permutation forms, apply pre-computed simplification rules from the Wolfram Invar database, and convert back.

## Related

- Wolfram source: `resources/xAct/Invar/Invar.m` (872 lines)
- Research: `research/XACT_MIGRATION_RESEARCH.md` (Section F)
- Papers: Martín-García et al. (2008) arXiv:0802.1274, Li et al. (2017) arXiv:1701.08487
- Cadabra2 reference: Young-projector-based multi-term canonicalization

## Current State

### What Works (mono-term)
- Butler-Portugal canonicalization for individual tensor terms (`canonicalize_slots()` in XPerm.jl)
- Symmetry types: Symmetric, Antisymmetric, GradedSymmetric, RiemannSymmetric, YoungSymmetry
- Young projectors: `YoungTableau`, `young_projector()`, `_canonicalize_young()` — complete but isolated

### What Works (multi-term, hardcoded)
- First Bianchi: `_bianchi_reduce!()` at XTensor.jl:1195-1250 — hardcoded 3-term pattern R_{a[bcd]}=0
- Second Bianchi: `_reduce_second_bianchi()` at XTensor.jl:1273-1334 — hardcoded regex-based pattern
- CovD commutation: `CommuteCovDs()` at XTensor.jl:1370-1493 — generates Riemann correction terms
- Simplify loop: `Simplify()` at XTensor.jl:2303-2313 — iterative Contract→ToCanonical convergence

### What's Missing
1. **General multi-term identity framework** — no way to define/register/apply arbitrary multi-term identities
2. **Invariant representation** — no RInv/RPerm permutation-based canonical forms
3. **Tensor-to-permutation conversion** — no RiemannToPerm pipeline
4. **Database loading** — no parser for Wolfram/Maple rule files (>600K relations)
5. **Dimension-dependent identities** — no generalized Kronecker delta / antisymmetrization vanishing
6. **Dual invariants** — no Levi-Civita epsilon tensor / dual Riemann handling
7. **InvSimplify** — no leveled simplification (6 levels: cyclic → Bianchi → commute → dim-dep → dual)

## Desired End State

A `RiemannSimplify(expr, metric; level=6)` function that:
1. Decomposes scalar expressions into monomials, classifying each by case
2. Converts each Riemann scalar monomial → canonical permutation form
3. Looks up invariant labels from a pre-computed database
4. Applies multi-term simplification at configurable levels (1-6)
5. Converts back to tensor expression strings

**How to verify:**
- `RiemannSimplify("RiemannCD[-a,-b,-c,-d] RiemannCD[a,b,c,d]", :CD)` → a simplified tensor expression string (Kretschner scalar in canonical form)
- `RiemannSimplify("RiemannCD[-a,-b,-c,-d] RiemannCD[a,b,c,d] - RiemannCD[-c,-d,-a,-b] RiemannCD[c,d,a,b]", :CD)` → `"0"` (same invariant with relabeled dummies)
- All 47 non-dual cases (order ≤ 12) produce correct independent invariant counts matching `MaxIndex` table
- Schwarzschild Kretschner: numeric evaluation matches 48M²/r⁶
- First/second Bianchi handled as special cases of the general engine (not hardcoded)

## Out of Scope

- Generating the Invar database from scratch (we port the existing Wolfram database)
- Dual invariants beyond 4D (Wolfram Invar is 4D-only for duals)
- TInvar (polynomial invariant classification — separate from simplification)
- Performance parity with Wolfram's C-compiled xPerm (acceptable to be slower initially)
- FieldsX integration (gauge theory, separate epic)
- Multi-metric simplification (bimetric gravity) — single metric only for now
- Expressions with free (uncontracted) indices — RiemannSimplify requires scalar input

## File Organization

XTensor.jl is already large. New code is organized as follows:

| File | Content | Phases |
|------|---------|--------|
| `src/XTensor.jl` | Multi-term identity framework (`_apply_identities!`, `register_identity!`) | Phase 1 |
| `src/XInvar.jl` | Invariant types (RPerm, RInv), RiemannToPerm, PermToRiemann, InvSimplify, RiemannSimplify | Phases 2-10 |
| `src/InvarDB.jl` | Database parser (Maple/Mathematica formats), caching, download | Phase 5 |
| `src/xAct.jl` | `include("XInvar.jl")` after `include("XTensor.jl")` | Phase 2 |

XInvar.jl depends on XTensor.jl (uses `ToCanonical`, `Contract`, tensor registries) but not vice versa.

## Naming Conventions

All public functions use **CamelCase** (matching existing XTensor.jl: `ToCanonical`, `CommuteCovDs`, `Simplify`):
- `RiemannToPerm`, `PermToRiemann`, `PermToInv`, `InvToPerm`
- `InvSimplify`, `RiemannSimplify`
- `InvarCases`, `LoadInvarDB`

Internal helpers use **snake_case** with leading underscore:
- `_classify_case`, `_extract_contraction_perm`, `_apply_dispatch_rules`

## Permutation Degree Formula

The RPerm permutation degree (number of points it acts on) is determined by the InvariantCase:

```
degree = 4 * length(case.deriv_orders) + sum(case.deriv_orders) + 4 * case.n_epsilon
```

Examples:
- Case `[0]` (1 Riemann, no derivatives): `4*1 + 0 + 0 = 4`
- Case `[0,0]` (2 Riemanns): `4*2 + 0 + 0 = 8`
- Case `[2]` (1 Riemann + 2 derivatives): `4*1 + 2 + 0 = 6`
- Case `[0,0]` dual (2 Riemanns + epsilon): `4*2 + 0 + 4 = 12`

Source: Invar.m:696 `translate[RPerm[metric_][{case_,dege_},perm_]] := First@TranslatePerm[perm, {Images, 4*Length[case] + Plus@@case + 4*dege}]`

## Performance Budget

| Operation | Target |
|-----------|--------|
| Degree-2 simplification (case [0,0], 3 invariants) | < 10ms |
| Degree-4 simplification (case [0,0,0,0], 38 invariants) | < 100ms |
| Degree-7 algebraic (case [0,...,0], 16532 invariants) | < 5s |
| Database loading (first use, with cache) | < 1s from cache, < 10s cold |
| Identity application in ToCanonical (Phase 1) | No measurable regression vs hardcoded Bianchi |

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Invar database not in repo (must download) | Blocks database-driven simplification | Phase 5 handles download + conversion; Phases 1-4 are algorithm-only. Fallback: bundle low-order cases (≤6) as Julia source code. |
| Database URL (xact.es) unavailable | Can't download | Mirror database in sxAct releases; archive on GitHub. Database is GPL-licensed. |
| Maple/Mathematica parser complexity | Could be error-prone | Use simple line-by-line parsing matching Invar.m's `ReadInvarPerms`/`ReadInvarRules` patterns |
| Permutation representation mismatch | Wolfram uses Cycles notation, we use images | Already solved: XPerm.jl has `TranslatePerm` for Cycles↔Images |
| Performance at high degree (7 Riemanns = 28 indices) | Could be slow | Use dispatch caching (like Wolfram's `Dispatch[]`) and lazy loading |
| Contraction pattern extraction (Phase 3) | Under-specified, could be harder than expected | Concrete parsing algorithm documented below; add 1 buffer session |
| Expressions outside database coverage (degree > 7) | No simplification possible | Return input unchanged with warning; database covers all practical GR cases |

## Edge Cases

All phases must handle these scenarios:

1. **`reset_state!()`**: All new registries (`_identity_registry`, Invar database cache, loaded rules) must be cleared. Each phase that adds global state must update `reset_state!()`.
2. **Non-scalar expressions**: `RiemannSimplify` validates that all indices are contracted; raises `ArgumentError` for free-index expressions.
3. **Database coverage bounds**: Degree > 7 algebraic or order > 12 differential → return input with warning, not error.
4. **Symbolic dimension**: Levels 5-6 of InvSimplify require integer dimension; symbolic dimensions skip these levels gracefully.
5. **Products of scalar invariants**: Input like `R * R_{abcd}R^{abcd}` is decomposed into separate scalar monomials (each classified independently) before simplification.
6. **Zero/trivial expressions**: `RiemannSimplify("0", :CD)` → `"0"`; `RiemannSimplify("RicciScalarCD[]", :CD)` → `"RicciScalarCD[]"`.

---

## Phase 1: Multi-Term Identity Framework [sxAct-x8q]

**Goal**: Replace hardcoded Bianchi patterns with a general identity representation and application engine. This phase IS the sxAct-x8q deliverable.

### Changes Required

**File: `src/XTensor.jl`**
- Add `MultiTermIdentity` struct
- Add `_identity_registry::Dict{Symbol, Vector{MultiTermIdentity}}` — identities keyed by tensor name
- Add `RegisterIdentity!(tensor_name, identity)` — register a multi-term identity
- Add `_apply_identities!(coeff_map, key_order)` — generalized identity application replacing `_bianchi_reduce!`
- Auto-register first Bianchi identity for all Riemann tensors in `_auto_create_curvature!`
- Refactor `_bianchi_reduce!` to use the general framework (keep behavior identical)
- Update `reset_state!()` to clear `_identity_registry`

### Data Structures

```julia
"""
A multi-term identity relating N canonical tensor terms by a linear relation.

The identity asserts: Σᵢ coefficients[i] * T[slot_perms[i](free_indices)] = 0

where `free_indices` are abstract indices grouped by `fixed_slots` into sectors.

Example — First Bianchi identity R_{a[bcd]} = 0:
  Identity: R[p,q,r,s] - R[p,r,q,s] + R[p,s,q,r] = 0
  - fixed_slots = [1]       # slot 1 (index p) is the same in all terms
  - cycled_slots = [2,3,4]  # slots 2,3,4 are permuted across terms
  - slot_perms = [[2,3,4], [3,4,2], [4,2,3]]  # how cycled_slots map in each term
                 (identity)  (231 cycle) (312 cycle) — but AFTER canonicalization,
                 the actual Bianchi terms are identified by which index lands in slot 2:
                 q (smallest), r (middle), s (largest)
  - coefficients = [1//1, -1//1, 1//1]  # signs: X₁ - X₂ + X₃ = 0
  - eliminate = 3            # eliminate term 3 (X₃ = X₂ - X₁)
"""
struct MultiTermIdentity
    name::Symbol                           # :FirstBianchi, :SecondBianchi, etc.
    tensor::Symbol                         # which tensor this applies to
    n_slots::Int                           # total tensor rank (4 for Riemann)
    fixed_slots::Vector{Int}               # slot positions held constant across terms
    cycled_slots::Vector{Int}              # slot positions permuted across terms
    slot_perms::Vector{Vector{Int}}        # for each term: permutation of cycled_slots
    coefficients::Vector{Rational{Int}}    # coefficient of each term in the identity
    eliminate::Int                         # which term index to eliminate (reduce)
end
```

### Worked Example: First Bianchi via Framework

The existing `_bianchi_reduce!` (XTensor.jl:1195-1250) works as follows:
1. For each Riemann term R[p,q,r,s] (already canonical: p < q,r,s), group by sector = (tensor_name, p, {q,r,s})
2. Within each sector, three terms exist: X₁ (second index = smallest remaining), X₂ (middle), X₃ (largest)
3. Identity: X₁ - X₂ + X₃ = 0. Eliminate X₃ = X₂ - X₁.

Under the new framework:
```julia
bianchi = MultiTermIdentity(
    :FirstBianchi,
    riemann_name,         # e.g. :RiemannCD
    4,                    # Riemann has 4 slots
    [1],                  # slot 1 is fixed (index p)
    [2, 3, 4],           # slots 2,3,4 are the cycled indices
    [[1,2,3], [2,3,1], [3,1,2]],  # identity perm, (231), (312) on cycled slots
    [1//1, -1//1, 1//1],  # X₁ - X₂ + X₃ = 0
    3,                    # eliminate term 3
)
RegisterIdentity!(riemann_name, bianchi)
```

The general `_apply_identities!` engine:
1. For each registered identity on tensor T, scan `coeff_map` for single-factor terms with tensor name T
2. Group terms by sector (values at fixed_slots)
3. Within each sector, map terms to identity positions by matching the cycled_slot values
4. If all N terms of the identity are present, eliminate the designated term

### Success Criteria
#### Automated:
- [ ] All 185 existing xTensor TOML tests pass (identity regression)
- [ ] All 316 existing Julia unit tests pass
- [ ] New tests: `test_multiterm_identity_registration` (register and query)
- [ ] New tests: `test_first_bianchi_via_framework` (same results as hardcoded `_bianchi_reduce!`)
- [ ] `_bianchi_reduce!` is now a thin wrapper over `_apply_identities!`
- [ ] `reset_state!()` clears `_identity_registry`

### Dependencies
None — purely internal refactoring.

### Estimated Effort
1 session

---

## Phase 2: Invariant Permutation Representation [sxAct-22s]

**Goal**: Implement the RInv/RPerm representation system — the canonical way to label and manipulate Riemann invariants as permutations.

### Changes Required

**New file: `src/XInvar.jl`**
- Add `InvariantCase` type: encodes a case as `(deriv_orders::Vector{Int}, n_epsilon::Int)`
- Add `RPerm` type: `(metric::Symbol, case::InvariantCase, perm::Vector{Int})`
- Add `RInv` type: `(metric::Symbol, case::InvariantCase, index::Int)`
- Add `MaxIndex` table: hardcoded from Invar.m:389-452 (47 non-dual cases)
- Add `InvarCases(order, degree)` — enumerate cases matching Invar.m:324-357
- Add `PermDegree(case)` — compute permutation degree from case

**File: `src/xAct.jl`**
- Add `include("XInvar.jl")` after `include("XTensor.jl")`

### Data Structures

```julia
struct InvariantCase
    deriv_orders::Vector{Int}   # e.g., [0,0] for 2 Riemanns, no derivatives
    n_epsilon::Int              # 0 = non-dual, 1 = dual (4D only)
end

struct RPerm
    metric::Symbol
    case::InvariantCase
    perm::Vector{Int}           # permutation in Images representation, degree = PermDegree(case)
end

struct RInv
    metric::Symbol
    case::InvariantCase
    index::Int                  # 1-based invariant number (1..MaxIndex[case])
end

"""Permutation degree: total index slots across all tensors + epsilon."""
PermDegree(c::InvariantCase) = 4 * length(c.deriv_orders) + sum(c.deriv_orders) + 4 * c.n_epsilon

# MaxIndex table (from Invar.m:389-452, all 47 non-dual cases)
const RINV_MAX_INDEX = Dict{Vector{Int}, Int}(
    [0] => 1,
    [0,0] => 3,          [2] => 2,
    [0,0,0] => 9,        [0,2] => 12,       [1,1] => 12,        [4] => 12,
    [0,0,0,0] => 38,     [0,0,2] => 99,     [0,1,1] => 125,
    [0,4] => 126,        [1,3] => 138,      [2,2] => 86,        [6] => 105,
    # ... (all 47 cases through order 12 + degree 7)
)
```

### Success Criteria
#### Automated:
- [ ] `InvarCases()` returns all 47 cases matching Wolfram output
- [ ] `MaxIndex` for all 47 cases matches Wolfram values
- [ ] `InvarCases(order)` partitions correctly by derivative order
- [ ] `PermDegree` matches Invar.m formula for all cases
- [ ] RPerm/RInv types are constructible and printable
- [ ] `xAct.jl` loads XInvar.jl without error

### Dependencies
None — standalone data types.

### Estimated Effort
1 session

---

## Phase 3: Riemann-to-Permutation Conversion (RiemannToPerm)

**Goal**: Convert Riemann scalar expressions (fully contracted tensor products) into canonical RPerm permutation forms.

### Changes Required

**File: `src/XInvar.jl`**
- Add `RiemannToPerm(expr, metric)` — converts a Riemann scalar expression to RPerm (threads over sums)
- Add `_classify_case(expr, metric)` — determines which InvariantCase an expression belongs to
- Add `_extract_contraction_perm(canonical_str, case)` — extracts the contraction permutation from canonical form
- Add `_ricci_to_riemann(expr, covd)` — replaces Ricci/RicciScalar with contracted Riemann
- Add `_canonical_index_list(metric, n)` — generates canonical index list for N Riemanns
- Add `PermToRiemann(rperm, metric; curvature_relations=false)` — convert permutation back to tensor expression

### Algorithm (from Invar.m:768-807)
1. **Expand & thread**: Parse sums; process each monomial independently
2. **Ricci → Riemann**: Replace `RicciCD[-a,-b]` → `RiemannCD[a,-c,b,c]` (with fresh dummy); `RicciScalarCD[]` → `RiemannCD[c,d,-c,-d]`
3. **Classify case**: Count Riemann factors and derivative orders → InvariantCase
4. **Validate**: All indices must be contracted (scalar invariant). Raise `ArgumentError` if free indices remain.
5. **Canonicalize**: Apply `ToCanonical` to get canonical index ordering
6. **Extract contraction permutation** (see algorithm below)

### Contraction Permutation Extraction Algorithm

Given a canonical string like `"RiemannCD[-a,-b,-c,-d] RiemannCD[a,b,c,d]"`:

```
Step 1: Parse all tensor factors and their index lists.
  Factor 1: RiemannCD with indices [-a, -b, -c, -d] → slots 1,2,3,4
  Factor 2: RiemannCD with indices [a, b, c, d]     → slots 5,6,7,8

Step 2: Build canonical slot assignment.
  Assign slots left-to-right across factors: factor 1 gets slots 1-4, factor 2 gets 5-8.
  For differential invariants, CovD indices precede the Riemann they act on.

Step 3: Identify contraction pairs.
  Index "a" appears at slot 1 (covariant) and slot 5 (contravariant) → pair (1,5)
  Index "b" appears at slot 2 (covariant) and slot 6 (contravariant) → pair (2,6)
  Index "c" appears at slot 3 (covariant) and slot 7 (contravariant) → pair (3,7)
  Index "d" appears at slot 4 (covariant) and slot 8 (contravariant) → pair (4,8)

Step 4: Build permutation from pairs.
  For each pair (i, j): perm[i] = j, perm[j] = i
  Result: perm = [5, 6, 7, 8, 1, 2, 3, 4]

Step 5: Canonicalize permutation via Butler-Portugal.
  The contraction permutation must be in canonical form with respect to the
  tensor product's symmetry group (product of Riemann 8-element groups).
  Use canonicalize_slots on the permutation in the (S_slot × S_dummy) double coset.
```

This parsing approach works entirely on the string output of `ToCanonical` — no internal hooks needed.

### Success Criteria
#### Automated:
- [ ] `RiemannToPerm("RicciScalarCD[]", :CD)` returns RPerm for case `[0]`
- [ ] `RiemannToPerm("RiemannCD[-a,-b,-c,-d] RiemannCD[a,b,c,d]", :CD)` returns the Kretschner RPerm
- [ ] `RiemannToPerm("RicciCD[-a,-b] RicciCD[a,b]", :CD)` correctly converts Ricci→Riemann first
- [ ] `RiemannToPerm("expr1 + expr2", :CD)` threads over sums, returns sum of RPerms
- [ ] `RiemannToPerm("RiemannCD[-a,-b,-c,-d]", :CD)` raises `ArgumentError` (free indices)
- [ ] Round-trip: `PermToRiemann(RiemannToPerm(expr))` is canonically equivalent to `ToCanonical(expr)`
- [ ] `PermToRiemann` with `curvature_relations=true` replaces contracted Riemanns with Ricci

### Dependencies
Phase 2 (RPerm types).

### Estimated Effort
3 sessions (contraction extraction is non-trivial)

---

## Phase 4: Permutation-to-Invariant Lookup (PermToInv)

**Goal**: Given a canonical RPerm, look up its invariant label RInv from the database.

### Changes Required

**File: `src/XInvar.jl`**
- Add `PermToInv(rperm)` — looks up the invariant index from a loaded database
- Add `InvToPerm(rinv)` — reverse lookup (invariant → canonical permutation)
- Add internal dispatch cache: `Dict{Vector{Int}, Dict{Vector{Int}, Int}}` keyed by `case.deriv_orders` for O(1) lookup

### Algorithm
- The database (loaded in Phase 5) provides a bijection: `RInv[case, index] ↔ permutation`
- `PermToInv`: the RPerm's permutation is already in canonical form (via `RiemannToPerm`'s Butler-Portugal canonicalization); look it up directly in the dispatch table
- `InvToPerm`: direct table lookup by (case, index)

### Success Criteria
#### Automated:
- [ ] After loading database for case `[0]`: `PermToInv(kretschner_rperm)` returns correct RInv
- [ ] `InvToPerm(RInv(:CD, InvariantCase([0,0], 0), 1))` returns the canonical permutation
- [ ] All degree-2 invariants (3 total for case `[0,0]`) are correctly indexed
- [ ] Unknown permutation → clear error "permutation not found in database for case [...]"

### Dependencies
Phase 2 (RPerm/RInv types), Phase 5 (database loading — but can unit-test with small hand-built tables).

### Estimated Effort
1 session

---

## Phase 5: Database Loading and Rule Parser

**Goal**: Download, parse, and cache the Wolfram Invar database in Julia-native format.

### Changes Required

**New file: `src/InvarDB.jl`** (included by XInvar.jl)
- Add `LoadInvarDB(dir)` — loads all step-1 through step-6 rule files
- Add Maple format parser: `_read_invar_perms_maple(filename)` — parse permutation cycle notation
- Add Mathematica format parser: `_read_invar_rules_mma(filename)` — parse simplification rules
- Add database caching: serialize to JLD2 or JSON for fast reload
- Add `_download_invar_database()` — fetch from xact.es if not present locally

**File: `src/XInvar.jl`**
- Add lazy loading: database loaded on first use of `RiemannSimplify`
- Add `_invar_db_loaded::Bool` flag, cleared by `reset_state!()`

### Database Structure (from Invar.m)
```
Riemann/
  1/RInv-{case}-1         # Step 1: Permutation basis (Maple format)
  1/DInv-{case}-1         # Step 1: Dual permutation basis
  2/RInv-{case}-2         # Step 2: Cyclic identity rules (Mathematica format)
  3/RInv-{case}-3         # Step 3: Bianchi identity rules
  4/RInv-{case}-4         # Step 4: CovD commutation rules
  5_4/RInv-{case}-5       # Step 5: Dimension-dependent rules (dim=4)
  6_4/RInv-{case}-6       # Step 6: Dual reduction rules (dim=4)
```

### Parsing Strategy
- **Maple format** (Step 1): Lines like `RInv-0_0-1(1) := [{2, 3}]` → extract cycle notation, convert to Images via `TranslatePerm`
- **Mathematica format** (Steps 2-6): Lines like `RInv[{0,0},3] -> RInv[{0,0},1] - RInv[{0,0},2]` → parse as substitution rules, store as `Dict{Int, Vector{Tuple{Int, Rational{Int}}}}` (maps dependent invariant index → linear combination of independent indices)

### Success Criteria
#### Automated:
- [ ] `_read_invar_perms_maple("1/RInv-0-1")` returns 1 permutation (MaxIndex[{0}]=1)
- [ ] `_read_invar_perms_maple("1/RInv-0_0-1")` returns 3 permutations (MaxIndex[{0,0}]=3)
- [ ] `_read_invar_rules_mma("2/RInv-0_0-2")` returns cyclic identity rules
- [ ] `LoadInvarDB()` loads without error and populates dispatch tables
- [ ] Database files not present → graceful error with download instructions (not a crash)
- [ ] `reset_state!()` clears loaded database state

### Dependencies
None — standalone parser.

### Estimated Effort
2 sessions (parsing + testing across all cases)

---

## Phase 6: InvSimplify — Multi-Level Simplification

**Goal**: Implement the 6-level InvSimplify pipeline that applies pre-computed rules.

### Changes Required

**File: `src/XInvar.jl`**
- Add `InvSimplify(expr, level=6; dim=nothing)` — apply simplification rules at specified level
- Level 1: No simplification (identity)
- Level 2: Cyclic identity rules (loaded from step-2 database)
- Level 3: Bianchi identity rules (loaded from step-3 database)
- Level 4: CovD commutation rules (loaded from step-4 database)
- Level 5: Dimension-dependent rules (loaded from step-5, requires integer dimension; skipped if dim is symbolic or nothing)
- Level 6: Dual reduction rules (loaded from step-6, 4D only; skipped otherwise)

### Algorithm (from Invar.m:628-678)
```julia
function InvSimplify(expr, level::Int; dim=nothing)
    level <= 1 && return expr
    result = _apply_dispatch_rules(expr, step=2)          # cyclic
    level >= 3 && (result = _apply_dispatch_rules(result, step=3))  # Bianchi
    level >= 4 && (result = _apply_dispatch_rules(result, step=4))  # commute CovDs
    if level >= 5 && dim isa Integer
        result = _apply_dispatch_rules(result, step=5, dim=dim)     # dim-dependent
    end
    if level >= 6 && dim isa Integer && dim == 4
        result = _apply_dispatch_rules(result, step=6, dim=dim)     # dual reduction
    end
    _expand(result)
end
```

### Success Criteria
#### Automated:
- [ ] Level 2 reduces degree-2 invariants: 3 perms → correct independent count
- [ ] Level 3 further reduces via Bianchi identity
- [ ] Level 4 commutes CovD (for differential invariants)
- [ ] `InvSimplify(rinv, 2)` matches Wolfram output for all degree-2 cases
- [ ] All 47 non-dual cases: `length(independent_invs(step, case))` matches `MaxIndex` at each step
- [ ] Symbolic or `nothing` dimension → levels 5-6 skipped gracefully

### Dependencies
Phase 4 (PermToInv), Phase 5 (database).

### Estimated Effort
2 sessions

---

## Phase 7: RiemannSimplify — End-to-End Pipeline

**Goal**: Implement the user-facing `RiemannSimplify(expr, metric; level, curvature_relations)` that ties everything together.

### Changes Required

**File: `src/XInvar.jl`**
- Add `RiemannSimplify(expr, metric; level=6, curvature_relations=false)` — top-level API
- Pipeline handles sums: decompose into monomials, classify each, simplify, recombine
- Validate: raise `ArgumentError` if expression has free indices

**File: `packages/sxact/src/sxact/adapter/julia_stub.py`**
- Add `RiemannSimplify` action handler
- Add `InvSimplify` action handler

**File: `packages/sxact/src/sxact/runner/schemas/test-schema.json`**
- Add schemas for `RiemannSimplify`, `InvSimplify`

### Implementation (from Invar.m:834-839)
```julia
function RiemannSimplify(expr::String, metric::Symbol;
                         level::Int=6, curvature_relations::Bool=false)
    s = strip(expr)
    (s == "0" || isempty(s)) && return "0"

    # Validate: no free indices (must be scalar)
    _validate_scalar(s) || throw(ArgumentError("RiemannSimplify requires scalar (fully contracted) input"))

    # Thread over sums: each monomial is processed independently
    terms = _parse_scalar_monomials(s)
    results = String[]
    for (coeff, monomial) in terms
        rperm = RiemannToPerm(monomial, metric)
        rinv = PermToInv(rperm)
        simplified = InvSimplify(rinv, level; dim=_dim_of_metric(metric))
        tensor_expr = PermToRiemann(InvToPerm(simplified), metric;
                                     curvature_relations=curvature_relations)
        push!(results, _scale(coeff, tensor_expr))
    end
    ToCanonical(join(results, " + "))
end
```

### Success Criteria
#### Automated:
- [ ] `RiemannSimplify("RicciScalarCD[]", :CD)` → `"RicciScalarCD[]"` (trivial case)
- [ ] `RiemannSimplify("0", :CD)` → `"0"`
- [ ] `RiemannSimplify(kretschner + ricci_sq, :CD)` handles sum of monomials from different cases
- [ ] `RiemannSimplify(kretschner - kretschner_relabeled)` → `"0"`
- [ ] `RiemannSimplify(expr_with_free_indices)` → `ArgumentError`
- [ ] Adapter round-trip: TOML test with RiemannSimplify action passes
- [ ] `curvature_relations=true` replaces contracted Riemanns with Ricci tensors
#### Manual:
- [ ] Verify on Schwarzschild: Kretschner scalar = 48M²/r⁶ (via CTensor evaluation)

### Dependencies
Phases 3, 4, 5, 6.

### Estimated Effort
2 sessions

---

## Phase 8: Generalized CovD Commutation at Multi-Term Level

**Goal**: Extend CovD commutation to handle products of covariant derivatives on Riemann tensors (needed for differential invariants with order > 0).

### Changes Required

**File: `src/XTensor.jl`**
- Extend `CommuteCovDs` to handle nested CovD chains: ∇_a ∇_b ∇_c R → fully commuted form
- Add `SortCovDs(expr, metric)` — bring all CovDs into canonical (lexicographic) order using Riemann correction terms
- Register CovD commutation as a MultiTermIdentity (Phase 1 framework)
- Handle the case where commutation generates MORE Riemann terms that themselves need simplification

### Implementation Approach
- For each pair of adjacent CovDs that are out of canonical order, apply CommuteCovDs
- This generates Riemann correction terms → re-canonicalize via `Simplify`
- Iterate until all CovD orderings are canonical (bubble sort on CovD indices)
- This is the algorithmic equivalent of what Invar level 4 does via database rules

**Note on second Bianchi**: The second Bianchi identity ∇_{[e}R_{ab]cd} = 0 is a CONSEQUENCE of the first Bianchi + Ricci identity (CovD commutation), but deriving it algorithmically requires: (1) apply ∇_e to first Bianchi, (2) expand via Leibniz, (3) apply metric compatibility ∇g=0, (4) rearrange. This derivation is implemented explicitly, NOT assumed to "fall out naturally" from CovD sorting.

### Success Criteria
#### Automated:
- [ ] `SortCovDs("CD[-a][CD[-b][RiemannCD[-c,-d,-e,-f]]]", :CD)` produces canonical CovD ordering
- [ ] Nested 3-CovD chain correctly generates all correction terms
- [ ] Differential invariants of order 4 (case `[2]`) simplify correctly
- [ ] Second Bianchi identity derivable from first Bianchi + Ricci identity

### Dependencies
Phase 1 (identity framework), Phase 7 (integration point).

### Estimated Effort
2 sessions

---

## Phase 9: Dimension-Dependent Identities

**Goal**: Implement dimension-dependent identities that hold only in specific dimensions (level 5 of InvSimplify).

### Changes Required

**File: `src/XInvar.jl`**
- Load step-5 database rules (dimension-specific)
- Apply via `InvSimplify` level 5

### Key Principle

Dimension-dependent identities arise from the vanishing of antisymmetrizations over (dim+1) indices in a dim-dimensional manifold. In n dimensions, any totally antisymmetric tensor of rank > n vanishes identically. For the Riemann tensor:
- In 2D: Riemann is determined by the Ricci scalar (1 independent component)
- In 3D: Riemann is determined by Ricci (no Weyl tensor)
- In 4D: The generalized Kronecker delta δ^{[a₁...a₅]}_{[b₁...b₅]} = 0 provides relations among degree-3+ invariants

These identities are NOT the Gauss-Bonnet theorem (which is an integral relation). They are algebraic consequences of the dimensionality of the index space, pre-computed and stored in the step-5 database files.

### Success Criteria
#### Automated:
- [ ] In 4D: `InvSimplify(expr, 5; dim=4)` reduces invariant counts beyond what level 4 achieves
- [ ] `MaxIndex` at step 5 matches Wolfram values for all 4D cases
- [ ] Non-4D integer dimensions correctly load their dimension-specific rules
- [ ] Non-integer / symbolic dimensions → level 5 skipped, no error

### Dependencies
Phase 6 (InvSimplify framework), Phase 5 (database for step-5 files).

### Estimated Effort
1 session

---

## Phase 10: Dual Invariants and Levi-Civita Tensor

**Goal**: Handle dual (epsilon tensor) invariants — level 6 of InvSimplify, 4D only.

### Changes Required

**File: `src/XInvar.jl`**
- Add `epsilon` tensor: totally antisymmetric Levi-Civita tensor (dimension-dependent rank)
- Add `DualRInv`, `DualRPerm` types (parallel to RInv/RPerm)
- Add dual database loading (DInv files from step-1, step-2 through step-5)
- Add level-6 simplification: reduce some non-dual invariants to products of dual invariants
- Add `MaxDualIndex` table from Invar.m:455-483

### Success Criteria
#### Automated:
- [ ] `DualRInv` types constructible for all 14 dual cases
- [ ] `MaxDualIndex` for all 14 cases matches Wolfram values
- [ ] Dual database loads correctly
- [ ] Level 6 simplification in 4D produces correct independent counts
- [ ] Non-4D correctly rejects dual operations with clear message

### Dependencies
Phase 6 (InvSimplify), Phase 5 (database loading for DInv files).

### Estimated Effort
2 sessions

---

## Phase 11: Validation Benchmarks

**Goal**: End-to-end validation on physically meaningful invariants.

### Changes Required

**File: `tests/xtensor/riemann_invariants.toml`** (new)
- Kretschner scalar: R_{abcd} R^{abcd} simplification and classification
- Ricci square: R_{ab} R^{ab} classification
- Cubic invariant: R_{abcd} R^{abce} R_e^d classification
- Product of invariants: R * R_{abcd} R^{abcd} (decomposition into separate cases)
- Degree-4 through degree-7 algebraic invariant counts
- Differential invariants through order 6
- Edge case: `RiemannSimplify("0")`, free-index rejection

**File: `test/julia/test_xtensor.jl`**
- Unit tests for all Phase 1-10 functions
- Property tests: random invariant generation → simplify → verify independence
- Performance tests: verify targets from Performance Budget section

### Success Criteria
#### Automated:
- [ ] All new TOML tests pass with oracle snapshots
- [ ] Independent invariant counts match MaxIndex for cases through order 8
- [ ] Round-trip: `RiemannSimplify(PermToRiemann(InvToPerm(rinv)))` returns same invariant
- [ ] Performance: degree-2 < 10ms, degree-4 < 100ms
#### Manual:
- [ ] Schwarzschild Kretschner matches analytic result
- [ ] Kerr invariants match known values from literature

### Dependencies
All previous phases.

### Estimated Effort
2 sessions

---

## Summary: Session Breakdown

| Session | Phase | Issue | Description | Est. Lines |
|---------|-------|-------|-------------|------------|
| 1 | Phase 1 | **sxAct-x8q** | Multi-term identity framework + refactor Bianchi | ~200 |
| 2 | Phase 2 | sxAct-22s | RPerm/RInv types + MaxIndex table + InvarCases | ~150 |
| 3-5 | Phase 3 | sxAct-22s | RiemannToPerm + PermToRiemann + contraction extraction | ~400 |
| 6 | Phase 4 | sxAct-22s | PermToInv lookup | ~100 |
| 7-8 | Phase 5 | sxAct-22s | Database parser (Maple + Mathematica formats) | ~400 |
| 9-10 | Phase 6 | sxAct-22s | InvSimplify (6 levels) | ~250 |
| 11-12 | Phase 7 | sxAct-22s | RiemannSimplify end-to-end + adapter | ~300 |
| 13-14 | Phase 8 | sxAct-22s | Generalized CovD commutation | ~250 |
| 15 | Phase 9 | sxAct-22s | Dimension-dependent identities | ~100 |
| 16-17 | Phase 10 | sxAct-22s | Dual invariants + epsilon tensor | ~250 |
| 18-19 | Phase 11 | sxAct-22s | Validation benchmarks + property tests | ~200 |
| — | Buffer | — | Contingency for Phase 3/5 complexity | ~2-3 sessions |

**Total: ~19 sessions + 2-3 buffer / ~2600 lines of Julia + tests**
**At 2 sessions/day: ~10-11 working days / ~2-3 calendar weeks**
**At 1 session/day: ~19-22 working days / ~4-5 calendar weeks**

## Milestones

| Milestone | After Phase | Deliverable |
|-----------|-------------|-------------|
| **MVP (sxAct-x8q complete)** | Phase 1 | General identity framework; Bianchi via framework |
| Invariant types ready | Phase 2 | RPerm/RInv types, case classification |
| Core pipeline | Phase 7 | `RiemannSimplify` end-to-end for algebraic invariants |
| Full Invar (sxAct-22s complete) | Phase 11 | All levels, duals, benchmarks validated |

## Testing Strategy

**Following TDD per-phase:**
1. Write TOML tests defining expected behavior for each new action
2. Write Julia unit tests for each function
3. Implement minimal code to pass
4. Refactor

**Test types:**
- **Unit tests** (Julia): Each function in isolation with small hand-built cases
- **Integration tests** (TOML): End-to-end through adapter pipeline
- **Property tests**: Random invariant generation → simplify → verify MaxIndex counts
- **Regression tests**: All 185 existing TOML + 316 Julia tests must continue to pass

## Rollback Strategy

Each phase is independently committable. If a phase introduces regressions:
1. Phase 1 refactors `_bianchi_reduce!` — rollback = restore hardcoded version
2. Phases 2-10 are purely additive (in XInvar.jl) — rollback = remove the `include`, no existing code affected
3. Database (Phase 5) is external data — can be deleted without affecting existing functionality

## Recommended Session Order

**Critical path**: 1 → 2 → 3 → 5 → 4 → 6 → 7 (enables `RiemannSimplify`)
**Can parallelize**: Phase 5 (database parser) can start alongside Phase 3
**Deferrable**: Phases 8-10 (CovD commutation, dim-dependent, duals) can be deferred without blocking the core pipeline

## Architecture Decision: Database-Driven vs Algorithmic

**Decision: Database-driven (port Wolfram Invar database)**

**Rationale:**
1. The Wolfram database contains >600,000 pre-computed relations — regenerating algorithmically would require implementing the full Martín-García/Portugal algorithm from the 2008 paper
2. The database is freely available (GPL) and just needs format conversion
3. The database approach matches exactly what the original Invar does — no risk of mathematical errors from re-derivation
4. Phase 1 (identity framework) + Phase 8 (CovD commutation) provide the algorithmic foundation for cases not covered by the database

**Alternative considered: Young-projector-based multi-term canonicalization (Cadabra approach)**
- Pro: No external database dependency
- Con: Research-level implementation, higher risk of mathematical bugs, slower for high-degree cases
- Verdict: Build the framework (Phase 1) but rely on database for actual rules

## References

- Martín-García, Yllanes & Portugal (2008) — *The Invar Tensor Package* [arXiv:0802.1274]
- Li et al. (2017) — *Riemann Tensor Polynomial Canonicalization* [arXiv:1701.08487]
- Wolfram Invar source: `resources/xAct/Invar/Invar.m`
- Invar database: downloadable from xact.es/Invar/ (Riemann.tar.gz)
- Cadabra2: github.com/kpeeters/cadabra2 (Young-projector reference)
