"""Subcommand: property – run Layer 2 property tests."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

from sxact.runner.property_runner import (
    Counterexample,
    PropertyFileResult,
    PropertyLoadError,
    PropertyResult,
    load_property_file,
    run_property_file,
)


# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------


def _print_terminal(file_results: list[PropertyFileResult]) -> None:
    total_props = 0
    total_pass = 0
    total_fail = 0
    total_error = 0
    total_skip = 0

    for fr in file_results:
        print(f"\n{fr.file_path}")
        print(f"  {fr.description}")
        for r in fr.results:
            total_props += 1
            icon = {"pass": "✓", "fail": "✗", "error": "!", "skip": "○"}.get(
                r.status, "?"
            )
            line = f"  {icon} {r.property_id}  ({r.num_passed}/{r.num_samples})"
            if r.status == "pass":
                total_pass += 1
            elif r.status == "fail":
                total_fail += 1
                line += "  FAIL"
            elif r.status == "error":
                total_error += 1
                line += f"  ERROR: {r.message}"
            elif r.status == "skip":
                total_skip += 1
            print(line)

            if r.counterexample:
                _print_counterexample(r.counterexample)

    print(f"\n{'=' * 60}")
    summary = f"{total_pass} passed, {total_fail} failed, {total_error} errors"
    if total_skip:
        summary += f", {total_skip} skipped"
    print(f"Properties: {total_props}  |  {summary}")


def _print_counterexample(cx: Counterexample) -> None:
    print(f"      Counterexample (sample {cx.sample_index}):")
    for name, val in cx.bindings.items():
        print(f"        ${name} = {val}")
    print(f"        LHS: {cx.lhs_expr}")
    print(f"           = {cx.lhs_result}")
    print(f"        RHS: {cx.rhs_expr}")
    print(f"           = {cx.rhs_result}")


def _print_json(file_results: list[PropertyFileResult]) -> None:
    output = []
    for fr in file_results:
        props = []
        for r in fr.results:
            obj: dict[str, Any] = {
                "id": r.property_id,
                "name": r.name,
                "status": r.status,
                "num_samples": r.num_samples,
                "num_passed": r.num_passed,
            }
            if r.message:
                obj["message"] = r.message
            if r.counterexample:
                cx = r.counterexample
                obj["counterexample"] = {
                    "sample_index": cx.sample_index,
                    "bindings": cx.bindings,
                    "lhs_expr": cx.lhs_expr,
                    "rhs_expr": cx.rhs_expr,
                    "lhs_result": cx.lhs_result,
                    "rhs_result": cx.rhs_result,
                }
            props.append(obj)
        output.append(
            {
                "file": fr.file_path,
                "description": fr.description,
                "properties": props,
            }
        )
    print(json.dumps(output, indent=2))


# ---------------------------------------------------------------------------
# Command entry point
# ---------------------------------------------------------------------------


def _cmd_property(args: argparse.Namespace) -> int:
    from sxact.cli.run import _make_adapter

    test_path = Path(args.test_path)
    if test_path.is_file():
        toml_files = [test_path]
    elif test_path.is_dir():
        toml_files = sorted(test_path.rglob("*.toml"))
    else:
        print(f"error: path not found: {test_path}", file=sys.stderr)
        return 1

    # Filter to property files only
    property_files = []
    for p in toml_files:
        try:
            import tomli

            raw = tomli.loads(p.read_text())
            if raw.get("layer") == "property":
                property_files.append(p)
        except Exception:
            pass  # non-TOML or unreadable files silently skipped

    if not property_files:
        print(
            f"warning: no property TOML files found under {test_path}", file=sys.stderr
        )
        return 0

    tag_filter: str | None = None
    for f in args.filter or []:
        if f.startswith("tag:"):
            tag_filter = f[4:]
            break

    try:
        adapter = _make_adapter(args)
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    file_results: list[PropertyFileResult] = []

    for toml_path in property_files:
        try:
            prop_file = load_property_file(toml_path)
        except PropertyLoadError as exc:
            print(f"LOAD ERROR {toml_path}: {exc}", file=sys.stderr)
            continue

        try:
            result = run_property_file(
                prop_file, adapter, tag_filter, adapter_name=args.adapter
            )
        except Exception as exc:
            result = PropertyFileResult(
                file_path=str(toml_path),
                description="",
                results=[
                    PropertyResult(
                        property_id="<runner>",
                        name="<runner>",
                        status="error",
                        num_samples=0,
                        num_passed=0,
                        message=str(exc),
                    )
                ],
            )

        file_results.append(result)

    if args.format == "json":
        _print_json(file_results)
    else:
        _print_terminal(file_results)

    any_failure = any(
        r.status in ("fail", "error") for fr in file_results for r in fr.results
    )
    return 1 if any_failure else 0
