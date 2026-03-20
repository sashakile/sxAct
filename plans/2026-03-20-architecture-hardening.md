# Architecture Review & Hardening Plan

**Date**: 2026-03-20
**Status**: Proposed
**Scope**: Structural refactorings to fix systemic issues found in red-team review

## 1. Current Architecture

```
xAct.jl (module entry)
├── XCore.jl       (663 lines)  — Symbol validation, utility functions
├── XTensor.jl    (5024 lines)  — Tensor algebra engine
│   └── XPerm.jl  (2250 lines)  — Butler-Portugal canonicalization
├── XInvar.jl     (2118 lines)  — Riemann invariant classification
│   └── InvarDB.jl (638 lines)  — Database parser
└── TExpr.jl       (983 lines)  — Typed expression layer

Python layer (two separate packages):
├── [xact-py] xact/api.py            (858 lines)  — Public Python API
├── [xact-py] xact/xcore/_runtime.py  (82 lines)  — Julia process manager
└── [sxact]   sxact/adapter/julia_stub.py (1896 lines) — Julia bridge adapter
```

**Total**: ~11,700 lines Julia + ~2,800 lines Python

## 2. Systemic Anti-Patterns

### 2.1 Global Mutable State (affects 27 tickets)

XTensor.jl has **15 module-level mutable containers**:

```julia
const _manifolds       = Dict{Symbol,ManifoldObj}()
const _vbundles        = Dict{Symbol,VBundleObj}()
const _tensors         = Dict{Symbol,TensorObj}()
const _metrics         = Dict{Symbol,MetricObj}()
const _perturbations   = Dict{Symbol,PerturbationObj}()
const _bases           = Dict{Symbol,BasisObj}()
const _charts          = Dict{Symbol,ChartObj}()
const _basis_changes   = Dict{Tuple{Symbol,Symbol},BasisChangeObj}()
const _ctensors        = Dict{Tuple{Symbol,Vararg{Symbol}},CTensorObj}()
const _traceless_tensors = Set{Symbol}()
const _trace_scalars   = Dict{Symbol,Tuple{Symbol,Int}}()
const _einstein_expansion = Dict{Symbol,Tuple{Symbol,Symbol,Symbol}}()
const _identity_registry  = Dict{Symbol,Vector{MultiTermIdentity}}()
```

XInvar.jl adds 3 more: `_invar_db`, `_perm_dispatch`, `_dual_perm_dispatch`.

**Problems this causes:**
- Thread safety (sxAct-bvh9, gzqq, ot5x) — no locking
- Stale references after reset (sxAct-kgh0) — objects hold symbols into cleared dicts
- Test isolation — every test must call reset_state!()
- No concurrent sessions — can't have two manifolds named :M in different contexts
- Implicit coupling — any function can read/write any global

### 2.2 String Interpolation as IPC (affects 7 tickets)

The Python→Julia bridge constructs Julia code as f-strings:

```python
# api.py — 20+ call sites like this:
self._jl.seval(f'Main.eval(:(global {name} = :{name}))')
self._jl.seval(f'xAct.def_manifold!(:{name}, {dim}, [:{", :".join(indices)}])')
```

**Problems:**
- Code injection (sxAct-7m5w) — no identifier validation
- Path injection (sxAct-854k) — filesystem paths unescaped
- No timeout (sxAct-iz1u) — seval blocks indefinitely
- Error propagation (sxAct-b6v1) — Julia errors are raw stack traces
- Fragile — any special character in user input breaks the f-string

### 2.3 String-Based Expression Core (affects 5 tickets)

Tensor expressions are plain strings parsed and serialized repeatedly:

```julia
# Internal flow:
"T[a,b] * V[-b]"  →  _parse_expression()  →  Vector{TermAST}
                   →  (canonicalize/contract)
                   →  _serialize_terms()   →  "T[a,-b] * V[b]"
```

**Problems:**
- _swap_indices substring corruption (sxAct-qmng) — `replace()` has no word boundaries
- Parser has no direct tests (sxAct-jz9s)
- Round-trip fidelity not guaranteed
- TExpr typed layer exists but is an overlay, not the primary representation

### 2.4 Inconsistent Validation (affects 12 tickets)

Validation exists but is inconsistent across boundaries. XPerm.jl has 20
`error()`/`throw()` calls with explicit checks (degree, range, arity).
XTensor.jl has 101 `error()`/`throw()` calls for registration and parsing.
But critical gaps remain at specific boundaries:

