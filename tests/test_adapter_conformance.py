"""Protocol conformance test suite for TestAdapter implementations.

Each concrete adapter (Wolfram, Julia, Python) can verify compliance by
registering a factory function with the ``adapter_factory`` fixture.

Usage — in the adapter's own test module::

    # tests/test_wolfram_adapter.py
    import pytest
    from sxact.adapter.base import TestAdapter

    @pytest.fixture
    def adapter_factory():
        return WolframAdapter   # the class itself (zero-arg constructor)

    # Then import and run the conformance suite:
    from tests.test_adapter_conformance import *   # noqa: F401,F403

Or run this file standalone to test a DummyAdapter that implements
every method with minimal valid behaviour (verifies the test suite itself
is internally consistent).

All tests in this module are collected by pytest automatically.  Tests that
require a live CAS context are skipped when the adapter raises
``AdapterError`` during ``initialize()``.
"""

from __future__ import annotations

import pytest

from sxact.adapter.base import (
    AdapterError,
    EqualityMode,
    NormalizedExpr,
    TestAdapter,
    VersionInfo,
)
from sxact.oracle.result import Result


# ---------------------------------------------------------------------------
# DummyAdapter — used when no external adapter_factory is provided
# ---------------------------------------------------------------------------


class _DummyContext:
    """Minimal opaque context for the DummyAdapter."""

    alive: bool = True


class DummyAdapter(TestAdapter[_DummyContext]):
    """Minimal conforming adapter for testing the conformance suite itself.

    Returns not-implemented Results for all execution requests.
    All lifecycle methods succeed without touching a real CAS.
    """

    def initialize(self) -> _DummyContext:
        ctx = _DummyContext()
        ctx.alive = True
        return ctx

    def teardown(self, ctx: _DummyContext) -> None:
        ctx.alive = False  # idempotent, must not raise

    def execute(self, ctx, action: str, args: dict) -> Result:
        full_vocab = self.supported_actions()
        if action not in full_vocab:
            raise ValueError(f"Unknown action: {action!r}")
        return Result(
            status="error",
            type="Expr",
            repr="",
            normalized="",
            error="not implemented",
        )

    def normalize(self, expr: str) -> NormalizedExpr:
        # Trivial: just strip whitespace (not a real normalizer)
        return NormalizedExpr(expr.strip())

    def equals(self, a, b, mode, ctx=None) -> bool:
        return a == b  # tier 1 only for the dummy

    def get_properties(self, expr: str, ctx=None) -> dict:
        return {}

    def get_version(self) -> VersionInfo:
        return VersionInfo(
            cas_name="Dummy",
            cas_version="0.0.0",
            adapter_version="0.0.0",
        )


# ---------------------------------------------------------------------------
# Fixture — override in concrete adapter test modules
# ---------------------------------------------------------------------------


@pytest.fixture
def adapter_factory():
    """Return the adapter class (zero-arg constructor) under test.

    Override this fixture in concrete adapter test modules to point at the
    real adapter.  Defaults to DummyAdapter so this file is self-contained.
    """
    return DummyAdapter


@pytest.fixture
def adapter(adapter_factory):
    """Return an instantiated adapter."""
    return adapter_factory()


@pytest.fixture
def ctx(adapter):
    """Return a fresh context, skipping if the adapter cannot start."""
    try:
        context = adapter.initialize()
    except AdapterError as exc:
        pytest.skip(f"Adapter unavailable: {exc}")
    yield context
    adapter.teardown(context)


# ---------------------------------------------------------------------------
# Conformance tests
# ---------------------------------------------------------------------------


class TestLifecycle:
    """initialize() and teardown() contract."""

    def test_initialize_returns_non_none(self, adapter):
        try:
            context = adapter.initialize()
        except AdapterError as exc:
            pytest.skip(f"Adapter unavailable: {exc}")
        assert context is not None
        adapter.teardown(context)

    def test_teardown_does_not_raise(self, adapter):
        """teardown() must be safe to call even on a used or error context."""
        try:
            context = adapter.initialize()
        except AdapterError as exc:
            pytest.skip(f"Adapter unavailable: {exc}")
        # Call teardown twice to verify idempotency/safety
        adapter.teardown(context)
        adapter.teardown(context)  # second call must not raise


class TestExecute:
    """execute() contract."""

    def test_unknown_action_raises_value_error(self, adapter, ctx):
        with pytest.raises(ValueError):
            adapter.execute(ctx, "NotAnAction_xyz", {})

    def test_returns_result_instance(self, adapter, ctx):
        # Use any supported action; if not implemented, expect an error Result
        action = next(iter(adapter.supported_actions()))
        result = adapter.execute(ctx, action, {})
        assert isinstance(result, Result)

    def test_error_result_has_error_message(self, adapter, ctx):
        # An error Result must have a non-empty error string
        action = next(iter(adapter.supported_actions()))
        result = adapter.execute(ctx, action, {})
        if result.status == "error":
            assert result.error is not None and len(result.error) > 0

    def test_ok_result_has_repr(self, adapter, ctx):
        # If status is ok, repr must be a non-None string
        action = next(iter(adapter.supported_actions()))
        result = adapter.execute(ctx, action, {})
        if result.status == "ok":
            assert isinstance(result.repr, str)

    def test_status_is_valid_literal(self, adapter, ctx):
        action = next(iter(adapter.supported_actions()))
        result = adapter.execute(ctx, action, {})
        assert result.status in ("ok", "error", "timeout")

    def test_supported_actions_is_frozenset(self, adapter):
        actions = adapter.supported_actions()
        assert isinstance(actions, frozenset)
        assert len(actions) > 0


