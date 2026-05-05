"""Architectural boundary checks for the sxAct → Elegua migration."""

from __future__ import annotations

import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "packages" / "sxact" / "src" / "sxact"


def test_legacy_isolation_runner_has_been_removed() -> None:
    """sxAct should consume elegua.isolation instead of shipping a local clone."""
    assert importlib.util.find_spec("sxact.runner.isolation") is None
    assert not (SRC / "runner" / "isolation.py").exists()


def test_sxact_source_does_not_import_legacy_isolation_runner() -> None:
    """Production code must not depend on the removed sxact.runner.isolation API."""
    offenders: list[str] = []
    for path in SRC.rglob("*.py"):
        if "__pycache__" in path.parts:
            continue
        text = path.read_text()
        if "sxact.runner.isolation" in text or "IsolatedContext" in text:
            offenders.append(str(path.relative_to(ROOT)))

    assert offenders == []


def test_oracle_client_reuses_elegua_http_client() -> None:
    """sxAct should adapt elegua.oracle instead of shipping separate HTTP plumbing."""
    oracle_client = SRC / "oracle" / "client.py"
    text = oracle_client.read_text()
    pyproject = (ROOT / "packages" / "sxact" / "pyproject.toml").read_text()

    assert "from elegua.oracle import OracleClient" in text
    assert "import requests" not in text
    assert "requests" not in pyproject