- **No identifier validation** at any Python→Julia boundary (sxAct-7m5w)
- `Cycles()` validates within-cycle duplicates but **not cross-cycle disjointness** (sxAct-dlw6)
- `inverse_perm()` validates range but **not duplicates** (sxAct-jf3w)
- `perturb()` accepts order=0 and negative orders (sxAct-y1q3)
- `InvariantCase` accepts unsorted deriv_orders (sxAct-15uh)
- `_parse_coefficient` silently falls back to 1//1 on unparseable input (sxAct-tecf)

The pattern: validation is rigorous for _common_ paths but absent for _edge_ inputs.

### 2.5 Unparameterized Numeric Types (affects 3 tickets)

```julia
struct BasisChangeObj
    matrix::Matrix{Any}     # should be Matrix{T}
    inverse::Matrix{Any}
    jacobian::Any           # should be T
end

struct CTensorObj
    array::Array            # should be Array{T,N}
end

const _trace_scalars = Dict{Symbol,Tuple{Symbol,Int}}()  # should be Rational{Int}
```

Type instability in every numeric operation — dynamic dispatch on every element access.

### 2.6 Monolithic 5k-Line File (code organization)

XTensor.jl handles 9 distinct concerns in one file:
1. Registration (def_manifold!, def_metric!, def_tensor!, etc.)
2. Expression parsing/serialization (_parse_expression, _serialize_terms)
3. Canonicalization (ToCanonical)
4. Contraction (_contract_pair, _einsum_eval)
5. Perturbation theory (perturb, PerturbationOrder)
6. Variational calculus (IBP, VarD, TotalDerivativeQ)
7. Basis/xCoba subsystem (BasisChange, CTensor, ToBasis, etc.)
8. Multi-term identities (RegisterIdentity!, _apply_identities!)
9. Utility functions (CollectTensors, AllContractions, MakeTraceFree, etc.)

File decomposition is out of scope for this hardening plan — it requires a separate
design pass to determine module boundaries without breaking the internal include/export
structure. Tracked as future work.

---

## 3. Proposed Refactorings

### TDD Approach

Per project mandate (CLAUDE.md: "follow TDD and Tidy First"), every phase starts
with failing tests before implementation:

| Phase | Failing Test First |
|-------|-------------------|
| A | `validate_identifier(:("M; evil()"))` must throw `ArgumentError` |
| B | `jl_symbol("M; evil()")` must raise `ValueError` in Python |
| C | `Contract("EinsteinM3[a,b] * gM3[-a,-b]")` on dim=3 manifold must yield `-(1//2)*RicciScalarM3[]` |
| D | `_swap_indices("Tab[-a,-ab]", "a", "b")` must yield `"Tab[-b,-ab]"` (not `"Tbb[-b,-bb]"`) |
| E | `InvSimplify(expr; dim=3)` after prior `dim=4` call must use dim=3 rules |
| F | Two `Session` objects can define `:M` independently without conflict |

### Phase A: Validation Layer (fixes 7 tickets, minimal risk)

**Goal**: Add a validation module for the Julia side. Python-side validation is in Phase B.

Phase A catches invalid inputs at the Julia boundary (defense in depth for direct
Julia callers and the test adapter). Phase B (below) catches them at the Python
boundary (first line of defense for Python API users). Both are needed: Phase A
without Phase B leaves Python seval paths open; Phase B without Phase A leaves
direct Julia callers unprotected.

```julia
# New file: src/Validation.jl (~100 lines)
module Validation

"""Validate a Julia identifier (tensor name, index label, manifold name).
Note: ASCII-only by design. Julia supports Unicode identifiers but we restrict
to ASCII to match the Python-side regex in Phase B. If Unicode support is needed,
use Julia's `Base.isidentifier()` instead."""
function validate_identifier(name::Union{Symbol,AbstractString}; context::String="")
    s = string(name)
    if !occursin(r"^[A-Za-z_][A-Za-z0-9_]*$", s)
        throw(ArgumentError("Invalid identifier '$s' in $context: must match [A-Za-z_][A-Za-z0-9_]*"))
    end
    return Symbol(s)
end

"""Validate a permutation is well-formed."""
function validate_perm(p::Vector{Int}; context::String="permutation")
    n = length(p)
    seen = falses(n)
    for x in p
        (1 <= x <= n) || throw(ArgumentError("$context: element $x out of range 1:$n"))
        seen[x] && throw(ArgumentError("$context: duplicate element $x"))
        seen[x] = true
    end
end

"""Validate cycles are disjoint."""
function validate_disjoint_cycles(cycles::Vector{Vector{Int}})
    seen = Set{Int}()
    for cyc in cycles
        for x in cyc
            x in seen && throw(ArgumentError("Element $x appears in multiple cycles"))
            push!(seen, x)
        end
    end
end

"""Validate perturbation order."""
function validate_order(order::Int; context::String="perturbation order")
    order >= 1 || throw(ArgumentError("$context must be >= 1, got $order"))
end

export validate_identifier, validate_perm, validate_disjoint_cycles, validate_order
end
```

