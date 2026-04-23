# Wolfram Translation Reference

!!! info "LLM TL;DR"
    - This page is the lookup reference for Wolfram xAct to XAct.jl translation
    - Use [Wolfram Migration Guide](wolfram-migration.md) for the workflow
    - Use [Getting Started](getting-started.md) if you are learning the native APIs rather than migrating

This page lists the direct mappings used during migration from Wolfram xAct. It is a reference page: use it when you need lookup tables, not when you need a step-by-step migration procedure.

## Rosetta stone: common operations

| Operation | Wolfram (xAct) | Julia (XAct.jl) | Status |
| :--- | :--- | :--- | :--- |
| DefManifold | `DefManifold[M, 4, {a,b}]` | `def_manifold!(:M, 4, [:a, :b])` | ✅ Verified |
| DefTensor | `DefTensor[T[-a,-b], M]` | `def_tensor!(:T, ["-a", "-b"], :M)` | ✅ Verified |
| DefMetric | `DefMetric[-1, g[-a,-b], CD]` | `def_metric!(-1, "g[-a,-b]", :CD)` | ✅ Verified |
| ToCanonical | `ToCanonical[expr]` | `ToCanonical(expr)` | ✅ Verified |
| ContractMetric | `ContractMetric[expr]` | `Contract(expr)` | ✅ Verified |
| Simplify / Simplification | `Simplification[expr]` | `Simplify(expr)` | ✅ Verified |
| RiemannSimplify | `RiemannSimplify[expr, CD]` | `RiemannSimplify(expr, :CD)` | ✅ Verified |
| RiemannToPerm | `RiemannToPerm[expr]` | `RiemannToPerm(expr)` | ✅ Verified |
| SortCovDs | `SortCovDs[expr]` | `SortCovDs(expr)` | ✅ Verified |
| CommuteCovDs | `CommuteCovDs[expr]` | `CommuteCovDs(expr)` | ✅ Verified |
| IBP | `IBP[expr, v]` | `IBP(expr, :CD)` | ✅ Verified |
| VarD | `VarD[field][CD]expr` | `VarD(expr, :field, :CD)` | ✅ Verified |
| Perturbation | `Perturbation[expr]` | `Perturb(expr)` or `perturb_curvature(...)` depending on context | ✅ Verified |

## Translator output formats

| Format | Flag | Use case |
| :--- | :--- | :--- |
| JSON | `--to json` | Machine-readable action dicts |
| Julia | `--to julia` | REPL sessions and Julia scripts |
| TOML | `--to toml` | XAct.jl verification test files |
| Python | `--to python` | Python adapter scripts |

## Supported definition translations

| Wolfram input | Julia output | Notes |
| :--- | :--- | :--- |
| `DefManifold[M, 4, {a,b}]` | `def_manifold!(:M, 4, [:a, :b])` | |
| `DefMetric[-1, g[-a,-b], CD]` | `def_metric!(-1, "g[-a, -b]", :CD)` | Auto-creates curvature tensors |
| `DefTensor[T[-a,-b], M]` | `def_tensor!(:T, ["-a", "-b"], :M)` | |
| `DefTensor[T[-a,-b], M, Symmetric[{-a,-b}]]` | `def_tensor!(:T, ..., symmetry_str=...)` | Symmetry passed as keyword |
| `DefBasis[e, M, {1,2,3,4}]` | `def_basis!(:e, :M, [1,2,3,4])` | |
| `DefChart[cart, M, {1,2,3,4}, {x,y,z,t}]` | `def_chart!(:cart, :M, ..., [:x,:y,:z,:t])` | |
| `DefPerturbation[pert, g]` | `def_perturbation!(:pert, :g)` | |

## Supported computation translations

| Wolfram input | Julia output | Notes |
| :--- | :--- | :--- |
| `ToCanonical[expr]` | `ToCanonical("expr")` | Butler-Portugal canonicalization |
| `ContractMetric[expr]` | `Contract("expr")` | Metric contraction |
| `Simplify[expr]` | `Simplify("expr")` | Iterative `Contract` + `ToCanonical` |
| `CommuteCovDs[expr]` | `CommuteCovDs("expr")` | Covariant derivative commutation |
| `SortCovDs[expr]` | `SortCovDs("expr")` | Canonical CovD ordering |
| `Perturb[expr]` | `perturb("expr", 1)` | Perturbation expansion |
| `Perturbation[expr]` | `perturb_curvature("expr", 1)` | Curvature perturbation |
| `PerturbationOrder[expr]` | `PerturbationOrder("expr")` | Query perturbation order |
| `PerturbationAtOrder[expr, n]` | `PerturbationAtOrder("expr", n)` | Extract specific order |
| `VarD[field][expr]` | `VarD("field", "expr")` | Euler-Lagrange variation |
| `IBP[expr, v]` | `IBP("expr", :v)` | Integration by parts |
| `TotalDerivativeQ[expr]` | `TotalDerivativeQ("expr")` | Total derivative check |
| `CheckMetricConsistency[g]` | `CheckMetricConsistency("g")` | Metric validation |

## Supported basis and component translations

| Wolfram input | Julia output | Notes |
| :--- | :--- | :--- |
| `SetBasisChange[...]` | `SetBasisChange(...)` | Define basis transformation |
| `ChangeBasis[expr, basis]` | `ChangeBasis("expr", :basis)` | Change basis |
| `ToBasis[basis][expr]` | `ToBasis(:basis, "expr")` | Convert to basis |
| `FromBasis[basis][expr]` | `FromBasis(:basis, "expr")` | Convert from basis |
| `SetComponents[...]` | `SetComponents(...)` | Assign component values |
| `GetComponents[...]` | `GetComponents(...)` | Retrieve component values |
| `TraceBasisDummy[expr]` | `TraceBasisDummy("expr")` | Trace over basis indices |

## Naming and behavior differences

| Concept | Wolfram | Julia / translator |
| :--- | :--- | :--- |
| Names | Bare symbols: `M`, `T` | Julia symbols: `:M`, `:T` |
| Indices in API calls | `T[-a, -b]` | Strings such as `"-a"`, `"-b"` |
| Session state | Global kernel | Global registry; use `reset_state!()` |
| Side effects | Often implicit | `!` suffix marks state mutation |
| Contraction | `ContractMetric` | `Contract` |
| Simplification naming | `Simplification` in Wolfram material | Use `Simplify` in translated/native code |
| CovD ordering | `SortCovDs` | `SortCovDs` and `CommuteCovDs` both exist |
| Perturbation naming | `Perturbation[expr]` | Split across `Perturb`, `perturb_curvature`, and related APIs |
| Auto-created tensors | `DefMetric` creates curvature objects | `def_metric!` does the same |
| Scoping constructs | `Module`, `Block`, `With` | Translate manually |
| Licensing | Mathematica license | GPL-3.0 open source |

## When this reference is the wrong page

| Need | Better page |
| :--- | :--- |
| Step-by-step migration procedure | [Wolfram Migration Guide](wolfram-migration.md) |
| First working Julia or Python examples | [Getting Started](getting-started.md) |
| Guided Julia practice | [Basics tutorial](examples/basics.md) |
| Typed expression details | [Typed Expressions (TExpr)](guide/TExpr.md) |
