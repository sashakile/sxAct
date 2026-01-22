---
title: Iterative Code Review (Rule of 5)
type: workflow
tags: [review, code-quality, rule-of-5]
status: tested
---

# Iterative Code Review (Rule of 5)

## When to Use

This workflow is for performing a deep, structured code review using an iterative, five-stage process. It's designed to go from a high-level architectural assessment to a detailed, production-ready polish, ensuring all aspects of the code (structure, correctness, clarity, edge cases, and excellence) are thoroughly examined.

## The Prompt

Your task is to review the provided code using the "Rule of 5" — five stages of iterative refinement.

**Philosophy:** "Breadth-first exploration, then editorial passes." Don't aim for perfection in early stages; each stage builds upon the last.

**Code to Review:**
[Paste code here or specify a file path]

---

### STAGE 1: DRAFT - Is the overall shape right?

-   **Question:** Is the overall approach sound?
-   **Focus:** High-level structure, architecture, and whether the code is solving the right problem. Don't focus on details.
-   **Output:** A high-level assessment of the approach and any major structural issues.

---

### STAGE 2: CORRECTNESS - Is the logic sound?

-   **Question:** Are there errors, bugs, or logical flaws?
-   **Focus:** Building on Stage 1, verify logical correctness, check algorithms, and ensure functions do what they claim.
-   **Output:** A list of specific correctness issues with their locations.

---

### STAGE 3: CLARITY - Can someone else understand this?

-   **Question:** Is the code comprehensible?
-   **Focus:** Building on the corrected code from Stage 2, improve readability, clarify names, simplify complex code, and add comments where the intent is not obvious.
-   **Output:** A list of specific clarity improvements and naming suggestions.

---

### STAGE 4: EDGE CASES - What could go wrong?

-   **Question:** Are boundary conditions handled?
-   **Focus:** Building on the clarified code from Stage 3, identify and handle unusual scenarios, boundary conditions (null, empty, max values), and gaps in input validation or error handling.
-   **Output:** A list of unhandled edge cases and error-handling vulnerabilities.

---

### STAGE 5: EXCELLENCE - Is it ready to ship?

-   **Question:** Would you be proud to ship this code?
-   **Focus:** A final polish of the code, checking for production quality, performance, documentation completeness, and overall best practices.
-   **Output:** Final recommendations for production readiness.

---

### Convergence and Reporting

#### Convergence Check

After each stage (starting with Stage 2), report the convergence status:
-   **New CRITICAL issues found.**
-   **Number of new issues vs. previous stage.**
-   **Status:**
    -   `CONVERGED`: No new critical issues and new issue rate is low (<10%).
    -   `CONTINUE`: Proceed to the next stage.
    -   `NEEDS_HUMAN`: Blocking issues were found that require human judgment.

#### Final Report

Once the review has converged or all stages are complete, provide a final summary report:
-   Total issues found by severity.
-   The top 3 most critical findings.
-   A prioritized list of recommended next actions.
-   A final production readiness assessment.