# Spec: Wolfram Expression Translator

**Date:** 2026-03-13
**Status:** Proposed
**Priority:** High (Onboarding & Adoption)
**Ticket:** TBD

---

## 1. Problem Statement

A researcher migrating from Wolfram xAct has a notebook (or mental model) full of expressions like:

```mathematica
DefManifold[M, 4, {a, b, c, d}]
DefMetric[-1, g[-a,-b], CD]
DefTensor[T[-a,-b], M, Symmetric[{-a,-b}]]
result = ToCanonical[T[-a,-b] - T[-b,-a]]
```

Today, to use sxAct they must:

1. Understand the TOML action+args decomposition format
2. Manually map each Wolfram function call to a TOML `[[setup]]`/`[[tests.operations]]` block
3. Or learn the Python adapter API (`adapter.execute(ctx, "DefManifold", {"name": "M", ...})`)

This is a significant onboarding barrier. The project already has the infrastructure to *generate* Wolfram expressions from action dicts (`wolfram.py:_build_expr()`) and to *parse* Wolfram FullForm output (`normalize/ast_parser.py`), but the **reverse direction** — Wolfram expression → action dict — does not exist.

---

## 2. Proposed Solution

Three components, layered so each builds on the previous:

### 2.1 Core: `wl_to_action()` — Reverse Parser

A function that takes a Wolfram xAct expression string and returns a structured action dict:

```python
from sxact.translate import wl_to_action

wl_to_action("DefManifold[M, 4, {a, b, c, d}]")
# → {"action": "DefManifold", "args": {"name": "M", "dimension": 4, "indices": ["a","b","c","d"]}}

wl_to_action("DefMetric[-1, g[-a,-b], CD]")
# → {"action": "DefMetric", "args": {"signdet": -1, "metric": "g[-a,-b]", "covd": "CD"}}

wl_to_action("ToCanonical[T[-a,-b] - T[-b,-a]]")
# → {"action": "ToCanonical", "args": {"expression": "T[-a,-b] - T[-b,-a]"}}
```

This is the inverse of `wolfram.py:_build_expr()`. It recognizes xAct function heads and extracts structured arguments.

**Input scope**: Standard Wolfram Language function-call syntax for the 32 supported sxAct actions (30 xTensor + Evaluate + Assert). Not a general Wolfram Language parser — it handles the xAct vocabulary only.

### 2.2 CLI: `xact-test translate` — Multi-Format Translator

A new subcommand of the existing `xact-test` CLI (consistent with `run`, `snapshot`, `regen-oracle`, `benchmark`, `property`).

```bash
# Single expression
echo 'DefManifold[M, 4, {a, b, c, d}]' | xact-test translate --to julia
# → xAct.def_manifold!(:M, 4, [:a, :b, :c, :d])

echo 'DefManifold[M, 4, {a, b, c, d}]' | xact-test translate --to toml
# → [[setup]]
# → action = "DefManifold"
# → [setup.args]
# → name = "M"
# → ...

# Multi-line script (reads a .wl file or multi-line stdin)
xact-test translate --to toml < my_session.wl > tests/xtensor/my_session.toml

# Show action dict (JSON)
echo 'ToCanonical[T[-a,-b]]' | xact-test translate --to json
# → {"action": "ToCanonical", "args": {"expression": "T[-a,-b]"}}
```

**Output formats:**

| Format | Flag | Description |
|--------|------|-------------|
| `json` | `--to json` | Raw action dict (useful for piping) |
| `julia` | `--to julia` | Julia XTensor call |
| `toml` | `--to toml` | TOML test file |
| `python` | `--to python` | Python adapter `execute()` call |

### 2.3 Interactive: `xact-test repl` — Wolfram-Style REPL

An interactive session where users type Wolfram-style expressions, which are parsed, translated to Julia, and evaluated live against the Julia backend.

