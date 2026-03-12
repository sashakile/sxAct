"""Layer 2 property test runner.

Loads property TOML files (layer = "property"), generates samples from
declared generators, substitutes $var references into law expressions, and
validates lhs == rhs via the adapter.

Supported equivalence types:
  - "identical"            : `(lhs) === (rhs)` must evaluate to True
  - "numerical_tolerance"  : `Max[Abs[Flatten[N[(lhs) - (rhs)]]]]` must be < tol

Supported generator strategies:
  - "fresh_symbol"         : unique xCore symbol with no dagger character
  - "symbol_list"          : Wolfram list of N fresh symbols (allow_duplicates optional)
"""

from __future__ import annotations

import random
import re
import string
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import tomli


# ---------------------------------------------------------------------------
# Data model
# ---------------------------------------------------------------------------


@dataclass
class GeneratorSpec:
    name: str
    type: str  # "Symbol", "SymbolList"
    strategy: str  # "fresh_symbol", "symbol_list"
    length: int = 3
    allow_duplicates: bool = False


@dataclass
class PropertySpec:
    id: str
    name: str
    tags: list[str]
    generators: list[GeneratorSpec]
    lhs: str
    rhs: str
    equivalence_type: str  # "identical" | "numerical_tolerance"
    num_samples: int
    random_seed: int
    tolerance: float = 1e-10
    skip_adapters: list[str] = field(default_factory=list)


@dataclass
class PropertyFile:
    path: Path
    description: str
    setup: list[dict[str, Any]]  # raw setup action dicts
    properties: list[PropertySpec]


@dataclass
class Counterexample:
    sample_index: int
    bindings: dict[str, str]  # generator name → generated value (Wolfram repr)
    lhs_expr: str
    rhs_expr: str
    lhs_result: str
    rhs_result: str


@dataclass
class PropertyResult:
    property_id: str
    name: str
    status: str  # "pass", "partial", "fail", "error", "skip"
    num_samples: int
    num_passed: int
    confidence: float = 0.0  # num_passed / num_samples; 0.0 when num_samples == 0
    counterexample: Counterexample | None = None
    message: str | None = None
    cross_adapter_diff: dict[str, str] | None = None


@dataclass
class PropertyFileResult:
    file_path: str
    description: str
    results: list[PropertyResult] = field(default_factory=list)


# ---------------------------------------------------------------------------
# TOML loader
# ---------------------------------------------------------------------------


class PropertyLoadError(ValueError):
    pass


def load_property_file(path: Path) -> PropertyFile:
    """Parse a property TOML file into a PropertyFile dataclass."""
    try:
        raw = tomli.loads(path.read_text())
    except Exception as exc:
        raise PropertyLoadError(f"TOML parse error in {path}: {exc}") from exc

    if raw.get("layer") != "property":
        raise PropertyLoadError(
            f"{path}: not a property file (layer = {raw.get('layer')!r}, expected 'property')"
        )

    setup = raw.get("setup", [])
    if isinstance(setup, dict):
        setup = [setup]

    props: list[PropertySpec] = []
    for p in raw.get("properties", []):
        gens = []
        forall = p.get("forall", {})
        for g in forall.get("generators", []):
            gens.append(
                GeneratorSpec(
                    name=g["name"],
                    type=g.get("type", "Symbol"),
                    strategy=g.get("strategy", "fresh_symbol"),
                    length=g.get("length", 3),
                    allow_duplicates=g.get("allow_duplicates", False),
                )
            )

        law = p.get("law", {})
        verification = p.get("verification", {})
        props.append(
            PropertySpec(
                id=p["id"],
                name=p.get("name", p["id"]),
                tags=p.get("tags", []),
                generators=gens,
                lhs=law.get("lhs", ""),
                rhs=law.get("rhs", ""),
                equivalence_type=law.get("equivalence_type", "identical"),
                num_samples=verification.get("num_samples", 10),
                random_seed=verification.get("random_seed", 0),
                tolerance=verification.get("tolerance", 1e-10),
                skip_adapters=p.get("skip_adapters", []),
            )
        )

    return PropertyFile(
        path=path,
        description=raw.get("description", ""),
        setup=setup,
        properties=props,
    )


# ---------------------------------------------------------------------------
# Symbol generation
# ---------------------------------------------------------------------------

