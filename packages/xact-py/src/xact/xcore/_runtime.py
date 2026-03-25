# sxAct — xAct Migration & Implementation
# Copyright (C) 2026 sxAct Contributors
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

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
    import juliacall

    jl = juliacall.Main

    # Attempt to load xAct. If juliapkg.json worked, it should be available.
    try:
        jl.seval("using xAct")
        # Only set globals after full success
        _jl = jl
        _xcore = jl.xAct
    except Exception:
        # Fallback for development if juliapkg hasn't resolved it yet,
        # or if we're running from source without a formal install.
        try:
            from xact._bridge import jl_escape

            julia_dir = (Path(__file__).parent.parent / "julia").resolve()
            if (julia_dir / "Project.toml").exists():
                escaped_dir = jl_escape(str(julia_dir))
                jl.seval(f'import Pkg; Pkg.activate("{escaped_dir}"; io=devnull)')
                xact_main = julia_dir / "src" / "xAct.jl"
                if xact_main.exists():
                    escaped_main = jl_escape(str(xact_main))
                    jl.seval(f'include("{escaped_main}")')
                    jl.seval("using .xAct")
                    # Only set globals after full success
                    _jl = jl
                    _xcore = jl.xAct
                else:
                    raise ImportError(f"xAct.jl not found at {xact_main}")
            else:
                raise ImportError(
                    "xAct Julia package not found. Ensure juliapkg.json is respected "
                    "or Project.toml is present at root."
                )
        except ImportError:
            raise
        except Exception as exc:
            # Reset to clean state so retries don't see a half-initialized runtime
            _jl = None
            _xcore = None
            raise ImportError(f"Failed to load xAct Julia package: {exc}") from exc
