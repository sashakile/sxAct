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

"""xUpvalues, tag assignment, extensions system, and misc."""

from __future__ import annotations

from collections.abc import Callable
from typing import Any

from . import _runtime
from .symbols import _sym

# ---------------------------------------------------------------------------
# 5. xUpvalues
# ---------------------------------------------------------------------------


def sub_head(expr: Any) -> Any:
    """Return the innermost atomic head of a nested expression.

    Julia: ``SubHead(expr)``
    """
    return _runtime.get_xcore().SubHead(expr)


def x_up_set(property: str | Any, tag: str | Any, value: Any) -> Any:
    """Attach *value* as the *property* upvalue of *tag*.

    Julia: ``xUpSet!(property, tag, value)``
    """
    return _runtime.get_xcore().xUpSet_b(_sym(property), _sym(tag), value)


def x_up_set_delayed(property: str | Any, tag: str | Any, thunk: Callable[[], Any]) -> None:
    """Attach a zero-argument thunk as a delayed upvalue.

    Julia: ``xUpSetDelayed!(property, tag, thunk)``
    """
    _runtime.get_xcore().xUpSetDelayed_b(_sym(property), _sym(tag), thunk)


def x_up_append_to(property: str | Any, tag: str | Any, element: Any) -> list[Any]:
    """Append *element* to the upvalue list *property[tag]*.

    Julia: ``xUpAppendTo!(property, tag, element)``
    """
    result = _runtime.get_xcore().xUpAppendTo_b(_sym(property), _sym(tag), element)
    return list(result)


def x_up_delete_cases_to(property: str | Any, tag: str | Any, pred: Callable[[Any], bool]) -> None:
    """Remove all upvalue-list elements satisfying *pred*.

    Julia: ``xUpDeleteCasesTo!(property, tag, pred)``
    """
    _runtime.get_xcore().xUpDeleteCasesTo_b(_sym(property), _sym(tag), pred)


# ---------------------------------------------------------------------------
# 6. Tag assignment
# ---------------------------------------------------------------------------


def x_tag_set(tag: str | Any, key: Any, value: Any) -> Any:
    """Assign *value* to *key* in the tag store for *tag*.

    Julia: ``xTagSet!(tag, key, value)``
    """
    return _runtime.get_xcore().xTagSet_b(_sym(tag), key, value)


def x_tag_set_delayed(tag: str | Any, key: Any, thunk: Callable[[], Any]) -> None:
    """Delayed variant of :func:`x_tag_set`.

    Julia: ``xTagSetDelayed!(tag, key, thunk)``
    """
    _runtime.get_xcore().xTagSetDelayed_b(_sym(tag), key, thunk)


# ---------------------------------------------------------------------------
# 8. Extensions system
# ---------------------------------------------------------------------------


def x_tension(
    package: str,
    defcommand: str | Any,
    moment: str,
    func: Callable[..., Any],
) -> None:
    """Register *func* to fire at *moment* during *defcommand*.

    *moment* must be ``"Beginning"`` or ``"End"``.

    Julia: ``xTension!(package, defcommand, moment, func)``
    """
    _runtime.get_xcore().xTension_b(package, _sym(defcommand), moment, func)


def make_x_tensions(defcommand: str | Any, moment: str, *args: Any) -> None:
    """Fire all hooks registered for *(defcommand, moment)*.

    Julia: ``MakexTensions(defcommand, moment, args...)``
    """
    _runtime.get_xcore().MakexTensions(_sym(defcommand), moment, *args)


# ---------------------------------------------------------------------------
# 11. Misc
# ---------------------------------------------------------------------------


def disclaimer() -> None:
    """Print the GPL warranty disclaimer.

    Julia: ``Disclaimer()``
    """
    _runtime.get_xcore().Disclaimer()