_LOWER = string.ascii_lowercase


def _fresh_symbol(prefix: str, n: int) -> str:
    """Return a unique Wolfram symbol name safe for xCore operations.

    Uses a deterministic prefix so different tests don't collide.
    E.g. fresh_symbol("pxA", 3) → "pxAc"  (base-26 encoding of 3)
    """
    # Encode n in base-26 using lowercase letters to stay short
    if n == 0:
        suffix = "a"
    else:
        digits = []
        x = n
        while x > 0:
            digits.append(_LOWER[x % 26])
            x //= 26
        suffix = "".join(reversed(digits))
    return prefix + suffix


def _generate_value(gen: GeneratorSpec, prefix: str, sample_idx: int) -> str:
    """Generate a Wolfram-syntax value string for a single generator."""
    # Scalar generators produce small integers (non-zero) for numeric substitution.
    # This allows scalar-tensor distributivity and similar algebraic properties
    # to be verified via symbolic canonicalization.
    if gen.type == "Scalar":
        rng = random.Random(sample_idx)
        val = rng.randint(1, 9)
        return str(val)

    if gen.strategy == "fresh_symbol":
        # Unique symbol: prefix + generator name + sample index
        sym = _fresh_symbol(f"px{prefix}{gen.name}", sample_idx)
        return sym

    if gen.strategy == "symbol_list":
        pool_size = gen.length if not gen.allow_duplicates else gen.length * 2
        pool = [
            _fresh_symbol(f"px{prefix}{gen.name}", sample_idx * 100 + i)
            for i in range(pool_size)
        ]
        if gen.allow_duplicates:
            # Mix in some duplicates deterministically
            rng = random.Random(sample_idx)
            chosen = [rng.choice(pool) for _ in range(gen.length)]
        else:
            chosen = pool[: gen.length]
        return "{" + ", ".join(chosen) + "}"

    raise PropertyLoadError(f"Unknown generator strategy: {gen.strategy!r}")


# ---------------------------------------------------------------------------
# Expression substitution
# ---------------------------------------------------------------------------

_VAR_RE = re.compile(r"\$([a-zA-Z_][a-zA-Z0-9_]*)")


def _substitute(expr: str, bindings: dict[str, str]) -> str:
    """Replace $name references with their bound values."""

    def repl(m: re.Match[str]) -> str:
        name = m.group(1)
        if name not in bindings:
            raise KeyError(f"Unbound variable ${name} in expression: {expr!r}")
        return bindings[name]

    return _VAR_RE.sub(repl, expr)


# ---------------------------------------------------------------------------
# Core runner
# ---------------------------------------------------------------------------


def run_property_file(
    prop_file: PropertyFile,
    adapter: Any,
    tag_filter: str | None = None,
    adapter_name: str = "",
) -> PropertyFileResult:
    """Run all properties in a PropertyFile against the given adapter."""
    file_result = PropertyFileResult(
        file_path=str(prop_file.path),
        description=prop_file.description,
    )

    ctx = adapter.initialize()
    try:
        # Execute setup actions (e.g. DefManifold, DefTensor)
        for action_dict in prop_file.setup:
            action = action_dict.get("action", "")
            args = action_dict.get("args", {})
            try:
                adapter.execute(ctx, action, args)
            except Exception as exc:
                # Setup failure → all properties in file are errors
                for spec in prop_file.properties:
                    file_result.results.append(
                        PropertyResult(
                            property_id=spec.id,
                            name=spec.name,
                            status="error",
                            num_samples=0,
                            num_passed=0,
                            message=f"setup action {action!r} failed: {exc}",
                        )
                    )
                return file_result

        for spec in prop_file.properties:
            if tag_filter and tag_filter not in spec.tags:
                continue
            if adapter_name and adapter_name in spec.skip_adapters:
                file_result.results.append(
                    PropertyResult(
                        property_id=spec.id,
                        name=spec.name,
                        status="skip",
                        num_samples=0,
                        num_passed=0,
                        message=f"skipped for adapter {adapter_name!r}",
                    )
                )
                continue
            result = _run_property(spec, adapter, ctx)
            file_result.results.append(result)
    finally:
        adapter.teardown(ctx)

    return file_result


