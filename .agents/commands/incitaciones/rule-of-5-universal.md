---
title: Universal Rule of 5 Review
type: workflow
tags: [review, quality, rule-of-5, universal]
status: tested
---

# Universal Rule of 5 Review

## When to Use

This workflow is for conducting a comprehensive, iterative review of *any* work product (code, plan, research, issue, specification, document) using Steve Yegge's "Rule of 5" methodology. It systematically refines the work through five distinct stages, ensuring rigor, correctness, clarity, robustness against edge cases, and overall excellence.

## The Prompt

Your task is to review the provided work using Steve Yegge's Rule of 5 — five stages of iterative editorial refinement until convergence.

**Work to Review:**
[PASTE YOUR WORK OR SPECIFY FILE PATH]

### Core Philosophy

"Breadth-first exploration, then editorial passes." Don't aim for perfection in early stages; each stage builds on insights from previous stages.

---

### Stage 1: DRAFT - Get the shape right

-   **Question:** Is the overall approach sound?
-   **Focus:** Overall structure, organization, major architectural/conceptual issues. Is it solving the right problem?
-   **Output:** High-level assessment, major structural issues.

---

### Stage 2: CORRECTNESS - Is the logic sound?

-   **Question:** Are there errors, bugs, or logical flaws?
-   **Focus:** Building on Stage 1, verify factual accuracy, logical consistency, and correctness of algorithms or reasoning.
-   **Output:** List of correctness issues with locations.

---

### Stage 3: CLARITY - Can someone else understand this?

-   **Question:** Is this comprehensible to the intended audience?
-   **Focus:** Building on Stage 2, improve readability, clarify language, define jargon, enhance organization, and ensure sufficient context.
-   **Output:** Clarity improvements and naming/wording suggestions.

---

### Stage 4: EDGE CASES - What could go wrong?

-   **Question:** Are boundary conditions and unusual scenarios handled?
-   **Focus:** Building on Stage 3, identify unhandled edge cases, failure modes, unusual inputs, and gaps in error handling or assumptions.
-   **Output:** A list of unhandled edge cases and recommendations for their treatment.

---

### Stage 5: EXCELLENCE - Ready to ship?

-   **Question:** Would you be proud to ship this?
-   **Focus:** Final polish, production quality assessment, adherence to best practices, performance, documentation, and overall completeness.
-   **Output:** Final recommendations for production readiness.

---

### Convergence Check & Final Report

-   After each stage (starting with Stage 2), assess **convergence**: If new critical issues are found, continue to the next stage. If no new critical issues and the new issue rate is low, the review is `CONVERGED`.
-   **Final Report:** After convergence or completing Stage 5, provide a summary of findings by severity, top critical findings, recommended actions, and an overall verdict on readiness.