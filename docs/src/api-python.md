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

The full Julia tensor algebra engine is accessible from Python via `juliacall`.
This is the recommended way to use xAct from Python notebooks or scripts.

### Setup

```python
from xact.xcore import get_julia

jl = get_julia()       # initializes Julia + loads xAct (once per process)
xAct = jl.xAct         # the xAct Julia module

# Helper: Python lists don't auto-convert to Julia Vector
jlvec = jl.seval("collect")
```

### Naming Convention

Julia functions with `!` (mutating) are accessed with a `_b` suffix:

| Julia | Python |
| :--- | :--- |
| `def_manifold!(:M, 4, [:a, :b])` | `xAct.def_manifold_b("M", 4, jlvec(["a", "b"]))` |
| `def_metric!(-1, "g[-a,-b]", :CD)` | `xAct.def_metric_b(-1, "g[-a,-b]", "CD")` |
| `def_tensor!(:T, ["-a", "-b"], :M)` | `xAct.def_tensor_b("T", jlvec(["-a", "-b"]), "M")` |
| `ToCanonical("expr")` | `xAct.ToCanonical("expr")` |
| `Contract("expr")` | `xAct.Contract("expr")` |
| `Simplify("expr")` | `xAct.Simplify("expr")` |
| `perturb("expr", 1)` | `xAct.perturb("expr", 1)` |

### Complete Example

```python
from xact.xcore import get_julia

jl = get_julia()
xAct = jl.xAct
jlvec = jl.seval("collect")

# Define spacetime
xAct.reset_state_b()
xAct.def_manifold_b("M", 4, jlvec(["a", "b", "c", "d", "e", "f"]))
xAct.def_metric_b(-1, "g[-a,-b]", "CD")

# Canonicalize — Riemann first Bianchi identity
result = xAct.ToCanonical(
    "RiemannCD[-a,-b,-c,-d] + RiemannCD[-a,-c,-d,-b] + RiemannCD[-a,-d,-b,-c]"
)
print(result)  # "0"

# Contract — lower a vector index
xAct.def_tensor_b("V", jlvec(["a"]), "M")
print(xAct.Contract("V[a] * g[-a,-b]"))  # "V[-b]"

# Perturbation theory
xAct.def_tensor_b("h", jlvec(["-a", "-b"]), "M",
                   symmetry_str="Symmetric[{-a,-b}]")
xAct.def_perturbation_b("h", "g", 1)
print(xAct.perturb("g[-a,-b]", 1))  # "h[-a,-b]"
```

### Interactive Notebooks

Pre-built Jupyter notebooks are available in the repository:

- **Julia**: [`notebooks/julia/basics.ipynb`](https://github.com/sashakile/sxAct/blob/main/notebooks/julia/basics.ipynb)
- **Python**: [`notebooks/python/basics.ipynb`](https://github.com/sashakile/sxAct/blob/main/notebooks/python/basics.ipynb)

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
