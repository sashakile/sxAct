"""Elegua integration bridge for sxAct.

Provides domain-specific components that plug into the Elegua testing framework:
- ``build_xact_expr``: action→Wolfram expression builder for OracleAdapter
- ``compare_canonical``: L3 canonical comparison layer for ComparisonPipeline
"""

from sxact.elegua_bridge.comparison_layers import compare_canonical
from sxact.elegua_bridge.expr_builder import build_xact_expr

__all__ = ["build_xact_expr", "compare_canonical"]
