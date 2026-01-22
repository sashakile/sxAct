---
title: Optionality Review
type: workflow
tags: [design, strategy, risk-management, decision-making]
status: tested
---

# Optionality Review

## When to Use

This workflow is for reviewing a piece of code, architecture, a plan, or a key decision through the lens of strategic optionality. It helps identify how a decision constrains or enables future choices. It is most valuable when dealing with high uncertainty, long-term projects, or foundational architectural choices where preserving flexibility is a key concern.

## The Prompt

Your task is to review the provided work (code, architecture, plan, etc.) through the lens of strategic optionality.

**Work to Review:**
[PASTE YOUR WORK OR SPECIFY FILE PATH]

**Context (optional):**
[Any relevant context: timeline, constraints, uncertainty level]

---

### Phase 1: Decision Classification (One-Way vs. Two-Way Doors)

First, classify the key decisions using Bezos's framework:
-   **Type 1 (One-Way Doors):** Consequential and irreversible (or very expensive to reverse). Examples: Core architecture, public APIs, major vendor commitments.
-   **Type 2 (Two-Way Doors):** Changeable and reversible. Examples: Internal tooling, UI tweaks, feature flags.

For each major decision, fill out the following:
| Decision | Type (1 or 2) | Reversibility (Easy/Hard/Irreversible) | Justification |
|---|---|---|---|
| [What's being decided] | | | |

*If no Type 1 decisions are identified, you can provide an abbreviated report and skip to the end.*

---

### Phase 2: Alternative Paths (For Type 1 Decisions)

For each Type 1 decision, evaluate the option space.
-   **Current Approach:** What does this lock in? What does it enable?
-   **Alternative A:** Describe a different approach. What options would it preserve? What is the trade-off?
-   **Alternative B:** (If applicable) Describe another different approach.

*For Type 2 decisions, don't deep-dive. Briefly note alternatives and move on.*

---

### Phase 3: Exit Costs & Escape Hatches (For Type 1 Decisions)

Map out the exit strategy for each major commitment.
-   **Reversal Cost:** (Low/Med/High)
-   **Reversal Time:** (Hours/Days/Weeks/Months)
-   **Escape Hatch:** What is the concrete path to undoing this decision if it proves wrong?

**Red Flags:** Irreversible decisions with no escape hatch, or relying on a vague "we can refactor later" plan.

---

### Phase 4: Failure Modes & Fallbacks

What happens if things go wrong?
| Failure Scenario | Probability (L/M/H) | Impact (L/M/H/Critical) | Fallback Plan |
|---|---|---|---|
| [What could fail] | | | [Plan B] |

Also, assess external dependencies for lock-in (vendor, technology, regulatory).

---

### Phase 5: Future Value Assessment

Does this decision create or destroy future options?
-   **Options CREATED:** What new capabilities are enabled? What does this make possible in the future?
-   **Options DESTROYED:** What possibilities are now closed off? Is the trade-off justified?
-   **Growth Potential:** Can it scale 10x? Can features be added without a rewrite?

---

### Phase 6: Decision Points & Triggers

Define future points for reassessment.
| Milestone | What to Assess | Reassess Trigger | Go/No-Go Criteria |
|---|---|---|---|
| [When] | [What we're evaluating] | [What event would cause a review] | [How to decide] |

---

### Final Report

Provide a summary of your findings.

-   **Scores (1-10):**
    -   Reversibility: [X/10]
    -   Resilience: [X/10]
    -   Future Value: [X/10]
    -   **Overall Optionality:** [X/10]
-   **Verdict:**
    -   **Assessment:** [FLEXIBLE | BALANCED | LOCKED_IN | CONCERNING]
    -   **Key Findings:** List the top 3 most significant optionality issues or strengths.
    -   **Recommendations:** Critical actions to take before proceeding.
-   **The Bottom Line:** A 2-3 sentence summary answering: Is the level of lock-in appropriate for the level of uncertainty?