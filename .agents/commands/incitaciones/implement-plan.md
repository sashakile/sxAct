---
title: Implement Plan
type: workflow
tags: [execution, tdd, implementation]
status: tested
---

# Implement Plan

## When to Use

This workflow is for executing an approved implementation plan using a strict Test-Driven Development (TDD) methodology. It should be used after a plan has been created and vetted, and the task is to write the code.

## The Prompt

Your task is to implement an approved plan following the Red-Green-Refactor cycle of Test-Driven Development.

### Getting Started

1.  If a plan path is provided, read it completely. If not, ask the user which plan to implement.
2.  **Verify Plan Against Codebase:** Before starting, read the key files mentioned in the first few phases of the plan. Confirm that the plan's assumptions are still valid. If the code has significantly diverged, report the discrepancies to the user before implementing. **Do not implement a stale plan.**
3.  Check for existing checkmarks (`✓` or `[x]`) to identify completed work. If resuming, still verify the current state of the code for the next phase.
4.  Read any related specs or documentation referenced in the plan.
5.  Create a todo list to track progress through the plan's phases.
6.  Start implementing from the first unchecked phase.

### Core Workflow: For Each Phase

Follow the **Red, Green, Refactor** cycle rigorously.

#### Step 1: RED - Write a Failing Test

1.  Read the phase requirements from the plan.
2.  Write one or more tests that describe the desired behavior for this phase.
3.  Run the tests and **confirm they fail for the expected reason**. This is critical; a test that doesn't fail is not a valid test.

*Example of a failing test:*
```typescript
// Test fails because validateToken is not defined
describe('validateToken', () => {
  it('should accept valid JWT tokens', async () => {
    const token = 'valid.jwt.token';
    const result = await validateToken(token);
    expect(result.valid).toBe(true);
  });
});
```

#### Step 2: GREEN - Write Minimal Code to Pass

1.  Write the simplest, most minimal code possible to make the failing test(s) pass.
2.  Do not add any functionality not required by the test. The goal is to get to green quickly, not to write perfect code.
3.  Run the tests again and **confirm they now pass**.

*Example of minimal passing code:*
```typescript
// Simplest code to make the test pass
export async function validateToken(token: string) {
  jwt.verify(token, SECRET); // Throws on invalid
  return { valid: true, userId: 'some-id' };
}
```

#### Step 3: REFACTOR - Clean Up the Code

1.  With the safety of passing tests, refactor the code you just wrote.
2.  Improve names, extract functions, remove duplication, and enhance clarity.
3.  Run the tests after each small refactoring to **ensure they remain green**.

*Example of refactored code:*
```typescript
export async function validateToken(token: string): Promise<TokenResult> {
  try {
    const decoded = jwt.verify(token, getSecret()) as JWTPayload;
    return { valid: true, userId: decoded.sub };
  } catch (error) {
    // Now with proper error handling
    return { valid: false, userId: null, error: error.message };
  }
}
```

#### Step 4: Verify and Inform

1.  **Run all success criteria checks** from the plan, including automated tests, type checking, and linting.
2.  Perform any manual verification steps.
3.  **Inform the user** of the phase completion, including what was changed and what verification steps were performed.
4.  **Wait for user confirmation** before proceeding to the next phase.

### Important Guidelines

-   **One Phase at a Time:** Complete and verify each phase before starting the next.
-   **Reality Wins:** If the plan doesn't match the reality of the codebase, stop and report the issue. Do not blindly follow an outdated plan.
-   **Communicate Blockers:** If a phase is blocked for any reason (e.g., a broken external dependency), inform the user immediately.
-   **Integrate with Other Workflows:** After implementation, use other workflows to commit changes (`deliberate-commits.md`) and create PRs (`describe-pr.md`). If you need to pause, create a handoff (`create-handoff.md`).