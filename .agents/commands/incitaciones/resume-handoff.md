---
title: Resume from Handoff
type: workflow
tags: [handoff, context-transfer, session-management]
status: tested
---

# Resume from Handoff

## When to Use

This workflow is used to resume work from a previously created handoff document. It ensures a seamless transition of context, allowing a new agent session or developer to quickly understand the current state of work, key decisions, and next steps without needing to re-investigate the entire project history.

## The Prompt

Your task is to resume work from a handoff document through analysis and verification.

### Step 1: Read Handoff Document

-   **If a handoff path is provided:** Read the handoff file (e.g., `cat handoffs/2026-01-12_14-30-00_oauth-integration.md`).
-   **If an issue ID is provided:** Find the most recent handoff for that issue (e.g., `ls handoffs/*issue-123* | sort -r | head -1`).
-   **If no parameter provided:** List recent handoffs (e.g., `ls -lt handoffs/ | head -10`) and ask the user which to resume.

### Step 2: Extract Key Information

Identify the following critical information from the handoff:

-   **Task Status:** What was completed? What's in progress? What's planned?
-   **Critical Files:** Which files are most important to understand, and what are their relevant line ranges?
-   **Key Learnings:** What discoveries or mistakes from the previous session affect future work?
-   **Open Questions:** What decisions or uncertainties need resolution?
-   **Next Steps:** What is the prioritized todo list for the current session?

### Step 3: Verify Current Codebase State

Before acting, verify the codebase's current state against the handoff.

```bash
# Check for commits since the handoff was created
git log --oneline [handoff_commit]..HEAD

# Check the current branch
git branch --show-current

# Check the working directory status
git status

# Compare current state to the state at handoff creation
git diff [handoff_commit]
```

### Step 4: Read Referenced Files

Read the "Critical Files" mentioned in the handoff. Focus on understanding the current implementation, verifying that past learnings still apply, and identifying any conflicts with changes made since the handoff.

### Step 5: Present Analysis and Recommended Action

Present a structured analysis of the handoff and the current codebase state, then propose the next highest priority action.

```
I've analyzed the handoff from [date]. Here's the current situation:

## Original Context
[Summary of what was being worked on]

## Task Status Review

**Completed (from handoff):**
- [x] Task 1 - VERIFIED: Still complete
**In Progress (from handoff):**
- [ ] Task 3 - STATUS: [describe current state]
**Planned:**
- [ ] Next task 1 [Priority from handoff]

## Changes Since Handoff
**Commits since handoff:**
[List any commits between handoff and now]
**Impact:**
[How these changes affect our work]

## Key Learnings Still Applicable
1. [Learning 1] - Still valid because [reason]

## Questions Needing Resolution
From handoff:
- [ ] [Question 1] - [Current thinking or need decision]

## Recommended Next Action
Based on the handoff priorities and current state:
**Priority 1:** [Action from handoff]
- Reason: [Why this is still the priority]
- Files: [What needs to change]
- Approach: [How to do it]

Shall I proceed with [action]?
```

### Step 6: Get Confirmation and Begin

Wait for user confirmation. Upon approval:
-   Create a todo list from the next steps.
-   Start with the highest priority action.
-   Apply learnings from the handoff.
-   Track progress.

## Guidelines and Scenarios

-   **Always verify before acting:** Do not assume the handoff perfectly matches reality.
-   **Adapt to changes:** If the codebase has diverged significantly, assess the impact and adapt the plan.
-   **Clean Continuation:** If all is aligned, proceed normally.
-   **Diverged Codebase:** If changes have occurred, read the new structures and patterns before continuing.
-   **Incomplete Work:** If a task was "in progress," verify its current state and propose to complete it before starting new work.
-   **Stale Handoff:** If the handoff is old and the codebase has many changes, offer options to review changes, start fresh, or cherry-pick work.