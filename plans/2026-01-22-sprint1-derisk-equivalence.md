# Sprint 1: De-risk Equivalence Implementation Plan

**Date**: 2026-01-22

## Overview

Prove the three-tier comparison strategy works before scaling. Build the Wolfram oracle runner, normalization pipeline, and comparator module. Validate with 5-10 hand-written tests.

## Related

- Spec: `specs/2026-01-22-design-framework-gaps.md` (Phase 6, Sprint 1)
- Session: `sessions/2026-01-08-initial-setup.md` (Docker/xAct setup)

## Current State

- **Exists**: Docker-based Wolfram Engine with xAct 1.2.0, wolframclient installed
- **Exists**: Example script `notebooks/test_xact.wls` showing xAct usage
- **Exists**: Stub Python file `notebooks/test_python_wolfram.py` (not functional)
- **Missing**: Python package structure for test framework
- **Missing**: Oracle runner that executes xAct commands via wolframclient
- **Missing**: Normalization pipeline for output comparison
- **Missing**: Three-tier comparator implementation

## Desired End State

A working Python module that can:
1. Connect to Wolfram Engine via Docker
2. Execute xAct commands and capture results
3. Normalize outputs (whitespace, dummy indices, term ordering)
4. Compare results using three-tier strategy

**How to verify:**
- Run `uv run pytest tests/` - all tests pass
- Execute sample xAct operations and verify normalized output
- Demonstrate comparator correctly handles dummy index variation

## Out of Scope

- TOML test file loading (Sprint 2)
- Julia/Python adapters (Sprint 2)
- Snapshot generation (Sprint 3)
- CI integration (Sprint 3)
- Full test extraction from notebooks (Sprint 4)

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| HTTP server stability | Medium | High | Health checks, timeout handling, restart logic |
| Normalization edge cases | High | Medium | Start with simple cases, iterate |
| xAct output format variations | Medium | Medium | Capture raw outputs, adjust normalization |
| Container startup time | Low | Medium | Lazy init, keep container running |

---

## Architecture Decision: HTTP Bridge

**Problem:** `wolframclient.WolframLanguageSession` requires a local kernel path. It cannot connect to Wolfram Engine running inside Docker from Python running on the host.

**Solution:** Add a lightweight HTTP server inside the Docker container that:
1. Receives POST requests with Wolfram expressions
2. Evaluates using WolframScript
3. Returns JSON results

**Why HTTP over batch files:**
- Real-time evaluation needed for Tier 2 comparator (`Simplify[lhs - rhs]`)
- Faster feedback loop during development
- Supports stateful sessions (xAct definitions persist)

---

## Phase 1: Oracle HTTP Bridge

### Changes Required

**Create: `oracle/server.py`** (runs inside Docker)
- Flask app with `/evaluate` endpoint
- POST `{"expr": "2+2"}` → `{"status": "ok", "result": "4", "timing_ms": 5}`
- Loads xAct on startup
- Handles errors gracefully

**Create: `oracle/init.wl`**
- xAct initialization script
- `AppendTo[$Path, "/opt"]; Needs["xAct`xTensor`"]`

**Update: `docker-compose.yml`**
- Add Python + Flask to container
- Expose port 8765
- Add healthcheck
- Command: `python /oracle/server.py`

**Create: `oracle/Dockerfile`** (optional, if base image needs Python)
- FROM wolframresearch/wolframengine
- Install Python, Flask

**Create: `packages/sxact/src/sxact/__init__.py`**
- Package initialization, version export

**Create: `packages/sxact/src/sxact/oracle/__init__.py`**

**Create: `packages/sxact/src/sxact/oracle/client.py`**
- `OracleClient` class:
  - `__init__(base_url: str = "http://localhost:8765")`
  - `evaluate(expr: str) -> Result` - HTTP POST, parse JSON
  - `health() -> bool` - Check server is up
  - `load_xact() -> None` - Trigger xAct initialization

