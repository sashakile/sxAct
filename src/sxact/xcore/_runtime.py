"""Julia runtime singleton for sxact.xcore.

Initialises the Julia runtime and loads XCore exactly once per process.
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
    """Return the Julia XCore module object, initialising Julia if needed."""
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

    # xAct.jl lives at src/julia/src/xAct.jl relative to the repo root.
    # From this file: src/sxact/xcore/_runtime.py → go up 3 levels → src/
    # then into julia/src/xAct.jl.
    julia_dir = (Path(__file__).parent.parent.parent / "julia").resolve()
    xact_path = julia_dir / "src" / "xAct.jl"

    if not xact_path.exists():
        raise FileNotFoundError(
            f"xAct.jl not found at {xact_path}. "
            "Ensure the sxAct repo structure is intact."
        )

    # Activate the Julia project so Reexport and other deps are available.
    _jl.seval(f'import Pkg; Pkg.activate("{julia_dir}"; io=devnull)')
    _jl.seval(f'include("{xact_path}")')
    _jl.seval("using .xAct")
    _xcore = _jl.xAct
