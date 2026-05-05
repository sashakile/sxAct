# Architecture

!!! info "Architecture TL;DR for AI Agents"
    Five Julia modules (XCore → XPerm → XTensor → XInvar, plus TExpr) bundled as `XAct.jl`. Verified via Python `sxact` framework against Dockerized Wolfram Oracle using TOML test cases and snapshot comparison. `sxact` now consumes Elegua for shared verification infrastructure: TOML schema loading via `elegua.bridge.load_test_file`, live test isolation via `elegua.IsolatedRunner`, and oracle HTTP transport via `elegua.oracle.OracleClient`. Python public API exposed via `xact-py`. Wolfram migration tooling in `sxact.translate`.

`XAct.jl` is a Julia port of the Wolfram xAct tensor algebra suite with ergonomic additions (TExpr typed expression layer, Python bindings). The `sxact` package provides verification tooling and Wolfram migration utilities. Chacana (external repo) is a language-agnostic tensor DSL; this repo will accept Chacana as an input format to the translate tooling once the Chacana spec stabilises.

## Related Projects

- **XAct.jl** (This Repo): The native computational engine, `xact-py` wrapper, and `sxact` xAct-specific verification plugins.
- [Elegua](https://github.com/sashakile/elegua) (External): Domain-agnostic validation infrastructure. `sxact` depends on it for adapter protocol, live-runner isolation, TOML bridge parsing, comparison-pipeline composition, and oracle HTTP transport.
- [Chacana](https://github.com/sashakile/chacana) (External): A language-agnostic Tensor DSL and specification. Once the Chacana spec stabilises, this repo will accept Chacana as an input format to the translate tooling.

## Julia Core

The native library follows the original xAct design, split into modules bundled by `XAct.jl`:

- **XCore.jl**: Foundational symbol registry, expression validator, and session state manager.
- **XPerm.jl**: Group theory engine implementing the Butler-Portugal algorithm for tensor index canonicalization. Includes Schreier-Sims, Niehoff shortcuts, and Young tableaux.
- **XTensor.jl**: Tensor algebra layer providing manifolds, bundles, metrics, curvature operators, covariant derivatives, perturbation theory, variational calculus, coordinate components (xCoba), and extended utilities (xTras).
- **XInvar.jl**: Riemann invariant classification and simplification engine. Ports the Wolfram Invar database. Provides `RiemannSimplify`, `InvSimplify`, `SortCovDs`, and dimension-dependent / dual invariant identities.
- **TExpr.jl**: Typed expression layer. Provides `@indices`, `tensor()`, and `T[-a,-b]` index-notation syntax for constructing tensor expressions directly in Julia without raw symbol manipulation.
- **InvarDB.jl**: Parser for the Invar database in Maple and Mathematica formats. Loaded lazily on first use.

## Python API

The `xact-py` package (`packages/xact-py`) exposes a Pythonic public API over the Julia engine:

- **`xact.api`**: User-facing functions (`canonicalize`, `contract`, `simplify`, `perturb`, `riemann_simplify`, etc.) and classes (`Manifold`, `Metric`, `Tensor`, `Perturbation`). Zero `juliacall` exposure.
- **`xact.adapter.julia_stub`**: Machine-facing adapter used by the TOML test runner (`sxact`). Dispatches 34+ actions to Julia. Intentionally separate from the public API — test-runner concepts (`store_as`, `Assert`, `Evaluate`) live here only.

## Translate Tooling

The `sxact.translate` module provides Wolfram Language → Julia migration utilities:

- Parses Wolfram xAct expressions and notebook syntax.
- Emits equivalent `xact-py` or `XAct.jl` code.
- Used for batch migration of existing Wolfram xAct workflows.

## Verification Layer

To ensure mathematical correctness, `XAct.jl` is verified against the original Wolfram implementation:

- **Wolfram Oracle**: A Dockerized Wolfram Engine running xAct. Provides reference results for parity testing. `sxact.oracle.client.OracleClient` preserves the historical sxAct `Result` envelope while delegating HTTP transport to `elegua.oracle.OracleClient`.
- **Elegua-backed Test Runner (`sxact`)**: A Python framework that drives TOML-defined test cases through Julia, Python, and Wolfram adapters. Regular TOML files are parsed through `elegua.bridge.load_test_file()` and wrapped in sxAct compatibility dataclasses; live execution uses `elegua.IsolatedRunner` with sxAct's xAct-specific adapters.
- **Comparison Plugins**: `sxact.elegua_bridge` registers the xAct-specific L3 canonical-normalization layer and L4 numeric-sampling layer with Elegua's `ComparisonPipeline`.
- **Oracle Snapshots**: Deterministic hash-based regression testing that allows verification without a live Wolfram Engine. The snapshot store and comparator remain sxAct-owned because they encode xAct oracle artifact layout and backwards-compatible result reporting.

## Data Flow

```text
Julia REPL / Notebook
  └── using XAct
        ├── XCore.jl    (symbol registry, session state)
        ├── XPerm.jl    (Butler-Portugal canonicalization)
        ├── XTensor.jl  (tensor algebra, xCoba, xTras)
        ├── TExpr.jl    (typed expression layer: @indices, tensor(), T[-a,-b])
        ├── XInvar.jl   (Riemann invariant engine, InvSimplify, RiemannSimplify)
        └── InvarDB.jl  (Invar database parser, lazy-loaded)

Python (xact-py)
  └── xact.api          (user-facing: Manifold, Metric, Tensor, canonicalize, ...)
        └── xact.adapter.julia_stub  (machine-facing: 34+ actions → Julia)

Verification Pipeline
  TOML test file
    → elegua.bridge.load_test_file
    → xact-test CLI (sxact compatibility layer)
      → elegua.IsolatedRunner (live) or sxAct snapshot runner (offline)
        → sxAct Elegua adapter wrapper (JuliaAdapter, PythonAdapter, or WolframAdapter)
          → Elegua ComparisonPipeline with sxAct L3/L4 layers
            → oracle snapshot or live Wolfram oracle result

Migration
  Wolfram Language expression / notebook
    → sxact.translate
      → xact-py or XAct.jl code
```
