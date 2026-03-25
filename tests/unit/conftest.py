"""Shared fixtures for tests/unit/ — avoids duplication across test modules."""

import pytest

import xact


@pytest.fixture(autouse=True)
def _reset():
    """Reset xAct state before each test."""
    xact.reset()


@pytest.fixture()
def manifold():
    return xact.Manifold("M", 4, ["a", "b", "c", "d", "e", "f"])


@pytest.fixture()
def metric(manifold):
    return xact.Metric(manifold, "g", signature=-1, covd="CD")
