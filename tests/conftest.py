"""Pytest configuration and fixtures."""

import os
import time

import pytest

from sxact.oracle import OracleClient


def pytest_configure(config: pytest.Config) -> None:
    config.addinivalue_line("markers", "oracle: tests requiring Docker oracle server")


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
