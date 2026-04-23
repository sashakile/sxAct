## 1. Specification
- [x] 1.1 Validate the proposed registry-based runtime behavior with OpenSpec

## 2. Tests
- [x] 2.1 Add or update Python runtime tests to cover successful registry-based initialization
- [x] 2.2 Add or update Python runtime tests to verify missing-package failures no longer rely on bundled source fallback

## 3. Implementation
- [x] 3.1 Update `packages/xact-py/src/xact/juliapkg.json` to depend on registered `XAct`
- [x] 3.2 Simplify `packages/xact-py/src/xact/xcore/_runtime.py` to load `XAct` only via Julia package resolution
- [x] 3.3 Preserve documented local-development workflow for editable installs without wheel-embedded Julia source

## 4. Documentation
- [x] 4.1 Update xact-py installation docs and README to describe registry-based Julia resolution
- [x] 4.2 Update any repository docs that still describe bundled Julia sources for xact-py

## 5. Verification
- [x] 5.1 Run targeted Python tests for runtime initialization
- [x] 5.2 Run relevant docs/tests checks for changed documentation or packaging metadata
