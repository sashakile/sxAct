# Python API Reference

!!! info "Project Profile for AI Agents (LLM TL;DR)"
    - **Core wrapper**: `import xact` (package: `xact-py`)
    - **Verification framework**: `import sxact` (package: `sxact`)
    - **Underlying bridge**: `PythonCall.jl` and `juliacall`

The Python ecosystem consists of two packages:

1. **`xact`** — Python wrapper for the Julia `xAct.jl` core, providing snake_case access to XCore functions.
2. **`sxact`** — Verification framework for automated parity testing against the Wolfram Oracle.

---

## 1. Core Wrapper (`xact.xcore`)

The `xact.xcore` module exposes XCore.jl functions with Python-idiomatic snake_case names. Julia is initialised lazily on first import.

### Type Conventions

- Symbol arguments accept Python `str`; the wrapper converts to Julia `Symbol`.
- Symbol return values are returned as Python `str`.
- `list[str]` maps to/from Julia `Vector{Symbol}`.
- Julia exceptions are re-raised as `juliacall.JuliaError`.

### Symbol Registry

```python
from xact.xcore import validate_symbol, register_symbol, find_symbols

# Check a name is available before defining
validate_symbol("MyTensor")   # raises JuliaError if name collides

# Query registered names by package
from xact.xcore import x_tensor_names, x_core_names, x_perm_names
print(x_tensor_names())       # list of symbols registered by XTensor
```

### List Utilities

```python
from xact.xcore import just_one, delete_duplicates, duplicate_free_q

just_one([42])              # 42
delete_duplicates([1,2,2])  # [1, 2]
duplicate_free_q([1,2,3])   # True
```

### Symbol Naming

```python
from xact.xcore import symbol_join, make_dagger_symbol, link_symbols

symbol_join("Riemann", "CD")      # "RiemannCD"
make_dagger_symbol("T")           # "Tdg" (or custom dagger character)
link_symbols(["a", "b", "c"])     # linked index symbols
```

### Options & Upvalues

```python
from xact.xcore import check_options, x_up_set, x_tag_set
```

### Full API

All exported functions (see `xact.xcore.__all__`):

| Category | Functions |
| :--- | :--- |
| **List utilities** | `just_one`, `map_if_plus`, `thread_array`, `delete_duplicates`, `duplicate_free_q` |
| **Argument guards** | `set_number_of_arguments`, `push_unevaluated` |
| **Options** | `check_options`, `true_or_false`, `report_set`, `report_set_option` |
| **Symbol naming** | `symbol_join`, `no_pattern` |
| **Dagger/Link characters** | `dagger_character`, `set_dagger_character`, `has_dagger_character_q`, `make_dagger_symbol`, `link_character`, `set_link_character`, `link_symbols`, `unlink_symbol` |
| **Symbol registry** | `validate_symbol`, `find_symbols`, `register_symbol` |
| **Package name queries** | `x_perm_names`, `x_tensor_names`, `x_core_names`, `x_tableau_names`, `x_coba_names`, `invar_names`, `harmonics_names`, `x_pert_names`, `spinors_names`, `em_names` |
| **Upvalues** | `sub_head`, `x_up_set`, `x_up_set_delayed`, `x_up_append_to`, `x_up_delete_cases_to` |
| **Tags** | `x_tag_set`, `x_tag_set_delayed` |
| **Extensions** | `x_tension`, `make_x_tensions`, `x_evaluate_at` |
| **Configuration** | `warning_from`, `set_warning_from`, `xact_directory`, `set_xact_directory`, `xact_doc_directory`, `set_xact_doc_directory` |
| **Misc** | `disclaimer` |

---

## 2. Using xAct from Python

The `xact` package provides a Pythonic API for tensor algebra. Julia
internals are completely hidden.

### Setup

```python
import xact

xact.reset()  # clear all state (optional, for clean sessions)
```

### Definitions

```python
# Manifold
M = xact.Manifold("M", 4, ["a", "b", "c", "d", "e", "f"])

# Metric (automatically creates Riemann, Ricci, Weyl, Einstein, Christoffel)
g = xact.Metric(M, "g", signature=-1, covd="CD")

# Tensor
T = xact.Tensor("T", ["-a", "-b"], M, symmetry="Symmetric[{-a,-b}]")

# Perturbation
h = xact.Tensor("h", ["-a", "-b"], M, symmetry="Symmetric[{-a,-b}]")
xact.Perturbation(h, g, order=1)
```

### Operations

| Function | Description |
| :--- | :--- |
| `xact.canonicalize(expr)` | Butler-Portugal canonicalization |
| `xact.contract(expr)` | Evaluate metric contractions |
| `xact.simplify(expr)` | Iterative contract + canonicalize |
| `xact.perturb(expr, order)` | Perturbation expansion |
| `xact.commute_covds(expr, covd, i, j)` | Commute covariant derivatives |
| `xact.sort_covds(expr, covd)` | Sort covariant derivatives |
| `xact.ibp(expr, covd)` | Integration by parts |
| `xact.var_d(expr, field, covd)` | Variational derivative |
| `xact.riemann_simplify(expr, covd)` | Scalar Riemann simplification |
| `xact.dimension(M)` | Manifold dimension |
| `xact.reset()` | Clear all state |

### Complete Example

