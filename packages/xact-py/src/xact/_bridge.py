"""Safe Julia bridge — typed argument builders for injection-proof seval calls.

All Julia arguments are constructed via builder functions (jl_sym, jl_int,
jl_str, etc.) that validate and escape inputs. This makes injection impossible
by construction: user strings never appear raw in seval expressions.

Usage::

    from xact._bridge import jl_sym, jl_int, jl_str, jl_sym_list, jl_call

    jl_call(
        jl,
        "xAct.def_manifold!",
        jl_sym(name, "manifold name"),
        jl_int(dim),
        jl_sym_list(indices, "index labels"),
    )
"""

from __future__ import annotations

import logging
import re
import threading
import time
from typing import Any

_IDENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
_lock = threading.Lock()
_log = logging.getLogger(__name__)


def validate_ident(name: str, context: str = "") -> str:
    """Validate a string is a safe Julia identifier.

    Uses same regex as Julia-side Validation.validate_identifier (Phase A).
    """
    if not _IDENT_RE.match(name):
        ctx = f" in {context}" if context else ""
        raise ValueError(f"Invalid identifier {name!r}{ctx}")
    return name


def jl_escape(s: str) -> str:
    """Escape a string for use inside Julia double-quoted string literals."""
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$")


# --- Typed argument builders ---


def jl_sym(name: str, context: str = "") -> str:
    """Build a validated Julia Symbol literal like ``':MyTensor'``."""
    validate_ident(name, context)
    return f":{name}"


def jl_int(n: int) -> str:
    """Build a Julia integer literal. Rejects non-int input."""
    if not isinstance(n, int) or isinstance(n, bool):
        raise TypeError(f"Expected int, got {type(n).__name__}")
    return str(n)


def jl_str(s: str) -> str:
    """Build an escaped Julia string literal like ``'"T[-a,-b]"'``."""
    return f'"{jl_escape(s)}"'


def jl_sym_list(names: list[str], context: str = "") -> str:
    """Build a Julia Symbol vector like ``'[:a, :b, :c]'``."""
    return "[" + ", ".join(jl_sym(n, context) for n in names) + "]"


def jl_path(p: str) -> str:
    """Build an escaped Julia string literal from a filesystem path."""
    return jl_str(str(p))


def timed_seval(
    jl: Any,
    expr: str,
    *,
    warn_after_s: float = 30.0,
    label: str = "",
) -> Any:
    """Wrap ``jl.seval(expr)`` with elapsed-time monitoring.

    Logs a WARNING if the call takes longer than *warn_after_s* seconds.
    Does **not** forcefully interrupt the call (juliacall is in-process and
    cannot be safely killed); this is a visibility aid, not a hard timeout.
    """
    t0 = time.monotonic()
    try:
        return jl.seval(expr)
    finally:
        elapsed = time.monotonic() - t0
        if elapsed >= warn_after_s:
            tag = f" [{label}]" if label else ""
            _log.warning(
                "Slow seval%s: %.1fs for %s",
                tag,
                elapsed,
                expr[:200],
            )


def jl_call(jl: Any, func: str, *args: str) -> Any:
    """Call a Julia function with pre-validated/escaped arguments.

    All args MUST be built via jl_sym/jl_int/jl_str/jl_sym_list.
    Adds locking for thread safety.

    Wraps Julia exceptions in RuntimeError with context.
    """
    expr = f"{func}({', '.join(args)})"
    with _lock:
        try:
            return timed_seval(jl, expr, label=func)
        except Exception as exc:
            raise RuntimeError(f"Julia call failed: {func}(...)\n{exc}") from exc
