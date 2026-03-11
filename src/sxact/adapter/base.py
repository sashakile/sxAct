"""Abstract base class and supporting types for sxAct CAS adapters.

Every adapter (Wolfram, Julia, Python) must subclass TestAdapter and implement
all abstract methods.  The protocol is defined in:
  specs/2026-01-22-design-framework-gaps.md §5.2

Typical lifecycle per test file::

    adapter = MyAdapter()
    ctx = adapter.initialize()
    try:
        result = adapter.execute(ctx, "DefManifold", {"name": "M", "dimension": 4, ...})
        ...
    finally:
        adapter.teardown(ctx)
"""

from __future__ import annotations

import abc
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Generic, NewType, TypeVar

from sxact.oracle.result import Result

# ---------------------------------------------------------------------------
# Supporting types
# ---------------------------------------------------------------------------

NormalizedExpr = NewType("NormalizedExpr", str)
"""A normalized expression string (dummy indices renamed to $1,$2,…; terms sorted)."""

ContextT = TypeVar("ContextT")
"""Type variable for adapter-specific context objects."""


class EqualityMode(Enum):
    """Comparison tier to use when testing expression equality.

    Tiers are ordered by cost; use the lowest tier that is sufficient.
    """

    NORMALIZED = 1
    """Tier 1: fast normalized string comparison."""

    SEMANTIC = 2
    """Tier 2: symbolic difference simplifies to zero (Simplify[lhs - rhs] == 0)."""

    NUMERIC = 3
    """Tier 3: numeric sampling fallback for expressions with free indices."""


@dataclass(frozen=True)
class VersionInfo:
    """Version metadata reported by an adapter."""

    cas_name: str
    """Name of the underlying CAS (e.g. 'Wolfram', 'Julia', 'Python')."""

    cas_version: str
    """Version string of the CAS runtime (e.g. '14.0.0' for Mathematica)."""

    adapter_version: str
    """Version string of this adapter implementation."""

    extra: dict[str, Any] = field(default_factory=dict)
    """Any additional version-relevant metadata (xAct version, Julia pkg versions, …)."""


# ---------------------------------------------------------------------------
# Abstract base class
# ---------------------------------------------------------------------------