**Where to call it (Julia side only):**
- `def_manifold!`, `def_metric!`, `def_tensor!` → `validate_identifier(name)`
- `Cycles()` → `validate_disjoint_cycles()`
- `inverse_perm()` → `validate_perm()`
- `perturb()` → `validate_order()`

**Tickets resolved:** dlw6, jf3w, y1q3, 15uh, e6d3 (partially)
**Contributes to:** 7m5w (Julia side only — Python side in Phase B)

### Phase B: Safe Julia Bridge (fixes 7 tickets, medium risk)

**Goal**: Replace raw seval string interpolation with a safe calling convention.
Covers both `api.py` (public API) and `julia_stub.py` (test adapter).

```python
# New: packages/xact-py/src/xact/_bridge.py (~120 lines)

from __future__ import annotations

import re
import threading
from typing import Any

_IDENT_RE = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*$')
_lock = threading.Lock()


def validate_ident(name: str, context: str = "") -> str:
    """Validate a string is a safe Julia identifier.
    Uses same regex as Julia-side Validation.validate_identifier (Phase A)."""
    if not _IDENT_RE.match(name):
        raise ValueError(
            f"Invalid identifier {name!r}{f' in {context}' if context else ''}"
        )
    return name


def jl_escape(s: str) -> str:
    """Escape a string for use inside Julia double-quoted string literals."""
    return s.replace("\\", "\\\\").replace('"', '\\"')


# --- Typed argument builders (prevent injection by construction) ---

def jl_sym(name: str, context: str = "") -> str:
    """Build a validated Julia Symbol literal like ':MyTensor'."""
    validate_ident(name, context)
    return f":{name}"


def jl_int(n: int) -> str:
    """Build a Julia integer literal. Rejects non-int input."""
    if not isinstance(n, int):
        raise TypeError(f"Expected int, got {type(n).__name__}")
    return str(n)


def jl_str(s: str) -> str:
    """Build an escaped Julia string literal like '\"T[-a,-b]\"'."""
    return f'"{jl_escape(s)}"'


def jl_sym_list(names: list[str], context: str = "") -> str:
    """Build a Julia Symbol vector like '[:a, :b, :c]'."""
    return "[" + ", ".join(jl_sym(n, context) for n in names) + "]"


def jl_path(p: str) -> str:
    """Build an escaped Julia string literal from a filesystem path."""
    return jl_str(p)


def jl_call(jl: Any, func: str, *args: str) -> Any:
    """Call a Julia function with pre-validated/escaped arguments.

    All args MUST be built via jl_sym/jl_int/jl_str/jl_sym_list.
    This function adds locking for thread safety.

    Note: timeout is NOT supported by juliacall's seval(). For timeout
    protection, use subprocess isolation (sxAct-iz1u — separate ticket).
    """
    with _lock:
        expr = f"{func}({', '.join(args)})"
        try:
            return jl.seval(expr)
        except Exception as exc:
            raise RuntimeError(
                f"Julia call failed: {func}(...)\n{exc}"
            ) from exc
```

**Migration example** (api.py):
```python
# Before (unsafe):
jl.seval(f'xAct.def_manifold!(:{name}, {dim}, [:{", :".join(indices)}])')

# After (safe — injection impossible by construction):
jl_call(jl, "xAct.def_manifold!",
    jl_sym(name, "manifold name"),
    jl_int(dim),
    jl_sym_list(indices, "index labels"))
```

**Scope**: Both `api.py` (~20 call sites) and `julia_stub.py` (~30 action handlers).

**Tickets resolved:** 7m5w (Python side), 854k, gzqq (locking), b6v1 (error wrapping)
**Not resolved here:** iz1u (timeout) — requires subprocess isolation, tracked separately

### Phase C: Type Fixes (fixes 3 tickets, low risk)

**C1**: Fix `_trace_scalars` type and Einstein trace computation:

```julia
# Change:
const _trace_scalars = Dict{Symbol,Tuple{Symbol,Rational{Int}}}()  # was Int
# And:
coeff = 1 - n // 2  # was 1 - div(n, 2)
```