```
$ xact-test repl
Loading Julia runtime... done (12.3s)

sxAct REPL (Julia backend) — type Wolfram xAct expressions
Type :help for commands, :quit to exit

In[1]: DefManifold[M, 4, {a, b, c, d}]
  Manifold M (dim=4, indices=[a,b,c,d])

In[2]: DefMetric[-1, g[-a,-b], CD]
  Metric g with covariant derivative CD

In[3]: DefTensor[T[-a,-b], M, Symmetric[{-a,-b}]]
  Tensor T[-a,-b] on M (Symmetric)

In[4]: ToCanonical[T[-a,-b] - T[-b,-a]]
Out[4]= 0

In[5]: :to julia
  --- Julia translation of session ---
  xAct.def_manifold!(:M, 4, [:a, :b, :c, :d])
  xAct.def_metric!(-1, "g[-a,-b]", :CD)
  xAct.def_tensor!(:T, ["-a", "-b"], :M; symmetry=:Symmetric)
  xAct.ToCanonical("T[-a,-b] - T[-b,-a]")
```

**REPL modes:**

| Mode | Flag | Requires Julia | Description |
|------|------|----------------|-------------|
| Live (default) | — | Yes | Parse, translate, evaluate, show result |
| Translate-only | `--no-eval` | No | Parse and translate only, no Julia execution |

**REPL commands:**

| Command | Description |
|---------|-------------|
| `:help` | Show available commands and syntax |
| `:quit` / `:q` | Exit REPL |
| `:reset` | Clear all definitions (calls `reset_state!()`) |
| `:to julia` | Dump current session as Julia code |
| `:to toml` | Dump current session as TOML test file |
| `:to python` | Dump current session as Python adapter calls |
| `:history` | Show expression history |

---

## 3. Design Details

### 3.1 WL Surface-Syntax Parser

The existing `normalize/ast_parser.py` handles FullForm syntax (`Head[arg1, arg2]`) but does **not** handle curly braces, infix operators, assignments, comments, or multi-line expressions. The translator needs a **superset parser** for standard Wolfram Language surface syntax (the subset used by xAct). This is distinct from the FullForm normalizer — the normalizer stays as-is.

**Proposed location:** `packages/sxact/src/sxact/translate/wl_parser.py`

**Grammar (informal PEG):**

```
Session     ← (Comment / Line)*
Line        ← Assignment (';' Assignment)* ';'?
Assignment  ← Identifier '=' Postfix / Postfix '//' Identifier / Expr
Expr        ← Sum
Sum         ← Product (('+' / '-') Product)*
Product     ← Unary (('*' / IMPLICIT_MUL) Unary)*
Unary       ← '-' Unary / Postfix
Postfix     ← Primary ('[' ArgList ']')*       # f[x][y] chained application
Primary     ← Number / String / List / '(' Expr ')' / Identifier
List        ← '{' ArgList? '}'
ArgList     ← BracketExpr (',' BracketExpr)*
BracketExpr ← BracketSum
BracketSum  ← BracketProduct (('+' / '-') BracketProduct)*
BracketProduct ← BracketUnary (('*' / IMPLICIT_MUL) BracketUnary)*
BracketUnary   ← SignedIndex / '-' BracketUnary / Postfix
SignedIndex ← '-' Identifier                   # covariant index: -a, -bcd
Number      ← [0-9]+ ('.' [0-9]+)?
String      ← '"' [^"]* '"'
Identifier  ← [a-zA-Z_$\p{L}] [a-zA-Z0-9_$`\p{L}]*
Comment     ← '(*' .* '*)'
```

**Design challenge: the `-index` ambiguity.**

In xAct, `-a` inside brackets denotes a covariant index (not negation). But `-` at the expression level is subtraction/negation. Examples:

| Input | Meaning | Parse |
|-------|---------|-------|
| `T[-a,-b]` | Tensor with covariant indices a,b | `T[SignedIndex(a), SignedIndex(b)]` |
| `T[-a,-b] - T[-b,-a]` | Subtraction of two tensors | `Sum(T[...], Neg(T[...]))` |
| `-3` | Negative number | `Neg(3)` |
| `-T[-a,-b]` | Negated tensor expression | `Neg(T[SignedIndex(a), SignedIndex(b)])` |

**Resolution**: The grammar uses **two expression sub-grammars**. At the top level (`Expr`), `-` is always an operator (subtraction/negation). Inside bracket arguments (`BracketExpr` / `ArgList`), the parser first tries `SignedIndex` (a `-` followed immediately by an identifier with no intervening whitespace), and falls back to treating `-` as negation if that fails. This mirrors how the existing `normalize/ast_parser.py` tokenizes `-a` as a single token via regex (`-[a-zA-Z][a-zA-Z0-9]*`).

**Multi-line handling**: Expressions with unbalanced brackets continue across newlines. The parser tracks bracket depth; a newline within `[...]`, `(...)`, or `{...}` is treated as whitespace, not as a line terminator. This handles the common case of wrapped long definitions:

```mathematica
DefTensor[T[-a,-b,-c,-d], M,
  RiemannSymmetric[{-a,-b,-c,-d}]]
