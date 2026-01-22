---
title: Iterative Research Review (Rule of 5)
type: workflow
tags: [research, review, rule-of-5]
status: tested
---

# Iterative Research Review (Rule of 5)

## When to Use

This workflow is for performing a thorough and structured review of a research document. It uses the "Rule of 5" iterative refinement process to ensure the research is accurate, complete, clear, actionable, and well-integrated into the project's context. This should be used before acting on research findings.

## The Prompt

Your task is to perform a thorough research document review using the Rule of 5 — five stages of iterative editorial refinement until convergence.

### Setup

-   If a research document path is provided, read the document completely.
-   If no path, ask for the research document path or list available research documents.

### The Process: 5 Passes of Review

Perform the following 5 passes, checking for convergence after each pass (starting with Pass 2).

#### PASS 1: Accuracy & Sources

-   **Focus:** Are the claims in the research backed by credible evidence and sources?
-   **Checks:**
    -   Claims supported by evidence.
    -   Source credibility and recency.
    -   Factual accuracy of technical details.
    -   Code references are correct (`file:line` exists and matches claim).
-   **Output:** A list of `[ACC-XXX]` issues with recommendations for corrections or additional sourcing.

#### PASS 2: Completeness & Scope

-   **Focus:** Does the research adequately cover the topic and answer all relevant questions without unnecessary tangents?
-   **Checks:**
    -   Missing important topics or considerations.
    -   Unanswered questions that should be addressed.
    -   Depth appropriate for the topic.
    -   All research questions answered.
-   **Output:** A list of `[COMP-XXX]` issues.

#### PASS 3: Clarity & Structure

-   **Focus:** Is the document easy to understand, well-organized, and free of ambiguity?
-   **Checks:**
    -   Logical flow and organization.
    -   Clear definitions of terms and consistent terminology.
    -   Appropriate headings and sections.
    -   Jargon explained or avoided.
-   **Output:** A list of `[CLAR-XXX]` issues with suggestions for improving readability.

#### PASS 4: Actionability & Conclusions

-   **Focus:** Does the research lead to clear, supported conclusions and actionable recommendations?
-   **Checks:**
    -   Clear takeaways and recommendations.
    -   Conclusions supported by the research.
    -   Practical applicability to the project.
    -   Next steps identified.
-   **Output:** A list of `[ACT-XXX]` issues if the research lacks actionable outcomes.

#### PASS 5: Integration & Context

-   **Focus:** How well does the research integrate with the broader project context (existing plans, specs, code)?
-   **Checks:**
    -   Alignment with existing research, specs, and requirements.
    -   Relevance to current project goals.
    -   No contradictions with established decisions.
    -   Cross-references to related work.
-   **Output:** A list of `[INT-XXX]` issues.

### Convergence Check

After each pass (starting with Pass 2), report on convergence:
-   **Status:** `[CONVERGED | ITERATE | NEEDS_HUMAN]`
-   **Converged** means no new critical issues and the new issue rate is low (<10% of previous pass). If converged, stop and create the final report.
-   **Iterate** means continue to the next pass.

### Final Report

Once the review has converged or all passes are complete, generate a final report.

```
## Research Review Final Report
**Research:** [path/to/research.md]
**Convergence:** Pass [N]

### Summary
- **Total Issues by Severity:**
  - CRITICAL: [count]
  - HIGH: [count]
  - MEDIUM: [count]
  - LOW: [count]

### Top 3 Most Critical Findings
1.  **[ID] [Description] - Section [N]:** Impact and recommended fix.
2.  **[ID] [Description] - Section [N]:** Impact and recommended fix.
3.  **[ID] [Description] - Conclusions:** Impact and recommended fix.

### Recommended Revisions
Provide specific, actionable steps to address the findings.

### Verdict
**[READY | NEEDS_REVISION | NEEDS_MORE_RESEARCH]**
**Rationale:** [1-2 sentences explaining the verdict.]
```