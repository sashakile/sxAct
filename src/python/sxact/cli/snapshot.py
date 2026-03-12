"""Subcommand: snapshot – run test files against a live Wolfram oracle."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


def _cmd_snapshot(args: argparse.Namespace) -> int:
    from sxact.adapter.wolfram import WolframAdapter
    from sxact.adapter.base import AdapterError
    from sxact.runner.loader import load_test_file, LoadError
    from sxact.snapshot.runner import run_file
    from sxact.snapshot.writer import write_oracle_dir

    test_dir = Path(args.test_dir)
    output_dir = Path(args.output)

    if not test_dir.exists():
        print(f"error: test directory not found: {test_dir}", file=sys.stderr)
        return 1

    adapter = WolframAdapter(base_url=args.oracle_url, timeout=args.timeout)

    if not adapter._oracle.health():
        print(
            f"error: oracle not reachable at {args.oracle_url}\n"
            "       Start the oracle server before running snapshot generation.",
            file=sys.stderr,
        )
        return 1

    version = adapter.get_version()

    toml_files = sorted(test_dir.rglob("*.toml"))
    if not toml_files:
        print(f"warning: no .toml test files found in {test_dir}", file=sys.stderr)
        return 0

    print(f"Snapshotting {len(toml_files)} file(s) from {test_dir} → {output_dir}/")

    all_snapshots = []
    errors = 0

    for toml_path in toml_files:
        rel = toml_path.relative_to(test_dir)
        print(f"  {rel} ... ", end="", flush=True)

        try:
            test_file = load_test_file(toml_path)
        except LoadError as exc:
            print(f"LOAD ERROR: {exc}", file=sys.stderr)
            errors += 1
            continue

        try:
            file_snap = run_file(test_file, adapter)
            all_snapshots.append(file_snap)
            print(f"ok ({len(file_snap.tests)} tests)")
        except AdapterError as exc:
            print(f"ADAPTER ERROR: {exc}", file=sys.stderr)
            errors += 1
        except Exception as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            errors += 1

    write_oracle_dir(
        all_snapshots,
        output_dir,
        oracle_version=f"xAct {version.extra.get('xact_version', '1.2.0')}",
        mathematica_version=version.cas_version,
    )

    total = sum(len(f.tests) for f in all_snapshots)
    print(f"\nWrote {total} snapshot(s) to {output_dir}/")

    return 1 if errors else 0
