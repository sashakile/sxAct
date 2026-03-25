"""Snapshot comparison: compare target adapter results against oracle snapshots.

Used by ``xact-test run --oracle-mode=snapshot`` to validate test results
against pre-generated oracle output without a live Wolfram Engine.

Comparison flow per test case:
1. Look up the oracle snapshot in the store (missing → MISSING outcome).
2. Verify the snapshot hash (corrupted → HASH_MISMATCH outcome).
3. Compare ``actual.normalized`` against ``snapshot.normalized_output``
   (Tier 1 string equality).
4. If the snapshot records properties and the actual result has properties,
   compare them too.

Public API::

    from sxact.snapshot.compare import SnapshotComparator, SnapshotCompareResult

    cmp = SnapshotComparator(store)
    result = cmp.compare(meta_id, test_id, actual_result)
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Literal

from sxact.oracle.result import Result
from sxact.snapshot.store import SnapshotStore

# ---------------------------------------------------------------------------
# Result type
# ---------------------------------------------------------------------------

Outcome = Literal["pass", "fail", "hash_mismatch", "missing"]


@dataclass(frozen=True)
class SnapshotCompareResult:
    """Outcome of comparing an actual result against an oracle snapshot.

    Attributes:
        test_id:             Test case identifier.
        outcome:             One of ``"pass"``, ``"fail"``,
                             ``"hash_mismatch"``, or ``"missing"``.
        actual_normalized:   Normalized output from the target adapter.
        expected_normalized: Normalized output from the oracle snapshot, or
                             ``None`` if the snapshot is missing.
        details:             Human-readable explanation of the outcome.
    """

    test_id: str
    outcome: Outcome
    actual_normalized: str
    expected_normalized: str | None
    details: str

    @property
    def passed(self) -> bool:
        return self.outcome == "pass"


# ---------------------------------------------------------------------------
# Comparator
# ---------------------------------------------------------------------------


class SnapshotComparator:
    """Compares actual adapter results against a :class:`~sxact.snapshot.store.SnapshotStore`.

    Args:
        store: A loaded :class:`~sxact.snapshot.store.SnapshotStore`.
    """

    def __init__(self, store: SnapshotStore) -> None:
        self._store = store

    def compare(
        self,
        meta_id: str,
        test_id: str,
        actual: Result,
    ) -> SnapshotCompareResult:
        """Compare *actual* against the stored oracle snapshot.

        Args:
            meta_id:  Test file meta ID (e.g. ``"xcore/basic"``).
            test_id:  Test case ID (e.g. ``"def_manifold_ok"``).
            actual:   The :class:`~sxact.oracle.result.Result` produced by
                      the target adapter for this test case.

        Returns:
            A :class:`SnapshotCompareResult` describing the outcome.
        """
        snap = self._store.load(meta_id, test_id)

        if snap is None:
            return SnapshotCompareResult(
                test_id=test_id,
                outcome="missing",
                actual_normalized=actual.normalized,
                expected_normalized=None,
                details=(
                    f"No oracle snapshot found for {meta_id}/{test_id}. "
                    "Run 'xact-test snapshot' to generate snapshots."
                ),
            )

        if not self._store.verify_hash(snap):
            return SnapshotCompareResult(
                test_id=test_id,
                outcome="hash_mismatch",
                actual_normalized=actual.normalized,
                expected_normalized=snap.normalized_output,
                details=(
                    f"Snapshot hash verification failed for {meta_id}/{test_id}. "
                    "The snapshot file may be corrupt or manually edited. "
                    "Re-run 'xact-test snapshot' to regenerate."
                ),
            )

        if actual.status != "ok":
            return SnapshotCompareResult(
                test_id=test_id,
                outcome="fail",
                actual_normalized=actual.normalized,
                expected_normalized=snap.normalized_output,
                details=f"Adapter returned {actual.status}: {actual.error or '(no message)'}",
            )

        if actual.normalized != snap.normalized_output:
            return SnapshotCompareResult(
                test_id=test_id,
                outcome="fail",
                actual_normalized=actual.normalized,
                expected_normalized=snap.normalized_output,
                details=(
                    f"Normalized output mismatch:\n"
                    f"  actual:   {actual.normalized!r}\n"
                    f"  expected: {snap.normalized_output!r}"
                ),
            )

        # Properties check: only when the snapshot recorded non-empty properties
        if snap.properties:
            prop_mismatch = _check_properties(actual.properties, snap.properties)
            if prop_mismatch:
                return SnapshotCompareResult(
                    test_id=test_id,
                    outcome="fail",
                    actual_normalized=actual.normalized,
                    expected_normalized=snap.normalized_output,
                    details=f"Properties mismatch: {prop_mismatch}",
                )

        return SnapshotCompareResult(
            test_id=test_id,
            outcome="pass",
            actual_normalized=actual.normalized,
            expected_normalized=snap.normalized_output,
            details="",
        )


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


def _check_properties(actual: dict[str, Any], expected: dict[str, Any]) -> str:
    """Return a human-readable description of property mismatches, or empty string."""
    mismatches = []
    for key, exp_val in expected.items():
        act_val = actual.get(key)
        if act_val != exp_val:
            mismatches.append(f"{key}: actual={act_val!r}, expected={exp_val!r}")
    return "; ".join(mismatches)
