---
title: Iterate Implementation Plan
type: workflow
tags: [planning, iteration, feedback]
status: tested
---

# Iterate Implementation Plan

## When to Use

This workflow is for updating an existing implementation plan based on new feedback, new requirements, or a change in understanding. It's a critical part of the feedback loop, ensuring that the plan remains a living document that accurately reflects the path to completion. Use this when a plan needs to be adjusted, corrected, or expanded upon.

## The Prompt

Your task is to update an existing implementation plan based on user feedback, grounding all changes in the reality of the codebase.

There are three scenarios for invocation:
1.  **No plan file provided**: Ask for the plan path (you can list available plans in `plans/`).
2.  **Plan file provided but NO feedback**: Ask what changes the user wants to make.
3.  **Both plan and feedback provided**: Proceed directly with the updates.

### Process

#### Step 1: Understand the Current Plan and Requested Changes

1.  Read the existing plan file completely to understand its structure, approach, and any work already completed.
2.  Carefully analyze the user's requested changes. Are they adding requirements, changing scope, fixing errors, or adjusting the approach?
3.  Ask clarifying questions if the feedback is ambiguous.

#### Step 2: Research Codebase Reality

**Before applying changes, ground your edits in the current state of the codebase.**

1.  **Search for relevant patterns** to understand how similar features are implemented.
2.  **Read affected files** to understand the impact of the proposed changes.
3.  **Validate feasibility** of the requested changes against the existing architecture.
4.  The goal of this research is to understand what *is*, not to propose new ideas. This understanding will inform how you update the plan.
5.  *Skip extensive research only if the changes are minor and non-technical (e.g., fixing typos).*

#### Step 3: Confirm Understanding

Before modifying the plan, confirm your intended changes with the user.

```
Based on your feedback, I understand you want to:
- [Change 1 with specific detail]
- [Change 2 with specific detail]

My research of the codebase found [relevant pattern or constraint].

I plan to update the plan by:
1. [Specific modification to plan section X]
2. [Specific modification to plan section Y]

Does this align with your intent?
```
**Wait for confirmation before proceeding.**

#### Step 4: Update the Plan

1.  Make focused, surgical edits to the existing plan file.
2.  Maintain the existing structure unless the change requires modifying it.
3.  Ensure consistency across the document (e.g., if you change scope, update the "Out of Scope" section).
4.  **Preserve completed work.** Do not remove checkmarks or modify phases already marked as complete without a very good reason.

#### Step 5: Present Changes and Iterate

1.  Show the user what you changed and explain the impact on the implementation.
2.  If the user has more feedback, repeat the process. Continue until the plan is approved.

## Common Iteration Scenarios

-   **Adding a New Phase:** The user wants to add a new step, like API caching. Research existing caching patterns, draft the new phase, and update dependencies.
-   **Changing an Approach:** The user wants to switch from in-memory caching to Redis. Research Redis usage in the codebase, identify all affected phases, and update their implementation details and success criteria.
-   **Adding Detail:** A phase is too vague. Research the specific implementation details and add concrete file paths, function names, and test requirements.
-   **Removing Scope:** The user decides to defer a feature. Identify the related phases, move them to the "Out of Scope" section, and ensure the remaining plan is still coherent.
-   **Correcting Errors:** The user points out that an approach is incorrect. Understand the constraint, research the correct approach, and update the affected phases.