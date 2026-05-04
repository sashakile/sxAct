# Design: Lightweight cross-adapter benchmarking

## Terminology

The word "setup" appears in three distinct contexts. To avoid ambiguity:

- **Adapter setup** (`adapter_setup_ms`): one-time adapter initialization, oracle health checks, and xAct loading.
- **File setup** (`file_setup_ms`): TOML file-level operations such as `DefManifold`, `DefMetric`, or `DefTensor` that run before the timed loop.
- **Cold-start / JIT overhead** (`first_iteration_ms`, `jit_overhead_ms`): first-use latency from Julia JIT compilation or Wolfram package loading.

All three are excluded from `median_ms` and reported as separate metadata fields.

## Context
The repository already has a TOML test corpus, adapter abstraction, Wolfram oracle, and `sxact.benchmarks.runner`. The main design challenge is avoiding misleading numbers: Wolfram kernel startup, Julia JIT, xAct package loading, oracle HTTP health checks, and test-file setup can dominate short symbolic operations.

## Goals
- Reuse existing harness components wherever possible.
- Make the primary metric a steady-state measurement that excludes one-time setup.
- Still report setup/cold-start costs so users can understand end-to-end latency.
- Support Wolfram-vs-Julia/Python ratios from baseline JSON.
- Keep local full-suite benchmarking possible while keeping CI lightweight.

## Non-Goals
- Introduce a new external benchmark framework.
- Require heavyweight profilers for normal benchmark runs.
- Make Wolfram-licensed benchmark execution mandatory in CI.
- Rewrite existing correctness tests into a new schema.

## Decisions

### Decision: Reuse TOML tests and adapter actions
Benchmark cases remain TOML test cases executed through existing adapters. A curated benchmark suite uses tags such as `benchmark`, `perf:smoke`, `perf:scaling`, and `perf:stress` to avoid timing correctness-only cases by accident.

### Decision: Primary metric excludes setup
The runner performs adapter initialization and file-level setup before the measured loop. The primary timing window covers repeated test-case execution after warmup. The output records separate setup fields such as `adapter_setup_ms`, `file_setup_ms`, and optional `first_iteration_ms`/`jit_overhead_ms` where available.

### Decision: Mark non-reusable cases instead of cloning heavy isolation by default
Some test cases define symbols or mutate state in ways that cannot safely repeat in a single context. The lightweight default excludes or skips those cases unless they are explicitly marked as isolated benchmarks. Isolated benchmarks may include per-iteration reset cost and MUST label that timing mode in output so it is not compared to steady-state measurements as if equivalent.

### Decision: Optional kernel timing, not mandatory
If an adapter already reports backend timing diagnostics (for example, Wolfram oracle timing), the benchmark result may include backend timing fields. The primary implementation does not require per-CAS profilers, but it keeps room for future `kernel_median_ms` fields.

### Decision: Separate local full suite from CI smoke suite
The full Wolfram comparison is a local/manual workflow because Wolfram licensing is not assumed in CI. CI can run a small Julia-only smoke benchmark without requiring the oracle. A baseline schema validation step is out of scope for this change.

### Decision: First curated suite scope
The first curated suite covers `perf:smoke` and a small `perf:scaling` set:
- At least one xCore tensor operation (e.g., basic tensor definition and index contraction).
- At least one xPerm permutation canonicalization case.
- At least one xTensor Riemann/Einstein reduction.
- Two to five `perf:scaling` cases from existing Butler/xTensor workloads without embedded `Timing` wrappers.

Rationale: smoke alone provides too little signal for JOSS performance claims; a combined smoke+small-scaling set gives coverage without requiring a Wolfram license in routine development.

### Decision: Baseline file structure
Use a single multi-adapter baseline file at `benchmarks/baseline.json`. Keys are structured as `"<adapter_name>::<relative_file_path>::<test_name>"` (e.g., `"wolfram::tests/benchmarks/xcore/smoke.toml::riemann_contraction"`). All adapter results live in one file, making cross-adapter ratio computation a single-parse operation. If adapters require incompatible schema fields, each entry uses an adapter-keyed sub-object with a shared `stable_id` field.

Rationale: a single file is simpler to diff, version, and compare across adapters; split files require joining two files to compute ratios and can diverge structurally.

## Risks / Trade-offs
- Repeating test cases in the same context can hide stateful pollution. Mitigation: only include reusable cases in steady-state benchmarks and label isolated mode distinctly.
- Excluding setup from primary metrics may understate first-use latency. Mitigation: record setup/cold-start metadata beside steady-state medians.
- Existing TOML tests may include Wolfram `Timing`/`AbsoluteTiming` expressions. Mitigation: curated benchmark cases time the underlying operation, not expressions that return embedded timing values.

