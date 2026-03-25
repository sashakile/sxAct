"""Integration tests: round-trip WL → action dict → Julia → result.

These tests require a working Julia installation with the xAct module.
They are skipped if Julia is not available.
"""

from __future__ import annotations

import tempfile
from pathlib import Path

import pytest

from xact.translate import wl_to_actions
from xact.translate.renderers import to_toml

# ---------------------------------------------------------------------------
# Skip if Julia/adapter not available
# ---------------------------------------------------------------------------

_julia_available = False
try:
    from sxact.adapter.julia_stub import JuliaAdapter

    _adapter = JuliaAdapter()
    _adapter._ensure_ready()
    _julia_available = True
except Exception:
    pass

pytestmark = pytest.mark.skipif(not _julia_available, reason="Julia runtime not available")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture(scope="module")
def adapter() -> JuliaAdapter:
    return _adapter


@pytest.fixture()
def ctx(adapter: JuliaAdapter):  # type: ignore[no-untyped-def]
    c = adapter.initialize()
    yield c
    adapter.teardown(c)


# ---------------------------------------------------------------------------
# Round-trip: WL → action → Julia execute → verify
# ---------------------------------------------------------------------------


class TestRoundTrip:
    def test_def_manifold(self, adapter: JuliaAdapter, ctx: object) -> None:
        actions = wl_to_actions("DefManifold[M, 4, {a, b, c, d}]")
        result = adapter.execute(ctx, actions[0]["action"], actions[0]["args"])
        assert result.status == "ok"

    def test_def_metric(self, adapter: JuliaAdapter, ctx: object) -> None:
        actions = wl_to_actions("DefManifold[M, 4, {a, b, c, d}]; DefMetric[-1, g[-a,-b], CD]")
        for ad in actions:
            result = adapter.execute(ctx, ad["action"], ad["args"])
            assert result.status == "ok", f"{ad['action']} failed: {result.error}"

    def test_to_canonical_symmetric(self, adapter: JuliaAdapter, ctx: object) -> None:
        """T[-a,-b] - T[-b,-a] with Symmetric should canonicalize to 0."""
        session = """\
DefManifold[M, 4, {a, b, c, d}]
DefMetric[-1, g[-a,-b], CD]
DefTensor[T[-a,-b], M, Symmetric[{-a,-b}]]
ToCanonical[T[-a,-b] - T[-b,-a]]
"""
        actions = wl_to_actions(session)
        for ad in actions:
            result = adapter.execute(ctx, ad["action"], ad["args"])
            assert result.status == "ok", f"{ad['action']} failed: {result.error}"
        # Last result should be "0"
        assert result.repr.strip() == "0"

    def test_postfix_pipe(self, adapter: JuliaAdapter, ctx: object) -> None:
        """Postfix // rewrite: T[-a,-b] - T[-b,-a] // ToCanonical → 0."""
        session = """\
DefManifold[M, 4, {a, b, c, d}]
DefMetric[-1, g[-a,-b], CD]
DefTensor[T[-a,-b], M, Symmetric[{-a,-b}]]
T[-a,-b] - T[-b,-a] // ToCanonical
"""
        actions = wl_to_actions(session)
        for ad in actions:
            result = adapter.execute(ctx, ad["action"], ad["args"])
            assert result.status == "ok", f"{ad['action']} failed: {result.error}"
        assert result.repr.strip() == "0"

    def test_contract(self, adapter: JuliaAdapter, ctx: object) -> None:
        session = """\
DefManifold[M, 4, {a, b, c, d}]
DefMetric[-1, g[-a,-b], CD]
ContractMetric[g[-a,b] g[-b,c]]
"""
        actions = wl_to_actions(session)
        for ad in actions:
            result = adapter.execute(ctx, ad["action"], ad["args"])
            assert result.status == "ok", f"{ad['action']} failed: {result.error}"

    def test_simplify(self, adapter: JuliaAdapter, ctx: object) -> None:
        session = """\
DefManifold[M, 4, {a, b, c, d}]
DefMetric[-1, g[-a,-b], CD]
DefTensor[S[-a,-b], M, Symmetric[{-a,-b}]]
Simplify[S[-a,-b] - S[-b,-a]]
"""
        actions = wl_to_actions(session)
        for ad in actions:
            result = adapter.execute(ctx, ad["action"], ad["args"])
            assert result.status == "ok", f"{ad['action']} failed: {result.error}"
        assert result.repr.strip() == "0"


# ---------------------------------------------------------------------------
# TOML round-trip: WL → TOML file → xact-test run
# ---------------------------------------------------------------------------


class TestTOMLRoundTrip:
    def test_generated_toml_valid(self) -> None:
        """Translate a WL session to TOML and verify it's loadable."""
        from sxact.runner.loader import load_test_file

        session = """\
DefManifold[M, 4, {a, b, c, d}]
DefMetric[-1, g[-a,-b], CD]
DefTensor[T[-a,-b], M, Symmetric[{-a,-b}]]
ToCanonical[T[-a,-b] - T[-b,-a]]
"""
        actions = wl_to_actions(session)
        toml_content = to_toml(actions)

        with tempfile.NamedTemporaryFile(mode="w", suffix=".toml", delete=False) as f:
            f.write(toml_content)
            f.flush()
            try:
                test_file = load_test_file(Path(f.name))
                assert test_file.meta.id == "translated-session"
                assert len(test_file.setup) == 3
                assert len(test_file.tests) >= 1
            finally:
                Path(f.name).unlink()
