---
description: Update today's session file with xAct migration experiments progress
allowed-tools: Read, Write, Bash
---

## Current Session Context

- Today's date: !`date +%Y-%m-%d`
- Session files: !`ls -1 sessions/ 2>/dev/null || echo "No session files yet"`
- Current working directory: !`pwd`
- Wolfram Engine status: !`docker compose run --rm wolfram wolframscript -code "\$Version" 2>/dev/null || echo "Not activated"`
- Git status: !`git status --short`

## Task

Update today's session file in `sessions/` with:

1. **Current Progress**: What xAct experiments, Wolfram scripts, or migration tasks were completed
2. **Learnings**: New xAct packages explored, Wolfram Language concepts, Julia/Python interop discoveries
3. **Issues & Solutions**: Problems with Docker setup, xAct loading, licensing, or package compatibility
4. **Code Examples**: Notable Wolfram/xAct code snippets, Python/Julia interop examples tested
5. **Configuration Changes**: Docker compose updates, package installations, environment setup
6. **Migration Notes**: Insights about porting xAct functionality to Julia/Python
7. **Next Steps**: Next experiments to try, packages to explore, or features to implement

**File naming**: Use format `sessions/YYYY-MM-DD-description.md` (e.g., `sessions/2026-01-08-setup-wolfram-docker.md`)

If today's session file doesn't exist, create it. Otherwise, update the existing one while preserving previous content.
