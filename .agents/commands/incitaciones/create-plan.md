---
title: Create Implementation Plan
type: workflow
tags: [planning, execution, tdd]
status: tested
---

# Create Implementation Plan

## When to Use

This workflow is used to create a detailed, phased implementation plan for a new feature or task. It is invoked when a feature request or specification needs to be broken down into concrete, actionable steps for a developer or an AI agent to execute.

## The Prompt

Your task is to create a detailed implementation plan for the requested feature.

### Step 1: Understand the Requirement

1.  If a spec file is provided, read it fully. If not, ask for the feature or task description.
2.  Read any mentioned spec files completely.
3.  Check existing research/documentation for related work.
4.  Review any previous discussions or decisions on the topic.
5.  Understand the scope and constraints.
6.  Ask clarifying questions if anything is unclear.

### Step 2: Research the Codebase

**Goal: Document the codebase AS-IS, without suggesting improvements.** Your role is that of a documentarian, not a critic.

1.  **Find relevant existing patterns and code**: Document how similar features are implemented.
2.  **Identify integration points**: Where will the new code connect with existing code?
3.  **Note conventions to follow**: Style, naming, and architectural conventions.
4.  **Understand the current architecture**: Document the existing structure and data flow.
5.  **Identify files that will need changes**: List specific files and line ranges.
6.  Use parallel research when possible (e.g., search for features, read key files, check tests simultaneously).

**CRITICAL: Your research output should be a neutral description of what exists, with file:line references, not a list of things to fix.**

### Step 3: Design Options (if applicable)

If multiple approaches are viable:

1.  Present 2-3 design options.
2.  Include pros/cons for each.
3.  Recommend an approach and explain your reasoning.
4.  Get user alignment before detailed planning.

### Step 4: Write the Plan

Save the plan to `plans/YYYY-MM-DD-description.md` using the following template:

```markdown
# [Feature Name] Implementation Plan

**Date**: YYYY-MM-DD

## Overview
[Brief description of what we're implementing]

## Related
- Spec: `specs/XX_feature.feature` (if applicable)
- Research: `research/YYYY-MM-DD-topic.md` (if applicable)
- Related issues/tickets: [references]

## Current State
[What exists now, what's missing, what needs to change]

## Desired End State
[What will exist after implementation]
**How to verify:**
- [Specific verification steps]

## Out of Scope
[What we're explicitly NOT doing to prevent scope creep]

## Risks & Mitigations
[Identified risks and how we'll handle them]

## Phase 1: [Name]

### Changes Required
**File: `path/to/file.ext`**
- Changes: [Specific modifications needed]
- Tests: [What tests to write first (TDD)]

### Implementation Approach
[How we'll implement this phase - key decisions, patterns to use]

### Success Criteria
#### Automated:
- [ ] Tests pass: `npm test` (or relevant command)
- [ ] Type checking passes
- [ ] Linting passes
- [ ] Build succeeds
#### Manual:
- [ ] [Specific manual verification step 1]

### Dependencies
[Any dependencies on other work or external factors]

---
(Continue with more phases as needed)
---

## Testing Strategy
**Following TDD:**
1. Write tests first for each behavior.
2. Watch tests fail (Red).
3. Implement minimal code to pass (Green).
4. Refactor while keeping tests green.

**Test types needed:**
- Unit tests: [What to unit test]
- Integration tests: [What integration scenarios]

## Rollback Strategy
[How to safely rollback if something goes wrong]

## References
- [Related documentation]
- [Similar implementations in the codebase]
```

### Step 5: Review and Iterate

1.  Present the plan to the user.
2.  Highlight key decisions made.
3.  Note any areas where feedback is particularly valuable.
4.  Iterate based on feedback until approved.

## Guidelines

1.  **Be specific**: Include actual file paths and concrete changes.
2.  **Follow TDD**: Plan tests before implementation for each phase.
3.  **Break into phases**: Each phase should be independently verifiable.
4.  **Track progress**: Use a todo list throughout the planning process.
5.  **No open questions**: Resolve all questions before finalizing.
6.  **Be realistic**: Account for complexity.

## Example Flows

### Scenario 1: Feature with a spec
The user provides a spec file. The agent reads the spec, researches the codebase, creates a multi-phase plan, and presents it for feedback.

### Scenario 2: Vague feature description
The user asks to "add pagination". The agent first researches existing pagination patterns in the codebase, proposes two design options (e.g., cursor-based vs. offset-based), gets user buy-in on the recommended approach, and then creates a detailed plan.

### Scenario 3: Complex feature requiring exploration
The user asks for "real-time notifications". The agent identifies this as a complex feature and first creates a research plan to investigate technical options (WebSockets vs. SSE), infrastructure capabilities, and scalability before creating the implementation plan.