# How XAct.jl Was Built

This page explains the migration strategy used to port Wolfram xAct to Julia, how the `sxact` verification framework is constructed, and how [Eleguá](https://github.com/sashakile/elegua) integrates with it. It also documents the known limitations and caveats that shape the project today.

## Background: what is Wolfram xAct?

[xAct](http://xact.es/) is a suite of Mathematica packages for symbolic tensor algebra and differential geometry. It covers tensor canonicalization (xPerm), abstract tensor calculus (xTensor), coordinate components (xCoba), perturbation theory (xPert), and Riemann invariant classification (Invar). The suite is the standard tool for computer-algebra work in general relativity.

XAct.jl is a native Julia port of the same functionality. It exposes the same operations through idiomatic Julia module boundaries and a Python wrapper (`xact-py`) so that the existing research ecosystem can migrate workflows without sacrificing verification coverage.

## The migration strategy

### Phase 1 — Prototype (January 2026)

The project started as a proof of concept: an HTTP oracle client that could send Wolfram Language expressions to a Dockerized Wolfram Engine running xAct, record the responses as JSON snapshots, and then compare a naive Julia reimplementation against those snapshots.

The core insight was to build the verification infrastructure first and let it drive the implementation. No Julia code was trusted until it passed a TOML test case that had been recorded against the live oracle.

### Phase 2 — Butler-Portugal and tensor algebra (February–March 2026)

v0.2.0 completed `XPerm.jl`: a full Julia port of the Butler-Portugal tensor canonicalization algorithm with Schreier-Sims, Niehoff shortcuts for symmetric/antisymmetric tensors, and Young tableaux. 92/92 Butler permutation examples matched the Wolfram reference.

v0.3.0 extended `XTensor.jl` with manifolds, metrics, curvature tensors, covariant derivatives, coordinate components (xCoba), variational calculus (IBP, VarD, CommuteCovDs), and perturbation theory (xPert).

### Phase 3 — Riemann invariants and the translator (March 2026)

v0.4.0 completed the multi-phase `XInvar.jl` pipeline:

- Parses a tensor expression into a canonical permutation (RPerm).
- Looks up the permutation in the ported Invar database.
- Applies six levels of simplification: identity rules, cyclic symmetry, Bianchi identities, covariant derivative commutation, dimension-dependent identities, and dual-invariant identities in 4D.
- Reconstructs a simplified tensor expression.

The same release introduced the Wolfram Language expression translator (`sxact.translate`): a surface-syntax parser that reads Wolfram xAct notebooks and emits equivalent Julia or Python code.

### Phase 4 — Typed expressions and Python API (March 2026)

v0.5.0 added `TExpr.jl`: a typed expression layer that wraps raw string representations in structured Julia types (`TTensor`, `Idx`, `TensorHead`, `CovDHead`). Every engine function was updated to return typed values, enabling index-notation syntax (`T[-a,-b]`) and catching index mismatches before evaluation.

The Python public API (`xact.api`) was introduced in the same release, with zero exposure of `juliacall` internals. User-facing classes (`Manifold`, `Metric`, `Tensor`, `Perturbation`) and functions (`canonicalize`, `contract`, `simplify`, …) sit in a separate module from the machine-facing adapter used by the TOML runner.

### Phase 5 — Hardening and tutorials (March–April 2026)

v0.6.0 replaced global mutable state with a `Session` struct, added a `Validation.jl` module for typed argument checking at the Julia bridge, and introduced zero-allocation hot paths for einsum, metric lookup, and CovD dispatch. Eight Jupyter/Quarto tutorial notebooks were added covering foundational geometry and GR textbook examples.

### Repository rename (April 2026)

v0.7.1 renamed the repository from `sxAct` to `XAct.jl` to comply with the Julia General registry naming convention (packages must match their module name). 41 files were updated across docs, notebooks, CI, package metadata, and Docker configurations.

---

## How `sxact` is built

> For the current module structure and data flow, see [Architecture](architecture.md). This section explains the design decisions and how the layers evolved.

`sxact` is the Python verification framework that lives in `packages/sxact/`. It is a separate package from `xact-py`: `sxact` is the verification framework (test runner, oracle, adapters); `xact-py` is the end-user public API. It has six layers.

### 1. Oracle layer

The oracle is a Dockerized Wolfram Engine with xAct loaded. The `sxact.oracle.client.OracleClient` sends Wolfram Language expressions over HTTP and gets back string results. Each call uses a `context_id` to give each test case an isolated Wolfram namespace, preventing symbol definitions from one test leaking into another.

When a live oracle is not available, pre-recorded JSON snapshots (SHA-256 content-hashed) replace it. Snapshots are stored in the `oracle/` directory and committed to the repository. Any test that passed against the live oracle can be re-run at any time without Wolfram Engine access.

### 2. Adapter layer

The adapter layer translates abstract test actions into concrete calls to a backend. Two adapters exist:

- **`julia_stub.py`** — the machine-facing Julia adapter. Dispatches 34+ named actions (`DefManifold`, `ToCanonical`, `Contract`, `RiemannSimplify`, …) to the Julia engine via `juliacall`. This adapter intentionally uses test-runner concepts (`store_as`, `Assert`, `Evaluate`) that are absent from the public Python API.
- **`wolfram.py`** — the Wolfram oracle adapter. Sends the same actions to the Docker oracle for comparison.

### 3. Runner layer

The TOML runner (`sxact.runner`) defines the test lifecycle:

1. Parse a TOML test file into `setup` blocks and `tests` blocks.
2. Execute each `setup` action against the adapter (define manifolds, tensors, metrics).
3. Execute each `test` action and collect the result.
4. Compare the result against the oracle snapshot (or a live oracle response).

The CLI entry point is `xact-test`:

```bash
uv run xact-test run tests/xtensor/ --adapter julia --oracle-mode snapshot --oracle-dir oracle
```

For live oracle usage, omit `--oracle-mode` or use `--oracle-mode live`; see [Snapshot management](#6-snapshot-management) below.

A TOML test file looks like this:

```toml
[meta]
id          = "xtensor/canonicalization"
description = "Antisymmetric tensor: T[-b,-a] - T[-a,-b] = 0"
tags        = ["xtensor", "layer:1"]

[[setup]]
action   = "DefManifold"
store_as = "M"
[setup.args]
name      = "M"
dimension = 4
indices   = ["a", "b", "c", "d"]

[[setup]]
action   = "DefTensor"
[setup.args]
name     = "T"
indices  = ["-a", "-b"]
manifold = "M"
symmetry = "Antisymmetric[{-a,-b}]"

[[tests]]
action   = "ToCanonical"
expected = "0"
[tests.args]
expr = "T[-b, -a] - T[-a, -b]"
```

### 4. Normalization layer

Raw string results from Julia and Wolfram rarely match character-for-character because dummy index names differ (`$1`, `$2`, … vs. `a`, `b`, …), term ordering varies, and whitespace conventions differ. The normalization layer (`sxact.normalize`) canonicalizes expressions before comparison:

- **AST normalization** — parse the expression into a symbolic tree, rename all dummy indices to canonical placeholders, and serialize back to a string.
- **Term ordering** — sort additive terms into a canonical order so that `A + B` and `B + A` compare equal.
- **Structural normalization** — handle Wolfram-style `Plus[…]` and Julia-style `+` interchangeably.

### 5. Comparison layer

After normalization, the comparator (`sxact.compare`) applies three tiers:

| Tier | Method | Confidence |
| :--- | :--- | :--- |
| 1 — Identity | Bitwise string equality after normalization | 1.0 |
| 2 — Structural | AST-level structural equivalence | 1.0 |
| 3 — Invariant | Numeric substitution sampling (N random tensors) | < 1.0 |

Tier 3 is the fallback when symbolic equality cannot be confirmed. It evaluates both expressions at random numeric tensors and checks for numerical agreement. A pass at tier 3 does not prove symbolic equality, only numerical agreement within the sample.

### 6. Snapshot management

Snapshots are generated once from a live oracle and then committed:

```bash
# Generate snapshots from live oracle
uv run xact-test snapshot tests/xtensor/ --output oracle/ --oracle-url http://localhost:8765

# Regenerate after engine changes
uv run xact-test regen-oracle tests/xtensor/ --oracle-dir oracle/ --diff --yes
```

The snapshot JSON stores the Wolfram result string and its SHA-256 hash. The runner verifies the hash before accepting a snapshot result, catching accidental file corruption. If the hash check fails, regenerate the affected snapshot with `xact-test regen-oracle` rather than editing the JSON directly.

---

## How Eleguá integrates

[Eleguá](https://github.com/sashakile/elegua) is a domain-agnostic multi-tier test orchestrator, maintained in a separate repository. It provides generic infrastructure for validating equivalence across symbolic computing systems: kernel isolation, warm-up phases, blob storage for large payloads, and pluggable normalizers.

The `sxact.elegua_bridge` module connects the xAct domain to Eleguá. It implements Eleguá's abstract adapter interface using the Julia stub adapter and the Wolfram oracle adapter. The bridge translates Eleguá's generic action vocabulary into xAct-specific TOML actions — for example, Eleguá's `evaluate(expr)` call maps to xAct's `ToCanonical` action.

In practice, most day-to-day verification uses the `xact-test` CLI directly against TOML files without going through Eleguá. Eleguá becomes relevant for multi-system comparisons (e.g., cross-validating a result in xAct, SymPy, and a custom CAS simultaneously) and for property-based testing that generates random inputs.

---

## Caveats and known limitations

The most architecturally significant limitation is string-based internals; the remaining caveats are operational or environmental.

### String-based internal representation

The engine core operates on Wolfram-style string expressions internally. Julia functions serialize tensor objects to strings, call the symbolic pipeline, and deserialize back. This mirrors the original xAct design and made it straightforward to verify results against the Wolfram oracle, but it is not idiomatic Julia and adds serialization overhead.

`TExpr.jl` provides a typed layer on top of this, but the underlying pipeline still passes strings at the boundary. Making `TExpr` the native representation throughout the engine (eliminating the string round-trip) is the top architectural priority and is tracked in the issue tracker.

### Unported modules

The following xAct modules have not yet been started:

- **xSpinors** — spinor calculus
- **xTerior** — exterior differential systems
- **Harmonics** — harmonic analysis on symmetric spaces
- **TexAct** — LaTeX output formatting (partial substitution exists in TExpr display)

`xPert` (perturbation theory) and the xTras utilities are partially ported; the ported subset is noted in the [Status page](status.md).

### AI-assisted development

Substantially all of the code in this repository was generated by AI coding assistants (Claude Code, Gemini, Amp Code) and then reviewed by a human and validated by oracle parity tests. This is deliberate: the project is an experiment in using AI tools for scientific software.

Mathematical correctness rests entirely on oracle parity testing. If a result matches the Wolfram Engine for the recorded test cases, it is trusted. This approach does not catch cases that are not covered by TOML tests. The test suite is extensive (see CI for current counts) but not exhaustive.

**Use the library at your own discretion for research and production work. Verify results independently for critical calculations.**

### Experimental and early-adopter status

The project is used only by its author in production. The API may change between minor versions. Pull requests are currently closed pending a contribution management strategy; issues are welcome.

### juliacall / PythonCall teardown

The Python wrapper calls Julia via `juliacall`. On process exit, Julia's garbage collector and PythonCall teardown can race, triggering a `SIGSEGV`. The workaround (`os._exit()`) in the bridge prevents the crash but skips normal Python cleanup. Library users who register `atexit` handlers should be aware that they will not run when the Python wrapper exits. This is a known `juliacall` limitation and not specific to this project.

### Oracle availability

The live Wolfram oracle requires a Wolfram Engine license and a running Docker container. All CI runs use pre-recorded snapshots so there is no runtime license dependency, but regenerating snapshots or running integration tests against new Wolfram functionality requires access to the oracle.

---

## See Also

- [Architecture](architecture.md) — current module structure and data flow
- [Verification Tools](verification-tools.md) — xact-test CLI reference
- [Migrating from Wolfram](wolfram-migration.md) — practical migration guide
- [Status](status.md) — feature coverage by xAct module