class TestAdapter(abc.ABC, Generic[ContextT]):
    """Abstract base class all CAS adapter implementations must conform to.

    Subclasses are responsible for one CAS backend (Wolfram, Julia, Python).
    Each instance may be shared across test files; isolation is enforced
    at the *context* level — one context per test file.

    Action vocabulary (valid values for the ``action`` parameter of
    :meth:`execute`) is defined in ``tests/schema/test-schema.json`` and
    mirrors the spec §5.1::

        DefManifold, DefMetric, DefTensor,
        Evaluate, ToCanonical, Simplify, Contract, Assert
    """

    # ------------------------------------------------------------------
    # Lifecycle
    # ------------------------------------------------------------------

    @abc.abstractmethod
    def initialize(self) -> ContextT:
        """Create and return a fresh CAS context.

        A new context represents an empty, isolated CAS session:
        - Wolfram: fresh kernel (no xAct symbols pre-loaded beyond xCore)
        - Julia: fresh module
        - Python: fresh Julia session (or subprocess)

        Returns:
            An opaque context object that is passed back to :meth:`execute`
            and :meth:`teardown`.  The type is adapter-specific.

        Raises:
            AdapterError: if the CAS runtime is unavailable or startup fails.
        """

    @abc.abstractmethod
    def teardown(self, ctx: ContextT) -> None:
        """Release resources associated with *ctx*.

        Called once per test file after all tests (pass or fail).
        Must not raise even if the context is in an error state.

        Args:
            ctx: The context returned by :meth:`initialize`.
        """

    # ------------------------------------------------------------------
    # Execution
    # ------------------------------------------------------------------

    @abc.abstractmethod
    def execute(self, ctx: ContextT, action: str, args: dict[str, Any]) -> Result:
        """Execute a single action in the given context.

        Args:
            ctx:    Context returned by :meth:`initialize`.
            action: One of the action names from the test vocabulary
                    (DefManifold, DefTensor, Evaluate, ToCanonical, …).
            args:   Action-specific keyword arguments matching the JSON Schema
                    ``args`` sub-object for that action.

        Returns:
            A :class:`~sxact.oracle.result.Result` envelope.  The ``status``
            field is always set; on failure ``status == "error"`` and
            ``error`` contains a human-readable message.  This method must
            **not** raise for recoverable execution errors — return an error
            Result instead.  Only raise for programming errors (e.g. unknown
            action name, wrong argument types).

        Raises:
            ValueError: if *action* is not in the supported vocabulary.
            TypeError:  if *args* has wrong types for the given action.
        """

    # ------------------------------------------------------------------
    # Comparison
    # ------------------------------------------------------------------

    @abc.abstractmethod
    def normalize(self, expr: str) -> NormalizedExpr:
        """Return the canonical normalized form of *expr*.

        The normalization pipeline (§5.3):
        1. Strip and collapse whitespace.
        2. Rename dummy indices to ``$1, $2, …`` in order of first appearance.
        3. Sort commutative (``Plus``) terms lexicographically.
        4. Normalize coefficients (``2*x → 2 x``, ``-1*x → -x``).

        Args:
            expr: Expression string in native CAS notation.

        Returns:
            Normalized form as a :data:`NormalizedExpr` (a typed ``str``).
        """

    @abc.abstractmethod
    def equals(
        self,
        a: NormalizedExpr,
        b: NormalizedExpr,
        mode: EqualityMode,
        ctx: ContextT | None = None,
    ) -> bool:
        """Test whether two normalized expressions are equal at the given tier.

        Args:
            a:    First normalized expression.
            b:    Second normalized expression.
            mode: Comparison tier to use.
            ctx:  Active context (required for SEMANTIC and NUMERIC modes
                  since they must execute CAS operations).  May be ``None``
                  for NORMALIZED mode.

        Returns:
            ``True`` if the expressions are equal at *mode* or any cheaper
            tier; ``False`` otherwise.

        Note:
            Implementations should attempt the cheapest tier first regardless
            of *mode* — i.e. always try NORMALIZED before SEMANTIC.
        """

    # ------------------------------------------------------------------
    # Introspection
    # ------------------------------------------------------------------

    @abc.abstractmethod
    def get_properties(self, expr: str, ctx: ContextT | None = None) -> dict[str, Any]:
        """Return structured properties of *expr*.

        The returned dict should contain zero or more of the keys defined in
        the schema ``properties`` object (``rank``, ``symmetry``, ``manifold``,
        ``type``), plus any adapter-specific extras.

        Args:
            expr: Expression string in native CAS notation.
            ctx:  Active context (needed if the adapter must query the CAS
                  to determine properties).  May be ``None`` for purely
                  syntactic analysis.

        Returns:
            A dict with string keys.  Never ``None``; return ``{}`` if no
            properties can be determined.
        """

    @abc.abstractmethod
    def get_version(self) -> VersionInfo:
        """Return version metadata for this adapter and its underlying CAS.

        Returns:
            A :class:`VersionInfo` dataclass.  All string fields must be
            non-empty.
        """

    # ------------------------------------------------------------------
    # Optional helpers (concrete, may be overridden)
    # ------------------------------------------------------------------

    def supported_actions(self) -> frozenset[str]:
        """Return the set of action names this adapter supports.

        The default implementation returns the full vocabulary.  Override to
        report a subset if the adapter does not yet implement all actions.
        """
        return frozenset(
            {
                "DefManifold",
                "DefMetric",
                "DefTensor",
                "DefBasis",
                "DefChart",
                "Evaluate",
                "ToCanonical",
                "Simplify",
                "Contract",
                "CommuteCovDs",
                "Assert",
                "DefPerturbation",
                "CheckMetricConsistency",
                "Perturb",
                "PerturbCurvature",
                "PerturbationOrder",
                "PerturbationAtOrder",
                "IntegrateByParts",
                "TotalDerivativeQ",
                "VarD",
                "SetBasisChange",
                "ChangeBasis",
                "GetJacobian",
                "BasisChangeQ",
            }
        )


# ---------------------------------------------------------------------------
# Sentinel error type
# ---------------------------------------------------------------------------


class AdapterError(RuntimeError):
    """Raised when an adapter fails in a way that cannot be represented as a
    Result (e.g. CAS runtime unavailable, authentication failure)."""