```

**Postfix `//` (pipe) support**: The common Wolfram idiom `expr // Simplify` is supported as syntactic sugar for `Simplify[expr]`. The grammar handles this via the `Assignment` rule: `Postfix '//' Identifier` rewrites to `Identifier[Postfix]` during parsing.

### 3.2 Action Recognition — Complete Mapping

Once parsed, the translator inspects the AST head to determine the action. This table is the **complete** mapping of all 32 sxAct actions.

#### Wolfram name → sxAct action name (where they differ)

| Wolfram Function | sxAct Action | Notes |
|------------------|-------------|-------|
| `ContractMetric` | `Contract` | Name differs |
| `ChristoffelP` | `Christoffel` | Name differs |
| `IBP` | `IntegrateByParts` | Name differs |
| `Jacobian` | `GetJacobian` | Name differs |

All other function names are identical between Wolfram and sxAct.

#### Definition actions (become `[[setup]]` in TOML)

| Wolfram Head | sxAct Action | Arg Extraction |
|--------------|-------------|----------------|
| `DefManifold` | `DefManifold` | `args[0]`→name, `args[1]`→dimension, `args[2]`→indices (List) |
| `DefMetric` | `DefMetric` | `args[0]`→signdet, `args[1]`→metric (re-serialize with indices), `args[2]`→covd |
| `DefTensor` | `DefTensor` | `args[0]`→name+indices (decompose, see 3.3), `args[1]`→manifold, `args[2]`→symmetry (optional) |
| `DefBasis` | `DefBasis` | `args[0]`→name, `args[1]`→vbundle, `args[2]`→cnumbers (List) |
| `DefChart` | `DefChart` | `args[0]`→name, `args[1]`→manifold, `args[2]`→cnumbers (List), `args[3]`→scalars (List) |
| `DefPerturbation` | `DefPerturbation` | `args[0]`→tensor, `args[1]`→background, `args[2]`→order |

#### Expression / computation actions (become `[[tests.operations]]` in TOML)

