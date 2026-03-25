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

"""List utilities, argument guards, stdlib aliases, and pure-Python shims."""

from __future__ import annotations

from collections.abc import Callable
from typing import Any

from . import _runtime

# ---------------------------------------------------------------------------
# 1. List utilities
# ---------------------------------------------------------------------------


def just_one(lst: Any) -> Any:
    """Return the single element of a one-element collection; raise otherwise.

    Julia: ``JustOne(list)``
    """
    return _runtime.get_xcore().JustOne(lst)


def map_if_plus(f: Callable[..., Any], expr: Any) -> Any:
    """Map *f* over a list, or apply once to a scalar.

    Julia: ``MapIfPlus(f, expr)``
    """
    return _runtime.get_xcore().MapIfPlus(f, expr)


def thread_array(head: Any, left: Any, right: Any) -> Any:
    """Map *head* over element pairs from *left* and *right*.

    Julia: ``ThreadArray(head, left, right)``
    """
    return _runtime.get_xcore().ThreadArray(head, left, right)


# ---------------------------------------------------------------------------
# 2. Argument guards
# ---------------------------------------------------------------------------


def set_number_of_arguments(f: Any, n: int) -> None:
    """No-op shim; Julia enforces arity via method dispatch.

    Julia: ``SetNumberOfArguments(f, n)``
    """
    _runtime.get_xcore().SetNumberOfArguments(f, n)


# ---------------------------------------------------------------------------
# 7. Unevaluated append (alias for push!)
# ---------------------------------------------------------------------------


def push_unevaluated(collection: list[Any], value: Any) -> list[Any]:
    """Append *value* to *collection* (Julia evaluates eagerly; this is push!).

    Julia: ``push_unevaluated!(collection, value)``
    """
    collection.append(value)
    return collection


# ---------------------------------------------------------------------------
# 9. Expression evaluation
# ---------------------------------------------------------------------------


def x_evaluate_at(expr: Any, positions: Any) -> Any:
    """No-op shim (Julia evaluates eagerly).

    Julia: ``xEvaluateAt(expr, positions)``
    """
    return expr


# ---------------------------------------------------------------------------
# Category B: stdlib aliases
# ---------------------------------------------------------------------------


def delete_duplicates(lst: list[Any]) -> list[Any]:
    """Remove duplicates from *lst*, preserving order.

    Julia: ``DeleteDuplicates`` (alias for ``unique``).
    """
    seen: set[Any] = set()
    result = []
    for item in lst:
        key = item if isinstance(item, str) else id(item)
        if key not in seen:
            seen.add(key)
            result.append(item)
    return result


def duplicate_free_q(lst: list[Any]) -> bool:
    """Return True if *lst* has no duplicate elements.

    Julia: ``DuplicateFreeQ`` (alias for ``allunique``).
    """
    return len(lst) == len(set(str(x) for x in lst))
