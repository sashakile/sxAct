# Python API Reference

!!! warning "No Public Python API"
    There is no user-facing Python API for tensor algebra yet. For research use, use the Julia package `xAct.jl` directly. The Python packages described here are internal to the verification framework.

---

## Verification Framework (`sxact`)

The `sxact` package powers the automated parity verification suite. It is an internal tool, not a user-facing API.

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

The adapter supports 30+ actions covering the full xAct feature set. Key actions include:

| Action | Description |
| :--- | :--- |
| `DefManifold` | Define a manifold with dimension and index labels |
| `DefMetric` | Define a metric tensor (auto-creates curvature tensors) |
| `DefTensor` | Define a tensor with optional symmetry |
| `DefBasis` / `DefChart` | Define coordinate bases and charts |
| `ToCanonical` | Canonicalize a tensor expression |
| `Contract` | Metric-aware index contraction |
| `Simplify` | Iterative contraction + canonicalization |
| `CommuteCovDs` | Commute covariant derivatives (introduces Riemann terms) |
| `DefPerturbation` / `Perturb` | Perturbation theory |
| `PerturbCurvature` | Curvature tensor perturbation rules |
| `IBP` | Integration by parts |
| `VarD` | Variational (Euler-Lagrange) derivative |
| `SetBasisChange` / `ChangeBasis` | Coordinate transforms |
| `SetComponents` / `GetComponents` | Component array operations |
| `ToBasis` / `FromBasis` | Abstract index ↔ component conversion |
| `Christoffel` | Christoffel symbol computation |
| `CollectTensors` / `AllContractions` | xTras utilities |

For the complete list, see the `_XTENSOR_ACTIONS` set in `sxact.adapter.julia_stub`.

---

## Julia Runtime (`xact.xcore`)

The `xact` package (in `packages/xact-py/`) provides the low-level Julia runtime bridge used internally by the adapter. It manages the Julia process via `juliacall` and `juliapkg`.

This is not a user-facing API. For direct tensor algebra, use `xAct.jl` in Julia.

---

For more on the verification architecture, see the [Architecture Guide](architecture.md) and [Verification Tools](verification-tools.md).
