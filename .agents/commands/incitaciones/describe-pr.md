---
title: Generate PR Description
type: task
tags: [git, pr, documentation]
status: tested
---

# Generate PR Description

## When to Use

This task is used to create a comprehensive and well-structured pull request description. A good PR description is crucial for efficient code reviews, providing context to future developers, and maintaining a clear project history. This should be run after code changes are complete and a PR has been or is about to be created.

## The Prompt

Your task is to create a comprehensive pull request description based on the actual changes in the PR.

### Step 1: Identify the PR

-   **If on a branch with an associated PR**, get its details:
    ```bash
    gh pr view --json url,number,title,state,baseRefName
    ```
-   **If the PR doesn't exist or you're not on its branch**, find it from a list:
    ```bash
    gh pr list --limit 10 --json number,title,headRefName,author
    ```
    Then ask the user to specify which PR to describe.

### Step 2: Gather PR Information

Collect all necessary context about the PR's changes:

```bash
# Get the full diff of all changes
gh pr diff {number}

# Get the commit history
gh pr view {number} --json commits --jq '.commits[] | "\(.oid[0:7]) \(.messageHeadline)"'

# Get PR metadata
gh pr view {number} --json url,title,number,state,baseRefName,additions,deletions
```

### Step 3: Analyze Changes

Review the collected information to understand the what, why, and impact of the changes.

-   **What changed?** (Files, lines, key functions/classes)
-   **Why it changed?** (Problem solved, requirement fulfilled)
-   **Impact?** (User-facing changes, API changes, breaking changes, performance, security)
-   **Context?** (Related issues, plans, design docs, dependencies)

### Step 4: Generate Description

Use the following template to structure the PR description.

```markdown
## Summary

[A 2-3 sentence overview of what this PR does and why it's needed. This should be a high-level summary that is easy for anyone to understand.]

## Changes

**Key changes in this PR:**
- [Specific change 1 with reasoning]
- [Specific change 2 with reasoning]
- [Specific change 3 with reasoning]

**Files changed:**
- `path/to/file1.ext` - [High-level summary of what changed in this file and why]
- `path/to/file2.ext` - [High-level summary of what changed in this file and why]

## Motivation

[Explain the problem this PR solves or the requirement it fulfills. Reference related issues (e.g., "Fixes #123"), user requests, or technical debt.]

## Implementation Details

[Explain key implementation decisions, trade-offs considered, and why this approach was chosen over alternatives. This is for complex changes that need more context.]

**Key decisions:**
1. [Decision 1]: [Rationale]
2. [Decision 2]: [Rationale]

## Related

- **Issue:** #123 [if applicable]
- **Plan:** `plans/2026-01-12-feature-name.md` [if applicable]
- **Depends on:** PR #456 [if applicable]
- **Blocks:** PR #789 [if applicable]

## Testing

**Automated tests:**
- [ ] Unit tests pass (`npm test`)
- [ ] Integration tests pass
- [ ] E2E tests pass [if applicable]

**Manual testing steps:**
- [ ] [Specific manual test case 1 for a reviewer to follow]
- [ ] [Specific manual test case 2 for a reviewer to follow]

## Breaking Changes

[If any breaking changes, list them prominently here with migration guidance. If none, state "None".]

## Security Considerations

[Note any security implications, or state "None identified".]

## Performance Impact

[Note any performance changes, with benchmarks if possible, or state "No significant impact".]

## Screenshots / Demos

[For UI changes, include before/after screenshots or GIFs to visually demonstrate the changes.]

## Reviewer Notes

[Add any specific notes for reviewers, such as areas to focus on, questions you have, or context they might need.]
```

### Step 5: Present to User for Approval

Show the generated description to the user and ask for confirmation before applying it.

```
I've generated a PR description for PR #{number}. Here's what I've created:

[Show generated markdown]

Would you like me to:
1. Update the PR with this description?
2. Make changes to the description first?
3. Copy it to the clipboard for you to update manually?
```

### Step 6: Update the PR

Upon approval, use the `gh` CLI to update the pull request.

```bash
# Save the description to a temporary file
cat > /tmp/pr-description.md <<'EOF'
[description content]
EOF

# Update the PR body from the file
gh pr edit {number} --body-file /tmp/pr-description.md

# Verify the update
gh pr view {number}
```

## Guidelines

1.  **Focus on "why"**: The `diff` shows *what* changed; the description must explain *why*.
2.  **Be specific**: Vague descriptions are not helpful for reviewers.
3.  **Provide context**: Link to issues, plans, and other relevant documents.
4.  **Guide reviewers**: Tell them what to look for and how to test your changes.
5.  **Highlight breaking changes**: Make them impossible to miss.
6.  **Be thorough but scannable**: Use headers, lists, and bold text to improve readability.