| Wolfram Head | sxAct Action | Arg Extraction |
|--------------|-------------|----------------|
| `ToCanonical` | `ToCanonical` | `args[0]`→expression (re-serialize) |
| `Simplify` | `Simplify` | `args[0]`→expression, `args[1]`→assumptions (optional) |
| `ContractMetric` | `Contract` | `args[0]`→expression |
| `CommuteCovDs` | `CommuteCovDs` | `args[0]`→expression, `args[1]`→covd, `args[2,3]`→indices |
| `Perturb` | `Perturb` | `args[0]`→expression, `args[1]`→order |
| `PerturbationOrder` | `PerturbationOrder` | `args[0]`→tensor |
| `PerturbationAtOrder` | `PerturbationAtOrder` | `args[0]`→background, `args[1]`→order |
| `CheckMetricConsistency` | `CheckMetricConsistency` | `args[0]`→metric |
| `IBP` | `IntegrateByParts` | `args[0]`→expression, `args[1]`→covd |
| `TotalDerivativeQ` | `TotalDerivativeQ` | `args[0]`→expression, `args[1]`→covd |
| `VarD` | `VarD` | Chained: `VarD[variable][expression]` → variable, expression, covd (from context or prompted) |
| `SetBasisChange` | `SetBasisChange` | `args[0]`→from_basis, `args[1]`→to_basis, `args[2]`→matrix |
| `ChangeBasis` | `ChangeBasis` | `args[0]`→expression, `args[1]`→target_basis |
| `Jacobian` | `GetJacobian` | `args[0]`→basis1, `args[1]`→basis2 |
| `BasisChangeQ` | `BasisChangeQ` | `args[0]`→from_basis, `args[1]`→to_basis |
| `SetComponents` | `SetComponents` | `args[0]`→tensor, `args[1]`→components |
| `GetComponents` | `GetComponents` | `args[0]`→tensor, `args[1]`→basis |
| `CTensorQ` | `CTensorQ` | `args[0]`→tensor, `args[1...]`→bases |
| `ToBasis` | `ToBasis` | Chained: `ToBasis[basis][expression]` → basis, expression |
| `FromBasis` | `FromBasis` | Chained: `FromBasis[basis][expression]` → basis, expression (same as Wolfram) |
| `TraceBasisDummy` | `TraceBasisDummy` | `args[0]`→expression |
| `ChristoffelP` | `Christoffel` | `args[0]`→covd (maps to metric+basis in adapter) |

#### Special actions (no Wolfram function head)

| Pattern | sxAct Action | Extraction |
|---------|-------------|------------|
| Unrecognized head `F[...]` | `Evaluate` | Entire expression re-serialized as string |
| Bare expression (no `[...]`) | `Evaluate` | Expression re-serialized as string |
| `expr == 0`, `expr === True` | `Assert` | condition = re-serialized comparison |

#### PerturbCurvature (special case)

`PerturbCurvature` has no single Wolfram head — it maps to various forms (`Perturbation[expr, order]` or key-based like `Riemann1[covd]`). The recognizer matches `Perturbation[expr, order]` → `PerturbCurvature` and known keys (`Christoffel1`, `Riemann1`, `Ricci1`, `RicciScalar1`) to the `key` arg.

### 3.3 Context-Sensitive Arg Extraction

Some actions require context-sensitive parsing of their arguments:

**`DefTensor` first argument**: `DefTensor[T[-a,-b], M, ...]` — the first argument `T[-a,-b]` is syntactically identical to a function call, but semantically it's a tensor-name-with-indices declaration. The recognizer knows that when the head is `DefTensor`, the first argument is always a declaration and must be decomposed:

```python
# AST:  Node("DefTensor", [Node("T", [Leaf("-a"), Leaf("-b")]), Leaf("M"), ...])
# Extract: name = head of first arg ("T"), indices = args of first arg (["-a", "-b"])
```

**`VarD` chained application**: `VarD[field][expression]` parses as a chained call. The recognizer unwraps it:

```python
# AST:  Node(Node("VarD", [Leaf("field")]), [Leaf("expression")])
# Extract: variable = "field", expression = re-serialize outer args
# Note: the `covd` arg required by the Julia adapter is not present in the Wolfram
# form. The REPL/CLI can prompt for it, or the TOML renderer can leave a placeholder.
```

**`CommuteCovDs` arg mismatch**: Wolfram uses `CommuteCovDs[expr, cd1, cd2]` with separate cd1/cd2 args, but the Julia adapter expects `covd` + `indices` (list of 2). The recognizer extracts `cd1` and `cd2` and maps them to `{"covd": cd1, "indices": [cd1_index, cd2_index]}` based on the TOML schema.

### 3.4 Re-serialization

When extracting expression arguments (e.g., the argument to `ToCanonical`), the AST subtree must be re-serialized to an infix string that both the Wolfram and Julia adapters accept. The existing `normalize/serializer.py` handles `Plus`/`Times` infix but the translator needs a serializer for the **input** grammar (curly braces, signed indices, string literals).

**Proposed location:** `packages/sxact/src/sxact/translate/wl_serializer.py`

### 3.5 Output Renderers

