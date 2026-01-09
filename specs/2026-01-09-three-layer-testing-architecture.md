# Three-Layer Testing Architecture for xAct Migration

**Date:** 2026-01-09
**Version:** 1.0
**Status:** Research Document
**Related:** [2026-01-08-test-framework-design.md](./2026-01-08-test-framework-design.md)

## Executive Summary

This document refines the xAct test framework design to support **two distinct goals**:

1. **Migration Goal**: Validate functional equivalence and performance when porting xAct (Wolfram) → Python/Julia
2. **Research Goal**: Explore language-agnostic mathematical property specifications that can be reused across implementations

The framework uses **three testing layers** that serve both goals synergistically:
- **Layer 1**: Unit tests (concrete examples, oracle validation)
- **Layer 2**: Property-based tests (mathematical invariants, reusable specifications) ⭐ Research contribution
- **Layer 3**: Performance regression tests (usability tracking)

**Key Insight**: Mutation testing is **not required** - it validates code coverage, not mathematical functionality.

---

## Dual-Purpose Framework Goals

### 🎯 Goal 1: Migration Validation (xAct → Python/Julia)

**Objective**: Ensure migrated implementations are:
- Mathematically correct (same results as Wolfram xAct)
- Performant enough for practical use
- Complete (all core functionality ported)

**Test Strategy**:
- Oracle-based regression testing
- Performance comparison against Wolfram baseline
- Extracted test cases from xAct documentation notebooks

### 🎯 Goal 2: Mathematical Property Specification Research

**Objective**: Create reusable, language-agnostic specifications of tensor algebra that:
- Describe mathematical laws independent of implementation
- Can validate any language's tensor library (Python, Julia, Rust, C++, Haskell...)
- Serve as executable documentation
- Enable formal verification approaches

**Test Strategy**:
- Property-based testing with random generation
- Abstract mathematical invariants
- Cross-language validation

---

## Three-Layer Testing Architecture

### Layer 1: Unit Tests (Gold Standard Cases)

**Purpose**: Concrete examples with known inputs/outputs for debugging and validation.

**Characteristics**:
- Fixed inputs with exact expected outputs
- Easy to debug when they fail
- Fast execution (subsecond)
- Oracle (Wolfram xAct) provides ground truth
- Extracted from documentation notebooks

**Example**:

```toml
# tests/unit/tensor_contraction_examples.toml
version = "1.0"
layer = "unit"
description = "Concrete tensor contraction examples"

[[tests]]
id = "contraction_known_001"
name = "Simple Einstein summation with numeric values"
tags = ["unit", "contraction", "basic"]

[[tests.operations]]
action = "DefTensor"
[tests.operations.args]
name = "T"
indices = ["a", "-a"]
components = [[1, 2], [3, 4]]  # Explicit 2x2 matrix

[[tests.operations]]
action = "Contract"
expression = "T[a, -a]"
store_as = "result"

[tests.expected]
expression = "5"  # Trace: 1 + 4 = 5
type = "exact_numeric"
tolerance = 1e-15

[tests.oracle]
commands = """
DefManifold[M, 2, {a, b}]
DefTensor[T[a, -a], M]
T[1, 1] = 1; T[1, 2] = 2; T[2, 1] = 3; T[2, 2] = 4;
Contract[T[a, -a]]
"""
```

**Migration Support** (Goal 1):
- Validates specific calculations match Wolfram
- Debugging entry point when property tests fail
- Regression prevention during refactoring

**Research Support** (Goal 2):
- Provides documentation examples
- Concrete instances of abstract properties
- Test case generation validation

---

### Layer 2: Property-Based Tests (Mathematical Laws) ⭐

**Purpose**: Encode mathematical invariants as executable, language-agnostic specifications.

**This is the primary research contribution.**

**Characteristics**:
- Randomly generated test inputs
- Describes mathematical laws (associativity, commutativity, distributivity, etc.)
- Implementation-independent
- Runs against all implementations (Wolfram, Python, Julia)
- Explores edge cases automatically

**Example**:

```toml
# tests/properties/tensor_algebra_laws.toml
version = "1.0"
layer = "property"
description = "Fundamental tensor algebra mathematical properties"

[[properties]]
id = "prop_contraction_associative"
name = "Tensor contraction is associative"
tags = ["property", "contraction", "associativity", "critical"]
difficulty = "medium"

[properties.mathematical_basis]
law_name = "Associativity of Einstein summation"
reference = "Wald, General Relativity (1984), Appendix B"
statement = """
For tensors T^{abc}, S_{cd}, U^{de}, the contraction order does not matter:
  (T^{abc} S_{cd}) U^{de} = T^{abc} (S_{cd} U^{de})
"""

[properties.forall]
description = "For any compatible tensors T, S, U"

[[properties.forall.generators]]
name = "T"
type = "Tensor"
rank = 3
indices = ["a", "b", "-c"]
shape = "$manifold_dim"
distribution = "uniform"
range = [-10.0, 10.0]

[[properties.forall.generators]]
name = "S"
type = "Tensor"
rank = 2
indices = ["c", "-d"]
shape = "$manifold_dim"
distribution = "uniform"
range = [-10.0, 10.0]

[[properties.forall.generators]]
name = "U"
type = "Tensor"
rank = 2
indices = ["d", "-e"]
shape = "$manifold_dim"
distribution = "uniform"
range = [-10.0, 10.0]

[properties.forall.constraints]
# Ensure indices are compatible for contraction
compatible_indices = [
  ["T.indices[2]", "S.indices[0]"],  # -c and c
  ["S.indices[1]", "U.indices[0]"]   # -d and d
]

[properties.law]
lhs = "Contract(Contract(T[a, b, -c], S[c, -d]), U[d, -e])"
rhs = "Contract(T[a, b, -c], Contract(S[c, -d], U[d, -e]))"
equivalence_type = "numerical_tolerance"

[properties.verification]
num_samples = 100
random_seed = 42
tolerance = 1e-12
parallel = true

[properties.oracle]
verify_oracle = true
description = "Verify Wolfram xAct also satisfies this property"
```

**Advanced Property Example**: Riemann Tensor Symmetries

```toml
[[properties]]
id = "prop_riemann_symmetries"
name = "Riemann tensor symmetry properties"
tags = ["property", "riemann", "symmetry", "critical", "GR"]

[properties.mathematical_basis]
law_name = "Riemann tensor symmetries"
reference = "Wald GR (1984), Section 3.2, Eq. 3.2.14-16"
statement = """
The Riemann curvature tensor R_{abcd} satisfies:
1. R_{abcd} = -R_{bacd}        (antisymmetric in first pair)
2. R_{abcd} = -R_{abdc}        (antisymmetric in second pair)
3. R_{abcd} = R_{cdab}         (symmetric under pair exchange)
4. R_{abcd} + R_{acdb} + R_{adbc} = 0  (First Bianchi identity)
"""

[properties.forall]
[[properties.forall.generators]]
name = "metric"
type = "Metric"
signature = "Lorentzian"
dimension = 4

[[properties.forall.generators]]
name = "Riemann"
type = "RiemannTensor"
from_metric = "$metric"
compute_method = "via_christoffel"

[properties.laws]
# All four symmetries must hold simultaneously
[[properties.laws.assertions]]
name = "antisymmetric_first_pair"
expression = "Riemann[-a, -b, -c, -d] == -Riemann[-b, -a, -c, -d]"

[[properties.laws.assertions]]
name = "antisymmetric_second_pair"
expression = "Riemann[-a, -b, -c, -d] == -Riemann[-a, -b, -d, -c]"

[[properties.laws.assertions]]
name = "symmetric_pair_exchange"
expression = "Riemann[-a, -b, -c, -d] == Riemann[-c, -d, -a, -b]"

[[properties.laws.assertions]]
name = "first_bianchi_identity"
expression = """
Riemann[-a, -b, -c, -d] +
Riemann[-a, -c, -d, -b] +
Riemann[-a, -d, -b, -c] == 0
"""

[properties.verification]
num_samples = 50
tolerance = 1e-10
```