def _run_property(
    spec: PropertySpec,
    adapter: Any,
    ctx: Any,
) -> PropertyResult:
    """Run a single property across all samples."""
    num_passed = 0
    counterexample: Counterexample | None = None

    # Derive a short unique prefix from seed + id to avoid symbol collisions
    # across different property files run in the same session
    prefix_seed = (spec.random_seed ^ hash(spec.id)) & 0xFFFF
    prefix = _fresh_symbol("", prefix_seed)[:3].upper()

    for i in range(spec.num_samples):
        sample_idx = spec.random_seed + i

        # Generate bindings for all generators
        try:
            bindings: dict[str, str] = {
                gen.name: _generate_value(gen, prefix, sample_idx)
                for gen in spec.generators
            }
        except Exception as exc:
            return PropertyResult(
                property_id=spec.id,
                name=spec.name,
                status="error",
                num_samples=i,
                num_passed=num_passed,
                message=f"generator error: {exc}",
            )

        # Substitute $var in lhs and rhs
        try:
            lhs_expr = _substitute(spec.lhs, bindings)
            rhs_expr = _substitute(spec.rhs, bindings)
        except KeyError as exc:
            return PropertyResult(
                property_id=spec.id,
                name=spec.name,
                status="error",
                num_samples=i,
                num_passed=num_passed,
                message=f"substitution error: {exc}",
            )

        # Build comparison expression
        if spec.equivalence_type == "identical":
            cmp_expr = f"({lhs_expr}) === ({rhs_expr})"
        elif spec.equivalence_type == "numerical_tolerance":
            cmp_expr = f"Max[Abs[Flatten[N[({lhs_expr}) - ({rhs_expr})]]]]"
        else:
            return PropertyResult(
                property_id=spec.id,
                name=spec.name,
                status="error",
                num_samples=spec.num_samples,
                num_passed=0,
                message=f"unknown equivalence_type: {spec.equivalence_type!r}",
            )

        # Execute via adapter
        try:
            result = adapter.execute(ctx, "Evaluate", {"expression": cmp_expr})
        except Exception as exc:
            return PropertyResult(
                property_id=spec.id,
                name=spec.name,
                status="error",
                num_samples=i + 1,
                num_passed=num_passed,
                message=f"adapter execute error: {exc}",
            )

        if result.status != "ok":
            return PropertyResult(
                property_id=spec.id,
                name=spec.name,
                status="error",
                num_samples=i + 1,
                num_passed=num_passed,
                message=f"sample {i}: adapter returned error: {result.error}",
            )

        passed = _check_result(result.repr, spec.equivalence_type, spec.tolerance)

        if passed:
            num_passed += 1
        elif counterexample is None:
            # Capture first counterexample
            lhs_result = _eval_single(adapter, ctx, lhs_expr)
            rhs_result = _eval_single(adapter, ctx, rhs_expr)
            counterexample = Counterexample(
                sample_index=i,
                bindings=bindings,
                lhs_expr=lhs_expr,
                rhs_expr=rhs_expr,
                lhs_result=lhs_result,
                rhs_result=rhs_result,
            )

    if num_passed == spec.num_samples:
        status = "pass"
    elif num_passed == 0:
        status = "fail"
    else:
        status = "partial"
    confidence = num_passed / spec.num_samples if spec.num_samples > 0 else 0.0
    return PropertyResult(
        property_id=spec.id,
        name=spec.name,
        status=status,
        num_samples=spec.num_samples,
        num_passed=num_passed,
        confidence=confidence,
        counterexample=counterexample if status != "pass" else None,
    )


def _check_result(repr_str: str, equivalence_type: str, tolerance: float) -> bool:
    """Return True if the comparison result indicates the law holds."""
    s = repr_str.strip()
    if equivalence_type == "identical":
        return s == "True"
    if equivalence_type == "numerical_tolerance":
        try:
            return abs(float(s)) < tolerance
        except ValueError:
            return False
    return False


def _eval_single(adapter: Any, ctx: Any, expr: str) -> str:
    """Evaluate a single expression and return its repr string."""
    try:
        result = adapter.execute(ctx, "Evaluate", {"expression": expr})
        return result.repr if result.status == "ok" else f"<error: {result.error}>"
    except Exception as exc:
        return f"<exception: {exc}>"
