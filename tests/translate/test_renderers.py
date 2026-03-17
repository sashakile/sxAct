"""Tests for output renderers and CLI translate subcommand."""

from __future__ import annotations

import json
import subprocess

import pytest

from xact.translate import wl_to_actions
from xact.translate.renderers import render, to_json, to_julia, to_python, to_toml


# ===================================================================
# Shared fixtures
# ===================================================================

_SESSION = """\
DefManifold[M, 4, {a, b, c, d}]
DefMetric[-1, g[-a,-b], CD]
DefTensor[T[-a,-b], M, Symmetric[{-a,-b}]]
result = ToCanonical[T[-a,-b] - T[-b,-a]]
result == 0
"""


@pytest.fixture()
def actions() -> list[dict]:
    return wl_to_actions(_SESSION)


# ===================================================================
# JSON renderer
# ===================================================================


class TestJSON:
    def test_single_action(self) -> None:
        actions = wl_to_actions("DefManifold[M, 4, {a,b,c,d}]")
        result = to_json(actions)
        parsed = json.loads(result)
        assert parsed["action"] == "DefManifold"

    def test_multiple_actions(self, actions: list[dict]) -> None:
        result = to_json(actions)
        parsed = json.loads(result)
        assert isinstance(parsed, list)
        assert len(parsed) == 5

    def test_round_trip(self) -> None:
        actions = wl_to_actions("ToCanonical[T[-a,-b]]")
        result = to_json(actions)
        parsed = json.loads(result)
        assert parsed["action"] == "ToCanonical"
        assert "expression" in parsed["args"]


# ===================================================================
# Julia renderer
# ===================================================================


class TestJulia:
    def test_def_manifold(self) -> None:
        actions = wl_to_actions("DefManifold[M, 4, {a,b,c,d}]")
        result = to_julia(actions)
        assert "xAct.def_manifold!" in result
        assert ":M" in result
        assert "4" in result

    def test_def_metric(self) -> None:
        actions = wl_to_actions("DefMetric[-1, g[-a,-b], CD]")
        result = to_julia(actions)
        assert "xAct.def_metric!" in result
        assert ":CD" in result

    def test_def_tensor(self) -> None:
        actions = wl_to_actions("DefTensor[T[-a,-b], M, Symmetric[{-a,-b}]]")
        result = to_julia(actions)
        assert "xAct.def_tensor!" in result
        assert ":T" in result
        assert "Symmetric" in result

    def test_to_canonical(self) -> None:
        actions = wl_to_actions("ToCanonical[T[-a,-b]]")
        result = to_julia(actions)
        assert "xAct.ToCanonical" in result

    def test_assignment(self) -> None:
        actions = wl_to_actions("result = ToCanonical[T[-a,-b]]")
        result = to_julia(actions)
        assert result.startswith("result = ")

    def test_assert(self) -> None:
        actions = wl_to_actions("result == 0")
        result = to_julia(actions)
        assert "@assert" in result

    def test_christoffel(self) -> None:
        actions = wl_to_actions("ChristoffelP[CD]")
        result = to_julia(actions)
        assert "xAct.Christoffel" in result
        assert ":CD" in result

    def test_ibp(self) -> None:
        actions = wl_to_actions("IBP[expr, CD]")
        result = to_julia(actions)
        assert "xAct.IBP" in result

    def test_full_session(self, actions: list[dict]) -> None:
        result = to_julia(actions)
        lines = result.strip().split("\n")
        assert len(lines) == 5


# ===================================================================
# TOML renderer
# ===================================================================


class TestTOML:
    def test_meta_section(self, actions: list[dict]) -> None:
        result = to_toml(actions)
        assert "[meta]" in result
        assert 'id = "translated-session"' in result

    def test_setup_blocks(self, actions: list[dict]) -> None:
        result = to_toml(actions)
        assert result.count("[[setup]]") == 3  # DefManifold, DefMetric, DefTensor

    def test_test_blocks(self, actions: list[dict]) -> None:
        result = to_toml(actions)
        assert "[[tests]]" in result
        assert "[[tests.operations]]" in result

    def test_store_as(self, actions: list[dict]) -> None:
        result = to_toml(actions)
        assert 'store_as = "result"' in result

    def test_assert_grouped(self, actions: list[dict]) -> None:
        result = to_toml(actions)
        # Assert should appear as an operation, not a separate test
        assert 'action = "Assert"' in result

    def test_single_expression(self) -> None:
        actions = wl_to_actions("ToCanonical[T[-a,-b]]")
        result = to_toml(actions)
        assert "[meta]" in result
        assert 'action = "ToCanonical"' in result


# ===================================================================
# Python renderer
# ===================================================================


class TestPython:
    def test_imports(self, actions: list[dict]) -> None:
        result = to_python(actions)
        assert "from sxact.adapter.julia_stub import JuliaAdapter" in result
        assert "adapter = JuliaAdapter()" in result

    def test_execute_calls(self) -> None:
        actions = wl_to_actions("DefManifold[M, 4, {a,b,c,d}]")
        result = to_python(actions)
        assert 'adapter.execute(ctx, "DefManifold"' in result

    def test_teardown(self, actions: list[dict]) -> None:
        result = to_python(actions)
        assert "adapter.teardown(ctx)" in result

    def test_store_as(self) -> None:
        actions = wl_to_actions("result = ToCanonical[T[-a,-b]]")
        result = to_python(actions)
        assert "result = adapter.execute" in result


# ===================================================================
# render() dispatch
# ===================================================================


class TestRenderDispatch:
    def test_json(self) -> None:
        actions = wl_to_actions("ToCanonical[x]")
        result = render(actions, "json")
        assert json.loads(result)["action"] == "ToCanonical"

    def test_julia(self) -> None:
        actions = wl_to_actions("ToCanonical[x]")
        result = render(actions, "julia")
        assert "xAct.ToCanonical" in result

    def test_toml(self) -> None:
        actions = wl_to_actions("ToCanonical[x]")
        result = render(actions, "toml")
        assert "[meta]" in result

    def test_python(self) -> None:
        actions = wl_to_actions("ToCanonical[x]")
        result = render(actions, "python")
        assert "adapter.execute" in result

    def test_unknown_format(self) -> None:
        with pytest.raises(ValueError, match="Unknown format"):
            render([], "xml")


# ===================================================================
# CLI translate subcommand
# ===================================================================


class TestCLI:
    def test_expr_flag_json(self) -> None:
        result = subprocess.run(
            [
                "xact-test",
                "translate",
                "-e",
                "DefManifold[M, 4, {a,b,c,d}]",
                "--to",
                "json",
            ],
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0
        parsed = json.loads(result.stdout)
        assert parsed["action"] == "DefManifold"

    def test_expr_flag_julia(self) -> None:
        result = subprocess.run(
            ["xact-test", "translate", "-e", "ToCanonical[T[-a,-b]]", "--to", "julia"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0
        assert "xAct.ToCanonical" in result.stdout

    def test_stdin_toml(self) -> None:
        session = "DefManifold[M, 4, {a,b}]; ToCanonical[T[-a,-b]]"
        result = subprocess.run(
            ["xact-test", "translate", "--to", "toml"],
            input=session,
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0
        assert "[[setup]]" in result.stdout
        assert "[[tests.operations]]" in result.stdout

    def test_empty_input(self) -> None:
        result = subprocess.run(
            ["xact-test", "translate", "-e", ""],
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0