Each output format is a function that takes a list of action dicts and produces text. All renderers live in a single module since each is a short function:

**Proposed location:** `packages/sxact/src/sxact/translate/renderers.py`

| Function | Description |
|----------|-------------|
| `to_json(actions)` | `json.dumps` with indent |
| `to_julia(actions)` | Julia XTensor calls (mirrors `julia_stub.py` dispatch) |
| `to_toml(actions)` | TOML test file with setup/test sections |
| `to_python(actions)` | Python `adapter.execute()` calls |

### 3.6 TOML Generation Strategy

When converting a multi-line Wolfram session to TOML, the translator must distinguish **setup** (definitions) from **test operations** (computations):

- **Setup actions** (always `[[setup]]`): `DefManifold`, `DefMetric`, `DefTensor`, `DefBasis`, `DefChart`, `DefPerturbation`
- **Compute actions** (become `[[tests.operations]]`): Everything else

**Heuristic for test boundaries:**

1. Each assignment or comparison starts a new `[[tests]]` block
2. A compute expression followed by an assertion (`== 0`, `=== True`) groups into one test
3. Consecutive unassigned computes each become a separate test
4. Assignments (`result = ToCanonical[...]`) generate `store_as` fields

**Example:** Wolfram session → TOML output:

```mathematica
(* Input *)
DefManifold[M, 4, {a, b, c, d}]
DefMetric[-1, g[-a,-b], CD]
DefTensor[S[-a,-b], M, Symmetric[{-a,-b}]]
result = ToCanonical[S[-a,-b] - S[-b,-a]]
result == 0
Simplify[RicciCD[-a,-b] - RicciCD[-b,-a]]
```

```toml
# Output
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
store_as = "g"
[setup.args]
signdet = -1
metric = "g[-a,-b]"
covd = "CD"

[[setup]]
action = "DefTensor"
store_as = "S"
[setup.args]
name = "S"
indices = ["-a", "-b"]
manifold = "M"
symmetry = "Symmetric[{-a,-b}]"

[[tests]]
id = "test_1"
description = "ToCanonical: S[-a,-b] - S[-b,-a]"

[[tests.operations]]
action = "ToCanonical"
store_as = "result"
[tests.operations.args]
expression = "S[-a,-b] - S[-b,-a]"

[[tests.operations]]
action = "Assert"
[tests.operations.args]
condition = "$result == 0"

[[tests]]
id = "test_2"
description = "Simplify: RicciCD[-a,-b] - RicciCD[-b,-a]"

[[tests.operations]]
action = "Simplify"
[tests.operations.args]
expression = "RicciCD[-a,-b] - RicciCD[-b,-a]"
```

---

## 4. Error Handling

### Parse Errors

Parse errors include the position in the input and the unexpected token:

```
ParseError at column 15: unexpected token '/@'
  DefManifold[M, 4, {a, b, c, d}] /@ something
                     ^
  Note: /@ (Map) is a Wolfram programming construct not supported by the translator.
  Use explicit function application: F[x] instead of F /@ {x, y, z}
```

### Unsupported Wolfram Idioms

When the parser encounters a construct it recognizes but cannot translate, it emits a specific suggestion:

| Wolfram Idiom | Error Message |
|---------------|---------------|
| `%` (Out) | `%` (last output) is not supported. Assign results explicitly: `result = ...` |
| `expr /. rule` | Rule replacement (`/.`) is not supported. Apply operations directly. |
| `@@`, `/@` | `Apply`/`Map` are programming constructs. Use explicit function calls. |
| `Module[...]` | Local scoping is not supported. Write expressions at top level. |

### Unrecognized Heads

Expressions with unrecognized heads are **not errors** — they become `Evaluate` actions with a warning:

```
Warning: unrecognized function 'MyCustomFunction' — treating as Evaluate.
  Known xAct functions: DefManifold, DefMetric, DefTensor, ToCanonical, ...
```

---

## 5. Relationship to Existing Components

