# xAct 1.2.0 → 1.3.0 audit

Date: 2026-04-30
Owner: `sxAct-nd7v`
Status: draft for human review

## Scope

This audit compares the xAct bundle currently pinned by the oracle (`oracle/VERSION` = `xAct 1.2.0, Mathematica 14.3`) against the upstream `xAct_1.3.0.tgz` release published on 2025-12-29.

Compared inputs:

- local bundle: `resources/xAct_1.2.0.tgz`
- upstream bundle: `https://xact.es/download/xAct_1.3.0.tgz`
- implemented / relevant modules for this repo:
  - `xCore`
  - `xPerm`
  - `xTensor`
  - `xCoba`
  - `xPert`
  - `xTras`
  - `Invar`
- adjacent bundled packages that affect roadmap planning:
  - `TexAct`
  - `SpinFrames`
  - `SymManipulator`
  - `xTerior`

Method used:

1. Compare bundle contents.
2. Compare package version headers in the `.m` / `PacletInfo.m` files.
3. Compare public `::usage` symbols to detect API additions/removals.
4. Read package history files to identify behavior changes likely to affect oracle snapshots.

## Executive summary

The xAct 1.3.0 bundle is **mostly additive** for the parts sxAct already implements.

The two changes most likely to affect oracle parity are:

1. **`xTensor 1.2.0 → 1.3.0`**
   - adds `InertHeadArgumentCount`
   - changes inert-head handling
   - adds / fixes **complex metrics on inner vbundles**
2. **`xPerm 1.2.3 → 1.2.4`**
   - fixes a bug in `RightTransversal`
   - this can change canonical representatives and therefore snapshot outputs

Everything else in the already-implemented core is either unchanged by version number or appears additive / bugfix-only from the public surface.

Also important: the original migration issue text mentions `xPert 1.1.0`, but the upstream `xAct_1.3.0.tgz` inspected here still contains **`xPert 1.0.6`**. This should be corrected in `sxAct-ltaa` and in any related migration issue text that repeats the `xPert 1.1.0` assumption.

## Bundle-level changes

### New bundled packages in xAct 1.3.0

Compared with `xAct_1.2.0.tgz`, the `xAct_1.3.0.tgz` bundle adds:

- `SpaceSpinors` `0.1.3`
- `xCPS` `1.0.1`
- `xIdeal` `0.0.1`

These are new bundle contents, not changes to the already-implemented core.

### Bundled package version changes

#### Implemented modules affecting oracle migration

| Package | xAct 1.2.0 bundle | xAct 1.3.0 bundle | Change | Migration significance |
|---|---:|---:|---|---|
| xCore | 0.6.10 | 0.6.10 | none | Low |
| xPerm | 1.2.3 | 1.2.4 | bugfix release | High |
| xTensor | 1.2.0 | 1.3.0 | major release | High |
| xCoba | 0.8.6 | 0.8.6 | none | Low |
| xPert | 1.0.6 | 1.0.6 | none | Low |
| Invar | 2.0.5 | 2.0.5 | none | Low |
| xTras | 1.4.2 | 1.4.2 | none | Low |

#### Adjacent packages affecting roadmap planning

| Package | xAct 1.2.0 bundle | xAct 1.3.0 bundle | Change | Migration significance |
|---|---:|---:|---|---|
| TexAct | 0.4.3 | 0.4.5 | additive | Roadmap-only |
| SpinFrames | 0.5.3 | 0.5.6 | additive | Roadmap-only |
| SymManipulator | 0.9.5 | 0.9.6 | bugfix/additive | Roadmap-only |
| xTerior | 0.9.1 | 0.9.1 | same-version bundle-content difference | Roadmap-only |

Methodological note:
- Same version strings do **not** guarantee identical package contents across xAct bundles.
- Where same-version content drift appears (notably `xTerior`), treat this as a bundle-content difference that requires manual verification, not as a semver signal by itself.

## Changes by implemented module

### xCore

- **Version**: unchanged (`0.6.10`)
- **Public symbol diff**: no additions, no removals detected
- **Migration risk**: low
- **Evidence**: version header unchanged; no public symbol additions/removals detected
- **Recommended action**: no xCore-specific migration work expected beyond normal parity reruns

