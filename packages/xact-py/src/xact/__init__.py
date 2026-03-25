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

"""xact-py: Python wrapper for the sxAct Julia core.

Example::

    import xact

    M = xact.Manifold("M", 4, ["a", "b", "c", "d", "e", "f"])
    g = xact.Metric(M, "g", signature=-1, covd="CD")
    T = xact.Tensor("T", ["-a", "-b"], M, symmetry="Symmetric[{-a,-b}]")

    xact.canonicalize("T[-b,-a] - T[-a,-b]")  # "0"
"""

__version__ = "0.3.0"

from xact.api import (
    Basis,
    Chart,
    CTensor,
    Manifold,
    Metric,
    Perturbation,
    Tensor,
    all_contractions,
    basis_change_q,
    canonicalize,
    change_basis,
    check_metric_consistency,
    christoffel,
    collect_tensors,
    commute_covds,
    component_value,
    contract,
    ctensor_q,
    def_basis,
    def_chart,
    dimension,
    from_basis,
    get_components,
    get_jacobian,
    ibp,
    make_trace_free,
    perturb,
    perturb_curvature,
    perturbation_at_order,
    perturbation_order,
    reset,
    riemann_simplify,
    set_basis_change,
    set_components,
    simplify,
    sort_covds,
    symmetry_of,
    to_basis,
    total_derivative_q,
    trace_basis_dummy,
    var_d,
)
from xact.expr import (
    AppliedTensor,
    CovDExpr,
    CovDHead,
    DnIdx,
    Idx,
    TensorHead,
    covd,
    indices,
    tensor,
)

__all__ = [
    "Manifold",
    "Metric",
    "Tensor",
    "Perturbation",
    "canonicalize",
    "contract",
    "simplify",
    "perturb",
    "commute_covds",
    "sort_covds",
    "ibp",
    "total_derivative_q",
    "var_d",
    "riemann_simplify",
    "collect_tensors",
    "all_contractions",
    "symmetry_of",
    "make_trace_free",
    "check_metric_consistency",
    "perturb_curvature",
    "perturbation_order",
    "perturbation_at_order",
    "reset",
    "dimension",
    # xCoba — coordinate basis and chart infrastructure
    "Basis",
    "Chart",
    "CTensor",
    "def_basis",
    "def_chart",
    "set_basis_change",
    "change_basis",
    "get_jacobian",
    "basis_change_q",
    # xCoba — component storage and expression projection
    "set_components",
    "get_components",
    "component_value",
    "ctensor_q",
    "to_basis",
    "from_basis",
    "trace_basis_dummy",
    "christoffel",
    # Typed expression layer
    "Idx",
    "DnIdx",
    "TensorHead",
    "AppliedTensor",
    "CovDHead",
    "CovDExpr",
    "indices",
    "tensor",
    "covd",
]
