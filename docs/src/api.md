# API Reference (Julia)

## Modules

```@docs
xAct
xAct.XCore
xAct.XPerm
xAct.XTensor
xAct.XInvar
xAct.TExprLayer
```

## Functions and Types

```@autodocs
Modules = [xAct, xAct.XCore, xAct.XPerm, xAct.XTensor, xAct.XInvar, xAct.TExprLayer]
Order = [:function, :type, :constant]
```

---

## Typed Expression API (`TExprLayer`)

The `TExprLayer` module provides a typed, validated expression layer on top of the string-based engine API.

!!! note "Stage 1 limitation"
    In Stage 1, engine functions accept `TExpr` inputs but still return `String`.
    Full round-trip (`TExpr` → engine → `TExpr`) is planned for Stage 2.

### Index Types

```julia
# Declare index variables bound to manifold M
def_manifold!(:M, 4, [:a, :b, :c, :d])
@indices M a b c d
# a = Idx(:a, :M), b = Idx(:b, :M), ...

# Covariant (down) index via negation
-a   # DnIdx wrapping a
--a  # back to Idx (identity)
```

| Type | Description |
| :--- | :--- |
| `Idx(label, manifold)` | Contravariant (up) index bound to a manifold |
| `DnIdx(parent)` | Covariant (down) index; produced by `-idx` |
| `SlotIdx` | Union of `Idx` and `DnIdx` |

### Expression Types

| Type | Description | Example |
| :--- | :--- | :--- |
| `TTensor` | Tensor with indices applied | `T[-a, -b]` |
| `TProd` | Product with rational coefficient | `2 * T[-a] * V[a]` |
| `TSum` | Sum of expressions | `T[-a,-b] + S[-a,-b]` |
| `TCovD` | Covariant derivative applied to expression | `CD[-a](phi[])` |

### Handles (not TExpr)

| Type | Description |
| :--- | :--- |
| `TensorHead` | Lightweight tensor name handle; apply indices via `T[...]` |
| `CovDHead` | Covariant derivative handle; apply index via `CD[-a]` |

### Factory Functions

```julia
# Declare typed index variables
@indices M a b c d       # binds a, b, c, d as Idx(:a,:M), ...

# Look up registered tensor by name
Riem = tensor(:RiemannCD)   # or tensor("RiemannCD")
g    = tensor(:g)

# Look up registered covariant derivative
CD = covd(:CD)
```

### Operator Overloading

```julia
def_manifold!(:M, 4, [:a, :b, :c, :d])
def_metric!(-1, "g[-a,-b]", :CD)
@indices M a b c d

# Apply indices
Riem = tensor(:RiemannCD)
expr = Riem[-a, -b, -c, -d]          # TTensor

# Arithmetic
T = tensor(:T)
prod = T[-a, -b] * T[a, c]           # TProd
sum  = T[-a, -b] + T[-b, -a]         # TSum
neg  = -T[-a, -b]                    # TProd(coeff=-1, ...)
scl  = 2 * T[-a, -b]                 # TProd(coeff=2, ...)

# Covariant derivative
CD = covd(:CD)
phi = tensor(:phi)
deriv = CD[-a](phi[])                 # TCovD
```

### Validation at Construction Time

Errors are raised when the expression is *built*, not deep in the engine:

```julia
# Wrong slot count
T[-a]                   # ERROR: T has 2 slots, got 1

# Index from wrong manifold
@indices N p q
T[-p, -q]               # ERROR: p is from manifold N, but T expects M
```

### Engine Integration

All engine functions accept `TExpr` in addition to `String`:

```julia
# These two are equivalent:
ToCanonical("RiemannCD[-a,-b,-c,-d] + RiemannCD[-a,-c,-d,-b]")

Riem = tensor(:RiemannCD)
@indices M a b c d
ToCanonical(Riem[-a,-b,-c,-d] + Riem[-a,-c,-d,-b])
```

Supported: `ToCanonical`, `Contract`, `Simplify`, `perturb`, `CommuteCovDs`,
`SortCovDs`, `IBP`, `TotalDerivativeQ`, `VarD`.
