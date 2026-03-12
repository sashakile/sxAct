"""Cross-file isolation integration tests.

Verify that manifold/tensor definitions from one test file do not pollute
subsequent test files, and that teardown + initialize correctly resets state.

Requires the Docker oracle server running with xAct loaded.
"""

import uuid
import warnings

import pytest

from sxact.adapter.wolfram import WolframAdapter
from sxact.oracle import OracleClient


@pytest.mark.oracle
@pytest.mark.slow
class TestCleanupEndpoint:
    """Verify /cleanup and /check-state oracle endpoints."""

    def test_cleanup_returns_ok(self, oracle: OracleClient) -> None:
        success = oracle.cleanup()
        assert success, "cleanup() should return True when oracle is available"

    def test_check_state_after_cleanup_is_clean(self, oracle: OracleClient) -> None:
        oracle.cleanup()
        is_clean, leaked = oracle.check_clean_state()
        assert is_clean, f"State should be clean after cleanup; leaked: {leaked}"

    def test_check_state_dirty_after_define_manifold(
        self, oracle: OracleClient
    ) -> None:
        # Define a manifold directly (no context_id → stays in Global/xAct registry)
        manifold_name = f"IsoTest{uuid.uuid4().hex[:4].upper()}"
        oracle.evaluate_with_xact(f"DefManifold[{manifold_name}, 4, {{a,b,c,d}}]")

        is_clean, leaked = oracle.check_clean_state()
        assert not is_clean, (
            f"State should be dirty after defining manifold {manifold_name}; "
            f"leaked: {leaked}"
        )
        assert any(manifold_name in s for s in leaked), (
            f"Leaked symbols should include {manifold_name}; got: {leaked}"
        )

        # Restore clean state for subsequent tests
        oracle.cleanup()


@pytest.mark.oracle
@pytest.mark.slow
class TestAdapterIsolation:
    """Verify WolframAdapter teardown/initialize provides file-level isolation."""

    def test_same_manifold_name_usable_in_consecutive_contexts(
        self, oracle: OracleClient
    ) -> None:
        """Defining the same manifold name in two consecutive adapter contexts
        must not raise 'symbol already defined' errors in the second context.
        """
        adapter = WolframAdapter(base_url=oracle.base_url)

        # First context: define manifold M
        ctx1 = adapter.initialize()
        result1 = adapter.execute(
            ctx1,
            "DefManifold",
            {
                "name": "IsoM",
                "dimension": 4,
                "indices": ["a", "b", "c", "d"],
            },
        )
        assert result1.status == "ok", f"First DefManifold failed: {result1.error}"
        adapter.teardown(ctx1)

        # Second context: same manifold name must be re-definable
        ctx2 = adapter.initialize()
        result2 = adapter.execute(
            ctx2,
            "DefManifold",
            {
                "name": "IsoM",
                "dimension": 4,
                "indices": ["a", "b", "c", "d"],
            },
        )
        assert result2.status == "ok", (
            f"Second DefManifold failed (isolation broken?): {result2.error}"
        )
        adapter.teardown(ctx2)

    def test_initialize_warns_and_restarts_on_dirty_kernel(
        self, oracle: OracleClient
    ) -> None:
        """If the kernel is dirty when initialize() is called (e.g. previous
        teardown failed), it should emit a RuntimeWarning and trigger restart.
        """
        # Manually leave the kernel dirty
        oracle.evaluate_with_xact("DefManifold[DirtyM, 4, {x,y,z,w}]")
        is_clean, _ = oracle.check_clean_state()
        assert not is_clean, "Pre-condition: kernel should be dirty"

        adapter = WolframAdapter(base_url=oracle.base_url)
        with warnings.catch_warnings(record=True) as caught:
            warnings.simplefilter("always")
            ctx = adapter.initialize()

        warning_messages = [str(w.message) for w in caught]
        assert any("dirty" in m.lower() for m in warning_messages), (
            f"Expected RuntimeWarning about dirty state; got: {warning_messages}"
        )

        # After forced restart, kernel should be clean and usable
        is_clean, leaked = oracle.check_clean_state()
        assert is_clean, f"Kernel should be clean after restart; leaked: {leaked}"

        adapter.teardown(ctx)


@pytest.mark.oracle
@pytest.mark.slow
class TestCrossFileSymbolLeakage:
    """Verify that symbols defined in file A are not visible in file B."""

    def test_manifold_from_file_a_absent_in_file_b(self, oracle: OracleClient) -> None:
        """Manifold defined in context A must be absent after teardown+cleanup."""
        adapter = WolframAdapter(base_url=oracle.base_url)

        # File A: define manifold
        ctx_a = adapter.initialize()
        adapter.execute(
            ctx_a,
            "DefManifold",
            {
                "name": "FileAManifold",
                "dimension": 4,
                "indices": ["a", "b", "c", "d"],
            },
        )
        adapter.teardown(ctx_a)

        # File B: FileAManifold should not exist
        ctx_b = adapter.initialize()
        result = adapter.execute(
            ctx_b,
            "Evaluate",
            {
                "expression": "MemberQ[Manifolds, FileAManifold]",
            },
        )
        assert result.status == "ok", f"Evaluate failed: {result.error}"
        assert result.repr.strip() == "False", (
            f"FileAManifold leaked from file A into file B; "
            f"MemberQ returned: {result.repr!r}"
        )
        adapter.teardown(ctx_b)