```
                     ┌──────────────────────────────────┐
                     │     Wolfram Expression Input      │
                     │  "DefManifold[M, 4, {a,b,c,d}]"  │
                     └──────────────┬───────────────────┘
                                    │
                              wl_parser.py         ← NEW
                                    │
                              ┌─────▼─────┐
                              │  AST Tree  │
                              └─────┬─────┘
                                    │
                         action_recognizer.py      ← NEW
                                    │
                          ┌─────────▼─────────┐
                          │   Action Dict      │
                          │ {"action":...,     │
                          │  "args":{...}}     │
                          └────┬───┬───┬───┬──┘
                               │   │   │   │
                    ┌──────────┘   │   │   └──────────┐
                    ▼              ▼   ▼              ▼
                 to_julia     to_toml  to_json  to_python   ← NEW
                    │              │       │         │        (renderers.py)
                    ▼              ▼       ▼         ▼
          Julia XTensor    TOML test   JSON dict  Python adapter
              calls          file                    calls

  Existing components (NOT modified):
  ────────────────────────────────────
  normalize/ast_parser.py  (FullForm parser — different purpose)
  wolfram.py:_build_expr() (Forward direction: action→Wolfram)
  julia_stub.py            (Forward direction: action→Julia)
  TOML test schema         (No schema changes)
  adapter.execute()        (Interface unchanged)
```

---

## 6. Scope & Constraints

### In Scope

- Parsing standard Wolfram xAct function-call syntax for the 32 supported actions
- Infix arithmetic expressions in arguments (`T[-a,-b] + T[-b,-a]`)
- Curly-brace lists (`{a, b, c}`)
- Chained application (`VarD[field][expr]`, `ToBasis[basis][expr]`)
- Multi-line expressions (balanced bracket continuation across newlines)
- Semicolons as expression separators
- Assignments (`result = ...` → `store_as`)
- Postfix application (`expr // Simplify` → `Simplify[expr]`)
- Comments (`(* ... *)` — skipped)
- String literals (`";"`, `"∇"`)
- Unicode identifiers for tensor names and indices
- Four output formats: JSON, Julia, TOML, Python
- REPL with live Julia evaluation and `--no-eval` translate-only mode

### Out of Scope

- General Wolfram Language parsing (pattern matching `_`, rule replacement `/.` `//.`, `Module`, `Block`, control flow, pure functions `#&`)
- Parsing BoxData or InterpretationBox from `.nb` files (see `specs/2026-03-05-notebook-extraction.md`)
- Parsing FullForm output (already handled by `normalize/ast_parser.py`)
- Semantic validation of expressions (adapter does this at execution time)
- Chacana syntax (separate project; see `specs/2026-03-08-chacana-specification.md`)

### Known Limitations

- **Implicit multiplication without space**: `2T[-a,-b]` (coefficient glued to symbol) is not supported. Use `2 T[-a,-b]` or `2*T[-a,-b]`.
- **`VarD` covd argument**: Wolfram's `VarD[field][expr]` has no explicit `covd` argument, but the Julia adapter requires one. The translator emits a `# TODO: add covd` placeholder in TOML output.
- **`ComponentValue` syntax**: In Wolfram, component access is bare indexing (`tensor[1,2,3]`), which is syntactically identical to a function call. The translator cannot distinguish this from `Evaluate` without semantic context. Users should use the explicit `ComponentValue[tensor, {1,2,3}, {basis}]` form.

---

## 7. File Layout

```
packages/sxact/src/sxact/translate/
├── __init__.py             # Public API: wl_to_action(), wl_to_actions(), translate()
├── wl_parser.py            # Recursive-descent parser for WL surface syntax
├── wl_serializer.py        # Re-serialize AST subtrees to infix strings
├── action_recognizer.py    # Map AST head → action dict (complete 32-action table)
└── renderers.py            # All output renderers: to_json, to_julia, to_toml, to_python

packages/sxact/src/sxact/cli/
├── translate.py            # Subcommand: xact-test translate
└── repl.py                 # Subcommand: xact-test repl
```

---

## 8. Implementation Tasks

Ordered by dependency. Each task is independently testable.

