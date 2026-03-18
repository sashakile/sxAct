# Handoff: CI Optimization & Efficiency Improvements
**Date:** 2026-03-18
**Status:** Completed

## Context
The project exceeded the 2000-minute free GitHub Actions tier. An investigation was conducted to reduce CI consumption while maintaining high coverage and quality gates.

## Changes Implemented

### 1. Workflow Consolidation (`.github/workflows/test.yml`)
*   **Single VM Run:** Merged `pytest`, `julia-tests`, and `toml-regression` into a single job (`unit-tests`). This reduces VM startup and setup overhead (Python/Julia installation, dependency syncing) from 4 instances to 1.
*   **Fail-Fast Execution:** Tests run sequentially (Python Unit → Julia Unit/Logic → TOML Regressions). Failure at any stage cancels subsequent heavier tests.
*   **Excluded Slow Tests:** Explicitly added `-m "not slow"` to `pytest` for the fast-path suite.

### 2. Strategic Benchmark Decoupling (`.github/workflows/benchmarks.yml`)
*   **Moved out of `test.yml`:** Benchmarks no longer run on every push/PR.
*   **New Triggers:**
    *   **Manual:** `workflow_dispatch`.
    *   **Label-based:** Adding `run-benchmarks` label to a PR.
    *   **Release:** Automatic run on every `published` release.
    *   **Schedule:** Weekly run every Sunday at 00:00 UTC.
*   **Impact:** Significant minute savings by preventing redundant benchmarking of identical hardware/code states.

### 3. Global Efficiency & Caching
*   **Concurrency Control:** Added `concurrency` groups to all major workflows (`test.yml`, `lint.yml`, `benchmarks.yml`) with `cancel-in-progress: true` to kill outdated runs.
*   **Path Filtering:** Added `paths-ignore` for documentation (`docs/`), Markdown (`.md`), and meta-configuration files to prevent unnecessary CI triggers.
*   **Modern Setup Tools:** Migrated to `astral-sh/setup-uv@v5` for Python setup, enabling faster global caching and more reliable dependency resolution.
*   **Static Analysis:** Integrated `mypy` into `lint.yml` to catch type errors in a lightweight, independent job.

## Files Modified/Created
*   `modified` `.github/workflows/test.yml`
*   `created` `.github/workflows/benchmarks.yml`
*   `modified` `.github/workflows/lint.yml`
*   `modified` `.github/workflows/record-ci-baseline.yml`

## Next Steps
*   **Monitor Usage:** Check GitHub Actions usage logs over the next 48 hours to confirm the expected drop in minute consumption.
*   **PR Labeling:** Inform contributors to use the `run-benchmarks` label only when significant performance-related changes are made.
