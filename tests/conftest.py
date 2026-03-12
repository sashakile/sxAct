"""Pytest configuration and fixtures."""

from __future__ import annotations

import os
import time
import uuid

import pytest

from sxact.oracle import OracleClient
from sxact.oracle.result import Result


class MockOracleClient:
    """Fake OracleClient for unit testing without a live server.

    Construct with a *responses* dict mapping expression strings to Results.
    Unrecognized expressions return a default error Result.
    All calls are recorded in ``self.calls`` for assertion.
    """

    def __init__(self, responses: dict[str, Result] | None = None) -> None:
        self._responses: dict[str, Result] = responses or {}
        self.calls: list[str] = []

    def health(self) -> bool:
        return True

    def evaluate(self, expr: str, timeout: int = 30) -> Result:
        self.calls.append(expr)
        return self._responses.get(
            expr,
            Result(
                status="error",
                type="",
                repr="",
                normalized="",
                error=f"MockOracleClient: no response configured for: {expr!r}",
            ),
        )

    def evaluate_with_xact(
        self, expr: str, timeout: int = 60, context_id: str | None = None
    ) -> Result:
        self.calls.append(expr)
        return self._responses.get(
            expr,
            Result(
                status="error",
                type="",
                repr="",
                normalized="",
                error=f"MockOracleClient: no response configured for: {expr!r}",
            ),
        )

    def cleanup(self) -> bool:
        return True

    def restart(self) -> bool:
        return True

    def check_clean_state(self) -> tuple[bool, list[str]]:
        return True, []


def pytest_configure(config: pytest.Config) -> None:
    config.addinivalue_line("markers", "oracle: tests requiring Docker oracle server")
    config.addinivalue_line("markers", "julia: tests requiring the Julia runtime")


@pytest.fixture(scope="session")
def oracle_url() -> str:
    """Get the oracle server URL from environment or use default."""
    return os.environ.get("ORACLE_URL", "http://localhost:8765")


@pytest.fixture(scope="session")
def oracle(oracle_url: str) -> OracleClient:
    """Provide an OracleClient connected to the running server."""
    client = OracleClient(base_url=oracle_url)

    max_retries = 10
    for i in range(max_retries):
        if client.health():
            return client
        if i < max_retries - 1:
            time.sleep(1)

    pytest.skip("Oracle server not available")
    return client  # unreachable, but satisfies type checker


@pytest.fixture
def mock_oracle() -> MockOracleClient:
    """Provide a MockOracleClient with no pre-configured responses."""
    return MockOracleClient()


@pytest.fixture
def context_id() -> str:
    """Generate unique context ID for test isolation.

    This fixture provides a unique identifier that can be passed to
    evaluate_with_xact() to isolate symbol contexts between tests.
    Each test gets its own Mathematica context namespace, preventing
    symbol pollution in the persistent kernel.
    """
    return uuid.uuid4().hex[:8]
