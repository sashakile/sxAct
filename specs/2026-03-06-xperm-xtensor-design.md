# XPerm.jl and XTensor.jl Design Spec

**Date:** 2026-03-06
**Status:** Draft (v2 — post Rule-of-5 review)
**Ticket:** sxAct-01g (Python adapter), sxAct-rl6 (xPerm epic), sxAct-ctx (xTensor epic)
**Prerequisites read:**
- `research/XACT_MIGRATION_RESEARCH.md`
- `resources/xAct/xPerm/xPerm.m` (API surface)
- `resources/xAct/xPerm/mathlink/xperm.c` (C reference implementation)
- `specs/2026-01-22-design-framework-gaps.md`
- `docs/sessions/2026-01-26-physics-math-understanding.md`

---

## 1. Scope and Goals

### What this spec covers

Two Julia modules and their Python adapter integration:

1. **`XPerm.jl`** — Permutation group library implementing Butler-Portugal tensor
   canonicalization. The algorithmic core of xAct's index canonicalization.

2. **`XTensor.jl`** — Abstract tensor algebra: manifolds, VBundles, tensors, metrics
   (including auto-created curvature tensors), and `ToCanonical` (which calls XPerm).

3. **Adapter wiring** — How `JuliaAdapter` and `PythonAdapter` route xTensor TOML
   actions to these modules.

### Targeted TOML test files (Tier 1)

This spec is designed to make the following test files pass:

| File | Key features needed |
|---|---|
| `tests/xtensor/basic_manifold.toml` | DefManifold, ManifoldQ, Dimension, VBundleQ, IndicesOfVBundle, MemberQ |
| `tests/xtensor/basic_tensor.toml` | DefTensor, TensorQ, SlotsOfTensor, MemberQ[Tensors] |
| `tests/xtensor/canonicalization.toml` | DefMetric (+ auto-curvature), ToCanonical on sym/antisym/Riemann, idempotency, "0" input |
| `tests/xtensor/curvature_invariants.toml` | Auto-curvature tensors (RiemannCovD, RicciCovD, EinsteinCovD), product expressions in ToCanonical |
| `tests/xtensor/quadratic_gravity.toml` | Mixed-variance partial-slot antisymmetric tensors, product idempotency |
| `tests/xperm/basic_symmetry.toml` | DefTensor with symmetry, ToCanonical |

### Explicitly deferred (Tier 2)

These test files require features beyond this spec's scope:

| File | Why deferred |
|---|---|
| `tests/xtensor/contraction.toml` | Requires `Contract` (index contraction), `Simplify`, `SignDetOfMetric`, metric inverse semantics (`g^{ab}g_{bc}=δ^a_c`), and the Wolfram `//` postfix operator |
| `tests/xtensor/gw_memory_3p5pn.toml` | Requires covariant derivatives, Christoffel symbols, full xTensor Phase 2 |

### What this spec does NOT cover

- Multi-term symmetries (Bianchi identity, Young projectors) — deferred; Cadabra approach per research doc.
- Covariant derivatives, Lie derivatives, metric raising/lowering — xTensor Phase 2.
- `Contract`, `Simplify`, `SignDetOfMetric` actions — Tier 2 (contraction.toml).
- xCoba (component calculations) — separate epic sxAct-l1w.
- Performance benchmarks (Layer 3) — after correctness is established.

### Guiding constraints

- **No external Julia dependencies beyond stdlib.** AbstractAlgebra.jl and Oscar.jl add
  FFI overhead; native Schreier-Sims is ~500 lines and preferable (per research doc).
- **`xperm.c` and SymPy `tensor_can.py` are reference implementations.**
  Cross-check canonical forms against both during development.
- **Niehoff 2018 shortcut.** The original Butler-Portugal has O(k!) blowup for fully
  symmetric/antisymmetric groups. Use direct sorting for `Symmetric` and `Antisymmetric`;
  reserve Butler-Portugal for `RiemannSymmetric` and general groups.
- **No ccall to `xperm.c` in production.** The C source is GPL-licensed; wrapping it
  would propagate the GPL to our binary. Build native Julia.
- **Condition evaluation lives in Python**, not Julia — see §5.

---

## 2. XPerm.jl Design

### 2.1 Permutation representation

Following xperm.c: permutations are **1-indexed image vectors** of degree `n`.

```
perm[i] = j  means point i maps to point j
identity(n) = [1, 2, 3, ..., n]
```

**Signed permutations** (needed for antisymmetric groups): extend to degree `n+2`
where positions `n+1` and `n+2` are a "sign bit" pair. A generator that changes sign
also transposes `n+1 ↔ n+2`. The canonical sign is read by checking whether `perm[n+1]
== n+1` (positive) or `perm[n+1] == n+2` (negative).

This matches xperm.c's representation exactly (see `canonical_perm_ext` signature).

```julia
const Perm = Vector{Int}       # 1-indexed, degree n (unsigned)
const SignedPerm = Vector{Int}  # 1-indexed, degree n+2; positions n+1,n+2 are sign bit
```

### 2.2 Key data structures

```julia
"""
Strong Generating Set for a permutation group G ≤ S_n.
  base[i]   — a point moved by the i-th stabilizer but fixed by all later ones.
  GS        — flat list of generators; each generator is a `Perm` (unsigned) or
              `SignedPerm` (signed) of the same degree.
  n         — degree of the physical points (1..n); generators may have degree n or n+2.
  signed    — true iff generators are signed (degree n+2); false iff unsigned (degree n).
"""
struct StrongGenSet
    base::Vector{Int}
    GS::Vector{Vector{Int}}  # Perm or SignedPerm depending on `signed`
    n::Int
    signed::Bool
end
```

```julia
"""
Schreier vector for orbit(point, generators, n).
  orbit  — sorted list of points reachable from `root` under the generators.
  nu     — length-(n) vector; nu[i] = index (1-based) into GS of the generator
           that moved point i into the orbit tree, or 0 if i ∉ orbit.
  w      — length-(n) vector; w[i] = the point from which i was reached in BFS
           (the "predecessor"), or 0 if i ∉ orbit.
  root   — the starting point of the orbit (first element of orbit).
"""
struct SchreierVector
    orbit::Vector{Int}
    nu::Vector{Int}    # length = n; nu[i] == 0 iff i ∉ orbit
    w::Vector{Int}     # length = n; w[i] == 0 iff i ∉ orbit
    root::Int
end
```

