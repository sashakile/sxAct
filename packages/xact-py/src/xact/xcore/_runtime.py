"""Julia runtime singleton for xact.xcore.

Initialises the Julia runtime and loads xAct exactly once per process.
Thread-safe: concurrent first-calls block until initialisation completes.
"""

from __future__ import annotations

import threading
from pathlib import Path
from typing import Any

_lock = threading.Lock()
_jl: Any = None
_xcore: Any = None


def get_julia() -> Any:
    """Return the juliacall Main module, initialising Julia if needed."""
    _ensure_initialized()
    return _jl


def get_xcore() -> Any:
    """Return the Julia xAct module object, initialising Julia if needed."""
    _ensure_initialized()
    return _xcore


def _ensure_initialized() -> None:
    global _jl, _xcore
    if _xcore is not None:
        return
    with _lock:
        if _xcore is None:
            _init_julia()


def _init_julia() -> None:
    global _jl, _xcore
    import juliacall  # noqa: PLC0415  (deferred import for lazy init)

    _jl = juliacall.Main

    # Attempt to load xAct. If juliapkg.json worked, it should be available.
    try:
        _jl.seval("using xAct")
        _xcore = _jl.xAct
    except Exception:
        # Fallback for development if juliapkg hasn't resolved it yet,
        # or if we're running from source without a formal install.
        julia_dir = (Path(__file__).parents[1] / "julia").resolve()
        if (julia_dir / "Project.toml").exists():
            _jl.seval(f'import Pkg; Pkg.activate("{julia_dir}"; io=devnull)')
            xact_main = julia_dir / "src" / "xAct.jl"
            if xact_main.exists():
                _jl.seval(f'include("{xact_main}")')
                _jl.seval("using .xAct")
                _xcore = _jl.xAct
            else:
                raise ImportError(f"xAct.jl not found at {xact_main}")
        else:
            raise ImportError(
                "xAct Julia package not found. Ensure juliapkg.json is respected "
                "or Project.toml is present at root."
            )