**Key Innovation: Language-Agnostic Specification**

These properties describe:
1. **What types** of mathematical objects are involved (tensors, metrics, etc.)
2. **What invariants** must hold (laws, identities)
3. **How to generate** test cases (random generation parameters)
4. **What equivalence means** (numerical tolerance, symbolic equality, etc.)

**Any language implementing tensor algebra should satisfy these properties**, making them reusable across:
- Python (NumPy, SymPy, PyTensor)
- Julia (TensorOperations.jl, AbstractTensors.jl)
- Rust (ndarray, tensor-rs)
- C++ (Eigen, TensorFlow)
- Haskell (hmatrix, accelerate)

**Migration Support** (Goal 1):
- If Python violates associativity but Wolfram doesn't → migration bug
- Catches subtle semantic differences between implementations
- Validates mathematical correctness beyond specific examples

**Research Support** (Goal 2):
- **Primary contribution**: Reusable mathematical specifications
- Formal property catalog for tensor algebra
- Foundation for formal verification
- Could evolve into domain-specific specification language

---

### Layer 3: Performance Regression Tests

**Purpose**: Ensure implementations are usable through performance tracking and regression prevention.

**Characteristics**:
- Tracks execution time, memory, compilation overhead
- Compares against Wolfram baseline (usability threshold)
- Compares against previous versions (regression detection)
- Scaling analysis (problem size vs. performance)

**Example**:

```toml
# tests/performance/regression_benchmarks.toml
version = "1.0"
layer = "performance"
description = "Performance regression and usability benchmarks"

[[benchmarks]]
id = "perf_canonicalization_scaling"
name = "ToCanonical scaling with term count"
tags = ["performance", "canonicalization", "scaling"]

[benchmarks.parameters]
num_terms = [10, 50, 100, 500, 1000, 5000]
term_complexity = "riemann_contractions"
expression_template = "sum_of_riemann_products"

[benchmarks.baseline]
implementation = "wolfram"
version = "14.3.0"
data_file = "baselines/canonicalization_baseline.json"
generated_date = "2026-01-08"

[benchmarks.regression_criteria]
# Fail if performance degrades >20% from last version
max_slowdown_factor = 1.2
comparison = "vs_previous_version"

# Warn if >5x slower than Wolfram (usability threshold)
warning_threshold_vs_oracle = 5.0

# Error if >50x slower than Wolfram (unusable)
error_threshold_vs_oracle = 50.0

[benchmarks.metrics]
primary = "median_execution_time_ms"
track = [
  "p95_execution_time_ms",
  "peak_memory_mb",
  "compilation_overhead_ms",
  "num_terms_before",
  "num_terms_after",
  "simplification_ratio"
]

[benchmarks.reporting]
plot_type = "scaling_curve"
x_axis = "num_terms"
y_axis = "median_execution_time_ms"
regression_model = "polynomial_degree_2"
save_plot = "reports/canonicalization_scaling.png"

[benchmarks.warmup]
iterations = 5
description = "JIT compilation and cache warming"

[benchmarks.measurement]
iterations = 100
aggregation = "median"
discard_outliers = true
outlier_threshold_stdev = 3.0
```

**Migration Support** (Goal 1):
- Validates performance is acceptable vs. Wolfram
- Identifies performance bottlenecks in migration
- Tracks compilation overhead (important for Julia)

**Research Support** (Goal 2):
- Provides empirical data on implementation trade-offs
- Informs language choice for specific use cases
- Documents computational complexity of operations

---

## How Layers Work Together

### Scenario 1: Implementing Python Tensor Contraction

1. **Layer 1**: Run unit test `contraction_known_001`
   - Input: T = [[1,2],[3,4]]
   - Expected: 5
   - Result: ✅ Pass

2. **Layer 2**: Run property `prop_contraction_associative`
   - Generate 100 random (T, S, U) tuples
   - Check: (T⊗S)⊗U = T⊗(S⊗U) for all 100
   - Result: ❌ Fail on case 42 (found edge case!)

