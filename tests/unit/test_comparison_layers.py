"""Tests for sxact elegua_bridge comparison layer functions."""

from elegua.comparison import ComparisonPipeline
from elegua.models import ValidationToken
from elegua.task import TaskStatus

from sxact.elegua_bridge.comparison_layers import compare_canonical


def _token(repr_str: str | None) -> ValidationToken:
    result = {"repr": repr_str, "type": "Expr"} if repr_str is not None else None
    return ValidationToken(adapter_id="test", status=TaskStatus.OK, result=result)


class TestCompareCanonical:
    def test_identical_expressions_equal(self) -> None:
        a = _token("T[-$1, -$2]")
        assert compare_canonical(a, a) == TaskStatus.OK

    def test_same_structure_different_index_names(self) -> None:
        # Core requirement: T[-a,-b] ≡ T[-x,-y] after canonicalization
        a = _token("T[-a, -b]")
        b = _token("T[-x, -y]")
        assert compare_canonical(a, b) == TaskStatus.OK

    def test_commutative_sum_plus_fullform(self) -> None:
        # Plus[A[a], B[b]] ≡ Plus[B[a], A[b]]
        a = _token("Plus[A[a], B[b]]")
        b = _token("Plus[B[a], A[b]]")
        assert compare_canonical(a, b) == TaskStatus.OK

    def test_different_expressions_mismatch(self) -> None:
        a = _token("T[-a, -b]")
        b = _token("S[-a, -b]")
        assert compare_canonical(a, b) == TaskStatus.MATH_MISMATCH

    def test_missing_repr_key(self) -> None:
        a = ValidationToken(adapter_id="test", status=TaskStatus.OK, result={"type": "Expr"})
        b = _token("T[-a]")
        assert compare_canonical(a, b) == TaskStatus.MATH_MISMATCH

    def test_none_result(self) -> None:
        a = ValidationToken(adapter_id="test", status=TaskStatus.OK, result=None)
        b = _token("T[-a]")
        assert compare_canonical(a, b) == TaskStatus.MATH_MISMATCH

    def test_whitespace_variants_equal(self) -> None:
        a = _token("T[ -a,  -b ]")
        b = _token("T[-a, -b]")
        assert compare_canonical(a, b) == TaskStatus.OK

    def test_coefficient_normalization(self) -> None:
        a = _token("Times[1, T[-a]]")
        b = _token("T[-a]")
        assert compare_canonical(a, b) == TaskStatus.OK


class TestPipelineRegistration:
    def test_register_as_l3_and_compare(self) -> None:
        pipeline = ComparisonPipeline()
        pipeline.register(3, "canonical", compare_canonical)

        a = _token("T[-a, -b]")
        b = _token("T[-x, -y]")
        result = pipeline.compare(a, b)

        assert result.status == TaskStatus.OK
        assert result.layer == 3
        assert result.layer_name == "canonical"

    def test_l1_short_circuits_before_l3(self) -> None:
        pipeline = ComparisonPipeline()
        pipeline.register(3, "canonical", compare_canonical)

        a = _token("T[-$1, -$2]")
        result = pipeline.compare(a, a)

        assert result.status == TaskStatus.OK
        assert result.layer == 1
