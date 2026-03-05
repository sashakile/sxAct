# Notebook Extraction Strategy and Automation Feasibility

**Date:** 2026-03-05
**Ticket:** sxAct-m42
**Status:** Decision
**Blocks:** sxAct-9b1 (xTensor/xPerm TOML test data)

---

## Recommendation: Skip Automation, Use Manual Curation with Reference-Guided Selection

**Bottom line:** Automated extraction from Wolfram .nb files is not feasible without a
running Wolfram kernel. The notebooks encode expressions in a 2D graphical format
(BoxData/RowBox/InterpretationBox) that cannot be reliably converted to plain WL source
without the Wolfram Frontend. Manual curation of hand-picked examples is preferable
for quality and is sufficient for our test volume needs.

---

## Q1: What Notebooks Exist

| File | Input cells (labeled) | Format | Content |
|---|---|---|---|
| `xCoreDoc.nb` | 74 | Mathematica 11.2, .nb | xCore utilities - "(Under construction)" |
| `xTensorDoc.nb` | 97 | Mathematica 11.2, .nb | xTensor tutorial with tensor notation |
| `xPermDoc.nb` | 91 | Mathematica 11.2, .nb | xPerm permutation algorithms |
| `ButlerExamples.nb` | 0 (old format) | Mathematica 5.2 | Butler book permutation examples |
| `xTensorRefGuide.nb` | 0 (labeled) | varies | Reference guide (no labeled cells) |
| `xTeriorDoc.nb` | — | .nb | xTerior (exterior calculus) |
| Others (xCoba, xPert, etc.) | — | .nb | Out of scope |

Total labeled Input cells in scope (xCore + xTensor + xPerm): **262 cells**.

---

## Q2: Wolfram Notebook Parsing

**The core problem: BoxData is a display format, not source.**

Wolfram Frontend stores expressions as BoxData trees for 2D rendering:

```mathematica
(* What the notebook stores: *)
Cell[BoxData[
 RowBox[{
  InterpretationBox[
   StyleBox[GridBox[{{"v"}, {"\[EmptyDownTriangle]"}}], ...],
   v[-b], ...],
  "[", "b", "]"}]], "Input", CellLabel->"In[5]:=", ...]

(* What the user typed: *)
v[-b]
```

The `InterpretationBox` wraps a graphical display of the tensor notation (∇v) with
the underlying WL expression `v[-b]`. Without the Wolfram Kernel to evaluate
`InterpretationBox`, you cannot recover the source.

**Available parsing approaches:**

| Approach | Feasibility | Notes |
|---|---|---|
| `wolframclient` Python lib | Requires Wolfram engine running | Would work but adds oracle dependency |
| Manual XML/regex parsing | Very fragile, ~30% accuracy | InterpretationBox kills it |
| WL `CellPrint`/`ToString` | Requires kernel | Clean output but needs license |
| Read plain-text fallback | Only works for simple cells | Cells like `"0"` or `"True"` work |

Only a handful of cells in xTensorDoc.nb have simple plain-text output (e.g.,
`Cell[BoxData["0"], "Output", ...]`). Most Input cells use InterpretationBox for
tensor index notation.

---

## Q3: Cell-to-TOML Conversion Feasibility

Even if we could extract plain WL source, conversion to TOML is non-trivial:

**Multi-cell context dependency**: xAct examples always start with manifold/tensor
definitions that persist across subsequent cells. Cell 5 (`v[-b]`) depends on
`DefManifold[M, 4, {a,b,c,d}]` from Cell 1 and `DefTensor[v[a], M]` from Cell 2.
A standalone test requires capturing the entire setup chain.

**Output format mismatch**: xAct outputs use 2D tensor notation (superscripts/subscripts)
stored as `InterpretationBox`. The oracle snapshot format uses `InputForm` strings.
The notebook outputs would need re-evaluation via oracle to get canonical `InputForm`.

**Estimated extraction yield**: Of 262 labeled Input cells, roughly:
- 30% are load/setup calls (`<<xAct`, `DefManifold`, `DefTensor`) — not extractable as standalone tests
- 40% use InterpretationBox inputs — not extractable without kernel
- 20% would need multi-cell context reconstruction — complex
- ~10% (26 cells) might yield clean standalone tests

**Net estimate: ~25 automatically extractable tests from 262 cells.** Not worth the
engineering investment.

---

## Q4: Oracle-in-the-Loop Extraction

The alternative: use the live oracle to re-execute notebook examples and generate fresh
snapshots. This avoids parsing old output entirely.

**Feasibility**: Moderate. Requires:
1. Extract WL source from the notebook (still needs kernel to decode BoxData)
2. Reorder into setup + test structure
3. Execute via `xact-test snapshot` to generate oracle snapshots

This collapses back to the same parsing problem for step 1. The oracle-in-the-loop
approach only helps with step 3; it doesn't solve step 1.

---

## Q5: Scope Assessment

**Manual curation is preferable.** Reasons:

1. **Quality**: Hand-picked examples are chosen for clarity and mathematical significance.
   Automatically extracted cells are often illustrative fragments, not robust test cases.

2. **Volume**: We need ~50-100 tests for xTensor/xPerm. At 26 extractable cells, automation
   doesn't provide meaningful scale-up.

3. **Existing baseline**: 58 manually written tests already exist. They cover the most
   important xCore functions well. xTensor/xPerm need the same careful treatment.

4. **Notebook purpose**: The xAct documentation notebooks are tutorials for human readers,
   not test suites. They contain duplicated examples, partial rewrites, and exploratory
   cells that don't map well to regression tests.

---

## Recommended Approach for sxAct-9b1

**Use the notebooks as a reference/checklist, not an extraction source.**

Workflow:
1. Read `xTensorDoc.nb` and `xPermDoc.nb` as documentation to identify which operations
   to test (DefManifold, DefTensor, DefMetric, ToCanonical, etc.)
2. Write TOML tests manually, guided by the notebook examples
3. Use the oracle server (`xact-test snapshot`) to generate snapshots for new TOML files

**Prioritized test areas from notebook review:**

| Area | Notebook source | Estimated test count |
|---|---|---|
| DefManifold/DefTensor basics | xTensorDoc In[1-10] | 8 |
| Index contraction | xTensorDoc In[5-15] | 10 |
| ToCanonical on tensor expressions | xTensorDoc In[15-30] | 12 |
| Metric/covariant derivatives | xTensorDoc In[30-50] | 10 |
| xPerm canonicalization | xPermDoc In[1-30] | 15 |
| Symmetry declarations | xPermDoc In[30-60] | 10 |

**Total: ~65 tests**, achievable manually in reasonable time, all high quality.

---

## Why Not ButlerExamples.nb

`ButlerExamples.nb` uses Mathematica 5.2 format (no cell labels). Content is about
the Butler permutation group algorithms — more algorithmic than xAct API tests.
It would provide xPerm permutation tests but requires older-format parsing.
Defer to a future ticket if xPerm test coverage is insufficient after manual work.
