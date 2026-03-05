"""Tests for the Oracle HTTP client."""

import pytest

from sxact.oracle import OracleClient


@pytest.mark.oracle
class TestOracleHealth:
    def test_health_returns_true_when_server_running(
        self, oracle: OracleClient
    ) -> None:
        assert oracle.health() is True


@pytest.mark.oracle
class TestOracleEvaluate:
    def test_simple_arithmetic(self, oracle: OracleClient) -> None:
        result = oracle.evaluate("2+2")
        assert result.status == "ok"
        assert result.repr == "4"

    def test_wolfram_function(self, oracle: OracleClient) -> None:
        result = oracle.evaluate("Expand[(x+1)^2]")
        assert result.status == "ok"
        assert "x" in result.repr

    def test_invalid_expression(self, oracle: OracleClient) -> None:
        result = oracle.evaluate("InvalidFunction[")
        assert (
            result.status == "error"
            or "$Failed" in str(result.repr)
            or "Syntax" in str(result.repr)
        )

    def test_timing_is_reported(self, oracle: OracleClient) -> None:
        result = oracle.evaluate("2+2")
        timing = result.diagnostics.get("execution_time_ms")
        assert timing is not None
        assert timing >= 0


@pytest.mark.oracle
@pytest.mark.slow
class TestOracleXAct:
    """Tests that require xAct loading (~3+ minutes per invocation)."""

    def test_xact_loads(self, oracle: OracleClient) -> None:
        result = oracle.evaluate_with_xact("$xTensorVersionNumber", timeout=300)
        assert result.status == "ok", f"xAct load failed: {result.error}"
        assert result.repr is not None


class TestOracleClientOffline:
    def test_health_returns_false_when_server_not_running(self) -> None:
        client = OracleClient(base_url="http://localhost:59999")
        assert client.health() is False

    def test_evaluate_returns_error_when_server_not_running(self) -> None:
        client = OracleClient(base_url="http://localhost:59999")
        result = client.evaluate("2+2")
        assert result.status == "error"
        assert result.error is not None
