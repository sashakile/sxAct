---
title: Research Codebase
type: task
tags: [codebase, research, documentation]
status: tested
---

# Research Codebase

## When to Use

This task is used to document and explain a specific part of the codebase as it exists today. It's crucial for gaining a factual understanding of existing systems without introducing bias or premature optimization. This task is often a prerequisite for planning new features, debugging, or refactoring efforts.

## The Prompt

Your task is to document and explain the codebase as it exists today.

### CRITICAL RULES

**You are a documentarian, not an evaluator:**

1.  ✅ **DO:** Describe what exists, where it exists, and how it works.
2.  ✅ **DO:** Explain patterns, conventions, and architecture.
3.  ✅ **DO:** Provide `file:line` references for everything.
4.  ✅ **DO:** Show relationships between components.
5.  ❌ **DO NOT:** Suggest improvements or changes.
6.  ❌ **DO NOT:** Critique the implementation.
7.  ❌ **DO NOT:** Recommend refactoring.
8.  ❌ **DO NOT:** Say things like "could be improved" or "should use".

### Process

#### Step 1: Understand the Research Question

The user will provide a specific question (e.g., "How does authentication work?", "Where are errors handled?", "What's the data flow for user registration?", "Document the API layer architecture").

-   **Clarify if needed:** What specific aspect to focus on? What level of detail is needed? Are there any specific files already identified?

#### Step 2: Decompose the Question

Break down the research question into searchable components.

*Example:* For "How does authentication work?", investigate:
1.  Where authentication logic lives.
2.  What authentication methods exist.
3.  How authentication state is managed.
4.  Where authentication is validated.
5.  How errors are handled.
6.  What the authentication flow looks like.

#### Step 3: Research with Parallel Searches

Use search tools efficiently to find relevant information.

```bash
# Example commands
find . -name "*auth*" -type f
grep -r "authenticate" --include="*.ts" --include="*.js"
grep -r "login" --include="*.ts" --include="*.js"
grep -r "middleware" --include="*.ts"
grep -r "auth" config/ .env.example
```

#### Step 4: Read Identified Files

Read identified files completely from top to bottom. Note imports, dependencies, and how components connect.

#### Step 5: Document Findings

Use the following template for your research output.

```markdown
# Research: [Topic]

**Date:** [ISO date]
**Question:** [Original research question]

## Summary
[2-3 paragraph high-level overview of findings]

## Architecture Overview
[Describe the overall architecture for this component/feature]
```
[Optional ASCII diagram showing relationships]
```

## Key Components

### Component 1: [Name]
**Location:** `path/to/file.ext:123-456`
**Purpose:** [What it does]
**Used by:** [What depends on this]
**Depends on:** [What this depends on]
**How it works:**
[Step-by-step explanation of the implementation]
**Key methods/functions:**
- `functionName()` (line 123): [What it does]

## Data Flow
[Describe how data flows through the system for this feature]
1. User action triggers X (`src/components/Button.tsx:67`)
2. X calls Y with data (`src/handlers/handler.ts:23`)
...

## Patterns and Conventions
**Pattern 1:** [Describe pattern found]
- Used in: [file:line, file:line]
- Purpose: [Why this pattern]

## Configuration
**Environment variables:**
- `AUTH_SECRET` - Used in `src/auth/jwt.ts:12`
**Config files:**
- `config/auth.json` - Contains [what]

## Error Handling
[How errors are handled in this area]
- Error types: [List error types]
- Error handlers: `src/errors/AuthError.ts:23`

## Testing
**Test files:**
- `tests/auth.test.ts` - Tests [what]
**Test patterns:** [How tests are structured]

## Dependencies
**External libraries:** `jsonwebtoken`, `bcrypt`
**Internal dependencies:** `src/db/users.ts`

## Entry Points
**Where this feature is invoked:**
1. `src/routes/auth.ts:45` - Login endpoint

## Related Code
**Related features:** Authorization, User management

## Open Questions
- [ ] How are refresh tokens handled?
```