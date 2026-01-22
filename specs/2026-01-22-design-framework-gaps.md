# Design Framework Gaps: Problem Definition & Tactical Design

**Date:** 2026-01-22
**Version:** 1.0
**Status:** Draft
**Related:** [2026-01-08-test-framework-design.md](./2026-01-08-test-framework-design.md), [2026-01-09-three-layer-testing-architecture.md](./2026-01-09-three-layer-testing-architecture.md)
**Issue:** sxAct-y9d

## Purpose

This document strengthens the existing specs by adding missing design phases:
- **Phase 1-2**: Problem statement and root cause analysis
- **Phase 3**: Explicit scope boundaries
- **Phase 4**: Alternatives considered for key decisions
- **Phase 5**: Tactical design details (actions, adapters, comparators, isolation)
- **Phase 6**: Risk-ordered implementation roadmap

---

## Phase 1: Problem Description (Symptoms)

### Observed Symptoms

| Symptom | Where/When Observed |
|---------|---------------------|
| No repeatable regression harness | Manual notebook inspection is current validation |
| Subtle symbolic mismatches | Dummy index renaming differs across implementations |
| Test order dependence | CAS definitions accumulate (manifolds, metrics, symmetries) |
| Misleading performance comparisons | Julia JIT, environment variance, warm vs cold runs |
| String comparison failures | Canonicalization conventions differ |
| Oracle reproducibility issues | xAct/Mathematica version, simplification settings |

### Concrete Failure Modes Expected During Migration

1. **Dummy index instability**: `T[-a, -b]` vs `T[-$1, -$2]` vs `T[-i, -j]`
2. **Term ordering**: `A + B` vs `B + A` in commutative expressions
3. **Canonicalization conventions**: Different "canonical" forms across implementations
4. **Simplification depth**: One impl simplifies further than another
5. **Symmetry representation**: `Symmetric[{-a, -b}]` vs internal bitmap
6. **Wrapper conversion bugs**: Python↔Julia data type mismatches
7. **Stateful pollution**: Previous test's definitions leak into current test
8. **Numeric precision**: Float comparisons across language boundaries

### Signal Sources

- xAct documentation notebooks (known-good examples)
- xAct mailing list (reported edge cases)
- Prior SymPy/SymEngine migration experiences
- Julia/Python interop known issues (PyJulia, PythonCall.jl)

---

## Phase 2: Root Cause Diagnosis

### Root Cause → Design Consequence Table

| Root Cause | Mechanism | Design Consequence |
|------------|-----------|-------------------|
| **No shared IR** | Each language has its own tensor expression AST | Need canonical string form + properties dict, or future AST/IR |
| **Symbolic ≠ textual equality** | Dummy indices, term order, simplification vary | Three-tier comparison: normalized → symbolic diff=0 → numeric |
| **CAS statefulness** | Definitions persist in session (manifolds, tensors, metrics) | Test isolation strategy: fresh context per test/file |
| **Oracle version dependence** | xAct behavior changes across versions | Pin versions, normalize output before hashing |
| **Performance is multi-dimensional** | JIT, caching, warm/cold, memory | Separate metrics, explicit benchmark protocol |
| **Wolfram licensing** | Can't run oracle in CI without license | Snapshot strategy: store oracle outputs as golden files |

### Problem Statement

**Current behavior:** Validation relies on manual notebook inspection with no automated cross-implementation comparison.

**Mechanism:** Symbolic algebra systems produce semantically equivalent but textually different outputs. Without a defined equivalence relation and isolation strategy, automated testing produces false negatives (correct code fails tests) or false positives (bugs pass due to lucky string matches).

**Evidence:**
- xAct's `ToCanonical` produces different dummy index names than naive implementations
- SymPy migration projects report 20-40% false negative rate with string comparison
- Julia JIT makes first-run 10-100x slower than steady-state

**Ruled out:**
- Simple string comparison: fails due to dummy indices and term ordering
- Always-live oracle: infeasible due to licensing and CI constraints
- Shared test state: causes order-dependent failures

---

## Phase 3: Scope Boundaries

### In Scope