### xPerm

- **Version**: `1.2.3 → 1.2.4`
- **Public symbol diff**: no additions, no removals detected
- **Migration risk**: high
- **Evidence**:
  - history note: `2025-11-17` fixed a problem in `RightTransversal`; `SortCycles` was missing

#### Breaking / parity-relevant behavior

This is the clearest behavior change in the permutation engine:

- `RightTransversal` may return **different canonical representatives / ordering** than before.
- Any oracle snapshots or derived canonicalization results that depend on those representatives may drift.

This is a **behavioral breaking change for parity**, even though the public API name set is unchanged.

#### Recommended action

Prioritize rerunning:

- `xperm` oracle fixtures
- Butler examples
- any `ToCanonical` / symmetry tests downstream that depend on `xPerm`

### xTensor

- **Version**: `1.2.0 → 1.3.0`
- **Public symbol additions**:
  - `InertHeadArgumentCount`
- **Public symbol removals**: none detected
- **Migration risk**: high

#### New API surface

`xTensor 1.3.0` adds:

- `InertHeadArgumentCount[ih]`
  - returns the number of tensorial arguments expected by inert head `ih`
  - default value is `1`

#### Observed release-history changes

- inert heads now know their tensor-argument count
- fixes / extensions for **complex metrics in inner vbundles**

#### Migration-specific parity risks

1. **Inert head handling changed**
   - formatting / boxing behavior for inert heads can differ
   - expressions involving custom inert heads may now print or validate differently
   - this is especially relevant if any oracle snapshots capture formatted or reconstructed inert-head structure

2. **Complex metrics on inner vbundles**
   - `DefMetric` gained new support / fixes for complex metrics on inner vbundles
   - behavior for these cases may differ from 1.2.0 because they were previously unsupported or partially supported

#### Recommended action

High-priority reruns after oracle upgrade:

- `xtensor` canonicalization
- contraction / metric tests
- covariant derivative tests
- any cases involving inert heads, custom formatting, or inner-vbundle metrics

Additional note:
- Unchanged downstream module versions do **not** rule out indirect drift caused by changed `xTensor` semantics.

### xCoba

- **Version**: unchanged (`0.8.6`)
- **Public symbol diff**: no additions, no removals detected
- **Migration risk**: low
- **Evidence**: version header unchanged; no public symbol additions/removals detected
- **Recommended action**: no bundle-level xCoba API migration expected, but expect possible indirect drift if `xTensor` semantics change under it

### xPert

- **Version**: unchanged (`1.0.6`)
- **Public symbol diff**: no additions, no removals detected
- **Migration risk**: low
- **Evidence**: version header unchanged; no public symbol additions/removals detected
- **Recommended action**: no xPert-specific parity drift expected from the bundle upgrade itself; correct issue text and downstream expectations to reflect that upstream `xAct_1.3.0.tgz` still contains **`xPert 1.0.6`**, not `1.1.0`

### xTras

- **Version**: unchanged (`1.4.2`)
- **Public symbol diff**: no additions, no removals detected from the inspected `.m` files in the bundle
- **Migration risk**: low
- **Evidence**: aggregated public-symbol extraction across the inspected `xTras` package files did not show additions or removals
- **Recommended action**: no xTras-specific parity drift expected from the 1.3.0 bundle itself

### Invar

- **Version**: unchanged (`2.0.5`)
- **Public symbol diff**: no additions, no removals detected
- **Migration risk**: low
- **Evidence**: version header unchanged; no public symbol additions/removals detected
- **Recommended action**: no Invar-specific migration work is required beyond rerunning parity against the new oracle baseline

## Adjacent packages that affect the roadmap

These do not block the oracle upgrade, but they matter for future implementation planning.

### TexAct

- **Version**: `0.4.3 → 0.4.5`
- **New public symbols / options detected**:
  - `$TexViewResolution`
  - `TexBreakAvoidEnvs`
- Additional history notes indicate support improvements for:
  - `OverlayBox`
  - `\infty`
  - `\mathring`
  - more LaTeX-breaking controls

