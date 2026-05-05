"""Tests for the elegua L4 numeric sampling comparison layer."""

import pytest
from elegua.comparison import ComparisonPipeline
from elegua.models import ValidationToken
from elegua.task import TaskStatus

from sxact.compare.sampling import TensorContext
from sxact.compare.tensor_objects import Manifold, Metric, TensorField
from sxact.elegua_bridge.comparison_layers import make_compare_numeric
from sxact.oracle.result import Result


class _ZeroOracle:
    """Mock oracle that always reports zero difference (expressions are equal)."""

    def evaluate(self, expr: str) -> Result:
        return Result(status="ok", type="Scalar", repr="0.0", normalized="0.0")


class _NonZeroOracle:
    """Mock oracle that always reports non-zero difference (expressions differ)."""

    def evaluate(self, expr: str) -> Result:
        return Result(status="ok", type="Scalar", repr="1.0", normalized="1.0")


class _FailingOracle:
    """Mock oracle that simulates an execution error."""

    def evaluate(self, expr: str) -> Result:
        return Result(status="error", type="Scalar", repr="", normalized="", error="kernel crash")


def _token(repr_str: str | None) -> ValidationToken:
    result = {"repr": repr_str, "type": "Expr"} if repr_str is not None else None
    return ValidationToken(adapter_id="test", status=TaskStatus.OK, result=result)


class TestMakeCompareNumeric:
    def test_equal_expressions_returns_ok(self) -> None:
        layer = make_compare_numeric(_ZeroOracle())
        a = _token("Sin[x]")
        b = _token("Sin[x]")
        assert layer(a, b) == TaskStatus.OK

    def test_different_expressions_returns_mismatch(self) -> None:
        layer = make_compare_numeric(_NonZeroOracle())
        a = _token("Sin[x]")
        b = _token("Cos[x]")
        assert layer(a, b) == TaskStatus.MATH_MISMATCH

    def test_oracle_failure_returns_mismatch(self) -> None:
        layer = make_compare_numeric(_FailingOracle())
        a = _token("x")
        b = _token("x")
        assert layer(a, b) == TaskStatus.MATH_MISMATCH

    def test_none_result_returns_mismatch(self) -> None:
        layer = make_compare_numeric(_ZeroOracle())
        a = ValidationToken(adapter_id="test", status=TaskStatus.OK, result=None)
        b = _token("x")
        assert layer(a, b) == TaskStatus.MATH_MISMATCH

    def test_missing_repr_key_returns_mismatch(self) -> None:
        layer = make_compare_numeric(_ZeroOracle())
        a = ValidationToken(adapter_id="test", status=TaskStatus.OK, result={"type": "Expr"})
        b = _token("x")
        assert layer(a, b) == TaskStatus.MATH_MISMATCH

    def test_custom_n_and_seed_do_not_crash(self) -> None:
        layer = make_compare_numeric(_ZeroOracle(), n=5, seed=0)
        a = _token("x + y")
        b = _token("x + y")
        assert layer(a, b) == TaskStatus.OK

    def test_none_oracle_raises_at_factory_time(self) -> None:
        with pytest.raises(TypeError, match="oracle must not be None"):
            make_compare_numeric(None)

    def test_tensor_ctx_forwarded(self) -> None:
        manifold = Manifold("M", 2)
        Metric("g", manifold)
        TensorField("T", rank=2, manifold=manifold)
        import numpy as np

        ctx = TensorContext(
            manifolds={"M": manifold},
            metric_arrays={"g": np.eye(2)},
            tensor_arrays={"T": np.eye(2)},
        )
        layer = make_compare_numeric(_ZeroOracle(), tensor_ctx=ctx)
        a = _token("T[-a, -b]")
        b = _token("T[-a, -b]")
        assert layer(a, b) == TaskStatus.OK


class TestPipelineRegistration:
    def test_register_as_l4_and_compare(self) -> None:
        pipeline = ComparisonPipeline()
        pipeline.register(4, "numeric", make_compare_numeric(_ZeroOracle()))

        a = _token("Sin[x]")
        b = _token("Sin[x]")
        result = pipeline.compare(a, b)

        assert result.status == TaskStatus.OK

    def test_l4_reached_only_when_l1_l2_miss(self) -> None:
        pipeline = ComparisonPipeline()
        pipeline.register(4, "numeric", make_compare_numeric(_ZeroOracle()))

        # Structurally different dicts → L1, L2 miss → L4 hits
        a = ValidationToken(
            adapter_id="test",
            status=TaskStatus.OK,
            result={"repr": "Sin[x]", "type": "A"},
        )
        b = ValidationToken(
            adapter_id="test",
            status=TaskStatus.OK,
            result={"repr": "Sin[x]", "type": "B"},
        )
        result = pipeline.compare(a, b)

        assert result.status == TaskStatus.OK
        assert result.layer == 4
