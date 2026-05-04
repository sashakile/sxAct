## 1. Benchmark Semantics
- [ ] 1.1 Add tests for benchmark timing that prove adapter initialization and file setup are excluded from primary measured iterations.
- [ ] 1.2 Add tests for setup/cold-start metadata fields in benchmark results.
- [ ] 1.3 Add tests that benchmark discovery respects file-level and test-level `skip` fields.
- [ ] 1.4 Add tests for tag filtering of `benchmark`, `perf:smoke`, `perf:scaling`, and `perf:stress` cases.

## 2. Runner Implementation
- [ ] 2.1 Extend `BenchResult` with setup/cold-start metadata and timing mode.
- [ ] 2.2 Update `bench_test_case` so primary median timing excludes adapter initialization, oracle health checks, xAct loading, and file setup.
- [ ] 2.3 Support a lightweight steady-state mode for reusable cases and a clearly labeled isolated mode for stateful cases.
- [ ] 2.4 Ensure benchmark errors identify whether failure occurred during setup, warmup, measurement, or teardown.

## 3. CLI and Output
- [ ] 3.1 Update `xact-test benchmark` to skip meta-skipped files and test-skipped cases.
- [ ] 3.2 Add JSON comparison output containing Wolfram baseline, current adapter result, ratio, setup metadata, and timing mode.
- [ ] 3.3 Add `docs/benchmarking.md` with step-by-step local workflow for recording Wolfram baselines and comparing Julia/Python adapter results, including the commands to update `benchmarks/baseline.json`.

## 4. Curated Suite
- [ ] 4.1 Create a small `perf:smoke` suite covering xCore, xPerm, and xTensor operations.
- [ ] 4.2 Create representative `perf:scaling` or `perf:stress` cases from existing Butler/xTensor workloads without embedded Wolfram `Timing` wrappers.
- [ ] 4.3 Mark stateful or non-repeatable benchmarks as isolated or exclude them from steady-state comparisons.

## 5. Validation
- [ ] 5.1 Run Python unit tests for benchmark runner and CLI behavior.
- [ ] 5.2 Run a Julia-adapter smoke benchmark without Wolfram.
- [ ] 5.3 When a Wolfram oracle is available, record a Wolfram baseline and run a Julia-vs-Wolfram comparison.
- [ ] 5.4 Validate OpenSpec with `openspec validate add-cross-adapter-benchmark-suite --strict`.
