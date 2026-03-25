# Migrating from Wolfram xAct

This guide is for researchers who already use the Wolfram Language `xAct` suite and want to migrate their workflows to `xAct.jl`. It covers the **Wolfram Expression Translator** — a CLI tool that automatically converts your existing Wolfram code into Julia, TOML, or Python.

!!! tip "Already familiar with the Julia API?"
    If you just need a quick reference, see the [Rosetta Stone](getting-started.md#4-reference-migration-rosetta-stone) table.

!!! info "Prerequisites"
    Install sxAct following the [Installation Guide](installation.md). The translator CLI (`xact-test translate`) is included — no Wolfram license required.

---

## The Translator

The `uv run xact-test translate` command parses standard Wolfram xAct expressions and emits equivalent sxAct code. The parser runs entirely locally.

### Quick Example

```bash
uv run xact-test translate -e 'DefManifold[M, 4, {a, b, c, d}]' --to julia
# => xAct.def_manifold!(:M, 4, [:a, :b, :c, :d])
```

### Supported Output Formats

| Format | Flag | Use Case |
|:-------|:-----|:---------|
| JSON | `--to json` | Machine-readable action dicts (default) |
| Julia | `--to julia` | Drop into a Julia REPL or script |
| TOML | `--to toml` | sxAct verification test files |
| Python | `--to python` | Python adapter scripts |

### Translating Multiple Expressions

Separate expressions with semicolons:

```bash
uv run xact-test translate -e \
  'DefManifold[M, 4, {a,b,c,d}]; DefMetric[-1, g[-a,-b], CD]; ToCanonical[g[-b,-a]]' \
  --to julia
```

Output:

```julia
xAct.def_manifold!(:M, 4, [:a, :b, :c, :d])
xAct.def_metric!(-1, "g[-a, -b]", :CD)
xAct.ToCanonical("g[-b, -a]")
```

### Translating a `.wl` File

If you have an existing Wolfram script:

```bash
uv run xact-test translate --file my_notebook.wl --to julia > my_notebook.jl
```

Wolfram comments `(* ... *)` are stripped automatically. For multiline expressions, prefer `--file` over `-e` to avoid shell quoting issues.

---

## Interactive REPL

For an interactive migration session, use the REPL:

```bash
# Full mode: parse, translate, and execute in Julia
uv run xact-test repl

# Translate-only mode: no Julia runtime needed
uv run xact-test repl --no-eval
```

In **translate-only** mode (`--no-eval`), each expression shows the Julia translation:

```
In[1]: DefManifold[M, 4, {a, b, c, d}]
  → xAct.def_manifold!(:M, 4, [:a, :b, :c, :d])

In[2]: DefMetric[-1, g[-a,-b], CD]
  → xAct.def_metric!(-1, "g[-a, -b]", :CD)

In[3]: ToCanonical[g[-b,-a] - g[-a,-b]]
  → xAct.ToCanonical("g[-b, -a] - g[-a, -b]")
```

In **full mode** (default), expressions are also evaluated and results are displayed:

```
In[1]: DefManifold[M, 4, {a, b, c, d}]
Out[1]=   Manifold M (dim=4)

In[2]: DefMetric[-1, g[-a,-b], CD]
Out[2]=   Metric g[-a, -b] with covd CD

In[3]: ToCanonical[g[-b,-a] - g[-a,-b]]
Out[3]= 0
```

### REPL Commands

| Command | Action |
|:--------|:-------|
| `:help` | Show all commands |
| `:quit` / `:q` | Exit |
| `:reset` | Clear all definitions (calls `reset_state!()`) |
| `:history` | Show expression history |
| `:to julia` | Export session as Julia code |
| `:to toml` | Export session as TOML test file |
| `:to python` | Export session as Python adapter calls |
| `:to json` | Export session as JSON |

Session export is useful for converting an interactive exploration into a reproducible script or test file.

---

## Supported Translations

The translator recognizes the following Wolfram xAct functions. Functions not in this list are passed through as `eval(...)` with a warning.

!!! warning "Wolfram name differences"
    Some Wolfram function names differ from their translator input. Notably, Wolfram's `Simplification` is **not** recognized — use `Simplify` instead. See the [naming differences table](#key-differences-from-wolfram-xact) below.

### Definitions

| Wolfram Input | Julia Output | Notes |
|:--------------|:-------------|:------|
| `DefManifold[M, 4, {a,b}]` | `def_manifold!(:M, 4, [:a, :b])` | |
| `DefMetric[-1, g[-a,-b], CD]` | `def_metric!(-1, "g[-a, -b]", :CD)` | Auto-creates Riemann, Ricci, Weyl, Christoffel |
| `DefTensor[T[-a,-b], M]` | `def_tensor!(:T, ["-a", "-b"], :M)` | |
| `DefTensor[T[-a,-b], M, Symmetric[{-a,-b}]]` | `def_tensor!(:T, ..., symmetry_str=...)` | Symmetry kwarg |
| `DefBasis[e, M, {1,2,3,4}]` | `def_basis!(:e, :M, [1,2,3,4])` | |
| `DefChart[cart, M, {1,2,3,4}, {x,y,z,t}]` | `def_chart!(:cart, :M, ..., [:x,:y,:z,:t])` | |
| `DefPerturbation[pert, g]` | `def_perturbation!(:pert, :g)` | |

### Computation

| Wolfram Input | Julia Output | Notes |
|:--------------|:-------------|:------|
| `ToCanonical[expr]` | `ToCanonical("expr")` | Butler-Portugal canonicalization |
| `ContractMetric[expr]` | `Contract("expr")` | Metric contraction |
| `Simplify[expr]` | `Simplify("expr")` | Iterative Contract + ToCanonical |
| `CommuteCovDs[expr]` | `CommuteCovDs("expr")` | Covariant derivative commutation |
| `SortCovDs[expr]` | `SortCovDs("expr")` | Canonical CovD ordering |
| `Perturb[expr]` | `perturb("expr", 1)` | Perturbation expansion |
| `Perturbation[expr]` | `perturb_curvature("expr", 1)` | Curvature perturbation |
| `PerturbationOrder[expr]` | `PerturbationOrder("expr")` | Query perturbation order |
| `PerturbationAtOrder[expr, n]` | `PerturbationAtOrder("expr", n)` | Extract specific order |
| `VarD[field][expr]` | `VarD("field", "expr")` | Euler-Lagrange variation |
| `IBP[expr, v]` | `IBP("expr", :v)` | Integration by parts |
| `TotalDerivativeQ[expr]` | `TotalDerivativeQ("expr")` | Check total derivative |
| `CheckMetricConsistency[g]` | `CheckMetricConsistency("g")` | Validate metric |

### Basis / Components

| Wolfram Input | Julia Output | Notes |
|:--------------|:-------------|:------|
| `SetBasisChange[...]` | `SetBasisChange(...)` | Define basis transformation |
| `ChangeBasis[expr, basis]` | `ChangeBasis("expr", :basis)` | Change basis |
| `ToBasis[basis][expr]` | `ToBasis(:basis, "expr")` | Convert to basis |
| `FromBasis[basis][expr]` | `FromBasis(:basis, "expr")` | Convert from basis |
| `SetComponents[...]` | `SetComponents(...)` | Assign component values |
| `GetComponents[...]` | `GetComponents(...)` | Retrieve components |
| `TraceBasisDummy[expr]` | `TraceBasisDummy("expr")` | Trace over basis indices |

---

## Complete Migration Walkthrough

Here is a typical Wolfram xAct session and its Julia equivalent.

### Wolfram (original)

```wolfram
DefManifold[M, 4, {a, b, c, d, e, f}]
DefMetric[-1, g[-a, -b], CD]
DefTensor[T[-a, -b], M, Symmetric[{-a, -b}]]

(* Canonicalize a symmetric tensor *)
ToCanonical[T[-b, -a] - T[-a, -b]]
(* => 0 *)

(* Contract with the metric *)
ContractMetric[g[a, b] T[-a, -b]]
(* => T[a, a] — the trace *)

(* Simplify a Riemann expression *)
Simplify[RiemannCD[-a, -b, -c, -d] g[a, c]]
```

### Julia (translated)

Translate the above in one shot:

```bash
uv run xact-test translate -e \
  'DefManifold[M, 4, {a,b,c,d,e,f}]; DefMetric[-1, g[-a,-b], CD]; DefTensor[T[-a,-b], M, Symmetric[{-a,-b}]]; ToCanonical[T[-b,-a] - T[-a,-b]]; ContractMetric[g[a,b] T[-a,-b]]; Simplify[RiemannCD[-a,-b,-c,-d] g[a,c]]' \
  --to julia
```

Or write the equivalent Julia directly:

```julia
using xAct
reset_state!()

M = def_manifold!(:M, 4, [:a, :b, :c, :d, :e, :f])
g = def_metric!(-1, "g[-a,-b]", :CD)
T = def_tensor!(:T, ["-a", "-b"], :M; symmetry_str="Symmetric[{-a,-b}]")

ToCanonical("T[-b, -a] - T[-a, -b]")   # => "0"
Contract("g[a, b] T[-a, -b]")           # => trace
Simplify("RiemannCD[-a, -b, -c, -d] g[a, c]")
```

### As a TOML Test

```bash
uv run xact-test translate -e \
  'DefManifold[M, 4, {a,b,c,d}]; DefMetric[-1, g[-a,-b], CD]; ToCanonical[g[-b,-a]]' \
  --to toml
```

Output:

```toml
[meta]
id = "translated-session"
description = "Translated from Wolfram xAct"
tags = ["translated"]
layer = 1
oracle_is_axiom = true

[[setup]]
action = "DefManifold"
store_as = "M"
[setup.args]
name = "M"
dimension = 4
indices = ["a", "b", "c", "d"]

[[setup]]
action = "DefMetric"
[setup.args]
signdet = -1
metric = "g[-a, -b]"
covd = "CD"

[[tests]]
id = "test_1"
description = "ToCanonical: g[-b, -a]"

[[tests.operations]]
action = "ToCanonical"
[tests.operations.args]
expression = "g[-b, -a]"
```

---

## Key Differences from Wolfram xAct

| Concept | Wolfram | Julia / Translator |
|:--------|:--------|:-------------------|
| **Names** | Bare symbols: `M`, `T` | Julia Symbols: `:M`, `:T` |
| **Indices** | `T[-a, -b]` | Strings: `"-a"`, `"-b"` (in API calls) |
| **State** | Global kernel | Global registry; `reset_state!()` to clear |
| **Side effects** | Implicit | Explicit `!` suffix: `def_manifold!`, `def_tensor!` |
| **Contraction** | `ContractMetric` | `Contract` (translator accepts `ContractMetric`) |
| **Simplify** | `Simplification` (Wolfram name) | `Simplify` (use `Simplify` in translator, not `Simplification`) |
| **CovD ordering** | `SortCovDs` | Both `SortCovDs` and `CommuteCovDs` work |
| **Perturbation** | `Perturbation[expr]` | `Perturb[expr]` for general; `Perturbation[expr]` routes to `perturb_curvature` |
| **Auto-tensors** | `DefMetric` creates Riemann etc. | Same: `def_metric!` auto-creates all curvature tensors |
| **Scoping** | `Module`, `Block`, `With` | Not supported — translate procedural code manually |
| **License** | Wolfram Mathematica license | Free and open source (GPL-3.0) |

---

## Tips for a Smooth Migration

1. **Start with the REPL.** Use `uv run xact-test repl` to interactively translate your expressions and verify they produce the same results.

2. **Translate file-by-file.** Use `uv run xact-test translate --file notebook.wl --to julia` to convert existing notebooks.

3. **Check the warnings.** If the translator emits "Unrecognized function" warnings, the function may need manual translation or a different name (e.g., `Simplify` instead of Wolfram's `Simplification`). File an issue if you think it should be supported.

4. **Use `reset_state!()`** at the top of Julia scripts to ensure a clean session — just like restarting the Wolfram kernel.

5. **Stick to ASCII identifiers.** Wolfram special characters like `\[Mu]` or `\[CapitalDelta]` are not supported. Use standard Latin-alphabet names.

6. **Run the verification suite** to confirm parity with Wolfram results:

    ```bash
    uv run xact-test run tests/xtensor/canonicalization.toml \
      --adapter julia --oracle-mode snapshot --oracle-dir oracle
    ```

---

## Next Steps

- [Getting Started](getting-started.md) — Full Julia tutorial from scratch
- [Basics Tutorial](examples/basics.md) — Step-by-step walkthrough with Julia, Python, and Wolfram examples
- [Feature Status](status.md) — What's implemented and verified
- [Architecture](architecture.md) — How xAct.jl is structured
