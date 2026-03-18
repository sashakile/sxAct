---
date: 2026-03-17T21:08:54-03:00
git_commit: b228bed
branch: main
directory: /var/home/sasha/para/areas/dev/gh/sk/sxAct
issue: sxAct-l52y (closed)
status: handoff
---

# Handoff: translate migration + JET pkgimage fix

## Context

This session completed the migration of the Wolfram→xAct translation tooling from
`sxact` (the dev/test package) into `xact-py` (the user-facing Python package), making
`xact translate` available with just `pip install xact-py` — no Julia runtime required.
We also diagnosed and fixed a flaky JET static analysis test failure caused by stale
Julia pkgimage cache files accumulating over development sessions.

The translate module has two conceptual layers: generic WL parsing (`wl_parser`,
`wl_serializer`) which could eventually migrate to Elegua, and xAct-specific mapping
(`action_recognizer`, `renderers`) which permanently belongs in xact-py. This split
was documented in the beads issue notes for when Elegua is ready (sxAct-rvzo).

## Current Status

### Completed
- [x] Migrated `wl_parser.py`, `wl_serializer.py`, `action_recognizer.py`, `renderers.py`
  to `packages/xact-py/src/xact/translate/`
- [x] Created `packages/xact-py/src/xact/cli.py` — `xact translate` argparse CLI
- [x] Added `[translate] = []` optional extra + `xact = "xact.cli:main"` script entry
  to `packages/xact-py/pyproject.toml`
- [x] Deleted `packages/sxact/src/sxact/translate/` — no re-exports needed
- [x] Updated `sxact/cli/translate.py` and `sxact/cli/repl.py` to import from `xact.translate`
- [x] Updated all `tests/translate/` test imports to `xact.translate`
- [x] 142/142 translate tests pass
- [x] Diagnosed JET failure: `QjpwK_XJHFC.ji` was a valid-but-broken pkgimage missing
  `xAct.jl` source-text; 9 stale candidates caused Revise to pick wrong one
- [x] Fixed `test/runtests.jl` to purge stale pkgimage caches before `JET.test_package()`
- [x] All pre-push hooks pass, pushed to remote

### In Progress
- nothing

### Planned
- [ ] sxAct-jpj4: Python API: export `covd()` and `CovDExpr` for typed covariant derivative expressions
- [ ] sxAct-9jxh: Julia getting-started guide (typed API first-class workflow)
- [ ] sxAct-45e3: Python API: expose xCoba coordinate functions
- [ ] sxAct-rvzo: Refactor sxAct to consume Elegua as external dependency (BLOCKED on Elegua)

## Critical Files

1. `packages/xact-py/src/xact/translate/__init__.py` — public API: `wl_to_action`, `wl_to_actions`
2. `packages/xact-py/src/xact/translate/action_recognizer.py` — xAct-specific WL→action-dict mapping; permanently in xact-py
3. `packages/xact-py/src/xact/translate/wl_parser.py` — generic WL parser; future Elegua candidate
4. `packages/xact-py/src/xact/translate/renderers.py` — JSON/Julia/TOML/Python output renderers
5. `packages/xact-py/src/xact/cli.py` — `xact translate` CLI entry point
6. `packages/xact-py/pyproject.toml` — `[translate]` extra + `xact` script
7. `test/runtests.jl:740-755` — JET test with pkgimage cache cleanup

## Recent Changes

- `packages/xact-py/src/xact/translate/` — new directory with 5 files (all moved from sxact)
- `packages/xact-py/src/xact/cli.py` — new file
- `packages/xact-py/pyproject.toml` — added optional-dependencies + scripts sections
- `packages/sxact/src/sxact/cli/translate.py:20-21` — imports changed to `xact.translate.*`
- `packages/sxact/src/sxact/cli/repl.py:18-20` — imports changed to `xact.translate.*`
- `packages/sxact/src/sxact/translate/` — deleted (5 files gone)
- `tests/translate/*.py` — all 4 files: `sxact.translate` → `xact.translate`
- `test/runtests.jl:740-755` — added stale pkgimage cleanup before JET test

