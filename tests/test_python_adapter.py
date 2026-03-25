"""Conformance tests for PythonAdapter stub."""

import pytest

from sxact.adapter.python_stub import PythonAdapter


# Override the fixture so the conformance suite runs against PythonAdapter
@pytest.fixture
def adapter_factory():
    return PythonAdapter


# Pull in all conformance tests
from tests.test_adapter_conformance import *  # noqa: E402, F403
