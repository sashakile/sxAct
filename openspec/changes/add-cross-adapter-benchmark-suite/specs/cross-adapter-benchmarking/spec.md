## ADDED Requirements
### Requirement: Curated Cross-Adapter Benchmark Suite
The system SHALL provide a curated benchmark suite that compares supported sxAct adapters against the Wolfram xAct oracle using the existing TOML test and adapter infrastructure. Valid benchmark tags are `benchmark`, `perf:smoke`, `perf:scaling`, and `perf:stress`; only cases tagged with at least one of these tags are eligible for the curated suite.

#### Scenario: Benchmark suite runs benchmark-tagged cases by default
- **WHEN** a user runs `xact-test benchmark` without an explicit tag filter
- **THEN** the runner executes only TOML cases tagged with `benchmark`, `perf:smoke`, `perf:scaling`, or `perf:stress`
- **AND** correctness-only tests not carrying any benchmark tag are not included

#### Scenario: Explicit tag filter overrides default
- **WHEN** a user runs `xact-test benchmark` with an explicit tag filter (e.g., `--tag=perf:smoke`)
- **THEN** the runner executes only TOML cases matching the specified tag
- **AND** cases tagged with other benchmark tags but not the filter tag are excluded

#### Scenario: Skipped cases are not benchmarked
- **WHEN** a benchmark file or benchmark case has a `skip` reason
- **THEN** the benchmark runner excludes that item from measurements
- **AND** the output reports the skip without recording a timing sample for it

#### Scenario: No benchmark cases found
- **WHEN** a user runs `xact-test benchmark` and no TOML cases match the active tag filter
- **THEN** the runner exits with a "no benchmark cases found" message
- **AND** the exit code is non-zero

#### Scenario: Unavailable adapter is reported
- **WHEN** `xact-test benchmark` is run and a required adapter is unavailable
- **THEN** the runner reports which adapter is unavailable and why
- **AND** benchmark results for available adapters are still recorded

### Requirement: Setup Time Discounting
The benchmark runner SHALL exclude one-time setup costs from the primary steady-state measurement and SHALL report those setup costs separately.

#### Scenario: Adapter initialization excluded from primary timing
- **WHEN** the runner benchmarks a test case
- **THEN** adapter initialization, oracle health checks, xAct loading, and context creation occur outside the primary measured loop
- **AND** their elapsed time is reported as setup or cold-start metadata rather than included in `median_ms`

#### Scenario: File setup excluded from primary timing
- **WHEN** a benchmark file defines setup operations such as `DefManifold`, `DefMetric`, or `DefTensor`
- **THEN** those setup operations run before warmup and measurement iterations
- **AND** the primary benchmark median measures only the benchmarked test-case work

#### Scenario: First-use overhead is visible
- **WHEN** a backend has first-use overhead such as Julia JIT compilation or Wolfram package loading
- **THEN** the benchmark result includes separate cold-start or first-iteration metadata when measurable
- **AND** users can distinguish cold-start latency from steady-state performance

#### Scenario: Warmup and measurement counts meet minimums
- **WHEN** the runner executes steady-state benchmarks
- **THEN** the warmup count SHALL be at least 3 and the measurement count SHALL be at least 5
- **AND** runs configured below these minimums are flagged in output as low-confidence

### Requirement: Lightweight Measurement Mode
The benchmark infrastructure SHALL remain lightweight by default and SHALL NOT require heavyweight profilers or a new benchmark framework for normal runs. **Isolated timing mode** is a benchmark execution mode for test cases that define symbols or mutate shared state in ways that cannot safely repeat within a single prepared context; each iteration in isolated mode may include per-iteration reset cost.

#### Scenario: Steady-state benchmark uses existing harness components
- **WHEN** a user runs the standard `xact-test benchmark` command
- **THEN** the runner reuses existing TOML loading, adapter execution, and baseline JSON mechanisms
- **AND** the run completes without requiring external profilers beyond the existing Wolfram oracle and Julia/Python runtimes

#### Scenario: Stateful benchmarks are labeled
- **WHEN** a benchmark case cannot be safely repeated in a single prepared context
- **THEN** the runner either excludes it from steady-state comparison or runs it in isolated timing mode
- **AND** isolated-mode results appear in a separate `isolated` section of the output annotated with `timing_mode: isolated`, and are excluded from cross-adapter ratio calculations that use only steady-state results

### Requirement: Wolfram Baseline Comparison
The benchmark runner SHALL record Wolfram baseline results and compare current implementation results against those baselines with explicit ratios.

#### Scenario: Current adapter compared to Wolfram baseline
- **WHEN** a Julia or Python benchmark result has a matching Wolfram baseline entry
- **THEN** the comparison output includes the current median, Wolfram median, slowdown ratio, timing mode, and setup metadata
- **AND** the result is classified using configured warning and failure thresholds

#### Scenario: Missing Wolfram baseline is reported
- **WHEN** a current implementation result has no matching Wolfram baseline entry
- **THEN** the comparison output marks the baseline as missing
- **AND** the runner does not fabricate a ratio

#### Scenario: Stale Wolfram baseline entry is reported
- **WHEN** the Wolfram baseline file contains an entry whose stable test identifier does not match any case in the benchmark corpus
- **THEN** the comparison output marks the entry as orphaned
- **AND** the runner does not use the stale entry in ratio calculations

### Requirement: Benchmark Output Is Reproducible
Benchmark output SHALL include enough metadata to reproduce and interpret cross-adapter measurements. Each benchmark entry carries a stable test identifier of the form `"<relative_file_path>::<test_name>"` (e.g., `"tests/benchmarks/xcore/smoke.toml::riemann_contraction"`); renaming a file or test produces a new identifier and orphans any prior baseline entry.

#### Scenario: Result includes machine and runtime metadata
- **WHEN** the runner records benchmark results
- **THEN** the output includes machine metadata, adapter name, runtime versions where available, warmup count, measurement count, timestamp, and baseline path
- **AND** each benchmark entry includes its stable test identifier

#### Scenario: Result identifies measured scope
- **WHEN** the runner writes a benchmark result
- **THEN** each entry states whether the primary metric is steady-state, isolated, or backend-reported timing
- **AND** setup/cold-start fields are separate from primary timing fields

#### Scenario: Benchmark error identifies phase of failure
- **WHEN** an error occurs during a benchmark run
- **THEN** the error output identifies whether failure occurred during setup, warmup, measurement, or teardown
- **AND** results for phases completed before the failure are preserved in the output
