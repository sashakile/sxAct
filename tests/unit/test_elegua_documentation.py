"""Documentation checks for the sxAct → Elegua migration boundary."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def _read_doc(relative: str) -> str:
    return (ROOT / relative).read_text()


def test_architecture_documents_current_elegua_pipeline() -> None:
    doc = _read_doc("docs/src/architecture.md")

    assert "Elegua" in doc
    assert "elegua.IsolatedRunner" in doc
    assert "elegua.bridge.load_test_file" in doc
    assert "sxact.runner.isolation" not in doc


def test_internals_documents_completed_elegua_refactor() -> None:
    doc = _read_doc("docs/src/internals.md")

    assert "Current status: the sxAct → Elegua refactor is complete" in doc
    assert "sxact.oracle.client.OracleClient" in doc
    assert "delegates HTTP transport to `elegua.oracle.OracleClient`" in doc
    assert "snapshot store and comparator remain sxAct-owned" in doc


def test_verification_docs_describe_elegua_backing_services() -> None:
    api_doc = _read_doc("docs/src/api-verification.md")
    guide_doc = _read_doc("docs/src/verification-tools.md")

    assert "compatibility wrapper around `elegua.oracle.OracleClient`" in api_doc
    assert "xAct-specific compatibility wrapper around `elegua.bridge.load_test_file()`" in guide_doc
    assert "live mode runs tests through `elegua.IsolatedRunner`" in guide_doc
