# sxAct Feature Completion Matrix

Generated: 2026-03-07

---

## XPerm.jl — Permutation Group Engine

| Feature | Spec | Status | Notes |
|---------|------|--------|-------|
| Signed permutation representation (n+2 degree) | yes | DONE | Matches `xperm.c` exactly |
| `StrongGenSet` data structure | yes | DONE | |
| `SchreierVector` data structure | yes | DONE | |
| Schreier-Sims algorithm | yes | DONE | |
| `canonicalize_slots()` API | yes | DONE | High-level entry point |
| Niehoff shortcut: `Symmetric` | yes | DONE | O(k log k) |
| Niehoff shortcut: `Antisymmetric` | yes | DONE | O(k log k) |
| `RiemannSymmetric` group (8 elements) | yes | DONE | |
| `NoSymmetry` group | yes | DONE | |
| Butler examples (permutation group tests) | yes | BROKEN | Snapshot hash failures — need `xact-test snapshot` regen |

---

## XTensor.jl — Tensor Algebra Actions

| Action | Spec | Status | Notes |
|--------|------|--------|-------|
| `DefManifold` | yes | DONE | |
| `DefMetric` | yes | DONE | |
| `DefTensor` (with symmetry) | yes | DONE | |
| `ToCanonical` | yes | DONE | Full parse->canonicalize->serialize pipeline |
| `Contract` | yes | DONE | sxAct-6tb |
| `Evaluate` | yes | DONE | Expr evaluation + `store_as` binding |
| `Assert` | yes | DONE | WL-like condition checking |
| Auto-creates Riemann/Ricci/RicciScalar/Einstein/Weyl | yes | DONE | |
| `reset_state!()` / per-file isolation | yes | DONE | |
| `Simplify` | yes | DEFERRED | Explicitly Tier 2 deferred |
| `SignDetOfMetric` | yes | DEFERRED | Deferred with `contraction.toml` |
| `CovD` (covariant derivative action) | yes | MISSING | sxAct-3to |
| `ChristoffelCD` auto-creation from `DefMetric` | yes | MISSING | sxAct-3to |

---

## Adapter Layer

| Feature | Spec | Status | Notes |
|---------|------|--------|-------|
| `JuliaAdapter` | yes | DONE | Routes all xTensor actions to XTensor.jl |
| `PythonAdapter` | yes | DONE | sxAct-bw4; wraps Julia via juliacall |
| `WolframAdapter` (oracle) | yes | DONE | Snapshot mode |
| Adapter interface: `initialize / execute / teardown` | yes | DONE | |
| `normalize` / `equals` comparator methods | yes | PARTIAL | Normalization in `sxact/normalize/`; not wired as formal adapter methods |
| `get_properties()` introspection | yes | MISSING | Properties returned ad-hoc in results |
| `get_version()` | yes | MISSING | |
| Per-file fresh context (`reset_state!`) | yes | DONE | |

---

## Test Infrastructure

| Feature | Spec | Status | Notes |
|---------|------|--------|-------|
| TOML loader + JSON Schema validation | yes | DONE | |
| `xact-test run` CLI | yes | DONE | |
| `xact-test snapshot` CLI | yes | DONE | |
| `xact-test regen-oracle` CLI | yes | DONE | |
| `xact-test property` CLI | yes | DONE | |
| `xact-test benchmark` CLI | yes | PARTIAL | Command exists; infrastructure not fully audited |
| Three-tier comparator: Tier 1 normalized string | yes | DONE | |
| Three-tier comparator: Tier 2 symbolic diff=0 | yes | PARTIAL | Only via oracle `Simplify`; not in adapter execution path |
| Three-tier comparator: Tier 3 numeric sampling | yes | DONE | `sampling.py` |
| Oracle snapshot golden files | yes | DONE | `oracle/` directory |
| `checksums.sha256` integrity | yes | DONE | Butler snapshots currently failing hash check |
| HTML reporting dashboard | yes | MISSING | Sprint 6 item |
| Baseline management (`benchmarks/baseline.json`) | yes | PARTIAL | `xcore_baseline.json` exists; no `bd update-baseline` workflow |
| Performance thresholds (warn >20%, error >50%) | yes | MISSING | |

