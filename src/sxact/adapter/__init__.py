"""sxAct adapter interface.

Each CAS backend (Wolfram, Julia, Python) is implemented as a subclass of
:class:`~sxact.adapter.base.TestAdapter`.
"""

from sxact.adapter.base import (
    AdapterError,
    EqualityMode,
    NormalizedExpr,
    TestAdapter,
    VersionInfo,
)
from sxact.adapter.julia_stub import JuliaAdapter
from sxact.adapter.python_stub import PythonAdapter

__all__ = [
    "AdapterError",
    "EqualityMode",
    "JuliaAdapter",
    "NormalizedExpr",
    "PythonAdapter",
    "TestAdapter",
    "VersionInfo",
]
