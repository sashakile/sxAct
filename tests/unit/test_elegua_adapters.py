"""Tests for EleguaPythonAdapter and EleguaJuliaAdapter (elegua.Adapter wrappers)."""

from __future__ import annotations

from typing import Any

import pytest

from elegua.adapter import Adapter
from elegua.models import ValidationToken
from elegua.task import EleguaTask, TaskStatus
from sxact.elegua_bridge.adapters import EleguaJuliaAdapter, EleguaPythonAdapter
from sxact.oracle.result import Result


# ---------------------------------------------------------------------------
# Stub inner adapters (no Julia required)
# ---------------------------------------------------------------------------


class _StubContext:
    pass


class _StubInner:
    """Stub that mimics the TestAdapter execute(ctx, action, args) -> Result API."""

    def __init__(self, result: Result | None = None) -> None:
        self._result = result or Result(status="ok", type="Expr", repr="42", normalized="42")
        self.last_action: str | None = None
        self.last_args: dict[str, Any] | None = None
        self.initialized = False
        self.torn_down = False

    def initialize(self) -> _StubContext:
        self.initialized = True
        return _StubContext()

    def teardown(self, ctx: _StubContext) -> None:
        self.torn_down = True

    def execute(self, ctx: _StubContext, action: str, args: dict[str, Any]) -> Result:
        self.last_action = action
        self.last_args = args
        return self._result


# ---------------------------------------------------------------------------
# EleguaPythonAdapter tests
# ---------------------------------------------------------------------------


class TestEleguaPythonAdapterConformance:
    def test_is_elegua_adapter(self) -> None:
        assert issubclass(EleguaPythonAdapter, Adapter)

    def test_adapter_id(self) -> None:
        stub = _StubInner()
        adapter = EleguaPythonAdapter(stub)
        assert adapter.adapter_id == "python"

    def test_execute_not_initialized_returns_error(self) -> None:
        adapter = EleguaPythonAdapter(_StubInner())
        task = EleguaTask(action="Evaluate", payload={"expression": "1+1"})
        token = adapter.execute(task)
        assert token.status == TaskStatus.EXECUTION_ERROR

    def test_initialize_then_execute_returns_ok(self) -> None:
        stub = _StubInner(Result(status="ok", type="Expr", repr="2", normalized="2"))
        adapter = EleguaPythonAdapter(stub)
        adapter.initialize()
        task = EleguaTask(action="Evaluate", payload={"expression": "1+1"})
        token = adapter.execute(task)
        assert token.status == TaskStatus.OK
        assert token.result is not None
        assert token.result["repr"] == "2"

    def test_execute_forwards_action_and_payload(self) -> None:
        stub = _StubInner()
        adapter = EleguaPythonAdapter(stub)
        adapter.initialize()
        task = EleguaTask(action="Assert", payload={"condition": "x == 1"})
        adapter.execute(task)
        assert stub.last_action == "Assert"
        assert stub.last_args == {"condition": "x == 1"}

    def test_teardown_calls_inner(self) -> None:
        stub = _StubInner()
        adapter = EleguaPythonAdapter(stub)
        adapter.initialize()
        adapter.teardown()
        assert stub.torn_down

    def test_teardown_before_initialize_is_safe(self) -> None:
        adapter = EleguaPythonAdapter(_StubInner())
        adapter.teardown()  # must not raise

    def test_result_error_maps_to_execution_error(self) -> None:
        stub = _StubInner(
            Result(status="error", type="", repr="", normalized="", error="boom")
        )
        adapter = EleguaPythonAdapter(stub)
        adapter.initialize()
        task = EleguaTask(action="Evaluate", payload={"expression": "bad"})
        token = adapter.execute(task)
        assert token.status == TaskStatus.EXECUTION_ERROR
        assert token.metadata.get("error") == "boom"

    def test_context_manager_protocol(self) -> None:
        stub = _StubInner()
        adapter = EleguaPythonAdapter(stub)
        with adapter as a:
            assert a is adapter
        assert stub.initialized
        assert stub.torn_down

    def test_double_initialize_raises(self) -> None:
        adapter = EleguaPythonAdapter(_StubInner())
        adapter.initialize()
        with pytest.raises(RuntimeError, match="already initialized"):
            adapter.initialize()

    def test_timeout_result_maps_to_timeout_status(self) -> None:
        stub = _StubInner(Result(status="timeout", type="", repr="", normalized=""))
        adapter = EleguaPythonAdapter(stub)
        adapter.initialize()
        task = EleguaTask(action="Evaluate", payload={"expression": "slow"})
        token = adapter.execute(task)
        assert token.status == TaskStatus.TIMEOUT


# ---------------------------------------------------------------------------
# EleguaJuliaAdapter tests
# ---------------------------------------------------------------------------


class _JuliaStubContext:
    """Stub context that mimics _JuliaContext for testing."""

    def __init__(self) -> None:
        self.alive = True
        self._manifolds: list[Any] = []
        self._metrics: list[Any] = []
        self._tensors: list[Any] = []


class _JuliaStubInner:
    """Stub that mimics JuliaAdapter's execute(ctx, action, args) -> Result."""

    def __init__(self, result: Result | None = None) -> None:
        self._result = result or Result(
            status="ok", type="Expr", repr="T[-a]", normalized="T[-$1]"
        )

    def initialize(self) -> _JuliaStubContext:
        return _JuliaStubContext()

    def teardown(self, ctx: _JuliaStubContext) -> None:
        ctx.alive = False

    def execute(
        self, ctx: _JuliaStubContext, action: str, args: dict[str, Any]
    ) -> Result:
        return self._result

    def get_tensor_context(self, ctx: _JuliaStubContext, rng: Any = None) -> Any:
        from sxact.compare.sampling import TensorContext

        return TensorContext()


class TestEleguaJuliaAdapterConformance:
    def test_is_elegua_adapter(self) -> None:
        assert issubclass(EleguaJuliaAdapter, Adapter)

    def test_adapter_id(self) -> None:
        adapter = EleguaJuliaAdapter(_JuliaStubInner())
        assert adapter.adapter_id == "julia"

    def test_execute_returns_validation_token(self) -> None:
        adapter = EleguaJuliaAdapter(_JuliaStubInner())
        adapter.initialize()
        task = EleguaTask(action="ToCanonical", payload={"expression": "T[-a,-b]"})
        token = adapter.execute(task)
        assert isinstance(token, ValidationToken)
        assert token.adapter_id == "julia"

    def test_get_tensor_context_delegated(self) -> None:
        from sxact.compare.sampling import TensorContext

        adapter = EleguaJuliaAdapter(_JuliaStubInner())
        adapter.initialize()
        ctx = adapter.get_tensor_context()
        assert isinstance(ctx, TensorContext)

    def test_get_tensor_context_before_initialize_raises(self) -> None:
        adapter = EleguaJuliaAdapter(_JuliaStubInner())
        with pytest.raises(RuntimeError, match="before initialize"):
            adapter.get_tensor_context()
