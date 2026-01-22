---
title: Extract Reusable Prompt from Conversation
type: workflow
tags: [prompt-engineering, meta, knowledge-management]
status: tested
---

# Extract Reusable Prompt from Conversation

## When to Use

This workflow is used to analyze a successful conversation with an AI agent and extract a reusable, high-quality prompt that captures the effective interaction pattern. This is a meta-workflow for knowledge management and continuous improvement of prompt engineering.

## The Prompt

Your task is to analyze the provided conversation and extract a reusable prompt that captures the successful pattern.

### Step 1: Analyze the Conversation

Review the entire conversation to identify:

-   **The Goal:** What was the problem being solved?
-   **The Success Factors:** What specific instructions, constraints, or structures led to the desired outcome?
-   **The Key Pattern:** Can this approach be generalized for a broader class of problems?

### Step 2: Extract the Core Pattern

Identify and document the core elements of the successful interaction:

-   **Problem Solved:** General class of problems this pattern addresses.
-   **Approach:** The method or structure that worked.
-   **Critical Elements:** The key instructions or constraints that were essential for success.

### Step 3: Generalize the Instructions

Convert specific instructions from the conversation into general, reusable ones.

-   **From:** "Read `src/auth/oauth.ts` and explain how it works."
-   **To:** "Read `[FILE]` and explain how it works."

-   **From:** "Don't suggest improvements to the authentication system."
-   **To:** "Document what exists without suggesting improvements."

### Step 4: Structure the New Prompt Document

Create a new, structured prompt document using the standard template below.

```markdown
---
title: [Descriptive Title]
type: [prompt-type, e.g., task, workflow]
tags: [tag1, tag2, tag3]
tools: [applicable-tools]
status: draft
version: 1.0.0
related: []
source: extracted-from-conversation
---

# [Title]

## When to Use
[When is this prompt appropriate? What problems does it solve?]

## The Prompt
[The actual prompt text, generalized and structured, goes here.]

## Rules
[Non-negotiable guidelines for the agent.]

## Example
**Context:** [Describe a concrete scenario where this prompt would be used.]
**Input:**
`[What you would actually say to the AI]`
**Expected Output:**
`[What the AI should produce]`
```

### Step 5: Determine Filename

Follow standard naming conventions:
-   `prompt-workflow-[descriptive-slug].md` (for multi-step processes)
-   `prompt-task-[descriptive-slug].md` (for single, focused tasks)

### Step 6: Classify and Tag

-   **type:** `prompt`
-   **status:** `draft` (all new prompts start as draft)
-   **tags:** 3-5 relevant keywords

### Step 7: Present the Draft Prompt

Present the newly created prompt to the user for review.

Example presentation:
```
I've extracted a reusable prompt from our conversation.

**Pattern identified:** [Name of the pattern]
**Key insight:** [What made this interaction work]
**Proposed filename:** `content/prompt-workflow-new-feature.md`

**Draft prompt:**
[Show the full, structured prompt document]

This prompt could be useful for [use cases].

Shall I:
1. Save this prompt to the `content/` directory?
2. Make adjustments first?
```

## Guidelines

1.  **Generalize without losing specificity:** Keep concrete examples but make the core instructions general.
2.  **Capture the "why":** The `When to Use` section should explain what makes the pattern effective.
3.  **Include anti-patterns:** Document when *not* to use the prompt.
4.  **Start with "draft" status:** All extracted prompts need to be tested before being considered verified.
