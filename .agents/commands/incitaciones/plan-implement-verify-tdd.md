---
title: Implement with TDD Workflow
type: workflow
tags: [tdd, implementation, phased-development]
status: tested
---

# Implement with TDD Workflow

## When to Use

This workflow is for implementing new features or resolving bugs following a strict Test-Driven Development (TDD) methodology and a phased approach. It ensures a systematic, verifiable development process, emphasizing early testing and continuous verification.

## The Prompt

Your task is to implement the requested feature following the TDD workflow: **Red, Green, Refactor**.

### Core Principle: Red, Green, Refactor

1.  **Red:** Write a failing test that clearly describes the desired behavior.
2.  **Green:** Write the absolute minimal code necessary to make that test pass.
3.  **Refactor:** Clean up the code, improving its design and readability, while ensuring all tests remain green.

### Process

#### Phase 0: Plan (If needed)

For complex features, create a detailed plan first. The plan must be grounded in the codebase reality.

1.  **Research the Codebase**: Read relevant code to understand the current state AS-IS. Document existing patterns, conventions, and architecture. Your role is to be a documentarian, not a critic.
2.  **Identify what needs to change**: Based on the research, pinpoint the files and components that will be affected.
3.  **Break work into logical phases**: Each phase should be an independently verifiable step.
4.  **Define success criteria (automated and manual)**: For each phase, define how to prove it's done correctly.
5.  **Get user approval of plan before implementing.**

**Plan Structure Example:**
```markdown
# [Feature Name] Implementation Plan

## Current State
[What exists now]

## Desired End State
[What will exist, how to verify]

## Out of Scope
[What we're NOT doing]

## Phase 1: [Name]

### Changes Required
- File: `path/to/file.ext`
- Changes: [Description]
- Tests: [What tests to write]

### Success Criteria
#### Automated:
- [ ] New tests pass
- [ ] Existing tests still pass
#### Manual:
- [ ] [Specific manual verification]
```
**Get plan approved before proceeding.**

#### For Each Implementation Phase:

##### Step 1: Write Failing Test (RED)

-   Write test(s) that describe the desired behavior for the current part of the feature.
-   Run the tests and **confirm they fail**. This verifies that your test is actually testing something new and that the functionality doesn't already exist.

##### Step 2: Implement Minimal Code (GREEN)

-   Write just enough code to make the failing test(s) pass.
-   Resist the urge to add extra features or perfect the code at this stage.
-   Run the tests and **confirm they pass**.

##### Step 3: Refactor If Needed

-   Clean up the code, improve its design, readability, and remove duplication.
-   Run tests after each refactoring step to **ensure they remain green**.

##### Step 4: Verify Phase Completion & Inform User

-   Run all automated verification steps (all tests, type checking, linting, build).
-   Perform any manual verification steps outlined in the plan.
-   Inform the user that the phase is complete, providing a summary of changes and verification results.
-   **Wait for user confirmation before proceeding to the next phase.**

### Key Guidelines

1.  **Tests first, always**: Write the test before the implementation.
2.  **Minimal implementation**: Write just enough code to pass the test.
3.  **One phase at a time**: Complete and verify before moving on.
4.  **Keep tests green**: Never commit with failing tests.
5.  **Verify at each phase**: Automated and manual checks.
6.  **Update plan**: Check off completed items as you go.

## Handling Unexpected Situations

### When Things Don't Match the Plan

If the codebase reality differs from the plan, stop and report:

```
Issue in Phase [N]:

Expected: [What the plan says]
Found: [Actual situation]
Why this matters: [Explanation]

Options:
1. Adapt implementation to reality.
2. Update plan to reflect new understanding.
3. Discuss with user.

How should I proceed?
```
**Do not blindly follow an outdated plan.**

### Resuming Work

If resuming from an existing plan:
-   Start from the first unchecked item in the plan.
-   Verify previous work only if something seems off (e.g., tests are failing unexpectedly).
-   Continue with the Red-Green-Refactor cycle from the current phase.