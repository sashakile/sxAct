# Typed Expressions (TExpr)

!!! info "LLM TL;DR"
    - `@indices M a b c` creates typed index variables bound to manifold `:M`
    - `tensor(:T)` returns a `TensorHead`; apply indices to get an expression: `T[-a,-b]`
    - **Stage 2**: Full round-trip — engine functions return `TExpr` objects, not strings
    - Catches slot-count and manifold errors **at construction**, not inside the engine
    - Both APIs coexist: `ToCanonical(T[-a,-b])` and `ToCanonical("T[-a,-b]")` are equivalent

The **TExpr layer** gives you a Julia- and Python-native way to write tensor expressions
using operator overloading and indexed syntax, rather than strings.

Both APIs coexist — the string API is never removed. Pick whichever fits your workflow.

```julia
# String API (always works)
ToCanonical("RiemannCD[-a,-b,-c,-d] + RiemannCD[-a,-c,-d,-b] + RiemannCD[-a,-d,-b,-c]")

# Typed API (same result, errors caught earlier)
@indices M a b c d
Riem = tensor(:RiemannCD)
ToCanonical(Riem[-a,-b,-c,-d] + Riem[-a,-c,-d,-b] + Riem[-a,-d,-b,-c])
```

## Why use the typed API?

The string API works, but creates friction:

| Problem | String API | Typed API |
|---------|-----------|-----------|
| Wrong slot count | `"T[-a,-b,-c]"` silently malformed | `T[-a,-b,-c]` → **error at construction** |
| Wrong manifold | Mixing `:a` from M and `:i` from N undetected | Manifold checked on every `Idx` |
| Index appearing 3× | Caught deep in canonicalization | Will fail validation at tensor application |
| Discoverability | Must memorize `RiemannCD`, `RicciCD`, ... | Tab-complete on `tensor(:` |
| Composability | String concatenation for multi-step expressions | `T[-a,-b] + S[-a,-b]` is valid Julia |
| IDE support | No completions, no hover docs | Full LSP support on tensor heads and indices |

The typed layer is a **thin wrapper** — it serializes to strings, calls the same
battle-tested engine, and returns the result. There is no performance penalty for
typical expressions; the engine dominates runtime at any meaningful expression size.

---

## Quick Start (Julia)

```julia
using xAct

reset_state!()
def_manifold!(:M, 4, [:a, :b, :c, :d, :e, :f])
def_metric!(-1, "g[-a,-b]", :CD)    # creates Riemann, Ricci, Weyl, ...

# Step 1: declare index variables bound to a manifold
@indices M a b c d e f

# Step 2: get tensor handles
Riem = tensor(:RiemannCD)
Ric  = tensor(:RicciCD)
g_h  = tensor(:g)

# Step 3: write expressions
ToCanonical(Riem[-a,-b,-c,-d] + Riem[-a,-c,-d,-b] + Riem[-a,-d,-b,-c])  # "0"
ToCanonical(Riem[-a,-b,-c,-d] - Riem[-c,-d,-a,-b])                       # "0"

# Contraction
def_tensor!(:V, ["a"], :M)
V = tensor(:V)
Contract(V[a] * g_h[-a,-b])   # "V[-b]"

# Rank-0 scalar: RS[] with empty index list
RS = tensor(:RicciScalarCD)
Simplify(RS[] * g_h[-a,-b])
```

---

## Core Concepts

The typed API is built on four building blocks: index variables (`@indices`),
tensor handles (`tensor()`), covariant derivative heads (`covd()`), and arithmetic operators.

### Index variables — `@indices`

```julia
@indices M a b c d e f
```

Creates `Idx` objects bound to manifold `:M`. The macro validates that each label
is registered for that manifold at runtime.

`a` is contravariant (up); `-a` (unary minus) is covariant (down):

```julia
a           # Idx(:a, :M)  — contravariant
-a          # DnIdx        — covariant
-(-a)       # Idx(:a, :M)  — back to contravariant
```

!!! warning "Avoid shadowing index names"
    `for a in 1:10` overwrites `a`. Don't reuse index labels as loop variables.

### Tensor handles — `tensor()`

```julia
T = tensor(:T)          # registered tensor
Riem = tensor(:RiemannCD)   # auto-created by def_metric!
```

`tensor()` returns a `TensorHead` — a lightweight named handle. It is **not** a
`TExpr`; you must apply indices to get an expression:

```julia
T         # TensorHead(:T) — not usable in arithmetic
T[-a,-b]  # TTensor — valid TExpr, ready for operators
```

### Covariant derivative heads — `covd()`

