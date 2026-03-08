---
date: 2026-03-06T23:06:04-03:00
git_commit: fdd517a
branch: main
directory: /var/home/sasha/para/areas/dev/gh/sk/sxAct
issue: sxAct-z1c
status: handoff
---

# Handoff: Extract xPerm tests from ButlerExamples.nb (sxAct-z1c)

## Context

sxAct-z1c calls for automated extraction of xPerm test cases from
`resources/xAct/Documentation/English/ButlerExamples.nb` — a Mathematica 5.2
plain-text notebook. The file stores all Input/Output cells as `\(expr\)`
linear WL syntax (readable without a Wolfram kernel), making automated
extraction feasible.

The goal is to emit TOML test files under `tests/xperm/butler_examples/`,
generate oracle snapshots (using the Julia adapter as axiom), and verify
>50 tests pass via `xact-test run --adapter julia --oracle-mode snapshot`.

## Current Status

### Completed
- [x] Wrote `scripts/extract_butler.py` — full bracket-counting parser,
      extracts 92 tests across 16 TOML files from all 16 Example sections
- [x] All 16 TOML files written to `tests/xperm/butler_examples/`
- [x] All 16 files pass TOML validation (`tomllib.load()` clean)
- [x] Test runner schema validation passes (no schema errors)
- [x] Wrote `scripts/gen_butler_snapshots.py` — drives JuliaAdapter, writes
      oracle JSON/wl snapshots to `oracle/xperm/butler_examples/`

