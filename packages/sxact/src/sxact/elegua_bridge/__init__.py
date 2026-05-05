"""Elegua integration bridge for sxAct.

Provides domain-specific components that plug into the Elegua testing framework:
- ``build_xact_expr``: action→Wolfram expression builder for OracleAdapter
- ``compare_canonical``: L3 canonical comparison layer for ComparisonPipeline
- ``make_compare_numeric``: factory for L4 numeric sampling layer
- ``EleguaPythonAdapter``: elegua.Adapter wrapper for xact-py backend
- ``EleguaJuliaAdapter``: elegua.Adapter wrapper for Julia XCore + XTensor backend
"""

from sxact.elegua_bridge.adapters import EleguaJuliaAdapter, EleguaPythonAdapter, EleguaWolframAdapter
from sxact.elegua_bridge.comparison_layers import compare_canonical, make_compare_numeric
from sxact.elegua_bridge.expr_builder import build_xact_expr

__all__ = [
    "EleguaJuliaAdapter",
    "EleguaPythonAdapter",
    "EleguaWolframAdapter",
    "build_xact_expr",
    "compare_canonical",
    "make_compare_numeric",
]
