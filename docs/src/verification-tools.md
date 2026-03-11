# Getting Started

This guide walks through the core sxAct workflow: querying xAct via the oracle,
normalizing results, and comparing implementations.

## Prerequisites

- Docker oracle running: `docker compose up -d oracle`
- Python environment set up: `uv sync`

## 1. Check the oracle is healthy

```python
from sxact.oracle.client import OracleClient

client = OracleClient()  # defaults to http://localhost:8765
print(client.health())   # True
```

## 2. Evaluate a Wolfram expression

Use `evaluate` for plain Wolfram expressions:

```python
result = client.evaluate("2 + 2")
print(result.status)   # "ok"
print(result.result)   # "4"
```

## 3. Evaluate with xAct pre-loaded

Use `evaluate_with_xact` for tensor algebra expressions. xAct initializes once
per server session (~3 minutes on first load, then cached):

```python
result = client.evaluate_with_xact("""
DefManifold[M, 4, {a, b, c, d}];
DefMetric[-1, g[-a, -b], CD];
g[a, -a]
""")
print(result.status)   # "ok"
print(result.result)   # "4"  (trace of 4D metric = 4)
```

For test isolation (prevents symbol pollution between test cases), pass a `context_id`:

```python
result = client.evaluate_with_xact(
    "DefManifold[M, 4, {a, b, c, d}]; ...",
    context_id="my-test-001"
)
```

## 4. Use the structured Result

`evaluate_result` returns a typed `Result` with normalization built in:

```python
from sxact.oracle.result import Result

result: Result = client.evaluate_result("x + y")
print(result.status)      # "ok" | "error" | "timeout"
print(result.type)        # "Expr", "Scalar", etc.
print(result.repr)        # raw xAct output
print(result.normalized)  # canonicalized form (for comparison)
print(result.properties)  # {"rank": ..., "symmetry": ..., ...}
```

## 5. Normalize expressions manually

The normalization pipeline canonicalizes xAct output independently:

```python
from sxact.normalize.pipeline import normalize

# Index names, whitespace, and term order are all canonicalized
a = normalize("v[a] * CD[-a][u[b]]")
b = normalize("v[c]  *CD[-c][u[d]]")
print(a == b)  # True — same structure, different dummy indices
```

The pipeline applies four transforms in order:

1. Whitespace normalization
2. Coefficient normalization (`2*x` → `2 x`, `1*x` → `x`)
3. Dummy index canonicalization (`a, b, c` → `$1, $2, $3`)
4. Term ordering (lexicographic sort of sums)

## 6. Compare two implementations

The comparator uses a three-tier strategy to determine equivalence:

| Tier | Method | Oracle needed? |
|------|--------|---------------|
| 1 | Normalized string equality | No |
| 2 | Symbolic `Simplify[lhs - rhs] == 0` | Yes |
| 3 | Numeric sampling (90% threshold) | Yes |

```python
from sxact.compare.comparator import compare, EqualityMode

lhs = client.evaluate_result("expr1")
rhs = client.evaluate_result("expr2")

result = compare(lhs, rhs, oracle=client)
print(result.equal)       # True / False
print(result.tier)        # 1, 2, or 3
print(result.confidence)  # 1.0 for tiers 1-2; <1.0 for tier 3
print(result.diff)        # description of mismatch, if any
```

To stop after normalized string comparison (no oracle calls):

```python
result = compare(lhs, rhs, oracle=None, mode=EqualityMode.NORMALIZED)
```

## 7. Write a test

```python
import pytest
from sxact.oracle.client import OracleClient
from sxact.compare.comparator import compare

@pytest.fixture
def oracle():
    return OracleClient()

@pytest.mark.oracle
def test_metric_trace(oracle):
    result = oracle.evaluate_result("""
        DefManifold[M, 4, {a, b, c, d}];
        DefMetric[-1, g[-a, -b], CD];
        g[a, -a]
    """)
    assert result.status == "ok"
    assert result.repr == "4"
```

Run oracle tests with:

```bash
uv run pytest tests/ -m oracle
```