3. **Debug**: Extract failing case from property test, add to Layer 1 as regression test

4. **Fix**: Correct contraction implementation

5. **Layer 3**: Run performance benchmark
   - Median time: 12ms (Wolfram: 8ms) → 1.5x slowdown
   - Result: ✅ Pass (within 5x threshold)

### Scenario 2: Comparing Implementations

Run all three layers against Wolfram, Python, Julia:

```bash
./harness/cli.py run --layers all --targets wolfram,python,julia --output comparison_report.json
```

**Layer 1 Results**:
- Wolfram: 150/150 ✅
- Python: 148/150 (2 failures)
- Julia: 150/150 ✅

**Layer 2 Results**:
- Wolfram: 25/25 properties ✅
- Python: 23/25 properties (associativity violation found!)
- Julia: 25/25 properties ✅

**Layer 3 Results**:
- Python: 1.8x slower than Wolfram (✅ usable)
- Julia: 1.1x slower than Wolfram (✅ excellent)

**Conclusion**: Python has a mathematical bug (Layer 2), Julia is ready for production.

---

## Why Mutation Testing Is Not Needed

**Mutation Testing**: Modifies source code (mutates) to check if tests detect the changes.

**Example**:
```python
# Original code
def contract(tensor, i, j):
    return sum(tensor[i][j])

# Mutated code (changed sum to product)
def contract(tensor, i, j):
    return product(tensor[i][j])
```

If tests still pass with mutation, tests are insufficient.

**Why it's not needed here**:

1. **Mutation testing validates code coverage, not functionality**
   - Useful for: Ensuring test suite catches code changes
   - Not useful for: Validating mathematical correctness

2. **We already have stronger validation**:
   - **Layer 1**: Oracle comparison catches wrong implementations
   - **Layer 2**: Property tests catch mathematical law violations
   - **Layer 3**: Performance tests catch algorithmic changes

3. **Language-agnostic tests can't mutate code**:
   - Mutation testing requires access to source code AST
   - Our tests run against compiled binaries/interpreters
   - Tests are implementation-agnostic (by design)

4. **Mathematical properties are more fundamental**:
   - If contraction violates associativity, implementation is wrong
   - Mutation testing would just confirm tests detect changes
   - Property testing directly validates mathematical correctness

**When mutation testing IS useful**:
- Unit testing internal helper functions
- Validating test quality for pure code coverage
- Finding redundant tests

**Our framework achieves mutation testing's goal** (finding untested code paths) through:
- Random property-based testing (explores edge cases)
- Oracle validation (catches semantic differences)

---

## Research Question: Property Specification Language

Layer 2 opens interesting design questions for the research goal.

### Current Approach: Pseudo-Code in TOML

```toml
[properties.law]
lhs = "Contract(T[a, b, -c], S[c, -d])"
rhs = "T[a, b, -c] * S[c, -d]"
```

**Problem**:
- Language-specific syntax (Python-like)
- Requires custom parser per implementation
- Ambiguous semantics

### Evolution Paths

#### Option A: Abstract Syntax Trees (ASTs) in TOML

```toml
[properties.law.lhs]
operation = "Contract"
arguments = [
  {type = "TensorExpression", tensor = "T", indices = ["a", "b", "-c"]},
  {type = "TensorExpression", tensor = "S", indices = ["c", "-d"]}
]

[properties.law.rhs]
operation = "Multiply"
arguments = [
  {type = "TensorExpression", tensor = "T", indices = ["a", "b", "-c"]},
  {type = "TensorExpression", tensor = "S", indices = ["c", "-d"]}
]
```

**Pros**:
- Unambiguous structure
- Easy to parse in any language
- Machine-readable

**Cons**:
- Verbose
- Hard to read/write manually
- Requires builders/pretty-printers

#### Option B: Reference Formal Specification Language

```toml
[properties.law]
spec_file = "specs/contraction_associativity.tla"
language = "TLA+"
verification_tool = "TLC"
```