**Update: `pyproject.toml`**
- Add `requests` dependency
- Add `pytest`, `mypy` as dev dependencies
- Configure src layout

**Create: `tests/conftest.py`**
- `@pytest.fixture` for OracleClient
- Startup/health check logic

**Create: `tests/oracle/__init__.py`**
**Create: `tests/oracle/test_client.py`**
- Test health endpoint
- Test simple expression: `2+2` → `4`
- Test xAct loading
- Test error handling

### Implementation Approach

1. **Server (inside Docker):**
   ```python
   # oracle/server.py
   from flask import Flask, request, jsonify
   import subprocess
   import time

   app = Flask(__name__)

   @app.route("/evaluate", methods=["POST"])
   def evaluate():
       expr = request.json.get("expr")
       start = time.time()
       result = subprocess.run(
           ["wolframscript", "-code", expr],
           capture_output=True, text=True, timeout=30
       )
       return jsonify({
           "status": "ok" if result.returncode == 0 else "error",
           "result": result.stdout.strip(),
           "error": result.stderr.strip() if result.returncode != 0 else None,
           "timing_ms": int((time.time() - start) * 1000)
       })
   ```

2. **Client (on host):**
   ```python
   # packages/sxact/src/sxact/oracle/client.py
   import requests

   class OracleClient:
       def __init__(self, base_url="http://localhost:8765"):
           self.base_url = base_url

       def evaluate(self, expr: str) -> dict:
           resp = requests.post(f"{self.base_url}/evaluate", json={"expr": expr})
           return resp.json()
   ```

3. **Docker Compose:**
   ```yaml
   services:
     oracle:
       build: ./oracle
       ports:
         - "8765:8765"
       volumes:
         - ./resources/xAct:/opt/xAct:ro
       healthcheck:
         test: ["CMD", "curl", "-f", "http://localhost:8765/health"]
         interval: 10s
         timeout: 5s
         retries: 3
   ```

### Success Criteria

#### Automated:
- [ ] `docker compose up oracle` starts successfully
- [ ] `curl http://localhost:8765/health` returns OK
- [ ] `uv run pytest tests/oracle/` passes
- [ ] Type checking passes: `uv run mypy src/`

#### Manual:
- [ ] `curl -X POST http://localhost:8765/evaluate -d '{"expr":"2+2"}'` returns `{"result":"4",...}`
- [ ] xAct expressions evaluate correctly

### Dependencies

- Docker running with Wolfram Engine activated
- Port 8765 available on host

---

## Phase 2: Result Envelope & Basic Normalization

### Changes Required

**Create: `packages/sxact/src/sxact/oracle/result.py`**
- `Result` dataclass matching spec:
  ```python
  @dataclass
  class Result:
      status: Literal["ok", "error", "timeout"]
      type: str  # Expr, Scalar, Bool, Handle
      repr: str  # Raw string representation
      normalized: str  # Normalized form
      properties: dict  # rank, symmetry, manifold
      diagnostics: dict  # execution_time_ms, memory_mb
      error: Optional[str]
  ```

**Update: `packages/sxact/src/sxact/oracle/client.py`**
- Return `Result` objects instead of raw dict

**Create: `packages/sxact/src/sxact/normalize/__init__.py`**
**Create: `packages/sxact/src/sxact/normalize/pipeline.py`**
- `normalize(expr: str) -> str` function with:
  1. Whitespace normalization
  2. Dummy index canonicalization (`$1, $2, ...`)
  3. Term ordering (lexicographic for commutative)
  4. Coefficient normalization

**Create: `tests/normalize/__init__.py`**
**Create: `tests/normalize/test_pipeline.py`**
- Test each normalization step independently
- Test combined pipeline

### Tests to Write First (TDD)