**C2**: Parameterize numeric types:

```julia
struct BasisChangeObj{T<:Number}
    from_basis::Symbol
    to_basis::Symbol
    matrix::Matrix{T}
    inverse::Matrix{T}
    jacobian::T
end

struct CTensorObj{T<:Number,N}
    tensor::Symbol
    array::Array{T,N}
    bases::Vector{Symbol}
    weight::Int
end
```

Storage dicts use `where` clauses to accept any numeric parameterization:
```julia
const _basis_changes = Dict{Tuple{Symbol,Symbol}, BasisChangeObj{<:Number}}()
const _ctensors = Dict{Vector{Symbol}, CTensorObj{<:Number}}()
```

**Risk note**: This changes struct layout. No serialization/persistence layer
exists, so backward compatibility is not a concern. All existing tests use the
constructor, which will infer `T` automatically from the matrix element type.

**Tickets fixed:** le8b, kcci, partially z1gp

### Phase D: Index-Aware String Operations (fixes 2 tickets, medium risk)

**Goal**: Replace naive `replace()` in `_swap_indices` with a bracket-aware substitution.

```julia
"""
    _swap_indices(expr, label_a, label_b) → String

Swap two index labels in a tensor expression. Only substitutes inside
bracket groups [...], leaving tensor names untouched.
"""
function _swap_indices(expr::AbstractString, label_a::AbstractString, label_b::AbstractString)::String
    result = IOBuffer()
    i = 1
    while i <= length(expr)
        if expr[i] == '['
            # Inside brackets — swap labels
            j = findnext(']', expr, i)
            j === nothing && error("Unmatched '[' in expression")
            bracket_content = expr[i:j]
            bracket_content = _replace_label(bracket_content, label_a, "__TMP__")
            bracket_content = _replace_label(bracket_content, label_b, label_a)
            bracket_content = _replace_label(bracket_content, "__TMP__", label_b)
            write(result, bracket_content)
            i = j + 1
        else
            write(result, expr[i])
            i += 1
        end
    end
    return String(take!(result))
end

function _replace_label(s::AbstractString, old::AbstractString, new::AbstractString)
    # Replace only whole labels: bounded by [, ], comma, -, or whitespace
    # Using $ (end anchor) not \$ (literal dollar sign)
    return replace(s, Regex("(?<=[\\[,\\s-]|^)" * Regex.escape(old) * "(?=[\\],\\s-]|$)") => new)
end
```

**Tickets fixed:** qmng, partially sf4t

### Phase E: InvarDB Dimension-Aware Cache (fixes 2 tickets, low risk)

```julia
# Change from single cached instance:
_invar_db::Union{Nothing,InvarDB} = nothing

# To dimension-keyed cache:
_invar_db_cache::Dict{Int,InvarDB} = Dict{Int,InvarDB}()

# Dispatch caches must also be keyed by dim, since step-5 rules differ per dim:
_perm_dispatch::Dict{Tuple{Int,Vector{Int}}, Dict{Vector{Int},Int}} =
    Dict{Tuple{Int,Vector{Int}}, Dict{Vector{Int},Int}}()
_dual_perm_dispatch::Dict{Tuple{Int,Vector{Int}}, Dict{Vector{Int},Int}} =
    Dict{Tuple{Int,Vector{Int}}, Dict{Vector{Int},Int}}()

function _ensure_invar_db(dbdir::String=""; dim::Int=4)::InvarDB
    global _invar_db_cache
    if !haskey(_invar_db_cache, dim)
        path = isempty(dbdir) ? joinpath(@__DIR__, "..", "resources", "xAct", "Invar") : dbdir
        _invar_db_cache[dim] = LoadInvarDB(path; dim=dim)
    end
    return _invar_db_cache[dim]
end

function _reset_invar_db!()
    empty!(_invar_db_cache)
    empty!(_perm_dispatch)
    empty!(_dual_perm_dispatch)
end
```

**Key change**: Dispatch caches (`_perm_dispatch`, `_dual_perm_dispatch`) are now
keyed by `(dim, case)` instead of just `case`, so dim=3 and dim=4 dispatch entries
don't collide.

**Tickets fixed:** 9b1d, partially 2cr2

### Phase F: Session Context (future, fixes thread safety structurally)

**Goal**: Replace global mutable dicts with a `Session` struct. This is the biggest
refactoring and should be done incrementally.

