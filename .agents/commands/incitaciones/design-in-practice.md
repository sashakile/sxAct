---
title: Design in Practice
type: workflow
tags: [design, problem-solving, architecture, methodology]
status: tested
---

# Design in Practice

## When to Use

This workflow applies a rigorous, 6-phase design framework to deeply understand a problem before implementing a solution. It is intended for complex problems where the root cause is not obvious and multiple solutions may exist. The goal is to move from symptoms to a well-understood, scoped, and planned solution, avoiding common pitfalls like premature optimization and solving the wrong problem.

## The Prompt

Your task is to apply the 6-phase design framework to understand and solve the problem at hand. Work through each phase sequentially; do not skip phases. The goal is understanding, not just creating artifacts.

### Process Rules

1.  **No phase skipping:** Each phase builds on the previous one.
2.  **Artifacts are thinking tools:** The goal is clarity of thought, not bureaucracy.
3.  **"Hammock time":** It's good practice to pause and reflect on ideas before committing to them.
4.  **Generate multiple hypotheses:** Relying on a single idea is a trap; always generate alternatives.
5.  **Incremental over iterative:** Understand → Design → Code → Value. Avoid a "code, fail, learn" cycle.

### PHASE 1: DESCRIBE (Symptoms)

**Objective:** Capture the current reality without imposing solutions.

1.  **Gather signals:** What symptoms are observed (errors, complaints, metrics)? Where and when do they occur? Who is affected?
2.  **Write a neutral description:** State facts only, with no speculation on causes or solutions. Describe observable behaviors, not interpretations. Avoid diagnoses ("the DB is slow") or solutions ("we need caching").

**Output Format:**
```
## Description

### Observed Symptoms
- [Symptom 1]: [Where/When observed]
- [Symptom 2]: [Where/When observed]

### Signal Sources
- [Bug reports, logs, user complaints, metrics]
```

### PHASE 2: DIAGNOSE (Root Cause)

**Objective:** Identify the mechanism causing the symptoms.

1.  **Generate multiple hypotheses** (at least 3) for the cause.
2.  **Test hypotheses systematically:** Use logic and evidence to rule out possibilities.
3.  **Write the Problem Statement:**

**Problem Statement Template:**
```
## Problem Statement

**Current behavior:** [What happens now - factual]
**Mechanism:** [The root cause - how/why it happens]
**Evidence:**
- [Fact supporting this diagnosis]
**Ruled out:**
- [Hypothesis A]: [Why it's not this]
```
*Quality Check: The solution should feel obvious after reading a good problem statement.*

### PHASE 3: DELIMIT (Scope)

**Objective:** Define what is in and out of scope for the solution.

1.  **Set explicit boundaries:** What subset of the problem will we solve? What constraints are accepted?
2.  **Document non-goals:** What is explicitly *not* being addressed?

**Output Format:**
```
## Scope

### In Scope
- [What we will address]
### Out of Scope (Non-Goals)
- [What we explicitly won't do and why]
### Constraints
- [Technical, time, or resource limitations]
```

### PHASE 4: DIRECTION (Strategic Approach)

**Objective:** Select the best approach from viable alternatives.

1.  **Generate multiple approaches**, always including "Status Quo" (do nothing) as a baseline.
2.  **Build a Decision Matrix** to compare them.
    - **Rows:** Criteria (e.g., implementation cost, performance, maintainability).
    - **Columns:** Approaches.
    - **Cells:** Factual, neutral descriptions (e.g., "Requires 5 days of work," not "Hard to implement"). Use color or symbols for subjective assessment.
3.  **Select and justify** the chosen approach, acknowledging the trade-offs.

**Decision Matrix Template:**
```
## Decision Matrix

| Criterion        | Status Quo | Approach A | Approach B |
|------------------|------------|------------|------------|
| [Criterion 1]    | [Fact]     | [Fact]     | [Fact]     |
| [Criterion 2]    | [Fact]     | [Fact]     | [Fact]     |

### Decision
**Selected approach:** [Approach name]
**Rationale:** [Why this approach best addresses the scoped problem]
**Trade-offs accepted:** [What we're giving up]
```

### PHASE 5: DESIGN (Tactical Plan)

**Objective:** Create a detailed blueprint for implementation.

After a direction is selected:

1.  **Define specifics:** Data structures, API contracts, component responsibilities, error handling, etc.
2.  **Write an Implementation Plan** (see `create-plan.md` for the standard format). The plan should have independently verifiable phases and follow a TDD approach.

### PHASE 6: DEVELOP (Execute)

**Objective:** Translate the design into working code.

If Phases 1-5 were done rigorously, this phase should feel mechanical. Follow the plan, write tests first, and verify against success criteria. If you are struggling here, it's a sign that the design is incomplete; return to an earlier phase.