### Phase 1: Core Parser & Recognizer

| # | Task | Depends On | Estimate |
|---|------|-----------|----------|
| 1 | WL surface-syntax parser with bracket-context index handling (`wl_parser.py`) | — | Medium |
| 2 | WL serializer for infix re-emission (`wl_serializer.py`) | 1 | Small |
| 3 | Action recognizer: all 32 actions, Wolfram↔sxAct name mapping, context-sensitive DefTensor/VarD extraction (`action_recognizer.py`) | 1, 2 | Medium |
| 4 | Unit tests for parser + recognizer (see Appendix A test matrix) | 1, 2, 3 | Medium |

### Phase 2: Output Renderers & CLI

| # | Task | Depends On | Estimate |
|---|------|-----------|----------|
| 5 | All renderers: `to_json`, `to_julia`, `to_toml`, `to_python` (`renderers.py`) | 3 | Medium |
| 6 | `xact-test translate` subcommand (stdin/file/arg input, `--to` flag) | 5 | Small |
| 7 | Tests for renderers + round-trip validation (see Appendix A) | 5, 6 | Medium |

### Phase 3: REPL

| # | Task | Depends On | Estimate |
|---|------|-----------|----------|
| 8 | `xact-test repl` interactive loop with Julia integration + startup progress | 3, 5 | Medium |
| 9 | REPL `--no-eval` mode (pure translation, no Julia) | 8 | Small |
| 10 | REPL session export (`:to julia`, `:to toml`, `:to python`) | 5, 8 | Small |
| 11 | Integration tests: round-trip WL→action→Julia→result | 8 | Medium |

### Phase 4: Polish

| # | Task | Depends On | Estimate |
|---|------|-----------|----------|
| 12 | Error messages with position + WL idiom suggestions (see Section 4) | 3 | Small |
| 13 | Getting-started guide for Wolfram users | 6, 8 | Small |

---

## 9. Success Criteria

1. **Round-trip fidelity**: For every expression produced by `wolfram.py:_build_expr()`, `wl_to_action(build_expr(action, args))` returns the original action dict (modulo formatting). Exception: `ComponentValue` bare-indexing form is not round-trippable (see Limitations).
2. **Session conversion**: A 10-line Wolfram xAct session (including multi-line expressions and comments) can be pasted into `xact-test translate --to toml` and produce a valid, runnable TOML test file.
3. **REPL usability**: A researcher familiar with Wolfram xAct can define a manifold, metric, and tensor, then canonicalize an expression — all using familiar syntax — within the first minute after the Julia runtime finishes loading.
4. **Zero new dependencies**: Uses only the existing `sxact` package and standard library.
5. **Appendix A coverage**: All test matrix expressions parse and round-trip correctly.

---

## 10. Interdependencies

- **Not blocked by** anything — uses existing adapter infrastructure.
- **Enhances** the notebook extraction pipeline (`specs/2026-03-05-notebook-extraction.md`) — the WL parser can be reused for parsing extracted notebook cells from ButlerExamples.nb.
- **Complements** Chacana — Chacana is the long-term DSL; this translator is the migration bridge for existing Wolfram users. They serve different audiences and timelines.
- **Feeds into** the public Python API (when it exists) — the REPL can evolve into the interactive API frontend.

---

## Appendix A: Test Matrix

These expressions serve as acceptance tests for the parser and recognizer. Each must parse correctly, produce the expected action dict, and (where applicable) round-trip through `_build_expr()`.

### A.1 Definition Parsing

