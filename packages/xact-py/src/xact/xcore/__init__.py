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

"""Python wrapper for the Julia XCore module.

Exposes all public XCore functions under the ``xact.xcore`` namespace with
Python-idiomatic (snake_case) names.  Julia is initialised once per process
on first import of this module.

Type conventions
----------------
- Symbol arguments accept Python ``str``; the wrapper converts to Julia Symbol.
- Symbol return values are returned as Python ``str``.
- Vector{Symbol} arguments accept ``list[str]``.
- Vector{Symbol} return values are returned as ``list[str]``.
- Julia exceptions are re-raised as :class:`juliacall.JuliaError`.

Example
-------
>>> from xact.xcore import validate_symbol
>>> validate_symbol("MyNewTensor")   # raises if name collides
"""

from __future__ import annotations

from ._runtime import get_julia as get_julia, get_xcore as get_xcore

try:
    from juliacall import JuliaError
except ImportError as exc:  # pragma: no cover
    raise ImportError(
        "juliacall is required for xact.xcore.  Install it with: pip install juliacall"
    ) from exc

from .list_utils import (
    just_one,
    map_if_plus,
    thread_array,
    set_number_of_arguments,
    push_unevaluated,
    x_evaluate_at,
    delete_duplicates,
    duplicate_free_q,
)
from .options import (
    check_options,
    true_or_false,
    report_set,
    report_set_option,
)
from .symbols import (
    symbol_join,
    no_pattern,
    dagger_character,
    set_dagger_character,
    has_dagger_character_q,
    make_dagger_symbol,
    link_character,
    set_link_character,
    link_symbols,
    unlink_symbol,
    validate_symbol,
    find_symbols,
    register_symbol,
    x_perm_names,
    x_tensor_names,
    x_core_names,
    x_tableau_names,
    x_coba_names,
    invar_names,
    harmonics_names,
    x_pert_names,
    spinors_names,
    em_names,
    warning_from,
    set_warning_from,
    xact_directory,
    set_xact_directory,
    xact_doc_directory,
    set_xact_doc_directory,
)
from .upvalues import (
    sub_head,
    x_up_set,
    x_up_set_delayed,
    x_up_append_to,
    x_up_delete_cases_to,
    x_tag_set,
    x_tag_set_delayed,
    x_tension,
    make_x_tensions,
    disclaimer,
)

__all__ = [
    "JuliaError",
    # 1. List utilities
    "just_one",
    "map_if_plus",
    "thread_array",
    # 2. Argument guards
    "set_number_of_arguments",
    # 3. Options
    "check_options",
    "true_or_false",
    "report_set",
    "report_set_option",
    # 4. Symbol naming
    "symbol_join",
    "no_pattern",
    "dagger_character",
    "set_dagger_character",
    "has_dagger_character_q",
    "make_dagger_symbol",
    "link_character",
    "set_link_character",
    "link_symbols",
    "unlink_symbol",
    # 5. xUpvalues
    "sub_head",
    "x_up_set",
    "x_up_set_delayed",
    "x_up_append_to",
    "x_up_delete_cases_to",
    # 6. Tag assignment
    "x_tag_set",
    "x_tag_set_delayed",
    # 7. Unevaluated append
    "push_unevaluated",
    # 8. Extensions
    "x_tension",
    "make_x_tensions",
    # 9. Expression evaluation
    "x_evaluate_at",
    # 10. Symbol registry
    "validate_symbol",
    "find_symbols",
    "register_symbol",
    "x_perm_names",
    "x_tensor_names",
    "x_core_names",
    "x_tableau_names",
    "x_coba_names",
    "invar_names",
    "harmonics_names",
    "x_pert_names",
    "spinors_names",
    "em_names",
    "warning_from",
    "set_warning_from",
    "xact_directory",
    "set_xact_directory",
    "xact_doc_directory",
    "set_xact_doc_directory",
    # Category B
    "delete_duplicates",
    "duplicate_free_q",
    # 11. Misc
    "disclaimer",
]