Where `specs/contraction_associativity.tla`:
```tla
---- MODULE ContractAssociativity ----
THEOREM Associativity ==
  \A T, S, U \in Tensors :
    Contract(Contract(T, S), U) = Contract(T, Contract(S, U))
====
```

**Pros**:
- Leverages existing formal methods
- Enables mechanical verification
- Well-defined semantics

**Cons**:
- Steep learning curve
- May not map cleanly to tensor algebra
- Requires external tools

#### Option C: Mathematical Notation (LaTeX)

```toml
[properties.law]
notation = "latex"
lhs = "T^{ab}{}_{c} S^{c}{}_{d}"
rhs = "\\sum_{c} T^{ab}{}_{c} S^{c}{}_{d}"
semantics = "einstein_summation"
```

**Pros**:
- Human-readable
- Standard mathematical notation
- Good for documentation

**Cons**:
- Requires LaTeX parser
- Ambiguous (e.g., implicit summation)
- Hard to execute directly

#### Option D: Domain-Specific Language (DSL)

Design a new language specifically for tensor algebra properties:

```toml
[properties.law]
language = "TensorSpec-v1"
expression = """
forall T[a,b,-c], S[c,-d], U[d,-e] in Tensors:
  contract(contract(T, S, c), U, d) == contract(T, contract(S, U, d), c)
"""
```

**Pros**:
- Tailored to domain
- Balance of readability and precision
- Extensible for future needs

**Cons**:
- Requires designing/maintaining new language
- No existing tooling
- Adoption barrier

### Recommended Approach

**Start with Option A (AST in TOML)** because:
1. Unambiguous and parseable
2. Can generate human-readable views (pretty-print)
3. Can generate LaTeX documentation (Option C)
4. Foundation for future DSL (Option D)
5. Doesn't require external tools (Option B)

**Evolution path**:
1. Phase 1: Manual AST writing + pretty-printer
2. Phase 2: Parser for friendly syntax → AST
3. Phase 3: Investigate formal verification integration

---

## Implementation Roadmap (Revised)

### Phase 1: Unit Tests + Oracle (Weeks 1-2)

**Goal**: Validate basic migration correctness (Goal 1)

1. Extract 50-100 concrete examples from xAct notebooks
2. Build TOML loader for Layer 1 tests
3. Implement Wolfram oracle runner (wolframclient)
4. Build comparison logic for exact numeric tests
5. Generate oracle results for all unit tests

**Deliverables**:
- `tests/unit/` directory with 50-100 tests
- Oracle database (`oracle/unit/`)
- Python/Julia runners for unit tests
- HTML report of pass/fail results

### Phase 2: Property Framework (Weeks 3-4) ⭐ Research Contribution

**Goal**: Design reusable mathematical specifications (Goal 2)

1. Design property specification format (AST-based TOML)
2. Implement random tensor generators
   - Uniform distribution over components
   - Respect symmetry constraints
   - Configurable manifold dimensions
3. Build property verifier
   - Evaluates law on generated instances
   - Collects pass/fail statistics
   - Reports failing cases
4. Create 15-20 core properties:
   - Tensor algebra (associativity, distributivity, etc.)
   - Index manipulation (contraction, raising/lowering)
   - Symmetry preservation
   - Curvature tensor identities (Bianchi, etc.)
5. Cross-language validation
   - Run properties against Wolfram, Python, Julia
   - Document violations/differences

**Deliverables**:
- `tests/properties/` directory with 15-20 properties
- Property generator framework
- Property verifier engine
- Cross-implementation comparison report
- **Research paper draft** on reusable mathematical specifications

### Phase 3: Performance Baselines (Week 5)

**Goal**: Ensure usability (Goal 1)

1. Design performance benchmark format (Layer 3)
2. Implement timing/memory profiling
   - Warmup iterations (JIT, caching)
   - Statistical aggregation (median, p95)
   - Outlier detection
3. Generate Wolfram baselines for key operations
   - ToCanonical scaling
   - Tensor contraction complexity
   - Curvature computation
