---
date: 2026-03-09T17:45:00-03:00
git_commit: 3e29cb9
branch: main
directory: /var/home/sasha/para/areas/dev/gh/sk/sxAct
status: handoff
---

# Handoff: xAct Implementation Roadmap & Repo Split

## Context

This session focused on clarifying the long-term architectural direction of the **sxAct** project. We formally separated the **Implementation Layer** (this repository) from the **Orchestrator** (Elegua) and the **Tensor DSL** (Chacana), which will now live in their own repositories. We also established a high-resolution migration roadmap for the xAct libraries and defined a new **Julia-centric documentation strategy** to provide a "no-complication" onboarding experience.

## Current Status

### Completed
- [x] **Repository Scope Clarification**: Updated `README.md`, `AGENTS.md`, and `docs/src/architecture.md` to define `sxAct` as the Julia/Python implementation core.
- [x] **Documentation Cleanup**: Removed all emojis from `README.md`, `AGENTS.md`, `docs/`, `specs/`, and `research/` for a clean, CLI-friendly aesthetic.
- [x] **Library Migration Roadmap**: Created `specs/XACT_LIBRARIES_MIGRATION_PLAN.md` (component-level) and `specs/2026-03-09-xact-migration-master-plan.md` (high-level progress).
- [x] **Issue Tracking**: Created 19 detailed `bd` (beads) tickets for all missing/in-progress xAct components and fixed cross-task dependencies.
- [x] **Documentation Strategy**: Created `specs/2026-03-09-documentation-strategy.md` detailing the pivot to a `Documenter.jl` + `Literate.jl` polyglot model with `PythonCall.jl` validation.

### In Progress
- [ ] **Phase 2 Refactoring**: The codebase is ready for the extraction of `Elegua`-specific logic (runner, adapters) to its new repository.

### Planned
- [x] **Refactor `docs/`**: Moved `docs/site/` to `docs/src/` and bootstrapped `make.jl`.
- [ ] **Literate Tutorial**: Create the first "Rosetta Stone" tutorial in `docs/examples/basics.jl`.
- [ ] **Implementation**: Start `CovD` (Covariant Derivative) in `XTensor.jl`.

## Critical Files

1. `specs/XACT_LIBRARIES_MIGRATION_PLAN.md` - The authoritative record of which xAct parts are ported/missing.
2. `specs/2026-03-09-documentation-strategy.md` - The blueprint for the new Julia-centric docs.
3. `AGENTS.md` - Crucial context for repository scope (sxAct vs Elegua vs Chacana).
4. `src/XCore.jl` & `src/XTensor.jl` - The primary targets for implementation work.

## Recent Changes

- `README.md`: Clarified ecosystem split (sxAct/Elegua/Chacana).
- `AGENTS.md`: Added "Repository Focus & Scope" section; removed emojis.
- `specs/2026-03-09-documentation-strategy.md`: New Julia-centric docs spec.
- `specs/XACT_LIBRARIES_MIGRATION_PLAN.md`: Component-level roadmap.
- `.beads/`: 19 new tasks created and linked.

## Key Learnings

1. **Repository Split is Essential**: Keeping the orchestrator (Elegua) in this repo was causing cognitive load. Treating it as an external "consumer" simplifies the implementation of the core physics libraries.
2. **"Docs as Tests" via Literate.jl**: Using `Literate.jl` with `PythonCall.jl` allows us to verify the Python wrapper *inside* the documentation build, ensuring zero-drift.
3. **Emoji Removal**: Emojis were cluttering the monospace terminal view. Removing them improved readability in a senior-developer CLI context.

## Open Questions

- [ ] How much of the current `sxact.runner` and `sxact.adapter` should remain in this repo as "bootstrap" code before being fully moved to `Elegua`?
- [ ] Should we use `DocumenterVitepress` for a more modern landing page within the Julia ecosystem?

## Next Steps

1. **Initialize `docs/Project.toml`** [Priority: HIGH]
   - Add `Documenter`, `Literate`, and `PythonCall`.
2. **Extract First Tutorial** [Priority: MEDIUM]
   - Convert an existing test or notebook into `docs/examples/basics.jl`.
3. **Wire `XCore` symbolic atoms** [Priority: HIGH]
   - Address the `AtomQ` / `SymbolName` blocker in `XCore.jl`.

## Artifacts

**New files:**
- `specs/2026-03-09-documentation-strategy.md`
- `specs/XACT_LIBRARIES_MIGRATION_PLAN.md`
- `specs/2026-03-09-xact-migration-master-plan.md`

**Modified files:**
- `README.md`
- `AGENTS.md`
- `docs/src/index.md`
- `docs/src/architecture.md`

**Not committed:**
- (Everything committed and pushed to `main`)
