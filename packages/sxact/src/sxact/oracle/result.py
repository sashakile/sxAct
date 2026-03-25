"""Result dataclass for Oracle responses."""

from dataclasses import dataclass, field
from typing import Any, Literal


@dataclass
class Result:
    """Structured result from evaluating a Wolfram/xAct expression.

    Attributes:
        status: Evaluation status - "ok", "error", or "timeout"
        type: Expression type - Expr, Scalar, Bool, Handle, etc.
        repr: Raw string representation from Wolfram
        normalized: Normalized form for comparison
        properties: Extracted properties (rank, symmetry, manifold, etc.)
        diagnostics: Execution info (execution_time_ms, memory_mb, etc.)
        error: Error message if status is "error"
    """

    status: Literal["ok", "error", "timeout"]
    type: str
    repr: str
    normalized: str
    properties: dict[str, Any] = field(default_factory=dict)
    diagnostics: dict[str, Any] = field(default_factory=dict)
    error: str | None = None
