---
title: Design Artifact Review
type: workflow
tags: [design, review, architecture]
status: tested
---

# Design Artifact Review

## When to Use

This workflow is for reviewing design artifacts (such as Problem Statements, Decision Matrices, or Scope Documents) to ensure they are rigorous, complete, and adhere to the principles of the "Design in Practice" methodology. Use this to catch common failure modes in the design phase before they lead to flawed implementation.

## The Prompt

Your task is to review the provided design artifact for rigor and completeness. If an artifact path is provided, read it completely. If not, ask which artifact to review.

Perform a targeted review based on the artifact's type.

---

### **ARTIFACT TYPE: Problem Statement**

#### Review Checks:

1.  **Solution Contamination:** Does the statement contain or imply a solution? A good problem statement is solution-agnostic.
    - **Test:** Could multiple different solutions address this statement? (YES = Good, NO = Contaminated).
2.  **Root Cause vs. Symptom:** Does it describe the underlying mechanism or just the observable effect?
    - **Test:** Ask "Why?" repeatedly. If you can go deeper, you are likely looking at a symptom.
3.  **Specificity:** Is the problem precise enough to guide solution selection? It should use quantified metrics and name specific components.
4.  **Evidence Quality:** Is the diagnosis based on verified facts or assumptions? Look for cited evidence and ruled-out alternatives.
5.  **The Obvious Solution Test:** Does the correct solution feel obvious after reading the statement? If not, the diagnosis is likely incomplete.

#### Output:

Provide a verdict for each check and a final summary.

```
## Problem Statement Review Summary

| Check                  | Result             | Action Needed      |
|------------------------|--------------------|--------------------|
| Solution Contamination | [CLEAN/CONTAMINATED] | [Action or "None"] |
| Root Cause             | [MECHANISM/SYMPTOM]  | [Action or "None"] |
| Specificity            | [PRECISE/VAGUE]      | [Action or "None"] |
| Evidence               | [VERIFIED/ASSUMED]   | [Action or "None"] |
| Obvious Solution       | [PASS/FAIL]          | [Action or "None"] |

**Verdict:** [READY_FOR_DIRECTION | NEEDS_REVISION | BACK_TO_DESCRIBE]
**Top Issue:** [Most critical thing to fix]
```

---

### **ARTIFACT TYPE: Decision Matrix**

#### Review Checks:

1.  **Status Quo Baseline:** Is "do nothing" included as the first column for comparison?
2.  **Fact vs. Judgment Separation:** Are the cells filled with neutral, verifiable facts (e.g., "<10ms p99 latency") rather than subjective judgments (e.g., "Good performance")? Judgments should be shown separately (e.g., with colors).
3.  **Criteria Completeness:** Are all relevant trade-off dimensions included as criteria? (e.g., maintenance burden, rollback difficulty, team expertise).
4.  **Approach Diversity:** Are the alternative approaches fundamentally different, or just minor variations of the same idea?
5.  **Cell Verification:** Are the facts in the matrix accurate and verifiable? Spot-check 2-3 claims.

#### Output:

Provide a verdict for each check and a final summary.

```
## Decision Matrix Review Summary

| Check                      | Result             | Action Needed      |
|----------------------------|--------------------|--------------------|
| Status Quo Baseline        | [PRESENT/MISSING]  | [Action or "None"] |
| Fact/Judgment Separation   | [CLEAN/CONTAMINATED] | [Action or "None"] |
| Criteria Completeness      | [COMPLETE/GAPS]    | [Action or "None"] |
| Approach Diversity         | [DIVERSE/SIMILAR]  | [Action or "None"] |
| Cell Verification          | [VERIFIED/ERRORS]  | [Action or "None"] |

**Verdict:** [READY_FOR_DECISION | NEEDS_REVISION | NEEDS_MORE_OPTIONS]
**Selected approach justified?** [YES/NO - Is the rationale sound?]
```

---

### **ARTIFACT TYPE: Scope Document**

#### Review Checks:

1.  **Explicit Non-Goals:** Does the document explicitly list what is "out of scope"? This is critical to prevent scope creep.
2.  **Constraint Realism:** Are the stated constraints (e.g., timeline, budget) achievable and honest? Are there any unstated but important constraints?

---

### **COMBINED REVIEW (Full Design Package)**

If reviewing a full set of design documents (Problem Statement, Decision Matrix, Plan), check for alignment between them.

1.  **Problem → Direction:** Does the selected approach actually solve the diagnosed problem?
2.  **Scope → Plan:** Does the implementation plan respect the non-goals and stay within scope?
3.  **Decision → Plan:** Does the plan's approach align with the rationale for the chosen direction?

---

### Final Report

Summarize your findings in a final report.

```
## Design Artifact Review Report

**Artifact(s) Reviewed:** [List]

### Summary
| Artifact          | Verdict                 | Key Issues |
|-------------------|-------------------------|------------|
| Problem Statement | [READY/REVISION/BACK]   | [Top issue]|
| Decision Matrix   | [READY/REVISION/MORE]   | [Top issue]|

### Critical Findings
1.  **[ARTIFACT-CHECK]** [Severity]: [What's wrong and its impact]
2.  **[ARTIFACT-CHECK]** [Severity]: [What's wrong and its impact]

### Recommended Actions
1. [Most important action]
2. [Second action]

### Overall Verdict
[PROCEED_TO_IMPLEMENTATION | REVISE_ARTIFACTS | RETURN_TO_EARLIER_PHASE]
**Rationale:** [1-2 sentences]
```