### In Progress
- [ ] **Fix `_is_tensor_expr` false-positive** — root cause of all test failures
      (see Key Learnings #1). After the fix, snapshot generation should produce
      >50 "True" results.
- [ ] Run `uv run python scripts/gen_butler_snapshots.py` to generate snapshots
- [ ] Verify `xact-test run --adapter julia --oracle-mode snapshot tests/xperm/butler_examples/` shows >50 passing

### Planned
- [ ] Close sxAct-z1c once >50 tests pass
- [ ] Commit scripts, TOML files, and oracle snapshots

## Critical Files

1. `src/sxact/adapter/julia_stub.py:552-558` — `_TENSOR_EXPR_RE` and `_is_tensor_expr()`: **the bug is here**
2. `src/sxact/adapter/julia_stub.py:173-184` — `execute()` Evaluate branch that calls `_is_tensor_expr`
3. `scripts/extract_butler.py` — full notebook parser (bracket-counting, not regex-spanning)
4. `scripts/gen_butler_snapshots.py` — snapshot generator using JuliaAdapter directly
5. `tests/xperm/butler_examples/example_0.toml` — canonical example of generated TOML

## Recent Changes

> All new, not yet committed

- `scripts/extract_butler.py` — 561-line notebook parser; generates TOML from ButlerExamples.nb
- `scripts/gen_butler_snapshots.py` — 161-line snapshot generator using JuliaAdapter
- `tests/xperm/butler_examples/example_0.toml` through `example_14.toml` — 16 generated TOML files (92 tests total)

## Key Learnings

### 1. `_is_tensor_expr` incorrectly classifies xPerm calls as tensor expressions

**This is the blocking bug.**

`_TENSOR_EXPR_RE = re.compile(r'\w+\[-?\w')` matches any `identifier[-optional_word`
pattern. It returns True for `Orbit[7, GenSet[a, b, c]]` because `GenSet[a` has a
word char after `[`. This causes the `execute()` Evaluate branch to skip Julia
evaluation and return the expression unchanged.

**Fix needed in `src/sxact/adapter/julia_stub.py:552`:**
```python
# Current (too broad — matches xPerm calls):
_TENSOR_EXPR_RE = re.compile(r'\w+\[-?\w')

# Fix (only match actual tensor index syntax — negative index prefix):
_TENSOR_EXPR_RE = re.compile(r'\w+\[-[a-z]')
```

A tensor expression has a NEGATIVE index like `Sps[-spa, -spb]` (mandatory `-` before
the index identifier). Plain xPerm function calls use positive integer or symbol args:
`Orbit[7, ...]`, `GenSet[a, b]`, `PermMemberQ[ID, SGS]`. The `-` prefix is the
reliable discriminator.

After this fix, `_is_tensor_expr('Orbit[7, GenSet[a, b, c]]')` returns False
and the expression goes through `_execute_expr()` → Julia evaluation → correct result.

### 2. Notebook parsing approach: bracket-counting, not regex

The notebook has Input/Output cells in `Cell[CellGroupData[{...}, Open]]` blocks.
A naive regex like `\\\((.+?)\\\)` with DOTALL spans across cell boundaries —
the closing `\)` in the Input cell pairs with content in the Output cell.

The correct approach (implemented in `scripts/extract_butler.py`):
- Use `find_matching_bracket()` (bracket-counter with string-literal awareness)
  to extract each `Cell[BoxData[...], "Type"]` individually
- Extract the `BoxData` content per-cell, then call `extract_wl_content()` on it
- Cell type ("Input"/"Output") is found by `re.search(r',"(Input|Output)"]\s*$', cell_content)`
  — searched INSIDE `cell_content`, not after it

### 3. Multi-statement setup cells use double-semicolon join

Multi-statement input cells like `Cell[BoxData[{\(\(a=...;\)\), "\n", \(\(b=...;\)\)}]`
get joined as `a=...;; b=...;` (double semicolons). The `generate_toml()` function
splits on `;\s*` which produces empty strings from `;;` — these are filtered
with `if s.strip()`. This is working correctly.

### 4. The `\\\(` regex confusion

In a Python raw string, `r'\\\('` is 4 chars (`\`, `\`, `\`, `(`).
As a regex: `\\` = match literal `\`, `\(` = match literal `(`. So it matches `\(`.
But testing via `python -c "..."` with the shell double-quoting can mangle
backslash counts — always test patterns in a `.py` file, not via `-c`.

## Open Questions

- [ ] Will all 92 tests pass after the `_is_tensor_expr` fix, or will some xPerm
      functions (e.g. `Schreier[...]`, `Group[...]`) need additional `_wl_to_jl`
      translation rules?
- [ ] `Timing[expr]` appears in example_10 — Julia probably doesn't have `Timing`.
      That test (`timing_02`) may need a skip annotation.
- [ ] `TranslatePerm[First@RightCosetRepresentative[...], Perm]` in example_13 —
      `First@` is WL function composition that `_wl_to_jl` may not handle.
      Check if the current `_rewrite_postfix` handles `@`.

## Next Steps

1. **Fix `_is_tensor_expr`** [Priority: HIGH, ~2 min]
   ```python
   # src/sxact/adapter/julia_stub.py:552
   _TENSOR_EXPR_RE = re.compile(r'\w+\[-[a-z]')
   ```
   Verify existing 40 xTensor tests still pass:
   ```bash
   uv run pytest tests/test_julia_adapter.py -q
   uv run xact-test run --adapter julia --oracle-mode snapshot oracle tests/xtensor/ --oracle-dir oracle
   ```

2. **Run snapshot generation** [Priority: HIGH, ~5-10 min]
   ```bash
   uv run python scripts/gen_butler_snapshots.py
   ```
   Expect most tests to return "True". Note any failures.

3. **Verify target count** [Priority: HIGH]
   ```bash
   uv run xact-test run --adapter julia --oracle-mode snapshot \
     tests/xperm/butler_examples/ --oracle-dir oracle
   ```
   Goal: >50 passing tests.

4. **Handle failures** [Priority: MEDIUM]
   - `Timing[expr]` → add `skip = "Timing not implemented in Julia"` to those tests
   - `First@expr` → may need a `_wl_to_jl` rule for `f@x` → `f(x)`
   - `Schreier[...]` structural equality — check if Julia's `==` handles it

5. **Commit and close** [Priority: HIGH]
   ```bash
   git add scripts/ tests/xperm/butler_examples/ oracle/xperm/butler_examples/
   git commit -m "feat: extract 92 xPerm butler tests from ButlerExamples.nb (sxAct-z1c)"
   git push
   bd close z1c
   ```

## Artifacts

**New files (not committed):**
- `scripts/extract_butler.py` — notebook extractor
- `scripts/gen_butler_snapshots.py` — oracle snapshot generator
- `tests/xperm/butler_examples/example_0.toml` (6 tests)
- `tests/xperm/butler_examples/example_1_symmetries_of_the_square.toml` (9 tests)
- `tests/xperm/butler_examples/example_2_projective_plane_of_order_2.toml` (24 tests)
- `tests/xperm/butler_examples/example_3_mathieu.toml` (6 tests)
- `tests/xperm/butler_examples/example_4.toml` (2 tests)
- `tests/xperm/butler_examples/example_5_rubik.toml` (8 tests)
- `tests/xperm/butler_examples/example_6.toml` (4 tests)
- `tests/xperm/butler_examples/example_7.toml` (2 tests)
- `tests/xperm/butler_examples/example_8.toml` (1 test)
- `tests/xperm/butler_examples/example_9.toml` (1 test)
- `tests/xperm/butler_examples/example_10.toml` (2 tests)
- `tests/xperm/butler_examples/example_11_symmetries_of_the_square_signatures.toml` (11 tests)
- `tests/xperm/butler_examples/example_11b.toml` (2 tests)
- `tests/xperm/butler_examples/example_12_projective_plane_of_order_2_signatures.toml` (6 tests)
- `tests/xperm/butler_examples/example_13_riemann.toml` (6 tests)
- `tests/xperm/butler_examples/example_14.toml` (2 tests)

**Modified (but not committed):**
- `.beads/backup/` — beads tracking state for sxAct-z1c in_progress

**Oracle snapshots:** None yet — pending `_is_tensor_expr` fix + `gen_butler_snapshots.py` run.

## References

- Issue: `bd show z1c` — full ticket description
- Spec: `specs/2026-03-05-notebook-extraction.md` — extraction strategy
- Notebook: `resources/xAct/Documentation/English/ButlerExamples.nb`
- Existing xPerm tests: `tests/xperm/basic_symmetry.toml`
- Julia XPerm impl: `src/julia/XPerm.jl`
- Oracle example: `oracle/xperm/basic_symmetry/symmetric_group_swap.json`