```julia
"""
    Session

Holds all mutable state for one xAct session. Replaces 15 global dicts.
Enables concurrent sessions, proper reset semantics, and thread safety.
"""
mutable struct Session
    generation::Int  # incremented on reset; objects check this
    manifolds::Dict{Symbol,ManifoldObj}
    vbundles::Dict{Symbol,VBundleObj}
    tensors::Dict{Symbol,TensorObj}
    metrics::Dict{Symbol,MetricObj}
    perturbations::Dict{Symbol,PerturbationObj}
    bases::Dict{Symbol,BasisObj}
    charts::Dict{Symbol,ChartObj}
    basis_changes::Dict{Tuple{Symbol,Symbol},BasisChangeObj{<:Number}}
    ctensors::Dict{Vector{Symbol},CTensorObj{<:Number}}  # was Tuple{Symbol,Vararg{Symbol}}
    traceless_tensors::Set{Symbol}
    trace_scalars::Dict{Symbol,Tuple{Symbol,Rational{Int}}}
    einstein_expansion::Dict{Symbol,Tuple{Symbol,Symbol,Symbol}}
    identity_registry::Dict{Symbol,Vector{MultiTermIdentity}}
    invar_db_cache::Dict{Int,InvarDB}
end
```

Note: `ctensors` uses `Dict{Vector{Symbol},...}` instead of `Tuple{Symbol,Vararg{Symbol}}`
because `Vararg` cannot appear as a struct field type in Julia.

**Migration strategy** (incremental, non-breaking):
1. Create `Session` struct with all fields
2. Create a global `const _default_session = Ref{Session}(Session())`
3. Migrate `def_*!` functions first (they write state) — add `session::Session = _default_session[]` kwarg
4. Then migrate `ToCanonical`/`Contract`/`Simplify` (they read state)
5. Internal helpers can keep using `_default_session[]` until all public functions are migrated
6. `reset_state!()` creates a new Session and increments generation
7. Old code keeps working throughout (uses default session)

**Tickets fixed structurally:** bvh9, ot5x, kgh0, v2sp — all thread safety + stale reference issues

---

## 4. Execution Order

```
┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐
│ Phase A (Validation) │  │ Phase C (Type Fixes) │  │ Phase E (InvarDB)   │
│ low risk, 7 tickets  │  │ low risk, 3 tickets  │  │ low risk, 2 tickets │
└────────┬────────────┘  └────────┬────────────┘  └─────────────────────┘
         │                        │
         │  ┌─────────────────────┤
         │  │                     │
┌────────▼──▼────────┐  ┌────────▼────────────┐
│ Phase B (Bridge)    │  │ Phase D (Index Ops)  │
│ medium risk, 7 tix  │  │ medium risk, 2 tix   │
└────────┬────────────┘  └─────────────────────┘
         │
┌────────▼────────────┐
│ Phase F (Session)    │
│ high effort, 5 tix   │
│ depends on A + C     │
└─────────────────────┘
```

Phases A, C, D, E are independent and can be done in parallel.
Phase B benefits from A (shares identifier regex) but can start independently.
Phase F depends on A (validation) and C (type fixes) being done first.

### Ticket Coverage

| Phase | Tickets Resolved | Contributes To | Effort |
|-------|-----------------|----------------|--------|
| A: Validation | dlw6, jf3w, y1q3, 15uh, e6d3 | 7m5w (Julia side) | 1 session |
| B: Safe Bridge | 7m5w (Python side), 854k, gzqq, b6v1 | iz1u (needs subprocess) | 1-2 sessions |
| C: Type Fixes | le8b, kcci | z1gp (partial) | 1 session |
| D: Index Ops | qmng | sf4t (partial) | 1 session |
| E: InvarDB Cache | 9b1d | 2cr2 (partial) | 1 session |
| F: Session Context | bvh9, ot5x, kgh0, v2sp | | 3-4 sessions |

**Total: 21 unique tickets resolved or contributed to across 6 phases.**

### Verification

After each phase, all existing tests must pass:
- 91 XPerm Julia tests
- 417 XTensor Julia tests
- 648,784 XInvar Julia tests
- 709 Python runner tests

Run benchmarks after Phases A, C, and D to ensure no performance regression
in canonicalization hot paths (XPerm's `_sift_with_cache`, XTensor's `ToCanonical`).

### Risk Mitigation

- **Phase C** changes struct definitions — verify no serialization/persistence layer exists before proceeding
- **Phase F** adds optional kwargs to every function — each function can be migrated and tested individually; if regression found, revert the single function
- **Phase B** replaces 50+ seval call sites — migrate one file at a time (api.py first, then julia_stub.py), run full test suite between