```python
import xact

xact.reset()
M = xact.Manifold("M", 4, ["a", "b", "c", "d", "e", "f"])
g = xact.Metric(M, "g", signature=-1, covd="CD")

a, b, c, d, e, f = xact.indices(M)
Riem = xact.tensor("RiemannCD")

# Canonicalize — Riemann first Bianchi identity
xact.canonicalize(Riem[-a,-b,-c,-d] + Riem[-a,-c,-d,-b] + Riem[-a,-d,-b,-c])  # "0"

# Contract — lower a vector index
V = xact.Tensor("V", ["a"], M)
V_h = xact.tensor("V")
xact.contract(V_h[a] * g[-a,-b])  # "V[-b]"

# Perturbation theory
h = xact.Tensor("h", ["-a", "-b"], M, symmetry="Symmetric[{-a,-b}]")
xact.Perturbation(h, g, order=1)
xact.perturb(g[-a,-b], order=1)  # "h[-a,-b]"
```

### Typed Expression API

The `xact` package includes a typed expression layer that catches mistakes at
expression-construction time — wrong slot counts, indices from the wrong
manifold — rather than deep inside the engine.

Stage 2 is fully implemented: engine functions accept typed expressions and
return typed expressions (round-trip).

#### Index Types

```python
# Create index objects bound to manifold M
a, b, c, d, e, f = xact.indices(M)   # tuple of Idx objects

# Manually: Idx(label, manifold_name)
a = xact.Idx("a", "M")

# Covariant (down) index via negation
-a   # DnIdx(-a)
```

| Class | Description |
| :--- | :--- |
| `xact.Idx(label, manifold)` | Contravariant (up) index bound to a manifold name |
| `xact.DnIdx(parent)` | Covariant (down) index; produced by `-idx` |

#### Tensor Handles and Expressions

| Class | Description |
| :--- | :--- |
| `xact.TensorHead(name)` | Lightweight tensor handle; use `T[-a, -b]` to apply indices |
| `xact.AppliedTensor` | Tensor with indices; result of `T[...]` |
| `xact.SumExpr` | Sum of expressions; result of `a + b` |
| `xact.ProdExpr` | Product with coefficient; result of `a * b`, `2 * a`, `-a` |
| `xact.CovDExpr` | Covariant derivative on an expression |

#### Factory Functions

```python
# All index labels for a manifold (ordered as defined)
a, b, c, d, e, f = xact.indices(M)

# Look up a registered tensor by name — validates existence, caches arity
Riem = xact.tensor("RiemannCD")
g_h  = xact.tensor("g")

# Tensor and Metric objects also support [] directly:
g[-a, -b]     # same as xact.tensor("g")[-a, -b]
```

#### Operator Overloading

```python
import xact

xact.reset()
M  = xact.Manifold("M", 4, ["a", "b", "c", "d", "e", "f"])
g  = xact.Metric(M, "g", signature=-1, covd="CD")
a, b, c, d, e, f = xact.indices(M)

# Apply indices to a tensor handle
Riem = xact.tensor("RiemannCD")
expr = Riem[-a, -b, -c, -d]           # AppliedTensor

# Arithmetic
T = xact.Tensor("T", ["-a", "-b"], M)
th = xact.tensor("T")
prod = th[-a, -b] * th[a, c]          # ProdExpr
ssum = th[-a, -b] + th[-b, -a]        # SumExpr
neg  = -th[-a, -b]                    # ProdExpr(coeff=-1)
scl  = 2 * th[-a, -b]                 # ProdExpr(coeff=2)
```

#### Validation at Construction Time

```python
# Wrong slot count — raised immediately, not in the engine
th[-a]                  # IndexError: T has 2 slots, got 1
```

#### Engine Integration

All engine functions accept typed expressions transparently:

```python
# String API (original)
xact.canonicalize("RiemannCD[-a,-b,-c,-d] + RiemannCD[-a,-c,-d,-b]")

# Typed API (equivalent)
Riem = xact.tensor("RiemannCD")
a, b, c, d, e, f = xact.indices(M)
xact.canonicalize(Riem[-a,-b,-c,-d] + Riem[-a,-c,-d,-b])   # returns str
```

Supported: `canonicalize`, `contract`, `simplify`, `perturb`, `commute_covds`,
`sort_covds`, `ibp`, `total_derivative_q`, `var_d`.

### Interactive Notebooks

Pre-built Jupyter notebooks are available in the repository:

- **Julia**: [`notebooks/julia/basics.ipynb`](https://github.com/sashakile/XAct.jl/blob/main/notebooks/julia/basics.ipynb)
- **Python**: [`notebooks/python/basics.ipynb`](https://github.com/sashakile/XAct.jl/blob/main/notebooks/python/basics.ipynb)

---

## 3. Verification Framework (`sxact`)

The `sxact` package powers the automated parity verification suite.

### Adapters (`sxact.adapter`)

Adapters translate TOML test actions into backend-specific calls and return normalized results.

| Adapter | Backend | Description |
| :--- | :--- | :--- |
| `JuliaAdapter` | `xAct.jl` via `juliacall` | Routes actions to XTensor.jl |
| `WolframAdapter` | Dockerized Wolfram Engine | Connects to the Oracle HTTP server |

### Adapter Lifecycle

```python
from sxact.adapter.julia_stub import JuliaAdapter

adapter = JuliaAdapter()
ctx = adapter.initialize()        # returns a context object

result = adapter.execute(ctx, "DefManifold", {
    "name": "M",
    "dimension": 4,
    "indices": ["a", "b", "c", "d"],
})

result = adapter.execute(ctx, "ToCanonical", {
    "expr": "T[-b, -a] - T[-a, -b]",
})

adapter.teardown(ctx)             # resets session state
```

### Supported Actions

The adapter supports 30+ actions. For the complete list, see the `_XTENSOR_ACTIONS` set in `sxact.adapter.julia_stub`.

---

For more on the verification architecture, see the [Architecture Guide](architecture.md) and [Verification Tools](verification-tools.md).