```python
# tests/normalize/test_pipeline.py
def test_whitespace_normalization():
    assert normalize("T[ -a,  -b ]") == "T[-a, -b]"

def test_dummy_index_canonicalization():
    assert normalize("T[-a, -b]") == "T[-$1, -$2]"
    assert normalize("T[-x, -y]") == "T[-$1, -$2]"

def test_term_ordering():
    assert normalize("B + A") == "A + B"

def test_coefficient_normalization():
    assert normalize("2*x") == "2 x"
    assert normalize("-1*x") == "-x"
```

### Implementation Approach

1. Regex-based whitespace normalization
2. Index detection via pattern matching (e.g., `-a`, `-b`, `a`, `b`)
3. Track index occurrences, rename in order of first appearance
4. Term ordering: split on `+`, sort, rejoin

### Success Criteria

#### Automated:
- [ ] `uv run pytest tests/normalize/` passes
- [ ] Handles: `T[-a, -b]` → `T[-$1, -$2]`
- [ ] Handles: `B + A` → `A + B`
- [ ] Handles: `2*x` → `2 x`

#### Manual:
- [ ] Run normalizer on real xAct output from oracle

---

## Phase 3: Three-Tier Comparator

### Changes Required

**Create: `packages/sxact/src/sxact/compare/__init__.py`**
**Create: `packages/sxact/src/sxact/compare/comparator.py`**
- `EqualityMode` enum: `NORMALIZED`, `SYMBOLIC`, `NUMERIC`
- `CompareResult` dataclass:
  ```python
  @dataclass
  class CompareResult:
      equal: bool
      tier: int  # 1, 2, or 3
      confidence: float = 1.0
      diff: Optional[str] = None
  ```
- `compare(lhs: Result, rhs: Result, oracle: OracleClient) -> CompareResult`
  - Tier 1: Normalized string comparison
  - Tier 2: Symbolic diff=0 via oracle (`Simplify[(lhs) - (rhs)] == 0`)
  - Tier 3: Numeric sampling (for expressions with free indices)

**Create: `packages/sxact/src/sxact/compare/sampling.py`**
- `sample_numeric(lhs, rhs, oracle: OracleClient, n=10, seed=42) -> list[Sample]`
- Substitute random values for free indices
- Compare numeric results within tolerance

**Create: `tests/compare/__init__.py`**
**Create: `tests/compare/test_comparator.py`**
- Test tier 1: identical normalized strings
- Test tier 2: semantically equal but different form
- Test tier 3: numeric sampling fallback

### Tests to Write First (TDD)

```python
# tests/compare/test_comparator.py
def test_tier1_exact_match():
    lhs = Result(status="ok", repr="T[-$1, -$2]", normalized="T[-$1, -$2]", ...)
    rhs = Result(status="ok", repr="T[-$1, -$2]", normalized="T[-$1, -$2]", ...)
    result = compare(lhs, rhs, oracle=None)  # No oracle needed for tier 1
    assert result.equal and result.tier == 1

def test_tier2_symbolic_equality(oracle):
    # T[-a,-b] + T[-b,-a] == 2*T[-a,-b] for symmetric T
    lhs = Result(repr="T[-a,-b] + T[-b,-a]", ...)
    rhs = Result(repr="2*T[-a,-b]", ...)
    result = compare(lhs, rhs, oracle)
    assert result.equal and result.tier == 2

def test_tier3_numeric_fallback(oracle):
    # When symbolic check fails but numeric sampling agrees
    ...
```

### Implementation Approach

1. Tier 1 is pure Python string comparison on `.normalized`
2. Tier 2 calls oracle: `Simplify[(lhs.repr) - (rhs.repr)] == 0`
3. Tier 3 substitutes random floats for indices, evaluates via oracle
4. Return early on first successful tier

### Success Criteria

#### Automated:
- [ ] `uv run pytest tests/compare/` passes
- [ ] Tier 1 catches exact matches
- [ ] Tier 2 catches `T[-a,-b] + T[-b,-a]` == `2*T[-a,-b]` for symmetric T

#### Manual:
- [ ] Compare two xAct outputs that differ only in dummy indices

---