4. Set regression thresholds
   - 5x slower than Wolfram: Warning
   - 50x slower: Error
   - 20% slower than previous: Regression

**Deliverables**:
- `tests/performance/` directory with benchmarks
- Wolfram baseline database
- Performance tracking dashboard
- Regression detection CI integration

### Phase 4: Cross-Language Validation (Week 6)

**Goal**: Validate both goals

1. Run all three layers against all implementations
2. Analyze failures:
   - Layer 1 failures: Implementation bugs
   - Layer 2 failures: Mathematical law violations
   - Layer 3 failures: Performance regressions
3. Generate comprehensive report:
   - Correctness comparison
   - Performance comparison
   - Feature coverage matrix
4. Document findings for research publication

**Deliverables**:
- Comprehensive test report (all layers, all languages)
- Performance comparison charts
- Research paper submission
- Public test suite release (GitHub)

---

## Property Generator Architecture

### Design Goals

1. **Reproducible**: Same seed → same tensors
2. **Configurable**: Control dimension, rank, distribution, symmetries
3. **Valid**: Only generate mathematically valid tensors
4. **Diverse**: Explore edge cases (zero tensors, identity, etc.)

### Generator Interface

```python
# harness/common/generators.py
from dataclasses import dataclass
from typing import List, Dict, Optional
import numpy as np

@dataclass
class GeneratorConfig:
    """Configuration for random tensor generation."""
    type: str  # "Tensor", "Metric", "RiemannTensor", etc.
    rank: int
    indices: List[str]
    shape: int  # Manifold dimension
    distribution: str = "uniform"  # "uniform", "gaussian", "sparse"
    range: tuple[float, float] = (-10.0, 10.0)
    symmetry: Optional[str] = None  # "Symmetric[{0,1}]", "Antisymmetric[{0,1}]"
    constraints: List[str] = []  # ["positive_definite", "orthogonal", etc.]
    seed: int = 42

class TensorGenerator:
    """Generate random tensors for property testing."""

    def __init__(self, config: GeneratorConfig):
        self.config = config
        self.rng = np.random.Generator(np.random.PCG64(config.seed))

    def generate(self) -> np.ndarray:
        """Generate a single random tensor satisfying config."""
        shape = tuple([self.config.shape] * self.config.rank)

        # Generate base tensor
        if self.config.distribution == "uniform":
            tensor = self.rng.uniform(*self.config.range, size=shape)
        elif self.config.distribution == "gaussian":
            tensor = self.rng.normal(0, 1, size=shape)
        elif self.config.distribution == "sparse":
            tensor = self._generate_sparse(shape)

        # Apply symmetry constraints
        if self.config.symmetry:
            tensor = self._symmetrize(tensor, self.config.symmetry)

        # Apply additional constraints
        for constraint in self.config.constraints:
            tensor = self._apply_constraint(tensor, constraint)

        return tensor

    def _symmetrize(self, tensor: np.ndarray, symmetry: str) -> np.ndarray:
        """Apply symmetry to tensor."""
        if "Symmetric" in symmetry:
            # Average over permutations
            return (tensor + tensor.T) / 2
        elif "Antisymmetric" in symmetry:
            return (tensor - tensor.T) / 2
        # ... more complex symmetries
        return tensor

    def _apply_constraint(self, tensor: np.ndarray, constraint: str) -> np.ndarray:
        """Apply mathematical constraint."""
        if constraint == "positive_definite":
            # Construct via A^T A
            return tensor.T @ tensor
        elif constraint == "orthogonal":
            # Use QR decomposition
            Q, _ = np.linalg.qr(tensor)
            return Q
        # ... more constraints
        return tensor
```

### Usage Example

