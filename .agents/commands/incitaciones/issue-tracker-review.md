---
title: Iterative Issue Tracker Review (Rule of 5)
type: workflow
tags: [project-management, issue-tracking, review, rule-of-5]
status: tested
---

# Iterative Issue Tracker Review (Rule of 5)

## When to Use

This workflow is for performing a thorough, structured review of a set of issues in an issue tracker (like Beads or GitHub Issues). It uses the "Rule of 5" methodology—five iterative passes of refinement—to ensure issues are clear, actionable, correctly scoped, and properly ordered before development begins.

## The Prompt

Your task is to perform a thorough issue review using the Rule of 5.

### Setup: Gather Issues

First, gather the issues to be reviewed using the appropriate tool commands.

-   **For Beads:** `bd list`, `bd ready`, `bd graph`, `bd show <id>`
-   **For GitHub Issues:** `gh issue list --label "needs-review"`, `gh issue view <number>`

### The Process: 5 Passes of Review

Perform the following 5 passes, checking for convergence after each pass (starting with Pass 2).

#### PASS 1: Completeness, Clarity & Codebase Alignment

-   **Focus:** Is the issue understandable, complete, and reflective of the current codebase?
-   **Checks:**
    -   Title is clear.
    -   Description provides enough context.
    -   File paths mentioned are correct and exist.
    -   Proposed changes are relevant to the current code (not based on a stale understanding).
    -   Acceptance criteria are defined and clear.
-   **Output:** A list of `[CLRT-XXX]` issues with recommendations for fixes.

#### PASS 2: Scope & Atomicity

-   **Focus:** Does each issue represent a single, logical, and appropriately sized unit of work?
-   **Checks:**
    -   Issues are not too large (e.g., "implement auth system") or too small (e.g., "fix typo").
    -   Scope does not overlap with other issues.
    -   Each issue is independently valuable.
-   **Output:** A list of `[SCOPE-XXX]` issues, with recommendations to split or merge.

#### PASS 3: Dependencies & Ordering

-   **Focus:** Are the relationships and order between issues correct?
-   **Checks:**
    -   Dependencies are correctly defined and not missing.
    -   No circular dependencies (e.g., A→B→C→A).
    -   The critical path is sensible.
    -   Parallel work is not unnecessarily blocked.
-   **Output:** A list of `[DEP-XXX]` issues with commands to add or remove dependencies.

#### PASS 4: Plan & Spec Alignment

-   **Focus:** Do the issues accurately represent the original plan or specification?
-   **Checks:**
    -   Issues trace back to a specific plan phase or spec requirement.
    -   All parts of the plan/spec are covered by issues.
    -   The issue breakdown matches the plan's structure.
-   **Output:** A list of `[ALIGN-XXX]` issues with recommendations to add references or correct misalignments.

#### PASS 5: Executability & Handoff

-   **Focus:** Can another developer or agent pick up this issue and complete it without ambiguity?
-   **Checks:**
    -   No implicit or missing knowledge is required.
    -   Verification steps are clear and specific.
    -   Priority and labels are appropriate.
-   **Output:** A list of `[EXEC-XXX]` issues with recommendations to add detail or context.

### Convergence Check

After each pass (from Pass 2 onwards), report on convergence:
-   **Status:** `[CONVERGED | ITERATE | NEEDS_HUMAN]`
-   **Converged** means no new critical issues and the new issue rate is low (<10% of previous pass). If converged, stop and create the final report.
-   **Iterate** means continue to the next pass.

### Final Report

After convergence or completing all passes, generate a final report.

```
## Issue Tracker Review Final Report
**System:** [Beads/GitHub/Linear/Jira]
**Scope:** [All issues / Milestone X / Labels Y]
**Convergence:** Pass [N]

### Summary
- **Total Issues Reviewed:** [count]
- **Issues Found by Severity:**
  - CRITICAL: [count]
  - HIGH: [count]
  - MEDIUM: [count]
  - LOW: [count]

### Top 3 Most Critical Findings
1.  **[ID] [Description]:** Impact and recommended fix.
2.  **[ID] [Description]:** Impact and recommended fix.
3.  **[ID] [Description]:** Impact and recommended fix.

### Recommended Actions
Provide the specific, runnable commands to fix the identified problems.
```bash
# Example for Beads
bd dep remove 42 44  # Fix circular dependency
bd close 38 --reason="split into phase issues" # Split large issue
```

### Verdict
**[READY_TO_WORK | NEEDS_UPDATES | NEEDS_REPLANNING]**
**Rationale:** [1-2 sentences explaining the verdict.]
```