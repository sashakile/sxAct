"""TOML test file loader with JSON Schema validation.

Public API::

    from sxact.runner.loader import load_test_file

    test_file = load_test_file("path/to/tests.toml")

Raises :class:`LoadError` for missing files, TOML parse errors, and schema
violations.  Error messages always include the offending field path so callers
(and humans) can pinpoint the problem without reading raw exception tracebacks.
"""

from __future__ import annotations

import json
import tomllib
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, cast

import jsonschema
import jsonschema.validators
from elegua import bridge as elegua_bridge

_SCHEMA_PATH = Path(__file__).parent / "schemas" / "test-schema.json"


# ---------------------------------------------------------------------------
# Public error type
# ---------------------------------------------------------------------------


class LoadError(ValueError):
    """Raised when a test file cannot be loaded or fails schema validation.

    Attributes:
        path:   Path to the test file that caused the error (may be None if
                the path itself was invalid).
        field:  JSON-path string to the violating field, e.g.
                ``"$.tests[2].operations[0].action"``.  None when the error
                is not field-specific (e.g. file not found, TOML syntax).
    """

    def __init__(
        self, message: str, *, path: Path | None = None, field: str | None = None
    ) -> None:
        super().__init__(message)
        self.path = path
        self.field = field


# ---------------------------------------------------------------------------
# Data model
# ---------------------------------------------------------------------------


@dataclass
class TestMeta:
    __test__ = False  # prevent pytest from treating this as a test class
    id: str
    description: str
    tags: list[str] = field(default_factory=list)
    layer: int = 1
    oracle_is_axiom: bool = True
    skip: str | None = None
    # Elegua-compatible fields — empty defaults allow IsolatedRunner duck typing
    requires: frozenset[str] = field(default_factory=frozenset)
    tier_overrides: dict[str, frozenset[str]] = field(default_factory=dict)


@dataclass
class Operation:
    action: str
    args: dict[str, Any] = field(default_factory=dict)
    store_as: str | None = None


@dataclass
class ExpectedProperties:
    rank: int | None = None
    symmetry: dict[str, Any] | None = None  # {type: str, slots?: list[int]}
    manifold: str | None = None
    type: str | None = None


@dataclass
class Expected:
    expr: str | None = None
    normalized: str | None = None
    value: Any = None
    is_zero: bool | None = None
    properties: ExpectedProperties | None = None
    comparison_tier: int | None = None
    expect_error: bool | None = None


@dataclass
class TestCase:
    __test__ = False
    id: str
    description: str
    operations: list[Operation]
    tags: list[str] = field(default_factory=list)
    dependencies: list[str] = field(default_factory=list)
    skip: str | None = None
    expected: Expected | None = None


@dataclass
class TestFile:
    __test__ = False
    meta: TestMeta
    setup: list[Operation]
    tests: list[TestCase]
    source_path: Path


# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------


def load_test_file(path: str | Path) -> TestFile:
    """Load and validate a TOML test file.

    Args:
        path: Path to the ``.toml`` test file.

    Returns:
        A :class:`TestFile` populated from the file contents.

    Raises:
        LoadError: If the file is not found, TOML is malformed, or schema
            validation fails.  The ``field`` attribute of the exception
            contains the JSON-path to the offending field when applicable.
    """
    path = Path(path)

    raw = _parse_toml(path)
    _validate_against_schema(raw, path)

    try:
        elegua_file = elegua_bridge.load_test_file(path)
    except Exception as exc:  # pragma: no cover - schema validation should catch this first
        raise LoadError(f"Elegua bridge failed to load {path.name}: {exc}", path=path) from exc

    return _build_from_elegua(elegua_file, path)


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


def _parse_toml(path: Path) -> dict[str, Any]:
    try:
        with open(path, "rb") as fh:
            return tomllib.load(fh)
    except FileNotFoundError as exc:
        raise LoadError(f"Test file not found: {path}", path=path) from exc
    except tomllib.TOMLDecodeError as exc:
        raise LoadError(f"TOML parse error in {path.name}: {exc}", path=path) from exc


def _load_schema() -> dict[str, Any]:
    with open(_SCHEMA_PATH) as fh:
        return cast(dict[str, Any], json.load(fh))


def _validate_against_schema(data: dict[str, Any], source: Path) -> None:
    schema = _load_schema()
    cls = jsonschema.validators.validator_for(schema)
    cls.check_schema(schema)
    validator = cls(schema)

    errors = sorted(validator.iter_errors(data), key=lambda e: list(e.absolute_path))
    if not errors:
        return

    # Report all violations, but raise on the first (most specific) one.
    first = errors[0]
    field_path = _json_path(first)
    details = "; ".join(f"{_json_path(e)}: {e.message}" for e in errors)
    raise LoadError(
        f"Schema validation failed in {source.name} — {details}",
        path=source,
        field=field_path,
    )


def _json_path(error: jsonschema.ValidationError) -> str:
    """Convert a jsonschema error's absolute_path to a $-prefixed JSON path."""
    parts: list[str] = []
    for part in error.absolute_path:
        if isinstance(part, int):
            parts.append(f"[{part}]")
        else:
            parts.append(f".{part}")
    return "$" + "".join(parts) if parts else "$"


# ---------------------------------------------------------------------------
# Object builders
# ---------------------------------------------------------------------------


def _build_from_elegua(elegua_file: elegua_bridge.TestFile, source: Path) -> TestFile:
    """Adapt Elegua's parsed TOML model to sxAct's compatibility dataclasses."""
    return TestFile(
        meta=TestMeta(
            id=elegua_file.meta.id,
            description=elegua_file.meta.description,
            tags=list(elegua_file.meta.tags),
            layer=int(elegua_file.meta.layer),
            oracle_is_axiom=bool(elegua_file.meta.oracle_is_axiom),
            skip=elegua_file.meta.skip,
        ),
        setup=[_build_operation(op) for op in elegua_file.setup],
        tests=[_build_test(tc) for tc in elegua_file.tests],
        source_path=source,
    )


def _build_operation(op: elegua_bridge.Operation) -> Operation:
    return Operation(
        action=op.action,
        args=dict(op.args),
        store_as=op.store_as,
    )


def _build_expected(exp: elegua_bridge.Expected) -> Expected:
    props_raw = exp.properties
    props = None
    if props_raw is not None:
        props = ExpectedProperties(
            rank=props_raw.get("rank"),
            symmetry=props_raw.get("symmetry"),
            manifold=props_raw.get("manifold"),
            type=props_raw.get("type"),
        )
    return Expected(
        expr=exp.expr,
        normalized=exp.normalized,
        value=exp.value,
        is_zero=exp.is_zero,
        properties=props,
        comparison_tier=exp.comparison_tier,
        expect_error=exp.expect_error,
    )


def _build_test(tc: elegua_bridge.TestCase) -> TestCase:
    return TestCase(
        id=tc.id,
        description=tc.description,
        operations=[_build_operation(op) for op in tc.operations],
        tags=list(tc.tags),
        dependencies=list(tc.dependencies),
        skip=tc.skip,
        expected=_build_expected(tc.expected) if tc.expected is not None else None,
    )