```python
# Property test using generator
def test_contraction_associativity(num_samples=100):
    """Test (T⊗S)⊗U = T⊗(S⊗U)."""

    # Configure generators
    gen_T = TensorGenerator(GeneratorConfig(
        type="Tensor", rank=3, indices=["a", "b", "-c"],
        shape=4, seed=42
    ))
    gen_S = TensorGenerator(GeneratorConfig(
        type="Tensor", rank=2, indices=["c", "-d"],
        shape=4, seed=43
    ))
    gen_U = TensorGenerator(GeneratorConfig(
        type="Tensor", rank=2, indices=["d", "-e"],
        shape=4, seed=44
    ))

    failures = []
    for i in range(num_samples):
        T = gen_T.generate()
        S = gen_S.generate()
        U = gen_U.generate()

        lhs = contract(contract(T, S, axis_c), U, axis_d)
        rhs = contract(T, contract(S, U, axis_d), axis_c)

        if not np.allclose(lhs, rhs, atol=1e-12):
            failures.append((i, T, S, U, lhs, rhs))

    return len(failures) == 0, failures
```

---

## Open Questions for Refinement

### 1. Property Generator Details

**Question**: How should random tensor generation balance coverage and validity?

**Options**:
- **A**: Purely random components (may generate pathological cases)
- **B**: Structured generation (only "reasonable" tensors)
- **C**: Hybrid (90% structured, 10% pathological)

**Recommendation**: Option C - most property violations occur at boundaries.

### 2. Property Specification Language

**Question**: What level of formality for property specifications?

**Options**:
- **A**: Informal pseudo-code (current approach)
- **B**: AST-based TOML (unambiguous)
- **C**: Formal specification language (TLA+, Coq)
- **D**: Custom DSL for tensor algebra

**Recommendation**: Start with B (AST), evaluate C (formal methods) in Phase 4.

### 3. Oracle Role in Property Testing

**Question**: Should properties be verified against Wolfram oracle?

**Arguments for**:
- Validates oracle itself (maybe xAct has bugs?)
- Establishes baseline for "correct" behavior
- If all implementations violate property, may be property specification bug

**Arguments against**:
- Properties are "more fundamental" than any implementation
- Mathematical laws exist independent of code
- Oracle is ground truth by definition

**Recommendation**: Always verify oracle, but allow override flag `oracle_is_axiom = true` for properties we trust more than implementations.

### 4. Failure Taxonomy and Reporting

**Question**: How should different failure types be reported?

**Proposed Taxonomy**:

| Layer | Failure Type | Severity | Action |
|-------|--------------|----------|--------|
| 1 (Unit) | Wrong result vs oracle | Error | Fix implementation |
| 1 (Unit) | Timeout | Warning | Optimize performance |
| 1 (Unit) | Crash | Error | Fix stability |
| 2 (Property) | Law violation | Critical | Fix mathematical bug |
| 2 (Property) | Failure on edge case | Warning | Document limitation |
| 2 (Property) | All implementations fail | Info | Check property spec |
| 3 (Perf) | >20% slower than previous | Error | Performance regression |
| 3 (Perf) | >5x slower than Wolfram | Warning | Usability concern |
| 3 (Perf) | >50x slower than Wolfram | Error | Unusable implementation |

**Recommendation**: Implement this taxonomy in test harness with separate exit codes.

### 5. Incremental Implementation Strategy

**Question**: How to handle expected failures during development?

**Options**:
- **A**: Skip tests (--skip flag)
- **B**: XFAIL (expected failure, like pytest)
- **C**: Separate test categories (implemented vs todo)

**Example XFAIL**:
```toml
[[tests]]
id = "advanced_canonicalization_001"
name = "Complex Riemann canonicalization"
xfail = true
xfail_reason = "Butler-Portugal algorithm not yet implemented"
xfail_implementations = ["python", "julia"]  # Wolfram should still pass

[tests.operations]
# ... test definition
```

**Recommendation**: Option B (XFAIL) - clearly documents implementation progress.

---

## Success Criteria

### Goal 1: Migration Validation

**Success = All three criteria met**:

1. **Correctness**: ≥95% of Layer 1 + Layer 2 tests pass
   - Layer 1: Direct oracle comparison
   - Layer 2: Mathematical properties hold