## Key Learnings

1. **JET failure was stale pkgimage accumulation, not a code bug**
   - `Base.find_all_in_cache_path(id)` returned 9 candidates; `QjpwK_XJHFC.ji` passed
     header validation but had no source-text for `xAct.jl`
   - Revise (used internally by JET) picked the broken candidate on that run
   - Fix: purge all but the newest `.ji`/`.so` pair before `JET.test_package()`
   - Broken file confirmed via `Base.read_dependency_src(cachefile, srcfile)` — threw
     while all others returned ~1499 chars

2. **`to_python` renderer references `sxact` in generated string output**
   - `renderers.py:to_python()` generates `from sxact.adapter.julia_stub import JuliaAdapter`
     as a string in its output (not an actual import)
   - This is correct behavior — it generates migration code for users of the sxact adapter
   - Do NOT change this when refactoring

3. **Architecture split for Elegua migration**
   - `wl_parser.py` + `wl_serializer.py`: generic WL parsing, zero xAct knowledge → future Elegua
   - `action_recognizer.py` + `renderers.py`: hardcoded xAct function names → permanently xact-py
   - Decision documented in beads issue sxAct-l52y notes

4. **sxact has xact-py as a dependency**
   - `packages/sxact/pyproject.toml` already lists `xact-py` as a dep
   - So `sxact/cli/repl.py` and `sxact/cli/translate.py` importing from `xact.translate` is fine

## Open Questions

- [ ] Should `to_python` renderer be updated to import from `xact` directly (bypassing sxact adapter)?
  Currently generates code using the sxact adapter which requires Julia. Might want a pure-Python mode.
- [ ] When Elegua is ready: move `wl_parser.py` + `wl_serializer.py` to `elegua.formats.wolfram`
  and update `xact.translate` imports. See sxAct-rvzo.

## Next Steps

1. **Run `bd ready`** to see what's next (sxAct-jpj4 / sxAct-9jxh / sxAct-45e3 are unblocked)

2. **TExpr Stage 3** — check if there are remaining TExpr batch issues open:
   `bd list --status=open | grep -i texpr`

3. **Elegua dependency** (when ready): update `xact.translate.wl_parser` and
   `xact.translate.wl_serializer` to import from `elegua.formats.wolfram` instead

## Artifacts

**New files:**
- `packages/xact-py/src/xact/translate/__init__.py`
- `packages/xact-py/src/xact/translate/wl_parser.py`
- `packages/xact-py/src/xact/translate/wl_serializer.py`
- `packages/xact-py/src/xact/translate/action_recognizer.py`
- `packages/xact-py/src/xact/translate/renderers.py`
- `packages/xact-py/src/xact/cli.py`

**Modified files:**
- `packages/xact-py/pyproject.toml`
- `packages/sxact/src/sxact/cli/translate.py`
- `packages/sxact/src/sxact/cli/repl.py`
- `tests/translate/test_wl_parser.py`
- `tests/translate/test_action_recognizer.py`
- `tests/translate/test_renderers.py`
- `tests/translate/test_integration.py`
- `test/runtests.jl`

**Deleted files:**
- `packages/sxact/src/sxact/translate/__init__.py`
- `packages/sxact/src/sxact/translate/wl_parser.py`
- `packages/sxact/src/sxact/translate/wl_serializer.py`
- `packages/sxact/src/sxact/translate/action_recognizer.py`
- `packages/sxact/src/sxact/translate/renderers.py`

**Commits this session:**
- `8ec32b3` feat(translate): move xact.translate to xact-py, add xact CLI
- `b228bed` fix(test): purge stale xAct pkgimage caches before JET test

## References

- Beads issue (closed): `bd show sxAct-l52y`
- Future Elegua migration: `bd show sxAct-rvzo`
- Next unblocked work: `bd ready`
- Architecture decision: `bd show sxAct-l52y` → notes section
