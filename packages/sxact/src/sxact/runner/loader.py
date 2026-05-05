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
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, cast

if sys.version_info >= (3, 11):
    import tomllib
else:
    import tomli as tomllib
import jsonschema
import jsonschema.validators

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
    return _build(raw, path)


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


def _build(data: dict[str, Any], source: Path) -> TestFile:
    return TestFile(
        meta=_build_meta(data["meta"]),
        setup=[_build_operation(op) for op in data.get("setup", [])],
        tests=[_build_test(tc) for tc in data.get("tests", [])],
        source_path=source,
    )


def _build_meta(m: dict[str, Any]) -> TestMeta:
    return TestMeta(
        id=m["id"],
        description=m["description"],
        tags=list(m.get("tags", [])),
        layer=int(m.get("layer", 1)),
        oracle_is_axiom=bool(m.get("oracle_is_axiom", True)),
        skip=m.get("skip"),
    )


def _build_operation(op: dict[str, Any]) -> Operation:
    return Operation(
        action=op["action"],
        args=dict(op.get("args", {})),
        store_as=op.get("store_as"),
    )


def _build_expected(exp: dict[str, Any]) -> Expected:
    props_raw = exp.get("properties")
    props = None
    if props_raw is not None:
        props = ExpectedProperties(
            rank=props_raw.get("rank"),
            symmetry=props_raw.get("symmetry"),
            manifold=props_raw.get("manifold"),
            type=props_raw.get("type"),
        )
    return Expected(
        expr=exp.get("expr"),
        normalized=exp.get("normalized"),
        value=exp.get("value"),
        is_zero=exp.get("is_zero"),
        properties=props,
        comparison_tier=exp.get("comparison_tier"),
        expect_error=exp.get("expect_error"),
    )


def _build_test(tc: dict[str, Any]) -> TestCase:
    expected_raw = tc.get("expected")
    return TestCase(
        id=tc["id"],
        description=tc["description"],
        operations=[_build_operation(op) for op in tc["operations"]],
        tags=list(tc.get("tags", [])),
        dependencies=list(tc.get("dependencies", [])),
        skip=tc.get("skip"),
        expected=_build_expected(expected_raw) if expected_raw is not None else None,
    )