### 2.3 Algorithm: Schreier-Sims

Builds a strong generating set for a permutation group from generators.

```
schreier_sims(initbase, generators, n) → StrongGenSet
```

Primary reference: SymPy `sympy/combinatorics/tensor_can.py`, function `_SchreierSims`
— directly readable Python with the same algorithm. Secondary: xperm.c `schreier_sims`.

Algorithm sketch (Butler's book §4.4):
1. Start with `base = copy(initbase)` (extended during the process).
2. For level `i` from 1 to `length(base)`:
   a. Compute `schreier_vector(base[i], current_GS, n)` → orbit and Schreier tree.
   b. For each orbit element `γ` and each generator `g`, derive the **Schreier generator**:
      `s = trace(base[i])^(-1) · g · trace(g(base[i]))` where `trace(p)` is the
      orbit element recovered by tracing the Schreier vector from `base[i]` to `p`.
   c. **Sift** `s` through the current partial SGS. If `s` does not reduce to identity,
      it is a new generator for the next stabilizer level; extend `base` if needed.
3. Repeat until no new generators are found at any level.

The algorithm runs in O(n⁵) time in the worst case. For tensor groups (k ≤ 10 slots),
this is negligible. The Schreier-Sims algorithm guarantees a complete BSGS.

### 2.4 Algorithm: Right coset representative

```
right_coset_rep(perm, SGS, free_points) → (Perm, Int)
```

Finds the lex-minimum element of the right coset `S · perm` where `S` is generated by
`SGS`, ordered by the base. Returns `(canonical_perm, sign)`.

- For unsigned groups (`SGS.signed == false`): sign is always `+1`.
- For signed groups (`SGS.signed == true`): sign is extracted from position `n+1` of
  the resulting signed permutation — `+1` if `result[n+1] == n+1`, `-1` otherwise.

`free_points` are slot positions that receive priority in the base ordering (placed
first in the minimization). Used as a first pass in `canonical_perm` to fix free
(non-dummy) indices before dummy index canonicalization.

### 2.5 Algorithm: Double coset representative

```
double_coset_rep(perm, SGS, dummy_groups) → (Perm, Int)
```

Finds the canonical representative of the double coset `S · perm · D` where:
- `S` is the slot symmetry group (from `SGS`)
- `D` is the dummy index exchange group (generated by `dummy_groups`)

Algorithm (Portugal's papers / xperm.c `double_coset_rep`):
Sequentially assign the smallest consistent image to each slot position (in base order),
using orbit information from both S and D to determine valid candidates. Tracks sign
through the extended degree representation. Returns `(canonical_perm, sign)`.

**Dummy canonicalization is only needed for contractions (shared up/down indices).**
For Tier 1 tests, all ToCanonical calls operate on free-index expressions; dummy
canonicalization is deferred to Tier 2 (contraction.toml).

### 2.6 Main entry point: canonical_perm

```julia
canonical_perm(perm, SGS, free_points, dummy_groups) → (Perm, Int)
```

Returns `(canonical_perm, sign)` where `sign ∈ {-1, 0, +1}`:
1. Apply `right_coset_rep` to canonicalize free indices → `(p1, s1)`.
2. Apply `double_coset_rep` to canonicalize dummy indices → `(p2, s2)`.
3. Return `(p2, s1 * s2)`.

**Zero indication**: Returns `(Int[], 0)` (empty permutation, sign=0) when the
canonical form under an antisymmetric symmetry has a repeated index (e.g.,
`Antisym[a,a]`). Callers check `sign == 0` to detect this case and set the
term coefficient to zero.

### 2.7 Predefined symmetry groups

```julia
"""
Symmetric group S_k on `slots` (1-indexed positions in 1..n).
Sign is always +1. Returns an unsigned StrongGenSet (signed=false).
Generators: adjacent transpositions (slots[i], slots[i+1]) for i = 1..k-1.
"""
function symmetric_sgs(slots::Vector{Int}, n::Int) :: StrongGenSet

"""
Alternating-sign group A_k on `slots`.
Transpositions carry sign=-1. Returns a signed StrongGenSet (signed=true).
Generators: adjacent transpositions expressed as SignedPerm (degree n+2),
  each transposing n+1 ↔ n+2 as well.
"""
function antisymmetric_sgs(slots::Vector{Int}, n::Int) :: StrongGenSet

"""
Riemann symmetry group on exactly 4 slots (i,j,k,l) (1-indexed).
  Generators (all as SignedPerm of degree n+2):
    g1 = transpose slots i,j  with sign=-1  (antisym in first pair)
    g2 = transpose slots k,l  with sign=-1  (antisym in second pair)
    g3 = cycle (i,k)(j,l)     with sign=+1  (pair exchange)
  Group order = 8. Returns a signed StrongGenSet (signed=true).
"""
function riemann_sgs(slots::NTuple{4,Int}, n::Int) :: StrongGenSet
```

The Riemann group's 8 elements (as slot permutations, applied to [i,j,k,l]):

| Element | Slot image | Sign |
|---|---|---|
| identity | [i,j,k,l] | +1 |
| g1 | [j,i,k,l] | -1 |
| g2 | [i,j,l,k] | -1 |
| g1·g2 | [j,i,l,k] | +1 |
| g3 | [k,l,i,j] | +1 |
| g3·g1 | [l,k,i,j] | -1 |
| g3·g2 | [k,l,j,i] | -1 |
| g3·g1·g2 | [l,k,j,i] | +1 |

The canonical form is the one whose index labels, read left-to-right, are
lexicographically smallest (by label name, variance-stripped) among these 8 variants.

### 2.8 Shortcut: Symmetric and Antisymmetric optimization

For `Symmetric[k]` and `Antisymmetric[k]` groups, Butler-Portugal has O(k!) blowup.
Use direct sorting instead. **This shortcut is always used for these two symmetry types.**

**Canonical index comparison rule**: Two index labels are compared by stripping their
leading `-` (variance marker) and comparing the resulting label names lexicographically
as strings. E.g., `"-spa" < "-spb"` because `"spa" < "spb"`.

**For Symmetric on slots `S = [s₁, s₂, ..., sₖ]` of an n-slot tensor**:

Given the current index labels at positions `S`, sorted by the comparison rule above:
1. Extract labels at positions `S`: `vals = [indices[s₁], indices[s₂], ..., indices[sₖ]]`
2. Sort `vals` by label name (stripping `-` prefix). Let `perm_to_sort` be the sorting permutation.
3. Re-insert sorted values back into their original slot positions: `new_indices[sᵢ] = sorted_vals[i]`.
4. Indices at positions outside `S` are unchanged.
5. Sign = `+1` always.

**For Antisymmetric on slots `S`**:

Same procedure, but:
4. Compute `sign = parity(perm_to_sort)`: count inversions in `perm_to_sort`; sign = `(-1)^inversions`.
5. If any two labels at positions in `S` have the same name after stripping `-`:
   return `([], 0)` (the expression is zero).

**Re-insertion example**: Tensor T has 3 slots. Antisymmetric on slots [2, 3].
Current indices: `["-cna", "-cnc", "-cnb"]`. Extract at slots [2,3]: `["-cnc", "-cnb"]`.
Strip `-`: `["cnc", "cnb"]`. Sort → `["cnb", "cnc"]` (swap needed → 1 inversion → sign=-1).
Re-insert: slot 2 ← `-cnb`, slot 3 ← `-cnc`. Result: `["-cna", "-cnb", "-cnc"]`, sign=-1.

### 2.9 Full Butler-Portugal for Riemann and general groups

For `RiemannSymmetric` and any other group, enumerate the group elements (feasible for
small groups: Riemann has 8, typical custom groups ≤ 48) and find the canonical
(lex-min label name, variance-stripped) arrangement with its sign.

For Riemann specifically: apply all 8 group elements (§2.7 table) to the current
index arrangement, find the lex-min result, record sign.

For general groups: use Schreier-Sims + right_coset_rep as in §2.4.

### 2.10 XPerm.jl exports

```julia
module XPerm

export StrongGenSet, SchreierVector

# Permutation utilities
export identity_perm, identity_signed_perm, compose, inverse_perm
export perm_sign, is_identity, on_point, on_list, perm_equal

# Group algorithms
export schreier_vector, trace_schreier, orbit
export schreier_sims, perm_member_q, order_of_group

# Coset algorithms  (all return (Perm, Int) where Int ∈ {-1,0,+1})
export right_coset_rep, double_coset_rep, canonical_perm

# Predefined groups
export symmetric_sgs, antisymmetric_sgs, riemann_sgs

end
```

### 2.11 Slot convention

XPerm receives only integer slot positions (1-indexed). A tensor `T[-a,-b,-c]` has
slots 1, 2, 3. The mapping from index labels (`:a`, `:b`) to slot positions is
established by `XTensor` before calling XPerm; XPerm is label-agnostic.

---

## 3. XTensor.jl Design

### 3.1 Data structures

```julia
module XTensor

"""An abstract index slot: the declared label and its variance."""
struct IndexSpec
    label::Symbol    # e.g. :a   (without the '-' prefix)
    covariant::Bool  # true ↔ '-a' (covariant/down); false ↔ 'a' (contravariant/up)
end

struct ManifoldObj
    name::Symbol
    dimension::Int
    index_labels::Vector{Symbol}   # declared abstract index names (without '-')
end

struct VBundleObj
    name::Symbol          # e.g. :TangentM
    manifold::Symbol
    index_labels::Vector{Symbol}
end

"""
Describes the permutation symmetry of a tensor's slot group.
  type  — one of: :Symmetric, :Antisymmetric, :RiemannSymmetric, :NoSymmetry
  slots — 1-indexed positions (within this tensor's slot list) that the symmetry acts on.
          For :RiemannSymmetric, exactly 4 elements.
          For :NoSymmetry, empty.
"""
struct SymmetrySpec
    type::Symbol
    slots::Vector{Int}
end

"""A fully defined tensor object."""
struct TensorObj
    name::Symbol
    slots::Vector{IndexSpec}   # declared slot list; defines rank and default variances
    manifold::Symbol
    symmetry::SymmetrySpec
end

struct MetricObj
    name::Symbol
    manifold::Symbol
    covd::Symbol     # name of auto-created covariant derivative (e.g. :CD)
    signdet::Int     # +1 (Riemannian) or -1 (Lorentzian)
end
```

### 3.2 Global state

Each test file gets a fresh context via `reset_state!()` called on teardown:

```julia
const _manifolds = Dict{Symbol, ManifoldObj}()
const _vbundles  = Dict{Symbol, VBundleObj}()
const _tensors   = Dict{Symbol, TensorObj}()
const _metrics   = Dict{Symbol, MetricObj}()

const Manifolds  = Symbol[]   # ordered list of defined manifold names
const Tensors    = Symbol[]   # ordered list of defined tensor names
const VBundles   = Symbol[]
```

**Note**: These dicts are module-level for juliacall access. External callers use the
accessor functions exported in §3.5 — do **not** export or directly access the
underscore-prefixed dicts.

### 3.3 Action implementations

#### `def_manifold!(name, dim, index_labels) → ManifoldObj`

```
Inputs:
  name         : Symbol or String — the manifold name (e.g. "Bm4" or :Bm4)
  dim          : Int — manifold dimension
  index_labels : Vector{String} — declared abstract index labels (e.g. ["bma","bmb"])

Steps:
  1. Normalise: name → Symbol, index_labels → Vector{Symbol} (strip '-' if present)
  2. Error if name ∈ _manifolds: throw("Manifold $name already defined")
  3. Create ManifoldObj(name, dim, index_labels)
  4. Create VBundleObj(Symbol("Tangent"*string(name)), name, index_labels)
     — auto-creates the tangent VBundle, e.g. :TangentBm4
  5. Register in _manifolds, _vbundles; push to Manifolds, VBundles
  6. Return the ManifoldObj
```

#### `def_tensor!(name, index_specs, manifold; symmetry_str=nothing) → TensorObj`

```
Inputs:
  name        : String — tensor name (e.g. "Bts")
  index_specs : Vector{String} — slot specs from TOML, e.g. ["-bta","-btb"] or ["bta"]
  manifold    : String — manifold name
  symmetry_str: String|nothing — Wolfram symmetry string, e.g. "Symmetric[{-bta,-btb}]"

Steps:
  1. Parse each spec into IndexSpec: strip '-' → covariant=true; else covariant=false
  2. Parse symmetry_str into SymmetrySpec (see §3.4 symmetry parser)
  3. Validate: each slot label must belong to the manifold's VBundle index_labels
     (or its TangentVBundle) — throw if not found
  4. Register TensorObj in _tensors; push to Tensors
  5. Return TensorObj
```

#### `def_metric!(signdet, metric_expr, covd_name) → MetricObj`

```
Inputs:
  signdet    : Int — +1 or -1
  metric_expr: String — e.g. "Cng[-cna,-cnb]"
  covd_name  : String — covariant derivative name, e.g. "Cnd"

Steps:
  1. Parse metric_expr: extract tensor name "Cng" and slot specs ["-cna","-cnb"]
  2. Register metric tensor via def_tensor!(name, slots, manifold,
       symmetry_str="Symmetric[{...}]") — a symmetric rank-2 covariant tensor
  3. Create MetricObj and register in _metrics
  4. AUTO-CREATE curvature tensors (see §3.4 below)
  5. Return MetricObj
```

#### Auto-created curvature tensors from `def_metric!`

When `def_metric!("Cnd", ...)` is called with `covd_name = "Cnd"` and manifold `M`
having indices `[i1, i2, i3, i4, ...]`, register the following tensors automatically.
Names are formed by appending the covd name to the standard name:

| Auto-tensor | Name pattern | Slots | Symmetry |
|---|---|---|---|
| Riemann curvature | `Riemann{CovD}` | `[-i1,-i2,-i3,-i4]` | `RiemannSymmetric[{-i1,-i2,-i3,-i4}]` |
| Ricci tensor | `Ricci{CovD}` | `[-i1,-i2]` | `Symmetric[{-i1,-i2}]` |
| Ricci scalar | `RicciScalar{CovD}` | `[]` (scalar) | `NoSymmetry` |
| Einstein tensor | `Einstein{CovD}` | `[-i1,-i2]` | `Symmetric[{-i1,-i2}]` |

Example: `covd_name = "Cnd"` → creates `RiemannCnd`, `RicciCnd`, `RicciScalarCnd`,
`EinsteinCnd`. `covd_name = "CID"` → `RiemannCID`, `RicciCID`, `RicciScalarCID`,
`EinsteinCID`.

These tensors use the first four declared manifold indices for their slots. The
Riemann tensor's canonical slot mapping: slots 1..4 correspond to index labels
`[i1, i2, i3, i4]` = first four elements of `manifold.index_labels`.

**Error**: if the manifold has fewer than 4 declared indices, Riemann and Einstein
tensors are not registered; Ricci and RicciScalar still are.

#### `ToCanonical(expression::String) → String`

Main canonicalization entry point. See §3.6 for the full pipeline.

Returns `"0"` if all terms cancel, otherwise the canonical sum/product string.
On parse error, throws a descriptive error (propagated as `Result(status="error", ...)`
by the adapter).

#### `Evaluate(expression::String)` — **NOT a Julia function**

The `Evaluate` and `Assert` actions are handled entirely in the Python adapter layer
(§5), not in Julia. There is no Julia `evaluate_condition` function. See §5.

### 3.4 Symmetry string parser

Parses a Wolfram symmetry string into `SymmetrySpec`.

```
symmetry_str = "Symmetric[{-bta,-btb}]"
             | "Antisymmetric[{-bta,-btb,-btc}]"
             | "RiemannSymmetric[{-bta,-btb,-btc,-btd}]"

Steps:
  1. Regex match: `^(Symmetric|Antisymmetric|RiemannSymmetric)\[\{([^}]*)\}\]$`
  2. Extract type name → :Symmetric / :Antisymmetric / :RiemannSymmetric
  3. Extract comma-split labels, strip whitespace, strip leading '-'
     → label_names: Vector{String}
  4. For each label_name, find its 1-based position in the TensorObj.slots list
     by matching label (ignoring variance — symmetry labels must match slot label names)
     → slot_positions: Vector{Int}
  5. Validate: RiemannSymmetric must have exactly 4 positions
  6. Return SymmetrySpec(type, slot_positions)

Error cases:
  - Label not found in tensor's declared slots: throw("Index label $lbl not in tensor $name")
  - RiemannSymmetric with ≠ 4 labels: throw("RiemannSymmetric requires exactly 4 slots")
  - Empty slot list ({}): treated as NoSymmetry
```

### 3.5 XTensor.jl exports

```julia
module XTensor

# Type exports (for juliacall inspection)
export ManifoldObj, VBundleObj, TensorObj, MetricObj, IndexSpec, SymmetrySpec

# State management
export reset_state!

# Def functions (snake_case; Julia convention for mutating functions)
export def_manifold!, def_tensor!, def_metric!

# Accessor functions (use these, not the underscore dicts)
export get_manifold, get_tensor, get_vbundle, get_metric
export list_manifolds, list_tensors, list_vbundles

# Query predicates (Wolfram-named, for direct use by _wl_to_jl translator)
export ManifoldQ, TensorQ, VBundleQ, MetricQ
export Dimension, IndicesOfVBundle, SlotsOfTensor
export MemberQ          # MemberQ(collection_sym::Symbol, name::Symbol) → Bool
                        # where collection_sym ∈ {:Manifolds, :Tensors, :VBundles}

# Canonicalization
export ToCanonical

end
```

Accessor implementations:
```julia
get_manifold(name::Symbol) = get(_manifolds, name, nothing)
get_tensor(name::Symbol)   = get(_tensors, name, nothing)
list_manifolds()           = copy(Manifolds)  # returns a copy, not the live array

ManifoldQ(s::Symbol) = haskey(_manifolds, s)
TensorQ(s::Symbol)   = haskey(_tensors, s)
VBundleQ(s::Symbol)  = haskey(_vbundles, s)
Dimension(s::Symbol) = _manifolds[s].dimension  # throws if not found
MemberQ(collection::Symbol, s::Symbol) =
    collection == :Manifolds ? s ∈ Manifolds :
    collection == :Tensors   ? s ∈ Tensors   :
    collection == :VBundles  ? s ∈ VBundles  :
    false
```

### 3.6 State reset

```julia
function reset_state!()
    empty!(_manifolds); empty!(_vbundles); empty!(_tensors); empty!(_metrics)
    empty!(Manifolds); empty!(Tensors); empty!(VBundles)
end
```

---

## 4. Tensor Expression Parser and ToCanonical Pipeline

### 4.1 Grammar

The parser handles sums and products of tensor monomials with integer coefficients.

```
expr     ::= '0'                            # bare zero: special case
           | term (addop term)*

addop    ::= '+' | '-'

term     ::= coeff? monomial
coeff    ::= '-'                            # bare minus = coefficient -1
           | integer                        # e.g. "2" = coefficient 2
           | '-' integer                    # e.g. "-2"
           | integer '*'?                   # "2*" also accepted (drop the *)

monomial ::= factor+                        # one or more tensor calls (juxtaposition = product)

factor   ::= name '[' index_list ']'        # a single tensor call

index_list ::= index (',' index)*
index    ::= '-'? name                      # '-name' = covariant, 'name' = contravariant
```

**Parser output**: `Vector{TermAST}` where:
```julia
struct TermAST
    coeff::Int                         # ±1, ±2, …
    factors::Vector{FactorAST}         # the tensors in this product monomial
end
struct FactorAST
    tensor_name::Symbol
    indices::Vector{String}            # raw index strings, e.g. ["-cna", "cnb"]
end
```

**Special cases**:
- Input `"0"` → return `"0"` immediately (no parsing needed).
- Input `""` → return `"0"`.
- Bare minus `"-T[...]"` → coeff = -1.
- No coeff → coeff = +1.

### 4.2 Canonicalization pipeline

Given parsed `terms::Vector{TermAST}`:

```
For each term in terms:
  1. Initialise running_sign = term.coeff  (may be ±1 or ±2 etc.)
  2. For each factor f in term.factors:
     a. Look up TensorObj t = get_tensor(f.tensor_name)
        If not found: throw("Unknown tensor: $name")
     b. Extract current index labels: `current = f.indices`  (strings like "-cna")
     c. Apply symmetry shortcut or Butler-Portugal:
          (canonical_indices, factor_sign) = canonicalize_factor(current, t.symmetry)
        where:
          - For :NoSymmetry: canonical_indices = current, factor_sign = +1
          - For :Symmetric:  sort (§2.8 shortcut), factor_sign = +1
          - For :Antisymmetric: sort + parity (§2.8 shortcut), factor_sign = parity
          - For :RiemannSymmetric: enumerate 8 group elements (§2.7 table), pick lex-min
     d. If factor_sign == 0: this term is zero; set running_sign = 0; break inner loop
     e. running_sign *= factor_sign
     f. Replace f.indices with canonical_indices
  3. If running_sign == 0: discard this term (it is zero).
  4. term.coeff = running_sign; term.factors now have canonical index ordering.

Collect like terms:
  Key = tuple of (tensor_name, frozen_indices) for each factor in the monomial,
        in the order they appear (products are NOT reordered between collection passes).
  Accumulate: coeff_sum[key] += term.coeff
  Drop entries where coeff_sum[key] == 0.

If coeff_sum is empty: return "0"
Otherwise: serialize (see §4.3)
```

**Idempotency**: A canonical expression fed back to `ToCanonical` produces the same
output, because: (1) slot-canonicalization is idempotent (already canonical → same
output); (2) like-term collection is idempotent; (3) serialization is deterministic.

### 4.3 Serialization

Produce a deterministic Wolfram-style string from `coeff_sum`:

```
Sort terms by key (lexicographic on the key tuple).
For each (key, coeff) in sorted order:
  monomial_str = join(["$name[$idx_str]" for (name,idxs) in key],  " ")
                 where idx_str = join(idxs, ",")
  If coeff == 1:  emit monomial_str
  If coeff == -1: emit "-" * monomial_str
  If coeff > 1:   emit "$coeff $monomial_str"
  If coeff < -1:  emit "$coeff $monomial_str"
Join terms with " + " / " - " as appropriate (handling leading sign).
```

**Example output for sum**: `"Cns[-cna,-cnb]"`
**Example for product**: `"RiemannCID[-cia,-cib,-cic,-cid] RiemannCID[cia,cib,cic,cid]"`

### 4.4 Canonical label comparison

Throughout: index labels are compared for ordering by:
1. Strip leading `-` to get the bare label name.
2. Compare bare label names as ASCII strings (`<`).

Variance (`-` prefix / covariant vs contravariant) does **not** affect the ordering.
This means `"-spa"` and `"spa"` compare as equal-position names (same bare label `spa`).
If both a covariant and contravariant version of the same label appear in the same
symmetry group's slots, this is a mixed-variance symmetric group — which is unusual
and not tested in Tier 1; treat the `-` prefix as a tiebreaker if bare names are equal.

---

## 5. Condition Evaluation — Python Layer

The `Evaluate` and `Assert` TOML actions evaluate Wolfram-like condition strings
**entirely in the Python adapter** using the existing `_wl_to_jl` → `seval` path.
There is no separate Julia `evaluate_condition` function.

### 5.1 Strategy

```
Assert(condition_str):
  1. condition_str has already had $bindings substituted by the runner.
  2. Apply _wl_to_jl(condition_str) → julia_str
     Translates: f[x] → f(x), {a,b} → [a,b], === → ==, True → true, False → false
  3. jl.seval(julia_str) → val
     The Julia expression executes in Main scope, where:
       - XTensor predicates (ManifoldQ, TensorQ, etc.) are imported via 'using .XTensor'
       - DefManifold-bound names (Bm4, etc.) are accessible as Main.Bm4 (see §6.2)
  4. passed = (str(val).strip().lower() == "true")
  5. Return Result(status="ok", repr="True") if passed,
          Result(status="error", repr=str(val), error=message) if not
```

### 5.2 Known `_wl_to_jl` gaps to fix

Before adapter implementation, extend `_wl_to_jl` to handle:

| Wolfram pattern | Julia output | Example |
|---|---|---|
| `SubsetQ[A, B]` | `issubset(B, A)` | `SubsetQ[IndicesOfVBundle[X], {a,b}]` |
| `expr // f` | `f(expr)` | `($r) // ToCanonical` → `ToCanonical($r)` |
| `$Name` (dollar-prefix) | strip `$` → look up in XTensor | `$DaggerCharacter` → `DaggerCharacter` |

The `//` rewrite should be applied **before** other translations (it restructures the
expression tree).

### 5.3 Evaluate action

`Evaluate(expression_str)` similarly runs `_wl_to_jl` → `seval` and returns the repr.
Used to store intermediate expressions (e.g. `store_as = "expr"` in contraction.toml).
For Tier 1 tests, `Evaluate` expressions are side-effect-free queries.

---

## 6. Adapter Integration

### 6.1 Julia module loading

`XPerm.jl` and `XTensor.jl` live in `src/julia/`. Both are loaded once, lazily, on
first xTensor action. Extend `src/sxact/xcore/_runtime.py`:

```python
_xtensor_loaded = False

def get_xtensor():
    global _xtensor_loaded
    if _xtensor_loaded:
        return
    jl = get_julia()
    julia_dir = Path(__file__).parents[3] / "julia"
    jl.seval(f'include("{julia_dir}/XPerm.jl")')
    jl.seval('using .XPerm')
    jl.seval(f'include("{julia_dir}/XTensor.jl")')
    jl.seval('using .XTensor')
    _xtensor_loaded = True
```

### 6.2 Adapter symbol binding

When `DefManifold("Bm4", ...)` is called, after registering in XTensor, the adapter
binds the Julia name `Bm4` in `Main` scope so that `Assert` conditions like
`ManifoldQ(Bm4)` resolve it:

```python
jl.seval(f'XTensor.def_manifold!(:{name}, {dim}, {idxs})')
jl.seval(f'Main.{name} = XTensor.get_manifold(:{name})')
```

Similarly for `DefTensor`:
```python
jl.seval(f'XTensor.def_tensor!(:{name}, ...)')
jl.seval(f'Main.{name} = XTensor.get_tensor(:{name})')
```

**Isolation note**: `Main.Bm4` persists after teardown (Julia cannot unbind module
globals). This is acceptable because:
- After `reset_state!()`, `ManifoldQ(:Bm4)` returns `false` (registry cleared).
- The next `DefManifold("Bm4", ...)` rebinds `Main.Bm4` to the new `ManifoldObj`.
- Stale leaks are prevented by the convention that each TOML file uses unique
  name prefixes (e.g. `Bm2`, `Bm3`, `Bm4`; `Cnm`, `Conm`).
- **Enforced note**: add a check in `def_manifold!` that warns (but does not error)
  if a name is re-registered after a `reset_state!` call without a prior definition
  in the current context, to catch accidental cross-file leaks during development.

### 6.3 JuliaAdapter xTensor dispatch

```python
_XTENSOR_ACTIONS = frozenset(
    {"DefManifold", "DefMetric", "DefTensor", "ToCanonical", "Evaluate", "Assert"}
)

def execute(self, ctx, action, args):
    if action not in self.supported_actions():
        raise ValueError(f"Unknown action: {action!r}")
    self._ensure_ready()
    get_xtensor()  # lazy load

    if action == "DefManifold":
        name = args["name"]
        dim  = args["dimension"]
        idxs = "[" + ", ".join(f':{i}' for i in args["indices"]) + "]"
        self._jl.seval(f'XTensor.def_manifold!(:{name}, {dim}, {idxs})')
        self._jl.seval(f'Main.eval(:(${name} = XTensor.get_manifold(:${name})))')
        return Result(status="ok", type="Handle", repr=name, normalized=name)

    if action == "DefTensor":
        name     = args["name"]
        idx_strs = '["' + '","'.join(args["indices"]) + '"]'
        manifold = args["manifold"]
        sym_str  = args.get("symmetry") or ""
        sym_arg  = f'symmetry_str="{_jl_escape(sym_str)}"' if sym_str else ""
        self._jl.seval(
            f'XTensor.def_tensor!(:{name}, {idx_strs}, :{manifold}; {sym_arg})'
        )
        self._jl.seval(f'Main.eval(:(${name} = XTensor.get_tensor(:${name})))')
        return Result(status="ok", type="Handle", repr=name, normalized=name)

    if action == "DefMetric":
        signdet    = args["signdet"]
        metric_str = _jl_escape(args["metric"])
        covd       = args["covd"]
        self._jl.seval(
            f'XTensor.def_metric!({signdet}, "{metric_str}", :{covd})'
        )
        return Result(status="ok", type="Handle", repr=args["metric"],
                      normalized=args["metric"])

    if action == "ToCanonical":
        expr   = _jl_escape(args["expression"])
        result = self._jl.seval(f'XTensor.ToCanonical("{expr}")')
        raw    = str(result)
        return Result(status="ok", type="Expr", repr=raw,
                      normalized=_normalize(raw))

    if action in ("Evaluate", "Assert"):
        return self._execute_expr_or_assert(action, args)
```

`_jl_escape(s)`: escapes backslashes and double-quotes in `s` for Julia string literals.

```python
def _jl_escape(s: str) -> str:
    return s.replace('\\', '\\\\').replace('"', '\\"')
```

### 6.4 Error handling

All Def failures (unknown manifold, duplicate name, bad symmetry spec) are caught
by the adapter and returned as:

```python
except Exception as exc:
    return Result(
        status="error",
        type="",
        repr="",
        normalized="",
        error=str(exc),
    )
```

This preserves the existing `Result` envelope contract.

### 6.5 PythonAdapter

`PythonAdapter` routes xTensor actions through the same Julia XTensor module as
`JuliaAdapter`. State is shared within a process; both adapters call `reset_state!()`
on teardown. This is acceptable for Tier 1 sequential test runs.

Remove `_XTENSOR_ACTIONS` from the error-return set in `python_adapter.py` and add the
same dispatch logic as §6.3.

---

## 7. Worked Examples

### Example 1: Symmetric tensor swap

Input: `"Cns[-cna,-cnb] - Cns[-cnb,-cna]"`
Tensor `Cns`: `SymmetrySpec(:Symmetric, [1,2])`.

Parse: `[(coeff=+1, [:Cns,["-cna","-cnb"]]), (coeff=-1, [:Cns,["-cnb","-cna"]])]`

Term 1: sort `["-cna","-cnb"]` → labels `["cna","cnb"]` → already sorted → canonical `["-cna","-cnb"]`, sign=+1.
Term 2: sort `["-cnb","-cna"]` → labels `["cnb","cna"]` → swap to `["cna","cnb"]` → canonical `["-cna","-cnb"]`, sign=+1 (Symmetric).
Result terms: `(+1, ["-cna","-cnb"])` and `(-1 * +1, ["-cna","-cnb"])`.
Collect: key=`(:Cns,["-cna","-cnb"])` → coeff=`+1+(-1)=0` → dropped.
Output: `"0"` ✓

### Example 2: Antisymmetric tensor

Input: `"Cna[-cna,-cnb] + Cna[-cnb,-cna]"`
Tensor `Cna`: `SymmetrySpec(:Antisymmetric, [1,2])`.

Term 1: `["-cna","-cnb"]` → labels `["cna","cnb"]` → sorted, 0 inversions → sign=+1.
Term 2: `["-cnb","-cna"]` → labels `["cnb","cna"]` → 1 inversion → sign=-1. Canonical: `["-cna","-cnb"]`.
Collect: `+1 + (+1)*(-1) = 0`. Output: `"0"` ✓

### Example 3: Riemann first-pair antisymmetry

Input: `"RiemannCnd[-cna,-cnb,-cnc,-cnd] + RiemannCnd[-cnb,-cna,-cnc,-cnd]"`
Tensor `RiemannCnd`: `SymmetrySpec(:RiemannSymmetric, [1,2,3,4])`.

Term 1: arrange `(-cna,-cnb,-cnc,-cnd)`. Enumerate 8 elements of Riemann group;
  canonical (lex-min bare labels): `(cna,cnb,cnc,cnd)` achieved by identity → sign=+1.

Term 2: arrange `(-cnb,-cna,-cnc,-cnd)`. Apply all 8 elements:
  - identity: `(cnb,cna,cnc,cnd)` — not lex-min
  - g1=(1,2)↔sign=-1: `(cna,cnb,cnc,cnd)` — lex-min! → sign=-1
  Canonical: `(-cna,-cnb,-cnc,-cnd)`, sign=-1.

Collect: `(+1) + (+1)*(-1) = 0`. Output: `"0"` ✓

### Example 4: Kretschner product (curvature_invariants.toml)

Input:
```
"RiemannCID[-cia,-cib,-cic,-cid] RiemannCID[cia,cib,cic,cid]
 - RiemannCID[-cic,-cid,-cia,-cib] RiemannCID[cic,cid,cia,cib]"
```

Term 1: product of two factors, coeff=+1.
  Factor 1: `R[-cia,-cib,-cic,-cid]` → labels `(cia,cib,cic,cid)` → already lex-min under Riemann group → canonical, sign=+1.
  Factor 2: `R[cia,cib,cic,cid]` → contravariant, bare labels `(cia,cib,cic,cid)` → lex-min → canonical, sign=+1.
  Term 1 canonical: `(+1)*(+1)*(+1) = +1`. Monomial: `R[-cia,-cib,-cic,-cid] R[cia,cib,cic,cid]`.

Term 2: product of two factors, coeff=-1.
  Factor 1: `R[-cic,-cid,-cia,-cib]` → labels `(cic,cid,cia,cib)`. Enumerate Riemann group:
    - g3=(1,3)(2,4) with sign=+1: slots become `(cia,cib,cic,cid)` → lex-min → sign=+1.
  Factor 2: `R[cic,cid,cia,cib]` → same permutation, sign=+1. Canonical: `R[cia,cib,cic,cid]`.
  Term 2 canonical: `(-1)*(+1)*(+1) = -1`. Monomial: `R[-cia,-cib,-cic,-cid] R[cia,cib,cic,cid]`.

Collect: key=`(R,[-cia,-cib,-cic,-cid]),(R,[cia,cib,cic,cid])` → coeff `+1+(-1)=0`.
Output: `"0"` ✓

### Example 5: Mixed-rank sum (idempotency test)

Input: `"Cns[-cna,-cnb] + Cnv[cna]"`

Two different tensors, no shared indices. Each has NoSymmetry or Symmetric.
- `Cns[-cna,-cnb]` → Symmetric → canonical already, sign=+1.
- `Cnv[cna]` → NoSymmetry → unchanged, sign=+1.

Collect: two distinct keys, each coeff=1.
Serialize: `"Cns[-cna,-cnb] + Cnv[cna]"` (sorted by key).

Second application of ToCanonical on `"Cns[-cna,-cnb] + Cnv[cna]"`: identical output.
Idempotency holds ✓

---

## 8. File Layout

```
src/julia/
├── XCore.jl        # existing
├── XPerm.jl        # NEW: Schreier-Sims + Butler-Portugal + shortcuts
├── XTensor.jl      # NEW: manifolds, tensors, metrics, ToCanonical
└── test/
    ├── runtests.jl               # existing XCore tests
    ├── test_xperm.jl             # NEW: XPerm unit + property tests
    └── test_xtensor.jl           # NEW: XTensor unit + integration tests

src/sxact/
├── xcore/          # existing
└── adapter/
    ├── julia_stub.py   # extended with xTensor dispatch
    └── python_adapter.py  # extended with xTensor dispatch

tests/
└── unit/
    ├── test_xperm_julia.py     # NEW: XPerm via juliacall
    └── test_xtensor_julia.py   # NEW: XTensor via juliacall adapter actions
```

---

## 9. Implementation Order

1. **XPerm.jl — permutation utilities**: `identity_perm`, `compose`, `inverse_perm`,
   `perm_sign`, `on_point`, `on_list`.
2. **XPerm.jl — Schreier-Sims**: `schreier_vector`, `trace_schreier`, `orbit`,
   `schreier_sims`, `perm_member_q`.
3. **XPerm.jl — shortcuts**: `symmetric_sgs` + sort shortcut, `antisymmetric_sgs`
   + sort+parity shortcut.
4. **XPerm.jl — Riemann**: `riemann_sgs`, 8-element enumeration canonicalization.
5. **Julia tests `test_xperm.jl`**: unit tests for all XPerm functions; verify
   worked examples 1-3 above at the Julia level.
6. **XTensor.jl — state and Def functions**: `ManifoldObj`, `TensorObj`, `MetricObj`,
   `def_manifold!`, `def_tensor!`, `def_metric!` (with auto-curvature tensors),
   `reset_state!`, all accessor/query exports.
7. **Julia tests (XTensor state)**: `test_xtensor.jl` for DefManifold, DefTensor,
   DefMetric, ManifoldQ, TensorQ, Dimension, MemberQ, VBundleQ, IndicesOfVBundle.
8. **XTensor.jl — expression parser**: grammar §4.1, TermAST/FactorAST.
9. **XTensor.jl — ToCanonical pipeline**: §4.2 pipeline + §4.3 serializer.
10. **Julia tests (ToCanonical)**: worked examples 1-5; idempotency invariant;
    "0" input; product expressions.
11. **Extend `_wl_to_jl`**: add `SubsetQ`, `//`, `$` prefix (§5.2).
12. **Adapter wiring**: update `JuliaAdapter` and `PythonAdapter` (§6.3-6.5).
13. **Python pytest**: `test_xtensor_julia.py` — exercise all 6 adapter actions
    against the Tier 1 TOML files using mock-oracle mode.
14. **Regression**: `uv run pytest tests/` — all 531+ existing tests still pass.

---

## 10. Open Questions / Risks

| Question | Risk | Mitigation |
|---|---|---|
| Symbol binding isolation | Stale `Main.X` leaks if TOML files reuse names | Convention: unique prefix per TOML file; dev-mode warning in `def_manifold!` |
| Riemann group enumeration performance | n=4 is trivial (8 elements); larger groups need BP | Only Riemann uses enumeration; all other groups use shortcuts or BP via Schreier-Sims |
| Mixed-variance symmetry groups | `Antisymmetric[{qga,-qgb}]` — one up, one down in the same symmetry group | Strip variance for comparison (bare label names only); this works for partial-slot cases tested |
| Product term ordering for collection | `T1 T2` and `T2 T1` are different keys | Don't reorder factors — products with shared contracted indices are NOT commutative; rely on canonical ordering of each factor's slots to make matching terms identical before collection |
| xperm.c GPL licence | ccall to C binary propagates GPL | Build native Julia; do not ccall xperm.c |
| `evaluate_condition` complex patterns | Missing patterns in `_wl_to_jl` for new query types | §5.2 lists the known gaps; add as tests reveal them |

---

## 11. Acceptance Criteria

### XPerm.jl

- [ ] `symmetric_sgs` + sort shortcut: canonicalizes Symmetric tensors; sign always +1.
- [ ] `antisymmetric_sgs` + sort shortcut: canonicalizes Antisymmetric tensors; sign = parity; returns `([], 0)` for repeated indices.
- [ ] Partial-slot antisymmetric (slots not contiguous): values re-inserted at correct slot positions.
- [ ] `riemann_sgs` + 8-element enumeration: canonicalizes Riemann tensors; worked example 3 passes at Julia level.
- [ ] `schreier_sims` builds a valid BSGS (verified by `perm_member_q` on all group elements).
- [ ] Julia tests in `test_xperm.jl` pass: `julia --project=src/julia src/julia/test/runtests.jl`.

### XTensor.jl

- [ ] `def_manifold!` + queries: `ManifoldQ`, `Dimension`, `VBundleQ`, `IndicesOfVBundle`, `MemberQ[Manifolds,X]`.
- [ ] `def_tensor!` parses symmetry strings for all three symmetry types.
- [ ] `def_metric!` auto-creates `RiemannCovD`, `RicciCovD`, `EinsteinCovD` with correct symmetries.
- [ ] `ToCanonical("0")` returns `"0"`.
- [ ] `ToCanonical` passes worked examples 1-5 at Julia level.
- [ ] `ToCanonical` is idempotent: `ToCanonical(ToCanonical(e)) == ToCanonical(e)` for all Tier 1 expressions.
- [ ] Julia tests in `test_xtensor.jl` pass.

### Adapter wiring

- [ ] `xact-test run --adapter julia tests/xtensor/basic_manifold.toml --oracle-mode snapshot` passes (with pre-generated snapshot).
- [ ] `xact-test run --adapter julia tests/xtensor/basic_tensor.toml --oracle-mode snapshot` passes.
- [ ] `xact-test run --adapter julia tests/xtensor/canonicalization.toml --oracle-mode snapshot` passes.
- [ ] `xact-test run --adapter julia tests/xtensor/curvature_invariants.toml --oracle-mode snapshot` passes.
- [ ] `xact-test run --adapter julia tests/xtensor/quadratic_gravity.toml --oracle-mode snapshot` passes.
- [ ] `xact-test run --adapter julia tests/xperm/basic_symmetry.toml --oracle-mode snapshot` passes.
- [ ] `uv run pytest tests/unit/test_xtensor_julia.py` passes (mock-oracle, no live Wolfram).
- [ ] `uv run pytest tests/` — all existing tests still pass (no regressions).

### Out of scope for Tier 1

- [ ] `tests/xtensor/contraction.toml` — deferred (requires `Contract`, `Simplify`, metric semantics).
- [ ] `tests/xtensor/gw_memory_3p5pn.toml` — deferred (Phase 2 xTensor).
