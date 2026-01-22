---
title: Commit Changes with Review
type: workflow
tags: [git, version-control, commit]
status: tested
---

# Commit Changes with Review

## When to Use

This workflow is used to create thoughtful, logical git commits for changes made during a development session. It enforces a review process to ensure commits are well-documented, atomic, and adhere to best practices, preventing large, meaningless commits.

## The Prompt

Your task is to create git commits for changes made during this session.

### CRITICAL RULES

1.  **NEVER commit without describing what will be committed first.**
2.  **NEVER use `git add -A` or `git add .`** Instead, add files explicitly.
3.  **ALWAYS review the conversation history** to write accurate commit messages that capture the "why".
4.  **ALWAYS make multiple, logical commits** instead of one large, monolithic commit.
5.  **NEVER add co-author or AI attribution.** Commits should be authored by the human user only.

### Process

#### Step 1: Review What Changed

Use `git status` and `git diff` to understand all modifications in the working directory.

```bash
# Show all changes
git status

# Review each file individually
git diff path/to/file1
git diff path/to/file2
```

#### Step 2: Propose Logical Commits

Group the changes into logical, atomic units and describe them to the user. For each proposed commit, list the files it will include and a brief summary of its purpose.

Example proposal:
```
I've made changes to the following files:

1.  `src/components/Login.tsx`
    - Added OAuth provider selection UI.
    - Implemented token refresh logic.
2.  `src/utils/auth.ts`
    - Created `validateToken` helper.
    - Added token expiry checking.
3.  `tests/auth.test.ts`
    - Added tests for new OAuth flow and token validation.

These changes can be grouped into two logical commits:

**Commit 1: "feat(auth): Add OAuth provider selection to login"**
- `src/components/Login.tsx`
- `src/utils/auth.ts`

**Commit 2: "feat(auth): Add token validation and refresh logic"**
- `src/utils/auth.ts` (remaining changes)
- `tests/auth.test.ts`

Shall I proceed with creating these commits?
```

#### Step 3: Wait for Confirmation

**Do not proceed** until the user confirms or provides different instructions.

#### Step 4: Execute Commits

For each approved commit, execute the following steps:

1.  **Add specific files only.**
2.  **Write a descriptive commit message** following the specified format.
3.  **Verify the commit** was created successfully.

```bash
# Add specific files for the first commit
git add src/components/Login.tsx src/utils/auth.ts

# Create the commit with a detailed message
git commit -m "feat(auth): OAuth provider selection in login

Added a UI for selecting an OAuth provider (e.g., Google, GitHub).
Implemented provider-specific configuration and redirect handling.

- LoginForm component now displays provider buttons.
- auth.ts handles provider-specific OAuth flows."

# Verify the commit was made
git log --oneline -1
```

#### Step 5: Repeat for Additional Commits

Continue the process for any remaining logical groups of changes.

## Guidelines

### Commit Message Format

```
<type>(<scope>): <short description>

<detailed description of what and why>

- Bullet points for key changes
- Focus on the 'why' not just the 'what'
```

-   **Types:** `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, etc.
-   **Scope:** The part of the codebase the commit affects (e.g., `auth`, `api`, `ui`).

### Verification Checklist

Before each commit, ensure:
- [ ] Reviewed `git diff` for each file.
- [ ] Grouped changes into a logical, atomic unit.
- [ ] Written a descriptive commit message with context ("why").
- [ ] Used explicit file paths in `git add`.
- [ ] No AI attribution in the commit message.