```julia
def_tensor!(:phi, String[], :M)  # scalar field (rank-0)
phi = tensor(:phi)
CD = covd(:CD)
expr = CD[-a](CD[-b](phi[]))     # nabla_a nabla_b phi
CommuteCovDs(expr, "CD", "-a", "-b")   # typed overload, no manual string conversion
```

### Arithmetic

All `TExpr` subtypes support `+`, `-`, `*`, and unary `-`:

```julia
# assumes reset_state!() + def_manifold!(:M, 4, ...) + def_metric!(-1,"g[-a,-b]",:CD) already run
def_tensor!(:T, ["-a", "-b"], :M; symmetry_str="Symmetric[{-a,-b}]")
def_tensor!(:S, ["-a", "-b"], :M)
@indices M a b c
T = tensor(:T)
S = tensor(:S)

T[-a,-b] + S[-a,-b]          # TSum
T[-a,-b] * S[-c,-d]          # TProd
2 * T[-a,-b]                 # TProd with coeff=2
(1//3) * T[-a,-b]            # Rational coefficient
-(T[-a,-b])                  # TProd with coeff=-1
T[-a,-b] - S[-a,-b]          # TSum with negated term
```

!!! note "Float coefficients are not supported"
    Use `Rational{Int}` for exact results: `(1//3) * T[-a,-b]` not `0.333 * T[-a,-b]`.

---

## Validation at construction time

Errors are caught when you build expressions, not when you call the engine:

```julia
# Slot count
Riem[-a,-b,-c]       # ERROR: RiemannCD has 4 slots, got 3

# Manifold membership
def_manifold!(:N, 3, [:i, :j, :k])
@indices N i j k
Riem[-a,-b,-i,-j]    # ERROR: index i is from manifold N, slot 3 expects M

# Tensor not defined
tensor(:Undefined)   # ERROR: Tensor Undefined is not defined (was reset_state!() called?)

# Index not registered for manifold
@indices M x y       # ERROR: Index x is not registered for manifold M
```

---

## Python quick start

```python
import xact

xact.reset()
M = xact.Manifold("M", 4, ["a", "b", "c", "d", "e", "f"])
g = xact.Metric(M, "g", signature=-1, covd="CD")

# Typed index objects
a, b, c, d, e, f = xact.indices(M)

# Tensor handles
Riem = xact.tensor("RiemannCD")
V    = xact.Tensor("V", ["a"], M)
g_h  = xact.tensor("g")

# Build expressions with operators
expr = Riem[-a,-b,-c,-d] + Riem[-a,-c,-d,-b] + Riem[-a,-d,-b,-c]
xact.canonicalize(expr)  # "0"

xact.contract(V[a] * g_h[-a,-b])  # "V[-b]"

# Error at construction
xact.tensor("RiemannCD")[-a,-b,-c]  # IndexError: RiemannCD has 4 slots, got 3
```

---

## Interoperability with the string API

All engine functions accept both `String` and `TExpr`. If you pass a `TExpr`,
you get a `TExpr` back (Stage 2). If you pass a `String`, you get a `String` back.

```julia
r1 = ToCanonical(Riem[-a,-b,-c,-d] + Riem[-a,-c,-d,-b])  # TExpr result
r2 = Contract(r1)     # TExpr in, TExpr out — perfect for chaining
r3 = Simplify(r2)     # same
```

You can freely mix the two styles:

```julia
# Start typed, continue with strings
step1 = ToCanonical(Riem[-a,-b,-c,-d] + Riem[-a,-c,-d,-b] + Riem[-a,-d,-b,-c])
step2 = RiemannSimplify(step1, :CD)
```

---

## Architecture

The typed layer is a thin serialization wrapper — the engine is untouched:

```
User code          TExpr layer              Engine
---------          -----------              ------
T[-a,-b]     ->   TTensor(:T, [DnIdx..])
                       |
                  _to_string()
                       |
                  "T[-a,-b]"         ->    _parse_expression()
                                           _canonicalize_term()
                                           canonicalize_slots()  ← XPerm
                                           _apply_identities!()
                                                |
                  result string      <-    "T[-a,-b]"
```

XPerm and the core canonicalization engine operate entirely on strings and
slot positions. The typed layer never reaches into them.

---

## Roadmap

| Stage | Status | Description |
|-------|--------|-------------|
| **Stage 1** | ✅ Shipped | Typed construction, validation, serialization |
| **Stage 2** | ✅ Shipped | Typed output — engine returns `TExpr`, not `String` |
| **Stage 3** | Planned | Rich display — Unicode REPL, LaTeX for Jupyter |
| **Stage 4** | Planned | Introspection — `free_indices()`, `rank()`, `terms()`. |


For the full design rationale, see the
[TExpr design spec](https://github.com/sashakile/XAct.jl/blob/main/plans/2026-03-17-typed-expression-api.md).
