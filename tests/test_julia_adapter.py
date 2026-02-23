"""Conformance tests for JuliaAdapter stub."""

import pytest

from sxact.adapter.julia_stub import JuliaAdapter

# Override the fixture so the conformance suite runs against JuliaAdapter
@pytest.fixture
def adapter_factory():
    return JuliaAdapter

# Pull in all conformance tests
from tests.test_adapter_conformance import *  # noqa: E402,F401,F403
