"""Tests for the Result dataclass."""

from sxact.oracle.result import Result


class TestResultDataclass:
    def test_ok_result(self) -> None:
        result = Result(
            status="ok",
            type="Expr",
            repr="T[-a, -b]",
            normalized="T[-$1, -$2]",
        )
        assert result.status == "ok"
        assert result.type == "Expr"
        assert result.error is None

    def test_error_result(self) -> None:
        result = Result(
            status="error",
            type="",
            repr="",
            normalized="",
            error="Syntax error",
        )
        assert result.status == "error"
        assert result.error == "Syntax error"

    def test_timeout_result(self) -> None:
        result = Result(
            status="timeout",
            type="",
            repr="",
            normalized="",
        )
        assert result.status == "timeout"

    def test_properties_default(self) -> None:
        result = Result(
            status="ok",
            type="Expr",
            repr="T[-a]",
            normalized="T[-$1]",
        )
        assert result.properties == {}

    def test_diagnostics_default(self) -> None:
        result = Result(
            status="ok",
            type="Scalar",
            repr="42",
            normalized="42",
        )
        assert result.diagnostics == {}

    def test_with_properties(self) -> None:
        result = Result(
            status="ok",
            type="Tensor",
            repr="g[-a, -b]",
            normalized="g[-$1, -$2]",
            properties={"rank": 2, "symmetry": "Symmetric"},
        )
        assert result.properties["rank"] == 2
        assert result.properties["symmetry"] == "Symmetric"

    def test_with_diagnostics(self) -> None:
        result = Result(
            status="ok",
            type="Expr",
            repr="result",
            normalized="result",
            diagnostics={"execution_time_ms": 150, "memory_mb": 12.5},
        )
        assert result.diagnostics["execution_time_ms"] == 150