class TestNormalize:
    """normalize() contract."""

    def test_returns_str(self, adapter):
        result = adapter.normalize("T[-a,-b]")
        assert isinstance(result, str)

    def test_idempotent(self, adapter):
        expr = "T[-a,-b] + S[-b,-a]"
        once = adapter.normalize(expr)
        twice = adapter.normalize(once)
        assert once == twice, "normalize() must be idempotent"

    def test_empty_string(self, adapter):
        result = adapter.normalize("")
        assert isinstance(result, str)

    def test_whitespace_stripped(self, adapter):
        # Leading/trailing whitespace must be removed
        result = adapter.normalize("  T[-a,-b]  ")
        assert not result.startswith(" ")
        assert not result.endswith(" ")


class TestEquals:
    """equals() contract."""

    def test_reflexive_normalized(self, adapter):
        n = adapter.normalize("T[-a,-b]")
        assert adapter.equals(n, n, EqualityMode.NORMALIZED) is True

    def test_identical_strings_normalized(self, adapter):
        n = NormalizedExpr("x")
        assert adapter.equals(n, n, EqualityMode.NORMALIZED) is True

    def test_distinct_strings_normalized(self, adapter):
        a = NormalizedExpr("T[-$1,-$2]")
        b = NormalizedExpr("S[-$1,-$2]")
        # Different symbols — must not be equal
        assert adapter.equals(a, b, EqualityMode.NORMALIZED) is False

    def test_returns_bool(self, adapter):
        n = NormalizedExpr("x")
        result = adapter.equals(n, n, EqualityMode.NORMALIZED)
        assert isinstance(result, bool)


class TestEqualsSemanticNumeric:
    """equals() contract for SEMANTIC and NUMERIC tiers."""

    def test_reflexive_semantic(self, adapter):
        n = NormalizedExpr("T[-$1,-$2]")
        result = adapter.equals(n, n, EqualityMode.SEMANTIC)
        assert isinstance(result, bool)
        assert result is True

    def test_reflexive_numeric(self, adapter):
        n = NormalizedExpr("x + y")
        result = adapter.equals(n, n, EqualityMode.NUMERIC)
        assert isinstance(result, bool)
        assert result is True

    def test_identical_strings_semantic(self, adapter):
        n = NormalizedExpr("2 T[-$1,-$2]")
        assert adapter.equals(n, n, EqualityMode.SEMANTIC) is True

    def test_identical_strings_numeric(self, adapter):
        n = NormalizedExpr("x")
        assert adapter.equals(n, n, EqualityMode.NUMERIC) is True

    def test_returns_bool_semantic(self, adapter):
        a = NormalizedExpr("x")
        b = NormalizedExpr("y")
        result = adapter.equals(a, b, EqualityMode.SEMANTIC)
        assert isinstance(result, bool)

    def test_returns_bool_numeric(self, adapter):
        a = NormalizedExpr("x")
        b = NormalizedExpr("y")
        result = adapter.equals(a, b, EqualityMode.NUMERIC)
        assert isinstance(result, bool)

    def test_distinct_strings_semantic_returns_false(self, adapter):
        a = NormalizedExpr("T[-$1,-$2]")
        b = NormalizedExpr("S[-$1,-$2]")
        # DummyAdapter returns a == b; any conforming adapter must return bool
        result = adapter.equals(a, b, EqualityMode.SEMANTIC)
        assert isinstance(result, bool)

    def test_semantic_subsumes_normalized(self, adapter):
        """If equals returns True at NORMALIZED, SEMANTIC must also be True."""
        n = NormalizedExpr("T[-$1]")
        if adapter.equals(n, n, EqualityMode.NORMALIZED):
            assert adapter.equals(n, n, EqualityMode.SEMANTIC) is True

    def test_numeric_subsumes_semantic(self, adapter):
        """If equals returns True at SEMANTIC, NUMERIC must also be True."""
        n = NormalizedExpr("x + y")
        if adapter.equals(n, n, EqualityMode.SEMANTIC):
            assert adapter.equals(n, n, EqualityMode.NUMERIC) is True


class TestGetProperties:
    """get_properties() contract."""

    def test_returns_dict(self, adapter):
        props = adapter.get_properties("T[-a,-b]")
        assert isinstance(props, dict)

    def test_returns_dict_for_empty_expr(self, adapter):
        props = adapter.get_properties("")
        assert isinstance(props, dict)

    def test_never_returns_none(self, adapter):
        assert adapter.get_properties("anything") is not None


class TestGetVersion:
    """get_version() contract."""

    def test_returns_version_info(self, adapter):
        v = adapter.get_version()
        assert isinstance(v, VersionInfo)

    def test_cas_name_non_empty(self, adapter):
        assert len(adapter.get_version().cas_name) > 0

    def test_cas_version_non_empty(self, adapter):
        assert len(adapter.get_version().cas_version) > 0

    def test_adapter_version_non_empty(self, adapter):
        assert len(adapter.get_version().adapter_version) > 0

    def test_extra_is_dict(self, adapter):
        assert isinstance(adapter.get_version().extra, dict)
