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

import os
import threading
from typing import Any

_lock = threading.Lock()
_jl: Any = None
_xcore: Any = None
_init_pid: int | None = None


def _check_fork_safety() -> None:
    """Raise RuntimeError if the current process is a fork of the one that initialized Julia."""
    if _init_pid is None:
        return
    current_pid = os.getpid()
    if current_pid != _init_pid:
        raise RuntimeError(
            f"xact: Julia runtime was initialized in process {_init_pid} but is "
            f"being accessed from process {current_pid}. This typically happens "
            f"after os.fork() or multiprocessing with fork start method. juliacall "
            f"is not fork-safe and may produce incorrect results or crash. Use "
            f"threading, or multiprocessing with the 'spawn' start method instead."
        )


def get_julia() -> Any:
    """Return the juliacall Main module, initialising Julia if needed."""
    _check_fork_safety()
    _ensure_initialized()
    return _jl


def get_xcore() -> Any:
    """Return the Julia xAct module object, initialising Julia if needed."""
    _check_fork_safety()
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
    global _jl, _xcore, _init_pid
    import juliacall

    jl = juliacall.Main

    try:
        jl.seval("using XAct")
        _jl = jl
        _xcore = jl.XAct
        _init_pid = os.getpid()
    except Exception as exc:
        _jl = None
        _xcore = None
        raise ImportError(
            "Could not load Julia package XAct. Ensure Julia can resolve "
            "XAct v0.7.1 via the configured registries or shared juliapkg "
            f"project. Original error: {exc}"
        ) from exc
