"""Snapshot runner: drives TOML test files against the live Wolfram oracle.

Produces :class:`FileSnapshot` / :class:`TestSnapshot` value objects that can
be handed to :mod:`sxact.snapshot.writer` to persist as the oracle directory.

Public API::

    from sxact.snapshot.runner import run_file, FileSnapshot, TestSnapshot

    snap = run_file(test_file, adapter)
"""

from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from sxact.adapter.wolfram import WolframAdapter
from sxact.oracle.result import Result
from sxact.runner.loader import Operation, TestCase, TestFile

# ---------------------------------------------------------------------------
# Value objects
# ---------------------------------------------------------------------------


@dataclass
class TestSnapshot:
    """Captured oracle output for a single test case, matching the spec §5.6 JSON."""

    __test__ = False  # prevent pytest from treating this as a test class

    test_id: str
    oracle_version: str
    mathematica_version: str
    timestamp: str
    commands: str
    raw_output: str
    normalized_output: str
    properties: dict[str, Any]
    hash: str


@dataclass
class FileSnapshot:
    """All snapshots produced from a single TOML test file."""

    __test__ = False

    meta_id: str  # TestFile.meta.id, e.g. "xcore/basic"
    source_path: Path
    tests: list[TestSnapshot] = field(default_factory=list)


# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------


def run_file(test_file: TestFile, adapter: WolframAdapter) -> FileSnapshot:
    """Run every test case in *test_file* against the oracle and capture snapshots.

    Setup operations are executed once to establish context.  Each test case's
    operations are then executed in sequence; the result of the final operation
    becomes the snapshot's ``raw_output``.

    ``$name`` references in operation args are resolved against the ``store_as``
    bindings accumulated so far (setup bindings + per-test bindings).

    Args:
        test_file: Loaded TOML test file.
        adapter:   Initialized WolframAdapter connected to a live oracle.

    Returns:
        A :class:`FileSnapshot` containing one :class:`TestSnapshot` per
        non-skipped test case.

    Raises:
        AdapterError: if the oracle is unreachable before setup starts.
    """
    version = adapter.get_version()
    xact_version = version.extra.get("xact_version", "1.2.0")
    oracle_ver = f"xAct {xact_version}"
    math_ver = version.cas_version

    ctx = adapter.initialize()
    try:
        bindings: dict[str, str] = {}
        setup_commands: list[str] = []

        for op in test_file.setup:
            expr, result = _run_op(adapter, ctx, op, bindings)
            setup_commands.append(expr)
            if op.store_as and result.repr:
                bindings[op.store_as] = result.repr

        file_snap = FileSnapshot(
            meta_id=test_file.meta.id,
            source_path=test_file.source_path,
        )
        timestamp = _utc_now()

        for tc in test_file.tests:
            if tc.skip:
                continue

            snap = _snapshot_test(
                tc,
                adapter=adapter,
                ctx=ctx,
                setup_commands=setup_commands,
                bindings=dict(bindings),  # copy so per-test bindings don't leak
                oracle_version=oracle_ver,
                mathematica_version=math_ver,
                timestamp=timestamp,
            )
            file_snap.tests.append(snap)

    finally:
        adapter.teardown(ctx)

    return file_snap


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


def _snapshot_test(
    tc: TestCase,
    *,
    adapter: WolframAdapter,
    ctx: Any,
    setup_commands: list[str],
    bindings: dict[str, str],
    oracle_version: str,
    mathematica_version: str,
    timestamp: str,
) -> TestSnapshot:
    """Execute a single test case and return its snapshot."""
    test_commands: list[str] = []
    raw_output = ""
    normalized_output = ""
    properties: dict[str, Any] = {}

    for op in tc.operations:
        expr, result = _run_op(adapter, ctx, op, bindings)
        test_commands.append(expr)
        if op.store_as:
            if not result.repr:
                raise ValueError(
                    f"Operation {op.action!r} required binding ${op.store_as!r} "
                    f"but returned no output (status={result.status!r})"
                )
            bindings[op.store_as] = result.repr
        if result.status == "ok":
            raw_output = result.repr
            normalized_output = result.normalized
            properties = result.properties

    all_commands = "\n".join(setup_commands + test_commands)
    return TestSnapshot(
        test_id=tc.id,
        oracle_version=oracle_version,
        mathematica_version=mathematica_version,
        timestamp=timestamp,
        commands=all_commands,
        raw_output=raw_output,
        normalized_output=normalized_output,
        properties=properties,
        hash=compute_oracle_hash(normalized_output, properties),
    )


def _run_op(
    adapter: WolframAdapter,
    ctx: Any,
    op: Operation,
    bindings: dict[str, str],
) -> tuple[str, Result]:
    """Substitute bindings, build the Wolfram expression, execute, return both."""
    resolved_args = _substitute_bindings(op.args, bindings)

    try:
        expr = adapter._build_expr(op.action, resolved_args)
    except (KeyError, ValueError):
        expr = f"{op.action}[...]"

    result = adapter.execute(ctx, op.action, resolved_args)
    return expr, result


def _substitute_bindings(args: dict[str, Any], bindings: dict[str, str]) -> dict[str, Any]:
    """Return a copy of *args* with ``$name`` references replaced by bound values."""
    return {
        key: _sub_refs(val, bindings) if isinstance(val, str) else val for key, val in args.items()
    }


_REF_RE = re.compile(r"\$(\w+)")


def _sub_refs(text: str, bindings: dict[str, str]) -> str:
    """Replace ``$name`` occurrences in *text* with bound values."""
    return _REF_RE.sub(lambda m: bindings.get(m.group(1), m.group(0)), text)


def _utc_now() -> str:
    return datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


# ---------------------------------------------------------------------------
# Hash computation (spec §5.6)
# ---------------------------------------------------------------------------


def compute_oracle_hash(normalized_output: str, properties: dict[str, Any]) -> str:
    """Compute the snapshot hash as specified in §5.6.

    Only ``normalized_output`` and ``properties`` participate in the hash so
    that cosmetic changes to raw output don't invalidate snapshots.
    """
    canonical = json.dumps(
        {"normalized_output": normalized_output, "properties": properties},
        sort_keys=True,
    )
    return f"sha256:{hashlib.sha256(canonical.encode()).hexdigest()[:12]}"
