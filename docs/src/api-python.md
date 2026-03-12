# Python API Reference

!!! info "Project Profile for AI Agents (LLM TL;DR)"
    - **Name**: sxact-py (Python Wrapper)
    - **Primary Purpose**: Verification of Julia `xAct.jl` against Wolfram Oracle.
    - **Underlying Bridge**: `PythonCall.jl` and `juliacall`.
    - **Key Components**: `sxact.adapter` (verification engine), `sxact.xcore` (low-level symbols).
    - **High-Level API**: Currently in development.

This page describes the `sxact-py` framework, which provides a Python interface to the Julia `xAct.jl` core using the `juliacall` bridge.

## 1. Status of the High-Level API

The high-level Python API (e.g., `sxact.Manifold("M", 4)`) is currently **in development**. For research use, we recommend using the Julia package `xAct.jl` directly.

However, for **automated verification**, `sxact-py` provides a powerful `JuliaAdapter` that can execute any `xAct` operation and verify its results against the Wolfram Engine.

---

## 2. The Verification Adapter (`sxact.adapter`)

The `JuliaAdapter` is the primary way to interact with the Julia engine from Python. It serializes commands into a standard format that can be compared against the Wolfram Oracle.

```python
from sxact.adapter.julia_stub import JuliaAdapter

# Initialize the Julia engine
adapter = JuliaAdapter()
adapter.initialize()

# Execute a command
result = adapter.execute("def_manifold", {
    "name": "M",
    "dim": 4,
    "index_labels": ["a", "b"]
})
```

### Supported Adapter Commands

| Command | Description | Expects |
| :--- | :--- | :--- |
| `def_manifold` | Defines a new manifold. | `name`, `dim`, `index_labels` |
| `def_tensor` | Defines a new tensor. | `name`, `index_specs`, `manifold` |
| `def_metric` | Defines a metric tensor. | `signature`, `metric_str`, `cd_name` |
| `ToCanonical` | Canonicalizes an expression. | `expr` (string) |
| `Contract` | Contracts metric indices. | `expr` (string) |

---

## 3. The `sxact.xcore` Module

The `sxact.xcore` module provides direct, low-level Python wrappers for the foundational functions in `XCore.jl`.

```python
from sxact.xcore import validate_symbol, register_symbol

# Validate a name before definition to avoid collisions
validate_symbol("M")

# List all registered tensor names
from sxact.xcore import x_tensor_names
print(x_tensor_names())
```

### Key Functions

- **Symbol Registry**: `validate_symbol`, `find_symbols`, `register_symbol`.
- **Naming Conventions**: `symbol_join`, `dagger_character`, `link_symbols`.
- **XUpvalues**: `x_up_set`, `x_tag_set` (for low-level tag assignment).

---

## 4. Why use Python?

The Python framework is the cornerstone of our **100% Parity** guarantee. It allows us to:

1.  **Orchestrate**: Run complex test suites that span across Julia and Wolfram Engines.
2.  **Verify**: Perform deep comparisons of tensor expressions between the two implementations.
3.  **Snapshot**: Generate and maintain a baseline of verified results for regression testing.

For more information on the verification architecture, see the [Architecture Guide](architecture.md).
