"""Tests for xact.xcore._runtime initialization safety (sxAct-ew7y).

Verifies that partial init failure does not leave the module in a
half-initialized state (_jl set, _xcore None).
"""

from __future__ import annotations

import json
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest


def test_juliapkg_metadata_uses_registered_xact() -> None:
    """xact-py should declare the registered Julia XAct package, not a local path."""
    juliapkg_path = (
        Path(__file__).resolve().parents[2]
        / "packages"
        / "xact-py"
        / "src"
        / "xact"
        / "juliapkg.json"
    )
    data = json.loads(juliapkg_path.read_text())

    xact = data["packages"]["XAct"]
    assert xact["uuid"] == "61ed89dc-cc38-478d-be53-e1ee1d7160f1"
    assert xact["version"] == "0.7.1"
    assert "path" not in xact
    assert "dev" not in xact


def test_failed_init_resets_jl() -> None:
    """If xAct loading fails, _jl must be reset to None so retries work cleanly."""
    import xact.xcore._runtime as rt

    # Save originals
    orig_jl = rt._jl
    orig_xcore = rt._xcore

    try:
        # Reset state
        rt._jl = None
        rt._xcore = None

        mock_main = MagicMock()
        mock_main.seval.side_effect = RuntimeError("xAct load failed")

        with patch.dict("sys.modules", {"juliacall": MagicMock(Main=mock_main)}):
            with pytest.raises(ImportError, match="Could not load Julia package XAct"):
                rt._init_julia()

        mock_main.seval.assert_called_once_with("using XAct")

        # After failure, _jl must be None (not half-set)
        assert rt._jl is None, "_jl should be None after failed init"
        assert rt._xcore is None, "_xcore should be None after failed init"
    finally:
        # Restore originals
        rt._jl = orig_jl
        rt._xcore = orig_xcore


def test_successful_init_sets_both():
    """On success, both _jl and _xcore must be set."""
    import xact.xcore._runtime as rt

    orig_jl = rt._jl
    orig_xcore = rt._xcore

    try:
        rt._jl = None
        rt._xcore = None

        mock_main = MagicMock()
        mock_xact = MagicMock()
        mock_main.XAct = mock_xact
        mock_main.seval.return_value = None

        with patch.dict("sys.modules", {"juliacall": MagicMock(Main=mock_main)}):
            rt._init_julia()

        assert rt._jl is not None
        assert rt._xcore is not None
    finally:
        rt._jl = orig_jl
        rt._xcore = orig_xcore
