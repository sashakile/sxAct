"""Subcommand: run – execute tests and report pass/fail results.

Also owns shared types and helpers used across CLI subcommands.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


# ---------------------------------------------------------------------------
# Shared internal types
# ---------------------------------------------------------------------------


@dataclass
class _RunResult:
    """Outcome of a single test case within xact-test run."""

    file_id: str
    test_id: str
    status: str  # "pass", "fail", "error", "skip", "missing"
    actual: str | None = None
    expected: str | None = None
    message: str | None = None


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

_REF_RE = re.compile(r"\$(\w+)")


def _make_adapter(args: argparse.Namespace) -> Any:
    """Instantiate the adapter specified by args.adapter."""
    name = getattr(args, "adapter", "wolfram")
    oracle_url = getattr(args, "oracle_url", "http://localhost:8765")
    timeout = getattr(args, "timeout", 60)

    if name == "wolfram":
        from sxact.adapter.wolfram import WolframAdapter

        return WolframAdapter(base_url=oracle_url, timeout=timeout)
    elif name == "julia":
        from sxact.adapter.julia_stub import JuliaAdapter

        return JuliaAdapter()
    elif name == "python":
        from sxact.adapter.python_stub import PythonAdapter

        return PythonAdapter()
    else:
        raise ValueError(f"Unknown adapter: {name!r}")


def _make_adapter_by_name(name: str, args: argparse.Namespace) -> Any:
    """Create an adapter by explicit name, using args for URL/timeout."""
    oracle_url = getattr(args, "oracle_url", "http://localhost:8765")
    timeout = getattr(args, "timeout", 60)
    if name == "wolfram":
        from sxact.adapter.wolfram import WolframAdapter

        return WolframAdapter(base_url=oracle_url, timeout=timeout)
    elif name == "julia":
        from sxact.adapter.julia_stub import JuliaAdapter

        return JuliaAdapter()
    elif name == "python":
        from sxact.adapter.python_stub import PythonAdapter

        return PythonAdapter()
    else:
        raise ValueError(f"Unknown adapter: {name!r}")


def _tc_matches_tag(tc_tags: list[str], file_tags: list[str], tag: str) -> bool:
    return tag in tc_tags or tag in file_tags


def _sub_bindings(args: dict[str, Any], bindings: dict[str, str]) -> dict[str, Any]:
    def _sub(val: str) -> str:
        return _REF_RE.sub(lambda m: bindings.get(m.group(1), m.group(0)), val)

    return {k: _sub(v) if isinstance(v, str) else v for k, v in args.items()}


# ---------------------------------------------------------------------------
# File runners
# ---------------------------------------------------------------------------


def _run_file_live(
    test_file: Any, adapter: Any, tag_filter: str | None
) -> list[_RunResult]:
    """Run a test file in live mode using IsolatedContext."""
    from sxact.runner.isolation import IsolatedContext

    results: list[_RunResult] = []
    with IsolatedContext(adapter, test_file) as iso:
        for tc in test_file.tests:
            if tag_filter and not _tc_matches_tag(
                tc.tags, test_file.meta.tags, tag_filter
            ):
                continue
            tr = iso.run_test(tc)
            results.append(
                _RunResult(
                    file_id=test_file.meta.id,
                    test_id=tc.id,
                    status=tr.status,
                    actual=tr.actual,
                    expected=tr.expected,
                    message=tr.message,
                )
            )
    return results


def _run_file_snapshot(
    test_file: Any, adapter: Any, tag_filter: str | None, store: Any
) -> list[_RunResult]:
    """Run a test file in snapshot mode, comparing against oracle snapshots."""
    from sxact.snapshot.compare import SnapshotComparator

    comparator = SnapshotComparator(store)
    results: list[_RunResult] = []

    ctx = adapter.initialize()
    try:
        # Run setup operations, building shared bindings
        bindings: dict[str, str] = {}
        for op in test_file.setup:
            resolved = _sub_bindings(op.args, bindings)
            res = adapter.execute(ctx, op.action, resolved)
            if op.store_as and res.repr:
                bindings[op.store_as] = res.repr

        for tc in test_file.tests:
            if tag_filter and not _tc_matches_tag(
                tc.tags, test_file.meta.tags, tag_filter
            ):
                continue

            if tc.skip:
                results.append(
                    _RunResult(
                        file_id=test_file.meta.id,
                        test_id=tc.id,
                        status="skip",
                        message=tc.skip,
                    )
                )
                continue

            # Run test operations with per-test binding scope
            local = dict(bindings)
            last_res = None
            error_msg: str | None = None
            try:
                for op in tc.operations:
                    resolved = _sub_bindings(op.args, local)
                    last_res = adapter.execute(ctx, op.action, resolved)
                    if op.store_as and last_res.repr:
                        local[op.store_as] = last_res.repr
            except Exception as exc:
                error_msg = str(exc)

            expects_error = tc.expected is not None and getattr(
                tc.expected, "expect_error", False
            )

            if error_msg:
                results.append(
                    _RunResult(
                        file_id=test_file.meta.id,
                        test_id=tc.id,
                        status="pass" if expects_error else "error",
                        message=error_msg,
                    )
                )
                continue

            if last_res is None:
                results.append(
                    _RunResult(
                        file_id=test_file.meta.id,
                        test_id=tc.id,
                        status="fail" if expects_error else "pass",
                        message="Expected error but no operations produced a result"
                        if expects_error
                        else None,
                    )
                )
                continue

            if last_res.status == "error" and expects_error:
                results.append(
                    _RunResult(
                        file_id=test_file.meta.id,
                        test_id=tc.id,
                        status="pass",
                        message=last_res.error,
                    )
                )
                continue

            if expects_error:
                results.append(
                    _RunResult(
                        file_id=test_file.meta.id,
                        test_id=tc.id,
                        status="fail",
                        message="Expected error but operation succeeded",
                    )
                )
                continue

            cmp = comparator.compare(test_file.meta.id, tc.id, last_res)
            if cmp.passed:
                status, msg = "pass", None
            elif cmp.outcome == "missing":
                status, msg = "missing", cmp.details
            else:
                status, msg = "fail", cmp.details

            results.append(
                _RunResult(
                    file_id=test_file.meta.id,
                    test_id=tc.id,
                    status=status,
                    actual=cmp.actual_normalized,
                    expected=cmp.expected_normalized,
                    message=msg,
                )
            )
    finally:
        adapter.teardown(ctx)

    return results


# ---------------------------------------------------------------------------
# Output formatters
# ---------------------------------------------------------------------------

_STATUS_LABEL = {
    "pass": "PASS",
    "fail": "FAIL",
    "error": "ERROR",
    "skip": "SKIP",
    "missing": "MISSING",
}


def _print_terminal_run(all_results: list[tuple[str, list[_RunResult]]]) -> None:
    passed = failed = skipped = errors = 0

    for file_path, results in all_results:
        print(file_path)
        for r in results:
            label = _STATUS_LABEL.get(r.status, r.status.upper())
            if r.status == "pass":
                passed += 1
                print(f"  {label:<8} {r.test_id}")
            elif r.status == "skip":
                skipped += 1
                suffix = f" ({r.message})" if r.message else ""
                print(f"  {label:<8} {r.test_id}{suffix}")
            else:
                if r.status in ("fail", "missing"):
                    failed += 1
                else:
                    errors += 1
                print(f"  {label:<8} {r.test_id}")
                if r.message:
                    for line in r.message.splitlines():
                        print(f"           {line}")

    total_files = len(all_results)
    parts = [f"{passed} passed"]
    if failed:
        parts.append(f"{failed} failed")
    if errors:
        parts.append(f"{errors} errors")
    if skipped:
        parts.append(f"{skipped} skipped")
    print(f"\n{', '.join(parts)} in {total_files} file(s)")


def _print_json_run(all_results: list[tuple[str, list[_RunResult]]]) -> None:
    passed = failed = skipped = errors = 0
    output_files = []

    for file_path, results in all_results:
        tests_out = []
        for r in results:
            if r.status == "pass":
                passed += 1
            elif r.status == "skip":
                skipped += 1
            elif r.status in ("fail", "missing"):
                failed += 1
            else:
                errors += 1

            t: dict[str, Any] = {"id": r.test_id, "status": r.status}
            if r.actual is not None:
                t["actual"] = r.actual
            if r.expected is not None:
                t["expected"] = r.expected
            if r.message is not None:
                t["message"] = r.message
            tests_out.append(t)

        output_files.append({"file": file_path, "tests": tests_out})

    out = {
        "summary": {
            "passed": passed,
            "failed": failed,
            "errors": errors,
            "skipped": skipped,
        },
        "files": output_files,
    }
    print(json.dumps(out, indent=2))


# ---------------------------------------------------------------------------
# Subcommand: run
# ---------------------------------------------------------------------------


def _cmd_run(args: argparse.Namespace) -> int:
    from sxact.runner.loader import load_test_file, LoadError
    from sxact.adapter.base import AdapterError

    test_path = Path(args.test_path)
    if not test_path.exists():
        print(f"error: path not found: {test_path}", file=sys.stderr)
        return 1

    # Collect TOML files
    if test_path.is_file():
        toml_files = [test_path]
    else:
        toml_files = sorted(test_path.rglob("*.toml"))

    if not toml_files:
        print(f"warning: no .toml test files found under {test_path}", file=sys.stderr)
        return 0

    # Parse tag filter
    tag_filter: str | None = None
    for f in args.filter or []:
        if f.startswith("tag:"):
            tag_filter = f[4:]
            break

    # Build adapter
    try:
        adapter = _make_adapter(args)
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    # Live mode: verify oracle is reachable
    if args.oracle_mode == "live":
        from sxact.adapter.wolfram import WolframAdapter

        if isinstance(adapter, WolframAdapter) and not adapter._oracle.health():
            print(
                f"error: oracle not reachable at {args.oracle_url}\n"
                "       Start the oracle server before running in live mode.",
                file=sys.stderr,
            )
            return 1

    # Snapshot mode: load snapshot store
    store = None
    if args.oracle_mode == "snapshot":
        from sxact.snapshot.store import SnapshotStore

        oracle_dir = Path(args.oracle_dir)
        try:
            store = SnapshotStore(oracle_dir)
        except ValueError as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 1

    # Run each file
    all_results: list[tuple[str, list[_RunResult]]] = []

    for toml_path in toml_files:
        try:
            test_file = load_test_file(toml_path)
        except LoadError as exc:
            all_results.append(
                (
                    str(toml_path),
                    [
                        _RunResult(
                            file_id=str(toml_path),
                            test_id="<load>",
                            status="error",
                            message=str(exc),
                        )
                    ],
                )
            )
            continue

        # Skip files where no tests match the tag filter
        if tag_filter:
            file_has_match = tag_filter in test_file.meta.tags or any(
                tag_filter in tc.tags for tc in test_file.tests
            )
            if not file_has_match:
                continue

        try:
            if args.oracle_mode == "live":
                results = _run_file_live(test_file, adapter, tag_filter)
            else:
                results = _run_file_snapshot(test_file, adapter, tag_filter, store)
        except AdapterError as exc:
            results = [
                _RunResult(
                    file_id=test_file.meta.id,
                    test_id="<adapter>",
                    status="error",
                    message=str(exc),
                )
            ]
        except Exception as exc:
            results = [
                _RunResult(
                    file_id=test_file.meta.id,
                    test_id="<runner>",
                    status="error",
                    message=str(exc),
                )
            ]

        all_results.append((str(toml_path), results))

    # Format output
    if args.format == "json":
        _print_json_run(all_results)
    else:
        _print_terminal_run(all_results)

    any_failure = any(
        r.status in ("fail", "error", "missing")
        for _, results in all_results
        for r in results
    )
    return 1 if any_failure else 0