Implication:
- the existing `TexAct` ticket should target the **1.3.0** surface, not the older 1.2.0-era feature set.

### SpinFrames

- **Version**: `0.5.3 → 0.5.6`
- **New public symbols detected** include:
  - `GHPPrime`
  - `GHPMatrixOp`
  - `ComponentMatrix`
  - `EqListToGHPMatrixEq`
  - `IndexFormattingFunction`
  - `IndexTexFunction`
  - `DyadIndexFormattingFunction`
  - `DyadIndexTexFunction`
  - several symmetric-component helpers

Implication:
- `SpinFrames` is richer than the old planning assumption.
- The future `SpinFrames` ticket should explicitly target this newer API surface.

### SymManipulator

- **Version**: `0.9.5 → 0.9.6`
- No public symbol additions detected, but there is a 2024 bugfix around `SymmetricSpinorOfArbitraryValenceQ` and related logic.

Implication:
- low risk for the current migration
- but spinor-adjacent future work should assume the newer behavior

### xTerior

- **Version header**: unchanged (`0.9.1`)
- **Public symbols added relative to the 1.2.0 bundle contents inspected**:
  - `ChangeGenCovD`
  - `ExpandCovD`
  - `ExpandKoszul`
  - `Koszul`
  - `PDFrame`
  - `eFrame`

Important caveat:
- This appears to be a **same-version bundle-content difference**, not a version bump.
- Verify manually before treating it as a formal upstream release change.

Implication:
- if / when `xTerior` is implemented, target the richer 1.3.0 bundle contents, not the older assumptions.

## Breaking-change list for `sxAct-ltaa`

Use these bullets verbatim in `sxAct-ltaa` unless issue-length constraints require shortening:

1. **`xPerm 1.2.4` changes `RightTransversal` behavior**
   - bugfix adds missing `SortCycles`
   - expect canonical representative / ordering drift in some permutation outputs
   - rerun Butler examples and downstream canonicalization snapshots carefully

2. **`xTensor 1.3.0` adds `InertHeadArgumentCount` and changes inert-head behavior**
   - expressions with inert heads may print, validate, or reconstruct differently
   - watch for snapshot drift in inert-head-heavy tests

3. **`xTensor 1.3.0` extends / fixes complex metrics on inner vbundles**
   - previously unsupported or partially supported behavior can now differ legitimately
   - if we have no coverage yet, add focused oracle cases after the baseline migration

4. **No removals detected in implemented-module public symbol sets**
   - this looks like an additive / bugfix upgrade, not a large API deletion event
   - most migration effort is therefore expected to be snapshot drift analysis, not wrapper breakage

5. **Ticket text discrepancy**
   - upstream `xAct_1.3.0.tgz` still contains `xPert 1.0.6`, not `1.1.0`
   - adjust migration expectations and documentation accordingly

## Recommended migration sequence

1. Update `sxAct-ltaa` with the breaking-change bullets above.
2. Change `oracle/VERSION` to the 1.3.0 bundle.
3. Rebuild the oracle image.
4. Rerun parity in this order:
   1. `xPerm`
   2. `xTensor`
   3. `xCoba`
   4. `xPert`
   5. `xTras`
   6. `Invar`
5. Treat drift first as possible **upstream bugfix / semantics change**, not automatically as a regression in sxAct.
6. Remember that unchanged module versions do **not** rule out indirect drift caused by changed dependencies such as `xPerm` and `xTensor`.
7. After parity is green, update `docs/src/status.md` to reflect the new oracle baseline.

## Bottom line

For sxAct, xAct 1.3.0 is a **manageable migration**:

- the implemented core has **very little surface-area churn**
- the real risk is **behavioral drift** in `xPerm` and `xTensor`
- the bundle adds meaningful future roadmap packages (`SpaceSpinors`, `xCPS`, `xIdeal`)
- roadmap tickets for `TexAct`, `SpinFrames`, and `xTerior` should assume the **1.3.0** bundle, not older assumptions

Conclusion: proceed with `sxAct-ltaa`, but expect review time to concentrate on `xPerm` canonicalization drift and `xTensor` semantic drift rather than broad API breakage.
