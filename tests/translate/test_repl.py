"""Tests for REPL session (non-interactive, no Julia required)."""

from __future__ import annotations

import subprocess

import pytest

from sxact.cli.repl import REPLSession

# ===================================================================
# REPLSession in translate-only mode
# ===================================================================


class TestREPLSessionNoEval:
    @pytest.fixture()
    def session(self) -> REPLSession:
        return REPLSession(no_eval=True)

    def test_execute_def_manifold(self, session: REPLSession) -> None:
        output = session.execute_line("DefManifold[M, 4, {a, b, c, d}]")
        assert len(output) == 1
        assert "xAct.def_manifold!" in output[0]

    def test_execute_to_canonical(self, session: REPLSession) -> None:
        output = session.execute_line("ToCanonical[T[-a,-b]]")
        assert any("xAct.ToCanonical" in line for line in output)

    def test_counter_increments(self, session: REPLSession) -> None:
        session.execute_line("DefManifold[M, 4, {a,b}]")
        assert session.counter == 1
        session.execute_line("DefMetric[-1, g[-a,-b], CD]")
        assert session.counter == 2

    def test_actions_accumulate(self, session: REPLSession) -> None:
        session.execute_line("DefManifold[M, 4, {a,b}]")
        session.execute_line("ToCanonical[T[-a,-b]]")
        assert len(session.actions) == 2
        assert session.actions[0]["action"] == "DefManifold"
        assert session.actions[1]["action"] == "ToCanonical"

    def test_parse_error(self, session: REPLSession) -> None:
        output = session.execute_line("f /@ {1,2}")
        assert any("ParseError" in line for line in output)

    def test_semicolon_multiple(self, session: REPLSession) -> None:
        output = session.execute_line("DefManifold[M, 4, {a,b}]; DefMetric[-1, g[-a,-b], CD]")
        assert len(output) == 2
        assert session.counter == 2

    def test_reset(self, session: REPLSession) -> None:
        session.execute_line("DefManifold[M, 4, {a,b}]")
        result = session.reset()
        assert "cleared" in result.lower() or "reset" in result.lower()
        assert session.actions == []
        assert session.counter == 0

    def test_export_julia(self, session: REPLSession) -> None:
        session.execute_line("DefManifold[M, 4, {a,b,c,d}]")
        session.execute_line("ToCanonical[T[-a,-b]]")
        result = session.export_session("julia")
        assert "xAct.def_manifold!" in result
        assert "xAct.ToCanonical" in result

    def test_export_toml(self, session: REPLSession) -> None:
        session.execute_line("DefManifold[M, 4, {a,b}]")
        session.execute_line("ToCanonical[T[-a,-b]]")
        result = session.export_session("toml")
        assert "[[setup]]" in result
        assert "[[tests.operations]]" in result

    def test_export_json(self, session: REPLSession) -> None:
        session.execute_line("DefManifold[M, 4, {a,b}]")
        result = session.export_session("json")
        assert '"DefManifold"' in result

    def test_export_python(self, session: REPLSession) -> None:
        session.execute_line("DefManifold[M, 4, {a,b}]")
        result = session.export_session("python")
        assert "adapter.execute" in result

    def test_export_empty(self, session: REPLSession) -> None:
        result = session.export_session("julia")
        assert "no actions" in result.lower()

    def test_history(self, session: REPLSession) -> None:
        session.execute_line("DefManifold[M, 4, {a,b}]")
        session.execute_line("ToCanonical[x]")
        assert len(session.history) == 2


# ===================================================================
# CLI --no-eval mode
# ===================================================================


class TestREPLCLI:
    def test_no_eval_piped(self) -> None:
        """Test --no-eval mode with piped stdin (non-interactive)."""
        result = subprocess.run(
            ["xact-test", "repl", "--no-eval"],
            input="DefManifold[M, 4, {a,b,c,d}]\n",
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0
        assert "xAct.def_manifold!" in result.stdout
