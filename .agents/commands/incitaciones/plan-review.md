---
title: Iterative Plan Review (Rule of 5)
type: workflow
tags: [planning, review, rule-of-5]
status: tested
---

# Iterative Plan Review (Rule of 5)

## When to Use

This workflow is for performing a thorough and structured review of an implementation plan. It applies the "Rule of 5" iterative refinement process to ensure the plan is feasible, complete, aligned with specifications, correctly ordered, and clearly executable. Use this before beginning implementation to catch potential issues early.

## The Prompt

Your task is to perform a thorough implementation plan review using the Rule of 5 — five iterative passes of refinement until convergence.

### Setup

-   If a plan path is provided, read the plan completely.
-   If no plan path, ask for it or list available plans from `plans/`.

### The Process: 5 Passes of Review

Perform the following 5 passes, checking for convergence after each pass (starting with Pass 2).

#### PASS 1: Feasibility & Risk (Codebase Alignment)

-   **Focus:** Is the plan technically sound, does it align with the current codebase, and does it adequately address risks?
-   **Checks:**
    -   **Codebase Alignment**: Does the plan accurately reflect the current state of the code (file paths, functions, architecture)?
    -   Technical feasibility of proposed changes.
    -   Identified risks and their mitigations.
    -   Assumptions that need validation.
    -   Resource requirements (time, expertise).
-   **Output:** A list of `[FEAS-XXX]` issues with recommendations for fixes.

#### PASS 2: Completeness & Scope

-   **Focus:** Is the plan comprehensive and clearly scoped?
-   **Checks:**
    -   Missing phases or steps.
    -   Undefined or vague success criteria.
    -   "Out of Scope" clearly defined.
    -   All affected files/components identified.
    -   Testing strategy covers all scenarios.
-   **Output:** A list of `[COMP-XXX]` issues.

#### PASS 3: Spec & TDD Alignment

-   **Focus:** Does the plan align with specifications and follow a Test-Driven Development approach?
-   **Checks:**
    -   Links to spec files (if applicable).
    -   Tests are planned *before* implementation for each phase.
    -   Success criteria are testable.
    -   All requirements from specs are covered.
-   **Output:** A list of `[TDD-XXX]` issues.

#### PASS 4: Ordering & Dependencies

-   **Focus:** Are the phases logically ordered, with correct dependencies?
-   **Checks:**
    -   Phases are in the correct sequence.
    -   Dependencies between phases are clearly stated.
    -   Each phase can be independently verified.
    -   No "big bang" integration at the end.
-   **Output:** A list of `[ORD-XXX]` issues.

#### PASS 5: Clarity & Executability

-   **Focus:** Is the plan clear, specific, and easy for someone else to implement?
-   **Checks:**
    -   Concrete file paths and changes.
    -   No ambiguous instructions (e.g., "Make it work with...").
    -   Clear definition of "done" for each phase.
    -   Assumptions about shared knowledge are avoided.
-   **Output:** A list of `[EXEC-XXX]` issues.

### Convergence Check

After each pass (starting with Pass 2), report on convergence:
-   **Status:** `[CONVERGED | ITERATE | NEEDS_HUMAN]`
-   **Converged** means no new CRITICAL issues and the new issue rate is low (<10% of previous pass). If converged, stop and create the final report.
-   **Iterate** means continue to the next pass.

### Final Report

Once the review has converged or all passes are complete, generate a final report.

```
## Plan Review Final Report
**Plan:** plans/[filename].md
**Convergence:** Pass [N]

### Summary
- **Total Issues by Severity:**
  - CRITICAL: [count]
  - HIGH: [count]
  - MEDIUM: [count]
  - LOW: [count]

### Top 3 Most Critical Findings
1.  **[ID] [Description] - Phase [N]:** Impact and recommended fix.
2.  **[ID] [Description] - Phase [N]:** Impact and recommended fix.
3.  **[ID] [Description] - Phase [N]:** Impact and recommended fix.

### Recommended Next Actions
Provide specific, actionable steps to address the findings.

### Verdict
**[READY_TO_IMPLEMENT | NEEDS_REVISION | NEEDS_MORE_RESEARCH]**
**Rationale:** [1-2 sentences explaining the verdict.]
```