2. **Performance**: ≤5x slower than Wolfram xAct
   - Layer 3: Median execution time across benchmark suite
   - Excludes JIT compilation overhead (measured separately)

3. **Completeness**: Core packages fully ported
   - xCore: 100% (manifolds, tensors, indices)
   - xPerm: 100% (canonicalization, symmetries)
   - xTensor: 100% (covariant derivatives, curvature)

### Goal 2: Reusable Mathematical Specifications

**Success = Research contribution validated**:

1. **Reusability**: Same property tests run on ≥3 languages
   - Wolfram, Python, Julia (required)
   - Bonus: Rust, C++, Haskell

2. **Expressiveness**: Catalog of ≥20 core tensor algebra properties
   - Covers: Algebra, symmetries, differential geometry, GR

3. **Validation**: Properties catch real bugs
   - Example: Find bug in Python implementation via property test
   - Example: Identify xAct quirk via cross-language comparison

4. **Publication**: Research paper accepted
   - Venue: POPL, ICFP, or domain conference (GR/DG)
   - Title: "Language-Agnostic Property Specifications for Tensor Algebra"

---

## Relationship to Original Design

This document **refines** (not replaces) the [2026-01-08 design](./2026-01-08-test-framework-design.md):

**Preserved from original**:
- ✅ TOML format for test specifications
- ✅ Oracle-based validation against Wolfram xAct
- ✅ Directory structure (`tests/unit/`, `tests/properties/`, etc.)
- ✅ Performance benchmarking framework
- ✅ Focus on xCore, xPerm, xTensor
- ✅ Test extraction from documentation notebooks

**Added in this document**:
- ✅ Three-layer architecture with clear purposes
- ✅ Property-based testing framework (Layer 2) as research contribution
- ✅ Random tensor generator design
- ✅ Property specification language exploration
- ✅ Clarification that mutation testing is not needed
- ✅ Cross-language validation strategy
- ✅ Dual-goal framework (migration + research)

**Modified**:
- 🔄 De-emphasized mutation testing (not aligned with goals)
- 🔄 Elevated property testing to primary research contribution
- 🔄 Added cross-language comparison as explicit goal

---

## Next Steps

### Immediate (Week 1)
1. ✅ Review and approve this architecture document
2. Design JSON Schema for three-layer TOML format
3. Implement Python TOML loader with validation
4. Write 5-10 manual Layer 1 tests as proof-of-concept
5. Set up Wolfram oracle runner (wolframclient)

### Short-term (Weeks 2-4)
6. Extract 50-100 Layer 1 tests from xAct notebooks
7. Design property specification format (AST-based TOML)
8. Implement random tensor generator framework
9. Write 10-15 Layer 2 property tests
10. Run cross-language validation (Wolfram, Python, Julia)

### Medium-term (Weeks 5-8)
11. Build performance benchmarking harness (Layer 3)
12. Generate Wolfram baselines for all benchmarks
13. Implement CI/CD integration (GitHub Actions)
14. Create HTML reporting dashboard
15. Write research paper draft

### Long-term (Months 3-6)
16. Expand test suite to 500+ tests across all layers
17. Explore formal verification integration (TLA+, Coq)
18. Design custom DSL for property specifications
19. Submit research paper
20. Public release of test suite and framework

---

## Conclusion

This three-layer testing architecture serves dual goals:

1. **Migration Goal**: Validate xAct → Python/Julia ports are correct and usable
   - **Layer 1**: Unit tests (concrete examples, oracle validation)
   - **Layer 3**: Performance regression tests

2. **Research Goal**: Create reusable mathematical specifications
   - **Layer 2**: Property-based tests (language-agnostic laws)

The framework provides:
- Systematic migration validation
- Performance tracking and regression prevention
- **Novel contribution**: Reusable, executable mathematical property catalog
- Foundation for formal verification
- Cross-language implementation comparison

**Key insight**: Mutation testing is not needed because property-based testing provides stronger validation of mathematical correctness.

**Next milestone**: Implement proof-of-concept with 5-10 tests per layer, validate approach before scaling to full test suite.
