# Change: Add lightweight cross-adapter benchmark suite

## Why
The project needs a repeatable benchmark suite to compare the current Julia/Python implementation against the original Wolfram xAct implementation without conflating CAS work with one-time setup costs. Existing benchmark primitives can time TOML tests across adapters, but they do not yet provide a curated suite or explicit accounting for setup, warmup, steady-state measurements, and Wolfram-vs-current ratios.

## What Changes
- Add a curated cross-adapter benchmark suite focused on xCore, xPerm, xTensor canonicalization, and representative physics workloads.
- Keep the infrastructure lightweight by reusing the existing TOML test format, adapters, and `xact-test benchmark` command instead of introducing a new benchmark framework.
- Measure setup separately from steady-state work: adapter initialization, oracle health checks, xAct loading, and file setup SHALL be excluded from primary medians and reported as setup/cold-start metadata.
- Add comparison output that records Wolfram baselines and current implementation results with explicit slowdown ratios.
- Ensure benchmark discovery respects benchmark tags and skips slow/unsupported correctness-only tests.

## Impact
- Affected specs: `cross-adapter-benchmarking`
- Affected code: `packages/sxact/src/sxact/benchmarks/runner.py`, `packages/sxact/src/sxact/cli/__init__.py`, benchmark TOML files under `tests/benchmarks/` or benchmark-tagged subsets of `tests/`
- Affected data: benchmark baseline JSON files under `benchmarks/`
- Non-goals: full profiling framework, mandatory memory profiler, or CI execution of the full Wolfram benchmark suite