- **Packages**: xCore, xPerm, xTensor (core trio)
- **Languages**: Wolfram (oracle), Julia (primary), Python (wrapper)
- **Test types**: Unit (Layer 1), Property (Layer 2), Performance (Layer 3)
- **Format**: TOML specifications with JSON Schema validation
- **Extraction**: Regression tests from documentation notebooks

### Out of Scope (Non-Goals)

| Non-Goal | Rationale |
|----------|-----------|
| Pretty-printing / formatting | Display is language-specific; test mathematical content only |
| Notebook UI behavior | Testing computation, not interactive features |
| Packages beyond core trio | xCoba, xPert, etc. deferred to future phases |
| Internal simplification steps | Test final results, not intermediate transformations |
| Exact internal representation | Test observable behavior via defined API |
| Full formal verification | Property tests are executable specs, not proofs |

### Oracle Policy

**Ground truth vs math laws**: When Wolfram xAct output conflicts with mathematical law:

1. **Default**: xAct is ground truth (migration goal is equivalence)
2. **Override**: `oracle_is_axiom = false` flag allows property to override oracle
3. **Document**: All known xAct quirks cataloged in `docs/oracle-quirks.md`

### Environment Constraints

| Constraint | Policy |
|------------|--------|
| Wolfram licensing | Oracle runs locally; CI uses golden file snapshots |
| xAct version | Pin to 1.2.0 (latest stable); document in `oracle/VERSION` |
| Mathematica version | Pin to 14.0+; required for wolframclient compatibility |
| Julia version | 1.10+ (LTS) or 1.11+ |
| Python version | 3.10+ (tomllib in 3.11+, tomli fallback for 3.10) |
| CI environment | GitHub Actions; oracle tests marked `@oracle` skip in CI |

---

## Phase 4: Direction (Alternatives Considered)

### Decision 1: Equivalence Strategy

| Criterion | String Comparison | AST/IR Comparison | Semantic (diff=0) | Numeric Sampling |
|-----------|-------------------|-------------------|-------------------|------------------|
| Implementation cost | Low | High | Medium | Low |
| Accuracy | Poor (false negatives) | High | High | Medium (misses symbolic) |
| Speed | Fast | Medium | Slow | Fast |
| Cross-language | Easy | Hard (needs shared IR) | Medium | Easy |
| Handles dummy indices | No | Yes | Yes | N/A |

**Decision**: Three-tier hybrid
1. **Tier 1**: Normalized string comparison (fast path, catches 70% of cases)
2. **Tier 2**: Semantic check via `Simplify(lhs - rhs) == 0` (oracle or target)
3. **Tier 3**: Numeric sampling fallback (when symbolic fails)

**Trade-off accepted**: Tier 2-3 are slower but necessary for correctness.

### Decision 2: Oracle Strategy

| Criterion | Live Execution | Golden File Snapshots | Hybrid |
|-----------|----------------|----------------------|--------|
| Reproducibility | Low (version drift) | High | High |
| CI compatibility | No (licensing) | Yes | Yes |
| Freshness | Always current | May be stale | Configurable |
| Storage cost | None | Medium (oracle outputs) | Medium |
| Regeneration | N/A | Manual workflow | Automated with review |

**Decision**: Hybrid (golden files for CI, live for local development)
- Store normalized oracle outputs in `oracle/` directory
- `bd regen-oracle` command regenerates from live Wolfram
- CI compares against snapshots; local can run live with `--live-oracle`

**Trade-off accepted**: Snapshot staleness requires periodic regeneration.

### Decision 3: Test Isolation Strategy

| Criterion | Per-Test Fresh | Per-File Fresh | Shared Session |
|-----------|----------------|----------------|----------------|
| Isolation | Perfect | Good | Poor |
| Speed | Slow (kernel startup) | Medium | Fast |
| Debugging | Easy | Medium | Hard (state pollution) |
| Dependencies | Cannot use | Can use within file | Can use anywhere |

**Decision**: Per-file fresh context with explicit teardown
- Each TOML file gets a fresh kernel/module
- `[[setup]]` runs once per file
- `[[tests]]` share setup but not each other's `store_as` bindings
- `dependencies` only valid within same file

