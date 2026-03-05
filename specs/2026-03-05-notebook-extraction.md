# Notebook Extraction Strategy and Automation Feasibility

**Date:** 2026-03-05
**Ticket:** sxAct-m42
**Status:** Decision
**Blocks:** sxAct-9b1 (xTensor/xPerm TOML test data)

---

## Recommendation

**Split strategy:**
- **ButlerExamples.nb**: Automate extraction. Old Mathematica 5.2 format stores code as
  plain text (`\(...\)` linear WL syntax) — 492 Input cells and 320 Output cells, all
  directly readable. A simple regex extracts clean Input→Output pairs for xPerm tests.
- **xTensorDoc.nb / xPermDoc.nb / xCoreDoc.nb**: Skip automation. Modern Mathematica 11.2
  format encodes expressions as BoxData/InterpretationBox (graphical notation) that cannot
  be decoded without the Wolfram kernel. Use these as a reference/checklist; write TOML
  tests manually.

**Estimated yield**: 30–60 auto-extractable xPerm tests from ButlerExamples.nb, plus
~65 manually-curated xTensor/xPerm tests from the modern notebooks.

---

## Q1: What Notebooks Exist

| File | Labeled Input cells (`CellLabel->In[N]:=`) | Format | Content |
|---|---|---|---|
| `xCoreDoc.nb` | 74 | Mathematica 11.2, BoxData | xCore utilities — "(Under construction)" |
| `xTensorDoc.nb` | 97 | Mathematica 11.2, BoxData | xTensor tutorial with tensor notation |
| `xPermDoc.nb` | 91 | Mathematica 11.2, BoxData | xPerm permutation algorithms |
| `ButlerExamples.nb` | 492 (plain text, no labels) | Mathematica 5.2, `\(...\)` | Butler book permutation examples |
| `xTensorRefGuide.nb` | 0 labeled | varies | Reference guide (no labeled cells) |
| `xTeriorDoc.nb` | — | .nb | xTerior (exterior calculus, out of scope) |
| Others (xCoba, xPert, etc.) | — | .nb | Out of scope |

Total labeled Input cells in scope for modern notebooks (xCore + xTensor + xPerm): **262 cells**.
ButlerExamples.nb has **492 plain-text Input cells** with **320 plain-text Output cells**.

---

## Q2: Wolfram Notebook Parsing

Two distinct cases exist:

### Modern format (Mathematica 11.2, xTensorDoc / xPermDoc / xCoreDoc)

**The core problem: BoxData is a display format, not source.**

Wolfram Frontend stores expressions as BoxData trees for 2D rendering:

```mathematica
(* What the notebook stores: *)
Cell[BoxData[
 RowBox[{
  InterpretationBox[
   StyleBox[GridBox[{{"v"}, {"b"}}], ...],
   v[-b], ...],          (* underlying WL: v[-b], a covariant 1-form *)
  "[", "b", "]"}]], "Input", CellLabel->"In[5]:=", ...]

(* What the user typed: *)
v[-b]
```

The `InterpretationBox` wraps a 2D graphical display of tensor index notation with
the underlying WL expression `v[-b]`. Without the Wolfram Kernel to evaluate
`InterpretationBox`, you cannot recover the source.

**Available parsing approaches:**

| Approach | Feasibility | Notes |
|---|---|---|
| `wolframclient` Python lib | **Practical** — oracle already required for Layer 1 | Decodes BoxData but needs oracle running |
| Manual regex on BoxData | Very fragile, ~30% accuracy | InterpretationBox blocks most cells |
| WL `CellPrint`/`ToString` | Requires kernel | Same oracle dependency as wolframclient |
| Read plain-text cells only | Works for simple cells | `Cell[BoxData["0"], "Output"]` etc. |

The oracle server (WolframAdapter) is already a required dependency for all Layer 1
snapshot work, so `wolframclient` is not a new dependency. However, the per-cell effort
to extract, sequence, and restructure cells into standalone TOML tests is still high
(see Q3).

### Old format (Mathematica 5.2, ButlerExamples.nb)

**Cells are plain text.** The old format uses `\(WL_code\)` linear syntax:

```mathematica
Cell[BoxData[
 \(Orbit[7, GenSet[a, b, c]]\)], "Input"],

Cell[BoxData[
 \({7, 8, 9}\)], "Output"]
```

The `\(...\)` notation is directly readable WL source. Regex extraction:
- Input: `\\\((.+?)\\\)], "Input"\]` → captures WL expression
- Output: `\\\((.+?)\\\)], "Output"\]` → captures result

492 Input cells + 320 Output cells are accessible this way. Not all Input cells have
corresponding Output cells (some return `Null` silently), but Input→Output pairs can be
matched by proximity in the file.

---

## Q3: Cell-to-TOML Conversion Feasibility

### Modern notebooks (262 cells)

Even if plain WL source were available, conversion to TOML is non-trivial:

**Multi-cell context dependency**: xAct examples always start with manifold/tensor
definitions that persist across subsequent cells. Cell 5 (`v[-b]`) depends on
`DefManifold[M, 4, {a,b,c,d}]` from Cell 1 and `DefTensor[v[a], M]` from Cell 2.
A standalone test requires capturing the entire setup chain.