| # | Input | Expected Action | Key Args |
|---|-------|----------------|----------|
| T1 | `DefManifold[M, 4, {a, b, c, d}]` | `DefManifold` | name="M", dimension=4, indices=["a","b","c","d"] |
| T2 | `DefMetric[-1, g[-a,-b], CD]` | `DefMetric` | signdet=-1, metric="g[-a,-b]", covd="CD" |
| T3 | `DefTensor[T[-a,-b], M, Symmetric[{-a,-b}]]` | `DefTensor` | name="T", indices=["-a","-b"], manifold="M", symmetry="Symmetric[{-a,-b}]" |
| T4 | `DefTensor[V[a], M]` | `DefTensor` | name="V", indices=["a"], manifold="M" |
| T5 | `DefTensor[R[-a,-b,-c,-d], M,`<br>`  RiemannSymmetric[{-a,-b,-c,-d}]]` | `DefTensor` | (multi-line — bracket continuation) |
| T6 | `DefBasis[tetrad, TangentM, {1,2,3,4}]` | `DefBasis` | name="tetrad", vbundle="TangentM", cnumbers=[1,2,3,4] |
| T7 | `DefChart[cart, M, {1,2,3,4}, {x,y,z,t}]` | `DefChart` | name="cart", manifold="M", cnumbers=[1,2,3,4], scalars=["x","y","z","t"] |
| T8 | `DefPerturbation[h, g, eps]` | `DefPerturbation` | tensor="h", background="g", parameter="eps" |

### A.2 Expression Parsing

| # | Input | Expected Action | Key Args |
|---|-------|----------------|----------|
| T9 | `ToCanonical[T[-a,-b] - T[-b,-a]]` | `ToCanonical` | expression="T[-a,-b] - T[-b,-a]" |
| T10 | `Simplify[R[-a,-b,-c,-d] + R[-a,-c,-d,-b]]` | `Simplify` | expression="R[-a,-b,-c,-d] + R[-a,-c,-d,-b]" |
| T11 | `ContractMetric[g[-a,b] V[-b]]` | `Contract` | expression="g[-a,b] V[-b]" |
| T12 | `Perturb[g[-a,-b], 2]` | `Perturb` | expression="g[-a,-b]", order=2 |
| T13 | `CommuteCovDs[T[-a,-b], CD, {-a,-b}]` | `CommuteCovDs` | expression="T[-a,-b]", covd="CD" |
| T14 | `IBP[CD[-a][V[a]], CD]` | `IntegrateByParts` | expression="CD[-a][V[a]]", covd="CD" |
| T15 | `TotalDerivativeQ[CD[-a][V[a]], CD]` | `TotalDerivativeQ` | expression="CD[-a][V[a]]", covd="CD" |
| T16 | `ChristoffelP[CD]` | `Christoffel` | covd="CD" |

### A.3 Chained Application

| # | Input | Expected Action | Key Args |
|---|-------|----------------|----------|
| T17 | `VarD[g[-a,-b]][R[]]` | `VarD` | variable="g[-a,-b]", expression="R[]" |
| T18 | `ToBasis[tetrad][T[-a,-b]]` | `ToBasis` | basis="tetrad", expression="T[-a,-b]" |
| T19 | `FromBasis[tetrad][T[-a,-b]]` | `FromBasis` | basis="tetrad", expression="T[-a,-b]" |

### A.4 Syntactic Sugar & Edge Cases

| # | Input | Expected Action | Notes |
|---|-------|----------------|-------|
| T20 | `T[-a,-b] - T[-b,-a] // ToCanonical` | `ToCanonical` | Postfix `//` rewrite |
| T21 | `result = ToCanonical[S[-a,-b]]` | `ToCanonical` | Assignment → store_as="result" |
| T22 | `(* This is a comment *)` | (skipped) | Comment handling |
| T23 | `DefManifold[M, 4, {a,b,c,d}]; DefMetric[-1, g[-a,-b], CD]` | Two actions | Semicolon separator |
| T24 | `2 T[-a,-b] + 3 S[-a,-b]` | `Evaluate` | Unrecognized head → Evaluate |
| T25 | `Simplify[expr, Assumptions -> {x > 0}]` | `Simplify` | String args with `->` (treated as opaque) |
| T26 | `DefMetric[-1, g[-a,-b], CD, {";", "∇"}]` | `DefMetric` | String literal arguments |
| T27 | `Jacobian[basis1, basis2]` | `GetJacobian` | Wolfram↔sxAct name mapping |
| T28 | `` (empty/blank lines) | (skipped) | Whitespace handling |