**Trade-off accepted**: Cross-file dependencies not supported (use integration tests).

### Decision 4: Representation Strategy

| Criterion | String Only | String + Properties | Full AST/IR |
|-----------|-------------|---------------------|-------------|
| Implementation cost | Low | Medium | High |
| Expressiveness | Low | Medium | High |
| Cross-language | Easy | Easy | Hard |
| Future-proof | No | Somewhat | Yes |

**Decision**: String + Properties (current approach)
- `expression`: canonical string form
- `properties`: structured dict (rank, symmetry, manifold, etc.)
- Escape hatch: `raw_ast` field for future IR migration

**Trigger for escalation**: >10% of tests fail due to comparison ambiguity → invest in shared IR.

---

## Phase 5: Tactical Design

### 5.1 Action Vocabulary

Canonical list of test operations with required/optional arguments:

```toml
# Action: DefManifold
# Creates a manifold definition
[action.DefManifold]
required = ["name", "dimension", "indices"]
optional = ["metric_signature"]
returns = "ManifoldHandle"
example = { name = "M", dimension = 4, indices = ["a", "b", "c", "d"] }

# Action: DefMetric
# Defines a metric tensor on a manifold
[action.DefMetric]
required = ["signdet", "metric", "covd"]
optional = ["symbols", "manifold"]
returns = "MetricHandle"
example = { signdet = -1, metric = "g[-a,-b]", covd = "CD", symbols = [";", "∇"] }

# Action: DefTensor
# Defines a tensor with optional symmetry
[action.DefTensor]
required = ["name", "indices"]
optional = ["manifold", "symmetry", "weight", "components"]
returns = "TensorHandle"
example = { name = "T", indices = ["-a", "-b"], symmetry = "Symmetric[{-a, -b}]" }

# Action: Evaluate
# Evaluates an expression in current context
[action.Evaluate]
required = ["expression"]
optional = []
returns = "ExprResult"
example = { expression = "T[-a, -b] + T[-b, -a]" }

# Action: ToCanonical
# Canonicalizes an expression
[action.ToCanonical]
required = ["expression"]
optional = ["method"]
returns = "ExprResult"
example = { expression = "RiemannCD[-a,-b,-c,-d] + RiemannCD[-b,-a,-c,-d]" }

# Action: Simplify
# Simplifies an expression
[action.Simplify]
required = ["expression"]
optional = ["assumptions", "depth"]
returns = "ExprResult"
example = { expression = "g[-a,-b] g[a,c]" }

# Action: Contract
# Contracts indices in expression
[action.Contract]
required = ["expression"]
optional = []
returns = "ExprResult"
example = { expression = "T[-a, -b] S[a]" }

# Action: Assert
# Validates a condition
[action.Assert]
required = ["condition"]
optional = ["message"]
returns = "bool"
example = { condition = "$result == 0", message = "Expected zero" }
```

### 5.2 Adapter Interface

Each implementation provides an adapter conforming to this interface:

```
interface TestAdapter:
    # Lifecycle
    initialize() -> Context
    teardown(ctx: Context) -> void
    
    # Execution
    execute(ctx: Context, action: str, args: dict) -> Result
    
    # Comparison
    normalize(expr: str) -> NormalizedExpr
    equals(a: NormalizedExpr, b: NormalizedExpr, mode: EqualityMode) -> bool
    
    # Introspection
    get_properties(expr: str) -> dict
    get_version() -> VersionInfo
```

**Result envelope**:
```json
{
  "status": "ok" | "error" | "timeout",
  "type": "Expr" | "Scalar" | "Bool" | "Handle",
  "repr": "T[-a, -b]",
  "normalized": "T[-$1, -$2]",
  "properties": {
    "rank": 2,
    "symmetry": {"type": "Symmetric", "slots": [0, 1]},
    "manifold": "M"
  },
  "diagnostics": {
    "execution_time_ms": 45,
    "memory_mb": 12
  },
  "error": null
}
```

### 5.3 Comparator Module

**Normalization pipeline**:

1. **Whitespace normalization**: Strip, collapse spaces
2. **Index canonicalization**: Rename dummies to `$1, $2, ...` in order of appearance
3. **Term ordering**: Sort commutative terms lexicographically
4. **Coefficient normalization**: `2*x` → `2 x`, `-1*x` → `-x`