---

## Layer 1 Test Files

| File | Tests | Status | Notes |
|------|-------|--------|-------|
| `xcore/` (basic, list, symbol, options, upvalues, dagger) | various | PASS | |
| `xperm/basic_symmetry.toml` | 6 | PASS 6/6 | |
| `xperm/butler_examples/` | ~70 | BROKEN | Snapshot hash failures — need regen |
| `xtensor/basic_manifold.toml` | ~8 | PASS | |
| `xtensor/basic_tensor.toml` | ~8 | PASS | |
| `xtensor/canonicalization.toml` | ~10 | PASS | |
| `xtensor/curvature_invariants.toml` | 8 | PASS 8/8 | |
| `xtensor/quadratic_gravity.toml` | ~8 | PASS | |
| `xtensor/contraction.toml` | 5 | PASS 4/5, 1 SKIPPED | `Simplify` test skipped (deferred) |
| `xtensor/gw_memory_3p5pn.toml` | 6 | MISSING | No snapshots; likely needs CovD (sxAct-3to) |
| Notebook-extracted tests (~65 target) | 0 | NOT STARTED | sxAct-3w1 |

---

## Layer 2 Property Tests

| File / Property | Count | Status | Notes |
|----------------|-------|--------|-------|
| `xcore_symbol_laws.toml` | 12 | PASS 10/12, 2 ERRORS | `AtomQ`, `Cases` not defined in Julia scope |
| `riemann_symmetries.toml` | 6 | FAIL 0/6 | See root cause below |
| `tensor_algebra_laws.toml` | 7 | FAIL 0/7 | See root cause below |
| xTensor props 9-10 (second Bianchi, metric compat) | 2 | MISSING | Require CovD (sxAct-3to) |

Root cause for tensor property failures:
The property runner uses `Max[Abs[Flatten[N[lhs-rhs]]]]` for `numerical_tolerance`
equivalence, but symbolic tensor expressions (e.g. `RiemannPCD[-pa,-pb,-pc,-pd]`)
cannot be numerically evaluated by Julia without a concrete metric substitution.
The spec (specs/2026-03-05-property-test-design.md S3) calls for N-sample tensor
sampling via `build_tensor_context`, but the property runner's tensor N-sample loop
is not implemented. The runner needs to call `build_tensor_context(seed + i)` per
sample and substitute numeric metric components before evaluating.

---

## Layer 3 Benchmarks

| Feature | Spec | Status | Notes |
|---------|------|--------|-------|
| `benchmarks/runner.py` | yes | PARTIAL | Exists; not fully audited against spec |
| `xcore_baseline.json` | yes | EXISTS | |
| Warm-up runs (3) + measurement runs (10) | yes | UNKNOWN | |
| Median / IQR statistics | yes | UNKNOWN | |
| `jit_overhead_ms` separation | yes | UNKNOWN | |
| Performance thresholds (warn/error) | yes | MISSING | |
| HTML report | yes | MISSING | |

---

## Priority Summary

| Priority | Item | Effort |
|----------|------|--------|
| Quick fix | Butler examples: regen snapshots with `xact-test snapshot` | Tiny |
| Quick fix | `AtomQ` / `Cases` missing in Julia — add to XTensor exports or route via Python | Small |
| Medium | Property runner: add tensor N-sample loop (`build_tensor_context` per sample) | Medium |
| Medium | `gw_memory_3p5pn.toml`: attempt `xact-test snapshot` — if it passes, free; if not, needs CovD | Medium |
| Large | CovD / ChristoffelCD in XTensor.jl (sxAct-3to) | Large |
| Large | Notebook-extracted TOML tests (~65, sxAct-3w1) | Large |
| Deferred | `Simplify`, `SignDetOfMetric` | Deferred |
| Deferred | HTML reporting, baseline management, `get_properties()` / `get_version()` | Deferred |
