"""Elegua-compatible adapter wrappers for sxAct CAS backends.

Wraps the sxact TestAdapter implementations (JuliaAdapter, PythonAdapter)
as elegua.Adapter subclasses, mapping the context-carrying TestAdapter
interface to elegua's context-free Adapter ABC:

    TestAdapter.initialize() -> ContextT   →   Adapter.initialize() -> None
    TestAdapter.teardown(ctx)              →   Adapter.teardown() -> None
    TestAdapter.execute(ctx, action, args) →   Adapter.execute(task) -> ValidationToken

Context is stored as instance state so the elegua interface (no context arg)
remains satisfied. Each adapter instance is single-use per session
(initialize → [execute*] → teardown).
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from elegua.adapter import Adapter
from elegua.models import ValidationToken
from elegua.task import EleguaTask, TaskStatus

if TYPE_CHECKING:
    from sxact.compare.sampling import TensorContext
    from sxact.oracle.result import Result


def _result_to_token(adapter_id: str, result: Result) -> ValidationToken:
    """Map a sxact Result to an elegua ValidationToken."""
    if result.status == "ok":
        status = TaskStatus.OK
    elif result.status == "timeout":
        status = TaskStatus.TIMEOUT
    else:
        status = TaskStatus.EXECUTION_ERROR

    result_dict: dict[str, Any] = {
        "repr": result.repr,
        "type": result.type,
    }
    if result.properties:
        result_dict["properties"] = result.properties

    metadata: dict[str, Any] = {}
    if result.error:
        metadata["error"] = result.error
    if result.diagnostics:
        metadata.update(result.diagnostics)

    return ValidationToken(
        adapter_id=adapter_id,
        status=status,
        result=result_dict,
        metadata=metadata,
    )


class _EleguaAdapterBase(Adapter):
    """Shared lifecycle logic for elegua-wrapped sxact adapters.

    Subclasses must set ``self._inner`` and implement ``adapter_id``.
    """

    _inner: Any
    _ctx: Any

    def initialize(self) -> None:
        if self._ctx is not None:
            raise RuntimeError(
                f"{type(self).__name__} already initialized — call teardown() first"
            )
        self._ctx = self._inner.initialize()

    def teardown(self) -> None:
        if self._ctx is not None:
            try:
                self._inner.teardown(self._ctx)
            finally:
                self._ctx = None

    def execute(self, task: EleguaTask) -> ValidationToken:
        if self._ctx is None:
            return ValidationToken(
                adapter_id=self.adapter_id,
                status=TaskStatus.EXECUTION_ERROR,
                metadata={"error": "Adapter not initialized — call initialize() first"},
            )
        result = self._inner.execute(self._ctx, task.action, task.payload)
        return _result_to_token(self.adapter_id, result)


class EleguaPythonAdapter(_EleguaAdapterBase):
    """elegua.Adapter wrapper around sxact's PythonAdapter (xact-py / Julia backend).

    Accepts an optional ``inner`` adapter for dependency injection (primarily for
    testing without a live Julia runtime).  If omitted, creates a
    ``PythonAdapter()`` instance.
    """

    def __init__(self, inner: Any | None = None) -> None:
        if inner is None:
            from sxact.adapter.python_adapter import PythonAdapter

            inner = PythonAdapter()
        self._inner = inner
        self._ctx: Any = None

    @property
    def adapter_id(self) -> str:
        return "python"


class EleguaJuliaAdapter(_EleguaAdapterBase):
    """elegua.Adapter wrapper around sxact's JuliaAdapter (Julia XCore + XTensor backend).

    Accepts an optional ``inner`` adapter for dependency injection (primarily for
    testing without a live Julia runtime).  If omitted, creates a
    ``JuliaAdapter()`` instance.
    """

    def __init__(self, inner: Any | None = None) -> None:
        if inner is None:
            from sxact.adapter.julia_stub import JuliaAdapter

            inner = JuliaAdapter()
        self._inner = inner
        self._ctx: Any = None

    @property
    def adapter_id(self) -> str:
        return "julia"

    def get_tensor_context(self, rng: Any = None) -> TensorContext:
        """Build a TensorContext from accumulated manifold/tensor state.

        Only meaningful after ``DefManifold`` / ``DefMetric`` / ``DefTensor``
        calls have been executed.  Delegates to the inner ``JuliaAdapter``'s
        ``get_tensor_context(ctx, rng)`` method.

        Raises:
            RuntimeError: if called before ``initialize()``.
        """
        if self._ctx is None:
            raise RuntimeError("get_tensor_context() called before initialize()")
        return self._inner.get_tensor_context(self._ctx, rng)
