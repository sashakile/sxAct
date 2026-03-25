"""Tensor object representations for numeric sampling (Tier 3).

Provides dataclasses for Manifold, Metric, and Tensor objects plus
random generation routines.  Used by sampling.py when comparing tensor
expressions numerically.

Design notes
------------
- Dimensions are kept small (2–4) to keep contraction fast.
- Metrics are generated to be well-conditioned (Cholesky-based) so that
  inverse computations during contraction don't blow up.
- Symmetry constraints are enforced by projecting after random generation,
  not by constructing symmetric matrices from scratch — this keeps the code
  simple and the generation uniform.
"""

from __future__ import annotations

import random
from dataclasses import dataclass
from typing import Any, Literal

import numpy as np

Symmetry = Literal["Symmetric", "Antisymmetric", None]


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------


@dataclass
class Manifold:
    """A Riemannian/pseudo-Riemannian manifold."""

    name: str
    dimension: int

    def __post_init__(self) -> None:
        if self.dimension < 1:
            raise ValueError(f"Manifold dimension must be >= 1, got {self.dimension}")


@dataclass
class Metric:
    """A metric tensor on a Manifold."""

    name: str
    manifold: Manifold
    signature: int = 0
    """Number of negative eigenvalues (0 = Euclidean, 1 = Lorentzian, etc.)"""

    @property
    def dimension(self) -> int:
        return self.manifold.dimension


@dataclass
class TensorField:
    """A tensor field on a Manifold with optional symmetry."""

    name: str
    rank: int
    manifold: Manifold
    symmetry: Symmetry = None

    @property
    def dimension(self) -> int:
        return self.manifold.dimension


# ---------------------------------------------------------------------------
# Random generation
# ---------------------------------------------------------------------------


def random_manifold(name: str = "M", rng: random.Random | None = None) -> Manifold:
    """Generate a Manifold with random dimension in [2, 4]."""
    r = rng or random.Random()
    return Manifold(name=name, dimension=r.randint(2, 4))


def random_metric_array(
    metric: Metric, rng: np.random.Generator | None = None
) -> np.ndarray[Any, np.dtype[Any]]:
    """Generate a random well-conditioned metric array.

    Uses the Cholesky construction: M = A^T A + eps*I to guarantee positive
    definiteness (Euclidean case).  For pseudo-Riemannian metrics the
    signature eigenvalues are negated after construction.

    Returns:
        Shape (n, n) float64 array representing g_{ab}.
    """
    n = metric.dimension
    rng = rng or np.random.default_rng()

    # Build positive-definite base via Cholesky
    A = rng.standard_normal((n, n))
    base = A.T @ A + 0.1 * np.eye(n)  # eps=0.1 ensures well-conditioned

    # Flip eigenvalues for pseudo-Riemannian signature
    neg = metric.signature
    if neg > 0:
        vals, vecs = np.linalg.eigh(base)
        vals[:neg] *= -1  # smallest eigenvalues → negative
        base = vecs @ np.diag(vals) @ vecs.T

    return base


def random_tensor_array(
    tensor: TensorField, rng: np.random.Generator | None = None
) -> np.ndarray[Any, np.dtype[Any]]:
    """Generate a random tensor component array respecting symmetry.

    Returns:
        Shape (n,) * rank float64 array for tensor components T_{a1...ak}.
    """
    n = tensor.dimension
    rng = rng or np.random.default_rng()

    shape = (n,) * tensor.rank
    arr = rng.standard_normal(shape)

    if tensor.rank < 2 or tensor.symmetry is None:
        return arr

    # Symmetrize or antisymmetrize over all pairs of axes
    # For rank-2 this is exact; for higher rank we do pairwise passes
    if tensor.symmetry == "Symmetric":
        arr = _symmetrize(arr)
    elif tensor.symmetry == "Antisymmetric":
        arr = _antisymmetrize(arr)

    return arr


def _symmetrize(arr: np.ndarray[Any, np.dtype[Any]]) -> np.ndarray[Any, np.dtype[Any]]:
    """Average over all permutations (exact for rank 2, approximate for higher)."""
    from itertools import permutations

    rank = arr.ndim
    result = np.zeros_like(arr)
    count = 0
    for perm in permutations(range(rank)):
        result += np.transpose(arr, perm)
        count += 1
    return result / count


def _antisymmetrize(
    arr: np.ndarray[Any, np.dtype[Any]],
) -> np.ndarray[Any, np.dtype[Any]]:
    """Antisymmetrize by averaging signed permutations."""
    from itertools import permutations
    from math import perm as _  # noqa: F401

    def _sign(p: tuple[int, ...]) -> int:
        """Compute permutation sign via inversion count."""
        inversions = sum(1 for i in range(len(p)) for j in range(i + 1, len(p)) if p[i] > p[j])
        return 1 if inversions % 2 == 0 else -1

    rank = arr.ndim
    result = np.zeros_like(arr)
    count = 0
    for perm in permutations(range(rank)):
        result += _sign(perm) * np.transpose(arr, perm)
        count += 1
    return result / count
