## Context
`xact-py` currently assumes two resolution paths for the Julia backend:
1. Preferred: `juliapkg` resolves `XAct`
2. Fallback: the Python package activates an embedded `xact/julia` project and `include`s `src/XAct.jl`

That fallback existed before `XAct.jl` was registered. Now it increases packaging complexity, obscures the true install path, and makes tests/docs diverge from production behavior.

## Goals / Non-Goals
- Goals:
  - Make the published Python package rely on the registered Julia `XAct` package
  - Keep runtime initialization simple and explicit
  - Preserve a workable local development flow for this monorepo
- Non-Goals:
  - Changing the Python public API
  - Reworking juliacall process model or error taxonomy
  - Changing the Julia package name or UUID

## Decisions
- Decision: `juliapkg.json` should specify the registered `XAct` package by UUID and version compatibility rather than a local path.
  - Why: this makes the packaged dependency explicit and lets Julia resolve through normal registries.
- Decision: `_runtime.py` should fail fast if `using XAct` cannot succeed, rather than activating bundled sources.
  - Why: runtime behavior should match installation behavior; hidden fallbacks make packaging bugs hard to detect.
- Decision: local development should be handled by documented Julia package development workflows, not by wheel-bundled source.
  - Why: development conveniences should not leak into released package behavior.

## Risks / Trade-offs
- First-use installation now depends on Julia registry/network access if `XAct` is not already installed.
  - Mitigation: document the behavior clearly and keep the error message actionable.
- Local editable development may require an extra Julia setup step.
  - Mitigation: document a dev override workflow.

## Migration Plan
1. Change `juliapkg.json` to resolve registered `XAct`
2. Update tests to encode the new failure/success expectations
3. Remove bundled-source fallback from runtime
4. Update docs for users and contributors

## Open Questions
- Which minimum Julia `XAct` version should `xact-py` require initially?
- Should contributor docs recommend `Pkg.develop(path="...")` or a `JULIA_PROJECT`/`JULIA_PYTHONCALL_EXE`-style override for local development?
