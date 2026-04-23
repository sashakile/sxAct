# Change: Use registered Julia XAct package from xact-py

## Why
`xact-py` still contains development-era logic for loading a bundled local copy of the Julia package. Now that `XAct.jl` is published in Julia registries, the Python package should install and load the registered Julia package instead of embedding Julia source paths and runtime fallbacks.

## What Changes
- Update `xact-py`'s Julia package metadata to resolve `XAct` from the Julia registries.
- Remove the runtime fallback that activates and includes a bundled `xact/julia` source tree.
- Preserve a development workflow for local repository checkouts without requiring the published wheel to embed Julia sources.
- Update tests and installation docs to reflect registry-based installation.

## Impact
- Affected specs: `xact-py-runtime-installation`
- Affected code: `packages/xact-py/src/xact/juliapkg.json`, `packages/xact-py/src/xact/xcore/_runtime.py`, Python runtime tests, xact-py docs