**Three-tier comparison**:

```python
def compare(lhs: ExprResult, rhs: ExprResult, ctx: Context) -> CompareResult:
    # Tier 1: Fast normalized string comparison
    if lhs.normalized == rhs.normalized:
        return CompareResult(equal=True, tier=1)
    
    # Tier 2: Semantic check (difference simplifies to zero)
    diff = ctx.execute("Simplify", {"expression": f"({lhs.repr}) - ({rhs.repr})"})
    if diff.normalized in ["0", "0."]:
        return CompareResult(equal=True, tier=2)
    
    # Tier 3: Numeric sampling (if expressions contain free indices)
    if has_free_indices(lhs) or has_free_indices(rhs):
        samples = sample_numeric(lhs, rhs, n=10, seed=ctx.seed)
        if all(abs(s.lhs - s.rhs) < ctx.tolerance for s in samples):
            return CompareResult(equal=True, tier=3, confidence=0.99)
    
    return CompareResult(equal=False, tier=3, diff=diff)
```

### 5.4 Test Isolation Semantics

**State machine**:

```
┌─────────────────────────────────────────────────────────────┐
│                     PER-FILE EXECUTION                       │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐  │
│  │  INIT   │───▶│  SETUP  │───▶│  TESTS  │───▶│TEARDOWN │  │
│  └─────────┘    └─────────┘    └─────────┘    └─────────┘  │
│       │              │              │              │        │
│  Fresh ctx     Run [[setup]]   For each [[tests]]: Cleanup │
│                Store handles   - Run operations            │
│                                - Compare expected          │
│                                - Record metrics            │
└─────────────────────────────────────────────────────────────┘
```

**Binding scope**:
- `[[setup]].store_as` → available to all tests in file
- `[[tests.operations]].store_as` → available only within that test
- Cross-test references require explicit `dependencies` (topologically sorted)

**Isolation enforcement**:
- Wolfram: Fresh kernel per file (`kernel.restart()`)
- Julia: Fresh module per file (`Module.new()`)
- Python: Fresh Julia session per file (PyJulia reinit)

### 5.5 Benchmark Protocol

**Methodology**:

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Warm-up runs | 3 | Ensure JIT compilation complete |
| Measurement runs | 10 | Statistical significance |
| Statistic | Median | Robust to outliers |
| Variance metric | IQR | Robust percentile-based spread |
| JIT separation | First run excluded | Report separately as `jit_overhead_ms` |
| Memory measurement | Peak RSS | Via `/proc` on Linux, `psutil` cross-platform |

**Threshold policy**:

| Metric | Warning | Error |
|--------|---------|-------|
| vs previous run | >20% slower | >50% slower |
| Julia vs Wolfram | >5x slower | >10x slower |
| Python vs Wolfram | >10x slower | >50x slower |
| Memory vs Wolfram | >3x higher | >10x higher |

**Baseline drift**:
- Store baselines in `benchmarks/baseline.json`
- `bd update-baseline` command updates after review
- CI fails on regression; requires explicit baseline update to pass

### 5.6 Oracle Snapshot Format

**Directory structure**:
```
oracle/
├── VERSION                    # "xAct 1.2.0, Mathematica 14.0"
├── config.toml               # Normalization settings
├── core/
│   ├── manifolds/
│   │   ├── tensor_basic_001.json
│   │   └── tensor_basic_001.wl   # Raw Wolfram output
│   └── ...
└── checksums.sha256          # Integrity verification
```

**Snapshot JSON format**:
```json
{
  "test_id": "tensor_basic_001",
  "oracle_version": "xAct 1.2.0",
  "mathematica_version": "14.0.0",
  "timestamp": "2026-01-22T10:30:00Z",
  "commands": "DefManifold[M, 4, {a,b,c,d}]\nDefTensor[T[-a,-b], M]",
  "raw_output": "T[-a, -b]",
  "normalized_output": "T[-$1, -$2]",
  "properties": {
    "type": "Tensor",
    "rank": 2,
    "manifold": "M"
  },
  "hash": "sha256:abc123..."
}
```