**Output format mismatch**: xAct outputs use 2D tensor notation stored as
`InterpretationBox`. The oracle snapshot format uses `InputForm` strings.
Notebook outputs would need re-evaluation via oracle to get canonical `InputForm`.

**Estimated extraction yield** (applied as sequential filters):
- Total labeled Input cells: 262
- Filter out load/setup calls (`<<xAct`, `DefManifold`, `DefTensor`): ~30% removed → ~183 remaining
- Filter out InterpretationBox inputs (non-decodable without kernel): ~60% of remaining → ~73 remaining
- Filter out cells requiring multi-cell context reconstruction: ~65% of remaining → ~26 remaining

**Net estimate: ~25 automatically extractable tests from 262 cells.** Not worth the
engineering investment for modern notebooks.

### ButlerExamples.nb (492 cells)

xPerm operations in ButlerExamples are algorithmic and self-contained: they define
permutation groups, then query them. Many cells are independent or have minimal context.

**Extraction approach:**
1. Regex-extract consecutive Input/Output pairs from the file
2. Group runs of setup + query cells by section (the file has section headers)
3. Generate TOML `[[setup]]` + `[[tests]]` blocks per section

**Estimated yield**: Of 492 Input cells, roughly:
- ~20% are package-load or display-config calls (skip): ~98 removed → ~394 remaining
- ~25% of remaining produce `Null` or PrintSchreier output (harder to assert): ~99 removed → ~295 remaining
- ~60% of remaining are clean Input→Output pairs: ~177 candidate cells
- After deduplication and quality review: conservatively **50–80 TOML tests**

This is a meaningful yield with low engineering cost.

---

## Q4: Oracle-in-the-Loop Extraction

For modern notebooks: the alternative is to use the live oracle to re-execute
notebook examples and generate fresh snapshots, bypassing the need to parse old output.

**Feasibility**: Moderate. Still requires:
1. Extract WL source from the notebook (needs kernel for BoxData decoding)
2. Reorder into setup + test structure
3. Execute via `xact-test snapshot` to generate oracle snapshots

Steps 1 and 2 remain bottlenecks. Oracle-in-the-loop only helps with step 3;
it doesn't solve the BoxData parsing problem for modern notebooks.

For ButlerExamples.nb, oracle-in-the-loop is worth considering: extract the WL source
via regex, re-execute against the oracle, and use the fresh oracle output as the
canonical expected value (rather than trusting the 2002-era stored outputs).

---

## Q5: Scope Assessment

**Manual curation for modern notebooks; automated extraction for ButlerExamples.nb.**

1. **Modern notebook quality**: Automatically extracted cells are often illustrative
   fragments, not robust test cases. Cells like `PrintSchreier[%]` (referencing `%`
   from the previous output) are meaningless without session continuity.

2. **ButlerExamples volume and quality**: xPerm permutation operations are stateless and
   compositional. `Orbit[7, GenSet[a, b, c]]` is a clean, self-contained test with
   a definite answer `{7, 8, 9}`. Automated extraction is appropriate here.

3. **Existing Layer 1 baseline**: 58 manually-written TOML tests cover xCore Layer 1
   functions. xTensor/xPerm have no TOML tests yet — that gap is what sxAct-9b1 fills.

4. **Modern notebook purpose**: xTensorDoc.nb and xPermDoc.nb are tutorials for human
   readers. They contain repeated examples, exploratory fragments, and cells whose
   pedagogical value exceeds their testing value. Manual curation picks the best ones.

---

## Recommended Approach for sxAct-9b1

**Prerequisites**: Oracle server must be running (`xact-test snapshot` requires it).

### Track A: ButlerExamples.nb automated extraction

1. Write a small extraction script (`scripts/extract_butler.py`) that:
   - Reads ButlerExamples.nb as plain text
   - Regex-extracts `\(...\)` Input/Output pairs
   - Groups by notebook section header
   - Emits TOML files under `tests/xperm/butler_examples/`
2. Review emitted TOML, discard noise, add `[[setup]]` blocks where needed
3. Run `xact-test snapshot` against oracle to generate fresh snapshots

**Expected yield**: 50–80 xPerm tests covering:
- Orbit computation
- Strong generating sets
- Membership testing
- Schreier-Sims algorithm
- Stabilizer chains

### Track B: Manual curation from modern notebooks

Use `xTensorDoc.nb` and `xPermDoc.nb` as a reference/checklist, write TOML manually,
snapshot via oracle.

**Prioritized test areas:**

| Area | Reference notebook | Estimated test count |
|---|---|---|
| DefManifold/DefTensor basics | xTensorDoc In[1–10] | 8 |
| Index contraction | xTensorDoc In[5–15] | 10 |
| ToCanonical on tensor expressions | xTensorDoc In[15–30] | 12 |
| Metric/covariant derivatives | xTensorDoc In[30–50] | 10 |
| xPerm canonicalization | xPermDoc In[1–30] | 15 |
| Symmetry declarations | xPermDoc In[30–60] | 10 |

**Expected yield**: ~65 tests, all hand-curated and high quality.

### Combined total: 115–145 new tests for sxAct-9b1
