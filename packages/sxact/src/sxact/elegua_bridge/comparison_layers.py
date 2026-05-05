"""Elegua comparison layer functions for xAct expression normalization.

Provides domain-specific layer functions that plug into elegua's
ComparisonPipeline:

- ``compare_canonical``: L3 canonical layer — normalizes both token
  reprs with ``ast_normalize`` and returns OK if they are equal.
"""

from __future__ import annotations

from elegua.models import ValidationToken
from elegua.task import TaskStatus
from sxact.normalize import ast_normalize


def compare_canonical(token_a: ValidationToken, token_b: ValidationToken) -> TaskStatus:
    """Layer 3 (canonical): normalize both reprs and compare.

    Extracts the ``repr`` string from each token's result dict, applies
    ``ast_normalize`` to both, and returns ``OK`` if they are equal.

    Returns ``MATH_MISMATCH`` if either result is absent or has no ``repr``.
    """
    if token_a.result is None or token_b.result is None:
        return TaskStatus.MATH_MISMATCH
    repr_a = token_a.result.get("repr")
    repr_b = token_b.result.get("repr")
    if repr_a is None or repr_b is None:
        return TaskStatus.MATH_MISMATCH
    if ast_normalize(str(repr_a)) == ast_normalize(str(repr_b)):
        return TaskStatus.OK
    return TaskStatus.MATH_MISMATCH