**Hash computation**:
```python
def compute_oracle_hash(snapshot: dict) -> str:
    canonical = json.dumps({
        "normalized_output": snapshot["normalized_output"],
        "properties": snapshot["properties"]
    }, sort_keys=True)
    return f"sha256:{hashlib.sha256(canonical.encode()).hexdigest()[:12]}"
```

---

## Phase 6: Risk-Ordered Implementation Roadmap

Reordered to attack biggest unknowns first:

### Sprint 1: De-risk Equivalence (Week 1-2)

**Goal**: Prove the comparison strategy works before scaling.

1. **Wolfram oracle runner** (3 days)
   - wolframclient integration
   - Execute single test, capture output
   - Basic error handling

2. **Normalization pipeline** (2 days)
   - Whitespace normalization
   - Dummy index renaming (`$1, $2, ...`)
   - Term ordering for commutative ops

3. **Three-tier comparator** (3 days)
   - Tier 1: Normalized string equality
   - Tier 2: Symbolic diff=0 check
   - Tier 3: Numeric sampling fallback

4. **Validation**: Run 5-10 hand-written tests through full pipeline

**Exit criteria**: Comparator correctly handles dummy index variation, term reordering.

### Sprint 2: Harness Foundation (Week 3-4)

**Goal**: Functional test runner for all three layers.

5. **TOML loader + JSON Schema validation** (2 days)
6. **Adapter interface** (3 days)
   - WolframAdapter (wraps oracle runner)
   - JuliaAdapter (stub, returns "not implemented")
   - PythonAdapter (stub)

7. **Test isolation** (2 days)
   - Per-file kernel management
   - Setup/teardown lifecycle

8. **CLI runner** (3 days)
   - `xact-test run tests/` 
   - `xact-test run --filter tag:critical`
   - JSON/terminal output

**Exit criteria**: Can run TOML test files against Wolfram oracle with proper isolation.

### Sprint 3: Oracle Snapshots (Week 5-6)

**Goal**: Enable CI without Wolfram license.

9. **Snapshot generation** (2 days)
   - `xact-test snapshot tests/ --output oracle/`
   - Normalized JSON format

10. **Snapshot comparison mode** (2 days)
    - `xact-test run --oracle-mode=snapshot`
    - Hash verification

11. **Regeneration workflow** (1 day)
    - `xact-test regen-oracle --diff`
    - Review gate for changed snapshots

**Exit criteria**: CI can run full test suite against snapshots.

### Sprint 4: Test Extraction (Week 7-8)

**Goal**: Populate test suite from xAct documentation.

12. **Notebook parser** (3 days)
    - Extract input/output cells
    - Identify test-worthy patterns

13. **TOML generator** (2 days)
    - Convert notebook cells to TOML format
    - Auto-tag by source notebook

14. **Manual curation** (3 days)
    - Review generated tests
    - Add tags, difficulty, expected metrics
    - Organize by category

**Exit criteria**: 50-100 Layer 1 tests extracted and passing.

### Sprint 5: Property Testing (Week 9-10)

**Goal**: Layer 2 property-based testing framework.

15. **Random tensor generator** (3 days)
16. **Property specification loader** (2 days)
17. **Cross-implementation validation** (3 days)
18. **10-15 core property tests** (2 days)

**Exit criteria**: Property tests run against Wolfram, catch known edge cases.

### Sprint 6: Performance & Polish (Week 11-12)

**Goal**: Layer 3 and production readiness.

19. **Benchmark harness** (3 days)
20. **Baseline management** (2 days)
21. **HTML reporting dashboard** (2 days)
22. **Documentation** (3 days)

**Exit criteria**: Full three-layer framework operational with reporting.

---

## Appendix: JSON Schema for Test Format

See `tests/schema/test-schema.json` (to be created based on Section 5.1).

---

## Appendix: Known xAct Quirks

To be documented in `docs/oracle-quirks.md` as discovered:

| ID | Quirk | Workaround |
|----|-------|------------|
| Q1 | TBD | TBD |

---

## Changelog

- 2026-01-22: Initial draft addressing design framework gaps (sxAct-y9d)
