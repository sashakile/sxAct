# Verification Framework Guide

This guide walks through the `sxact` verification workflow: defining tests in TOML, running them against the Julia backend, and using oracle snapshots for regression testing.

## Prerequisites

- Julia 1.12+ installed
- Python environment set up: `uv sync`
- For live oracle comparison: Docker oracle running (`docker compose up -d oracle`)

## 1. TOML Test Runner (Primary Workflow)

The main verification tool is `xact-test`, which runs declarative TOML test files against an adapter (Julia or Wolfram) and compares results to oracle snapshots.

### Running tests

```bash
# Run all xTensor tests against the Julia backend
uv run xact-test run tests/xtensor/ --adapter julia --oracle-mode snapshot --oracle-dir oracle

# Run a single test file
uv run xact-test run tests/xtensor/canonicalization.toml --adapter julia --oracle-mode snapshot --oracle-dir oracle

# Run xPerm tests
uv run xact-test run tests/xperm/ --adapter julia --oracle-mode snapshot --oracle-dir oracle
```

### Test file structure

Tests are TOML files with a `[meta]` header, `[[setup]]` blocks for definitions, and `[[tests]]` blocks for assertions:

```toml
[meta]
id          = "xtensor/example"
description = "Example test"
tags        = ["xtensor", "layer:1"]

[[setup]]
action   = "DefManifold"
store_as = "M"
[setup.args]
name      = "M"
dimension = 4
indices   = ["a", "b", "c", "d"]

[[tests]]
action = "ToCanonical"
[tests.args]
expr = "T[-b, -a] - T[-a, -b]"
```

### Oracle snapshots

Oracle snapshots are pre-recorded Wolfram results stored as JSON with SHA-256 content hashes. They allow verification without a live Wolfram Engine.

```bash
# Generate snapshots from a live oracle
uv run xact-test snapshot tests/xtensor/ --output oracle/ --oracle-url http://localhost:8765

# Regenerate and diff changed snapshots
uv run xact-test regen-oracle tests/xtensor/ --oracle-dir oracle/ --diff --yes
```

## 2. Using the Oracle Client

```python
from sxact.oracle.client import OracleClient

client = OracleClient()          # defaults to http://localhost:8765
print(client.health())           # True

result = client.evaluate_with_xact(
    "DefManifold[M, 4, {a, b, c, d}]; ...",
    context_id="my-test-001"     # prevents symbol pollution between tests
)
```

For full API details, see [Verification API Reference](api-verification.md#1-oracleclient).

## 3. Normalizing Expressions

```python
from sxact.normalize.pipeline import normalize, ast_normalize

a = normalize("v[a] * CD[-a][u[b]]")
b = normalize("v[c]  *CD[-c][u[d]]")
print(a == b)  # True — same structure, different dummy indices

a = ast_normalize("Plus[T[-a, -b], T[-b, -a]]")
b = ast_normalize("Plus[T[-c, -d], T[-d, -c]]")
print(a == b)  # True
```

For full API details, see [Verification API Reference](api-verification.md#2-normalization-functions).

## 4. Comparing Results

```python
from sxact.compare.comparator import compare, EqualityMode

lhs = client.evaluate_with_xact("expr1")
rhs = client.evaluate_with_xact("expr2")

result = compare(lhs, rhs, oracle=client)
print(result.equal)       # True / False
print(result.tier)        # 1, 2, or 3
print(result.confidence)  # 1.0 for tiers 1-2; <1.0 for tier 3
```

For full API details, see [Verification API Reference](api-verification.md#3-comparator-api).

## 5. Run Python tests

```bash
# All Python unit tests
uv run pytest tests/ -q --ignore=tests/integration --ignore=tests/properties --ignore=tests/xperm --ignore=tests/xtensor

# Integration tests (requires live oracle)
uv run pytest tests/integration/ -m oracle
```

For API details, see the [Verification API Reference](api-verification.md).
