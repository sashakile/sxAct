---
title: Multi-Agent Parallel Code Review
type: workflow
tags: [review, code-quality, multi-agent, parallel-processing]
status: experimental
---

# Multi-Agent Parallel Code Review

## When to Use

This workflow is for conducting a highly comprehensive, parallelized code review using a simulated multi-agent "Wave/Gate" architecture. It is suitable for mission-critical code changes where maximum scrutiny is required from multiple, diverse perspectives simultaneously. This is a heavyweight process designed to trade speed for extreme thoroughness.

## The Prompt

I need a comprehensive multi-agent parallel code review using the Wave/Gate architecture.

**Code to Review:** [paste code or specify: "Review all files in `src/auth/`"]

Execute the following workflow:

---

### WAVE 1: PARALLEL INDEPENDENT ANALYSIS

Launch 5 parallel, independent analysis tasks. Each simulated agent reviews the code from a unique perspective and outputs its findings in a structured JSON format.

#### **TASK 1: Security Review**
-   **Role:** Security Engineer
-   **Focus:** OWASP Top 10, input validation, auth flaws, injections, data exposure, secret management.
-   **Output:** JSON with issues (`SEC-XXX`), severity, CWE ID, location, description, attack vector, and recommendation.

#### **TASK 2: Performance Review**
-   **Role:** Performance Engineer
-   **Focus:** Algorithmic complexity, N+1 queries, memory leaks, caching opportunities, blocking I/O.
-   **Output:** JSON with issues (`PERF-XXX`), severity, category, location, quantified impact, and recommendation.

#### **TASK 3: Maintainability Review**
-   **Role:** Future Developer (6 months from now)
-   **Focus:** Clarity, documentation, consistency, naming, technical debt, DRY violations.
-   **Output:** JSON with issues (`MAINT-XXX`), severity, category, location, confusion risk, and recommendation.

#### **TASK 4: Requirements Validation**
-   **Role:** QA Engineer
-   **Focus:** Requirements coverage, edge case handling, test gaps, behavioral correctness.
-   **Output:** JSON with issues (`REQ-XXX`), severity, requirement ID, status (MISSING, INCOMPLETE, INCORRECT), and expected vs. actual behavior.

#### **TASK 5: Operations Review**
-   **Role:** Site Reliability Engineer (SRE)
-   **Focus:** Failure modes, observability (logging, metrics), resilience, deployment/rollback risks, configuration.
-   **Output:** JSON with issues (`OPS-XXX`), severity, category, failure mode, blast radius, and recommendation.

---

### GATE 1: CONFLICT RESOLUTION & SYNTHESIS

After all Wave 1 tasks complete, act as a **Senior Technical Lead** to consolidate the findings.

1.  **Deduplicate Issues:** Merge issues that have the same root cause.
2.  **Resolve Severity Conflicts:** The highest severity wins, with Security CRITICAL taking precedence.
3.  **Calculate Confidence:** Confidence increases with the number of reviewers who flagged the same issue.
4.  **Identify Cross-Cutting Concerns:** Note systemic patterns that appear in multiple domains.
5.  **Output:** A single JSON object containing `consolidated_issues`, `conflicts_resolved`, and `critical_themes`.

---

### WAVE 2: PARALLEL CROSS-VALIDATION

Launch parallel tasks to review the consolidated findings from Gate 1.

-   **TASK 6: Meta-Review (QA Lead):** Check for coverage gaps, false positives, and systemic patterns in the review process itself.
-   **TASK 7: Integration Analysis (Systems Architect):** Check for system-wide impacts, cascading failures, and data flow issues.

---

### GATE 2: FINAL SYNTHESIS

Act as the final arbiter to synthesize all previous outputs into a single, actionable report.

1.  **Generate Executive Summary:** Top-line numbers and key blockers.
2.  **Create Prioritized Action List:** Group issues into "Must Fix" (CRITICAL) and "Should Fix" (HIGH).
3.  **Provide Blocking Assessment:** State whether the PR `BLOCKS_MERGE`, `BLOCKS_DEPLOY`, is `APPROVED`, or `APPROVED_WITH_NOTES`.
4.  **Output:** A final markdown report for the developer.

---

### WAVE 3: CONVERGENCE CHECK

Finally, determine if another iteration is needed.
-   **CONVERGED:** If no new CRITICAL issues are found and the new issue rate is low (<10%).
-   **ITERATE:** If new CRITICAL issues are found or the new issue rate is high. If so, restart Wave 1, focusing only on the remaining CRITICAL and HIGH issues.
-   **ESCALATE_TO_HUMAN:** If the review is stuck, conflicting, or requires nuanced judgment after multiple iterations.