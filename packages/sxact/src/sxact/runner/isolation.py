"""Per-file test isolation and lifecycle management.

Implements the INIT → SETUP → TESTS → TEARDOWN state machine from
specs/2026-01-22-design-framework-gaps.md §5.4.

Public API::

    from sxact.runner.isolation import IsolatedContext, TestResult

    ctx = IsolatedContext(adapter, test_file)
    with ctx:
        for tc in test_file.tests:
            result = ctx.run_test(tc)
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any, Literal

from sxact.adapter.base import EqualityMode, TestAdapter
from sxact.oracle.result import Result
from sxact.runner.loader import TestCase, TestFile

# ---------------------------------------------------------------------------
# Result value object
# ---------------------------------------------------------------------------


@dataclass
class TestResult:
    """Outcome of running a single test case through an IsolatedContext."""

    __test__ = False  # prevent pytest from collecting this

    test_id: str
    status: Literal["pass", "fail", "skip", "error"]
    actual: str | None = None
    expected: str | None = None
    message: str | None = None


# ---------------------------------------------------------------------------
# IsolatedContext
# ---------------------------------------------------------------------------


class IsolatedContext:
    """Manages lifecycle and binding scope for a single TOML test file.

    State machine (§5.4)::

        INIT → SETUP → TESTS → TEARDOWN

    Binding scope::

        - Setup store_as  → available to ALL tests in the file
        - Per-test store_as → available only within that test; does not leak

    Usage::

        ctx = IsolatedContext(adapter, test_file)
        with ctx:
            for tc in test_file.tests:
                result = ctx.run_test(tc)

    The context manager calls :meth:`~TestAdapter.initialize` on entry and
    :meth:`~TestAdapter.teardown` on exit (even on exception).
    """

    def __init__(self, adapter: TestAdapter[Any], test_file: TestFile) -> None:
        self._adapter = adapter
        self._test_file = test_file
        self._ctx: Any = None
        self._setup_bindings: dict[str, str] = {}
        self._ready = False

    # ------------------------------------------------------------------
    # Context manager protocol
    # ------------------------------------------------------------------

    def __enter__(self) -> IsolatedContext:
        self._ctx = self._adapter.initialize()
        self._run_setup()
        self._ready = True
        return self

    def __exit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> None:
        if self._ctx is not None:
            self._adapter.teardown(self._ctx)
            self._ctx = None
        self._ready = False
        # returning None (falsy) means: do not suppress exceptions

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def run_test(self, tc: TestCase) -> TestResult:
        """Execute *tc* and return a :class:`TestResult`.

        Setup bindings are available for substitution.  Bindings produced
        by test operations are scoped to this invocation and do not leak
        to subsequent tests.

        Args:
            tc: A :class:`~sxact.runner.loader.TestCase` from the same
                :class:`~sxact.runner.loader.TestFile` passed at construction.

        Returns:
            A :class:`TestResult` with ``status`` one of
            ``"pass"``, ``"fail"``, ``"skip"``, ``"error"``.

        Raises:
            RuntimeError: if called outside the ``with`` block.
        """
        if not self._ready:
            raise RuntimeError("IsolatedContext must be used as a context manager")

        if tc.skip:
            return TestResult(test_id=tc.id, status="skip", message=tc.skip)

        # Per-test bindings start as a copy of setup bindings so that
        # additions within this test never propagate to subsequent tests.
        local_bindings: dict[str, str] = dict(self._setup_bindings)

        expects_error = tc.expected is not None and tc.expected.expect_error

        last_result: Result | None = None
        try:
            for op in tc.operations:
                resolved_args = _substitute_bindings(op.args, local_bindings)
                last_result = self._adapter.execute(self._ctx, op.action, resolved_args)
                if op.store_as and last_result.repr:
                    local_bindings[op.store_as] = last_result.repr
        except Exception as exc:
            if expects_error:
                return TestResult(test_id=tc.id, status="pass", message=str(exc))
            return TestResult(test_id=tc.id, status="error", message=str(exc))

        if last_result is None:
            if expects_error:
                return TestResult(
                    test_id=tc.id,
                    status="fail",
                    message="Expected error but no operations produced a result",
                )
            return TestResult(test_id=tc.id, status="pass")

        if last_result.status == "error":
            if expects_error:
                return TestResult(
                    test_id=tc.id,
                    status="pass",
                    actual=last_result.repr,
                    message=last_result.error,
                )
            return TestResult(
                test_id=tc.id,
                status="error",
                actual=last_result.repr,
                message=last_result.error,
            )

        return self._evaluate_expected(tc, last_result, local_bindings)

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _run_setup(self) -> None:
        """Execute setup operations, populating ``_setup_bindings``."""
        for op in self._test_file.setup:
            resolved_args = _substitute_bindings(op.args, self._setup_bindings)
            result = self._adapter.execute(self._ctx, op.action, resolved_args)
            if op.store_as and result.repr:
                self._setup_bindings[op.store_as] = result.repr

    def _evaluate_expected(
        self,
        tc: TestCase,
        result: Result,
        bindings: dict[str, str],
    ) -> TestResult:
        """Compare *result* against ``tc.expected``; return pass or fail."""
        exp = tc.expected
        if exp is None:
            return TestResult(test_id=tc.id, status="pass", actual=result.repr)

        if exp.expect_error:
            return TestResult(
                test_id=tc.id,
                status="fail",
                actual=result.repr,
                message="Expected error but operation succeeded",
            )

        actual_norm = self._adapter.normalize(result.repr or "")

        # --- expr: normalized equality check ---
        if exp.expr is not None:
            expected_text = _sub_refs(exp.expr, bindings)
            expected_norm = self._adapter.normalize(expected_text)
            mode = (
                EqualityMode(exp.comparison_tier)
                if exp.comparison_tier
                else EqualityMode.NORMALIZED
            )
            if not self._adapter.equals(actual_norm, expected_norm, mode, self._ctx):
                return TestResult(
                    test_id=tc.id,
                    status="fail",
                    actual=result.repr,
                    expected=exp.expr,
                    message=f"Expression mismatch: got {result.repr!r}, expected {exp.expr!r}",
                )

        # --- normalized: literal normalized-form check ---
        if exp.normalized is not None and actual_norm != exp.normalized:
            return TestResult(
                test_id=tc.id,
                status="fail",
                actual=str(actual_norm),
                expected=exp.normalized,
                message=(
                    f"Normalized form mismatch: got {actual_norm!r}, expected {exp.normalized!r}"
                ),
            )

        # --- is_zero: compare normalized output to canonical zero ---
        if exp.is_zero is not None:
            zero_norm = self._adapter.normalize("0")
            actually_zero = actual_norm == zero_norm
            if actually_zero != exp.is_zero:
                return TestResult(
                    test_id=tc.id,
                    status="fail",
                    actual=result.repr,
                    message=f"is_zero check failed: expected {exp.is_zero}, got {actually_zero}",
                )

        # --- properties checks ---
        if exp.properties is not None:
            props = result.properties or {}
            for attr, key in [
                ("rank", "rank"),
                ("type", "type"),
                ("manifold", "manifold"),
            ]:
                expected_val = getattr(exp.properties, attr)
                if expected_val is not None and props.get(key) != expected_val:
                    return TestResult(
                        test_id=tc.id,
                        status="fail",
                        actual=str(props.get(key)),
                        expected=str(expected_val),
                        message=(
                            f"Property {key!r} mismatch: "
                            f"got {props.get(key)!r}, expected {expected_val!r}"
                        ),
                    )

        return TestResult(test_id=tc.id, status="pass", actual=result.repr)


# ---------------------------------------------------------------------------
# Binding helpers
# ---------------------------------------------------------------------------

_REF_RE = re.compile(r"\$(\w+)")


def _sub_refs(text: str, bindings: dict[str, str]) -> str:
    """Replace ``$name`` occurrences in *text* with bound values."""
    return _REF_RE.sub(lambda m: bindings.get(m.group(1), m.group(0)), text)


def _substitute_bindings(args: dict[str, Any], bindings: dict[str, str]) -> dict[str, Any]:
    """Return a copy of *args* with ``$name`` references substituted."""
    return {
        key: _sub_refs(val, bindings) if isinstance(val, str) else val for key, val in args.items()
    }
