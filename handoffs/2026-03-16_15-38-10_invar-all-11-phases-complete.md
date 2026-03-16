---
date: 2026-03-16T15:38:10-03:00
git_commit: 823f0f5
branch: main
directory: /var/home/sasha/para/areas/dev/gh/sk/sxAct
issue: All Invar phases (1-11) CLOSED
status: handoff
---

# Handoff: Invar All 11 Phases Complete

## Context

Full port of Wolfram xAct's Invar module (Riemann invariant simplification) to Julia. All 11 phases from the plan at `plans/2026-03-11-multi-term-symmetry-engine.md` are now implemented and tested. The pipeline supports algebraic invariant classification, database-driven simplification at levels 1-3, CovD sorting, and dual invariant routing.

## Completed Phases

| Phase | Issue | Description | Lines | Tests |
|-------|-------|-------------|-------|-------|
| 1 | sxAct-x8q | Multi-term identity framework | ~200 | 26 |
| 2 | sxAct-04r | InvariantCase/RPerm/RInv + MaxIndex | ~300 | 385 |
| 3 | sxAct-lwb | RiemannToPerm / PermToRiemann | ~890 | +237 |
| 4 | sxAct-w50 | PermToInv / InvToPerm + dispatch cache | ~100 | +34 |
| 5 | sxAct-h85 | InvarDB parser (Maple + Mathematica) | ~500 | +138 |
| 6 | sxAct-23p | InvSimplify 6-level pipeline | ~100 | +34 |
| 7 | sxAct-6i2 | RiemannSimplify end-to-end | ~120 | +23 |
| 8 | sxAct-6e3 | SortCovDs + RicciIdentity | ~460 | 24 (XTensor) |
| 9 | sxAct-sci | Dim-dependent (already done by 5+6) | 0 | — |
| 10 | sxAct-mbj | Dual invariant routing | ~50 | +58 |
| 11 | sxAct-1gx | Validation benchmarks + parser fixes | ~200 | 648k+ |

## Invar Database Setup

The Invar database contains ~640,000 pre-computed permutation bases and simplification rules. It is **not committed** to the repo (350MB uncompressed, in `.gitignore`).

### Download and install

```bash
# Download from xact.es (40MB compressed)
cd /tmp
curl -LO http://www.xact.es/Invar/Riemann.tar.gz

# Extract into the project
cd /path/to/sxAct
tar xzf /tmp/Riemann.tar.gz -C resources/xAct/Invar/

# Verify
ls resources/xAct/Invar/Riemann/1/RInv-0-1
# Should output: resources/xAct/Invar/Riemann/1/RInv-0-1
```

### Directory structure after setup

```
resources/xAct/Invar/
├── Invar.m          # Wolfram source (reference)
├── Invar.nb         # Wolfram notebook
├── Invar.Readme
└── Riemann/         # ← Downloaded database (350MB, gitignored)
    ├── 1/           # Step 1: Permutation bases (48 RInv + 15 DInv files)
    ├── 2/           # Step 2: Cyclic identity rules
    ├── 3/           # Step 3: Bianchi identity rules
    ├── 4/           # Step 4: CovD commutation rules (polynomial format)
    ├── 5_4/         # Step 5: Dimension-dependent rules (dim=4)
    └── 6_4/         # Step 6: Dual reduction rules (dim=4)
```

### Database file formats

**Step 1 (Maple format)** — one permutation per line:
```
[[2,3],[4,5],[6,7]]:
[[2,3,5],[4,7,6]]:
```
Each line is cycle notation + trailing colon. Line number = invariant index.

**Steps 2-3 (Mathematica format)** — linear substitution rules:
```
RInv[{0,0},3] -> RInv[{0,0},2]/2
RInv[{0,0,0},9] -> -RInv[{0,0,0},5]/4+RInv[{0,0,0},8]
```

**Steps 4-6 (Mathematica format)** — polynomial substitution rules:
```
RInv[{0,0,0,0},2] -> -RInv[{0},1]^4/12+(3*RInv[{0},1]^2*RInv[{0,0},1])/4-...
```
These involve products of RInv terms across cases. **Not yet parseable** by our step-2/3 linear parser — polynomial expression support is a future enhancement.

### Using the database in Julia

```julia
using xAct

# Load the database
db = LoadInvarDB("resources/xAct/Invar")  # path to directory containing Riemann/

# Check what loaded
println(db)  # InvarDB(648k perms, 7k dual_perms, N rules, ...)

# Convert expression → canonical invariant
rperm = RiemannToPerm("RiemannCD[-a,-b,-c,-d] RiemannCD[a,b,c,d]", :g; covd=:CD)
rinv = PermToInv(rperm; db=db)
println(rinv)  # RInv(:g, InvariantCase([0,0]), N)

# Simplify at level 2 (cyclic identities)
simplified = InvSimplify(rinv, 2; db=db)

# Full pipeline
result = RiemannSimplify("RicciScalarCD[]", :g; covd=:CD, db=db)
```

### Running validation tests

The Phase 11 tests auto-detect the database and skip if not present:
```bash
julia --project=. test/julia/test_xinvar.jl
# With DB: 648k+ tests including per-perm validation
# Without DB: 771 tests (all synthetic)
```

## Test Results

| Suite | Count |
|-------|-------|
| Julia XInvar | 648,712 (with DB) / 771 (without) |
| Julia XTensor | 441/441 |
| Julia XPerm | 91/91 |
| Python | 567/567 |

## Known Limitations

1. **Steps 4-6 rules**: Polynomial expressions (`RInv[...]^2*RInv[...]`) not yet parsed. Only linear rules (steps 2-3) are loaded. This means InvSimplify levels 4-6 only work for cases that have rules in those levels.
2. **Performance at high degree**: Brute-force contraction perm canonicalization is O(8^n) for n Riemanns. Acceptable for n ≤ 7 (practical GR), slow beyond that.
3. **Database size**: 350MB uncompressed — not suitable for bundling in the package.
4. **SortCovDs**: Works at string level with custom parsers, not via the ToCanonical/Simplify loop.

## Follow-up Tasks

- `specs/2026-03-16-yachay-specification.md` — mentioned by user as follow-up
- Polynomial expression parser for step 4-6 rules
- Bundle low-order cases (≤ order 6) as Julia source for DB-free usage
- Python adapter actions for RiemannSimplify/InvSimplify/SortCovDs

## References

- Plan: `plans/2026-03-11-multi-term-symmetry-engine.md`
- Wolfram source: `resources/xAct/Invar/Invar.m`
- Database: http://www.xact.es/Invar/ (Riemann.tar.gz, 40MB)
- Paper: Martín-García et al. (2008) arXiv:0802.1274