## Phase 4: Integration & Validation

### Changes Required

**Create: `tests/integration/__init__.py`**
**Create: `tests/integration/test_xact_basics.py`**
- 5-10 hand-written integration tests:
  1. Define manifold, verify output
  2. Define metric, verify properties
  3. Define symmetric tensor, test symmetry
  4. ToCanonical on simple expression
  5. Simplify with metric contraction
  6. Riemann tensor definition
  7. Two expressions that are symbolically equal
  8. Expression requiring numeric sampling

**Create: `docs/oracle-quirks.md`**
- Document any xAct quirks discovered during testing

### Tests to Write First (TDD)

```python
# tests/integration/test_xact_basics.py
import pytest

@pytest.mark.oracle
def test_define_manifold(oracle):
    result = oracle.evaluate('DefManifold[M, 4, {a,b,c,d}]; M')
    assert result.status == "ok"
    assert "M" in result.repr

@pytest.mark.oracle
def test_symmetric_tensor(oracle):
    oracle.evaluate('DefManifold[M, 4, {a,b,c,d}]')
    oracle.evaluate('DefTensor[T[-a,-b], M, Symmetric[{-a,-b}]]')
    result = oracle.evaluate('T[-b,-a]')
    # Should be equal to T[-a,-b] due to symmetry
    assert result.status == "ok"

@pytest.mark.oracle
def test_comparator_tier2(oracle):
    # Two symbolically equal expressions
    lhs = oracle.evaluate('T[-a,-b] + T[-b,-a]')
    rhs = oracle.evaluate('2*T[-a,-b]')
    cmp = compare(lhs, rhs, oracle)
    assert cmp.equal and cmp.tier == 2
```

### Implementation Approach

1. Each test uses real Wolfram/xAct via oracle HTTP server
2. Tests are marked `@pytest.mark.oracle` for CI skip
3. Capture actual outputs, verify comparator handles them

### Success Criteria

#### Automated:
- [ ] `uv run pytest tests/integration/ -m oracle` passes (with Docker running)
- [ ] All three comparison tiers exercised

#### Manual:
- [ ] Review oracle-quirks.md for completeness

---

## Testing Strategy

**Following TDD:**
1. Write tests first for each module (see "Tests to Write First" in each phase)
2. Watch tests fail (Red)
3. Implement minimal code to pass (Green)
4. Refactor while keeping tests green

**Test directory structure:**
```
tests/
├── conftest.py          # Oracle fixture, pytest config
├── oracle/
│   ├── __init__.py
│   └── test_client.py   # Oracle HTTP client tests
├── normalize/
│   ├── __init__.py
│   └── test_pipeline.py # Normalization tests
├── compare/
│   ├── __init__.py
│   └── test_comparator.py # Three-tier comparator tests
└── integration/
    ├── __init__.py
    └── test_xact_basics.py # Full xAct integration tests
```

**Test markers:**
- `@pytest.mark.oracle` - requires Docker oracle server running

**Running tests:**
```bash
# Unit tests only (no Docker needed for normalize tests)
uv run pytest tests/normalize/

# All tests (requires `docker compose up oracle`)
uv run pytest tests/

# Skip oracle tests in CI
uv run pytest tests/ -m "not oracle"
```

## Rollback Strategy

- All changes are new files; rollback = delete files
- No modifications to existing working code
- Git branch: `sprint1-oracle-http`

## References

- Spec: `specs/2026-01-22-design-framework-gaps.md` Section 5.1-5.3
- Flask docs: https://flask.palletsprojects.com/
- Existing example: `notebooks/test_xact.wls`

## Open Questions

None - architecture decided (HTTP bridge), spec provides sufficient detail.

## Estimated Timeline

- Phase 1: 2 days (Oracle HTTP server + client)
- Phase 2: 1 day (Result envelope + normalization)
- Phase 3: 1 day (Three-tier comparator)
- Phase 4: 1 day (Integration tests + validation)

**Total: 5 days**
