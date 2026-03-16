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

"""Options validation and related utilities."""

from __future__ import annotations

from typing import Any

from . import _runtime


# ---------------------------------------------------------------------------
# 3. Options
# ---------------------------------------------------------------------------


def check_options(*opts: Any) -> list[tuple[Any, Any]]:
    """Validate and flatten option rules.

    Each argument may be a ``(key, value)`` tuple, a dict, or a list of
    ``(key, value)`` tuples.  Returns a flat list of ``(key, value)`` pairs
    on success; raises ``ValueError`` on invalid structure.

    Julia: ``CheckOptions(opts...)``
    """
    flat: list[tuple[Any, Any]] = []
    for o in opts:
        if isinstance(o, dict):
            flat.extend(o.items())
        elif isinstance(o, (list, tuple)):
            if len(o) == 2 and not isinstance(o[0], (list, tuple, dict)):
                flat.append((o[0], o[1]))
            else:
                for item in o:
                    if isinstance(item, (list, tuple)) and len(item) == 2:
                        flat.append((item[0], item[1]))
                    else:
                        raise ValueError(
                            f"check_options: expected (key, value) pair, got {item!r}"
                        )
        else:
            raise ValueError(
                f"check_options: expected dict or (key, value) pair, got {o!r}"
            )
    return flat


def true_or_false(x: Any) -> bool:
    """Return True if *x* is a bool; False otherwise.

    Julia: ``TrueOrFalse(x)``
    """
    return bool(_runtime.get_xcore().TrueOrFalse(x))


def report_set(ref: Any, value: Any, *, verbose: bool = True) -> None:
    """Assign *value* to *ref[]*, printing if changed.

    Julia: ``ReportSet(ref, value; verbose=verbose)``
    """
    _runtime.get_xcore().ReportSet(ref, value, verbose=verbose)


def report_set_option(symbol: Any, pair: tuple[Any, Any]) -> None:
    """No-op shim.

    Julia: ``ReportSetOption(symbol, pair)``
    """
    # no-op; matches Julia behaviour
    pass
