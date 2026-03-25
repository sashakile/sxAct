"""Subcommand: regen-oracle – regenerate oracle snapshots from a live oracle."""

from __future__ import annotations

import argparse
import difflib
import sys
from pathlib import Path
from typing import Any


def _interactive_review(
    new_snapshots: Any, added: Any, removed: Any, changed: Any, store: Any
) -> Any:
    """Prompt for each changed/added snapshot; return filtered FileSnapshot list or None on quit."""
    import dataclasses

    revert_keys: set[tuple[str, str]] = set()  # keep old snapshot
    skip_keys: set[tuple[str, str]] = set()  # skip new addition
    accept_all = False

    for (meta_id, test_id), diff_lines in changed:
        if accept_all:
            continue
        print(f"\n--- {meta_id}/{test_id} [CHANGED] ---")
        for line in diff_lines:
            print(line)
        while True:
            try:
                ans = input("Accept change? [y]es/[n]o/[a]ll/[q]uit: ").strip().lower()
            except (EOFError, KeyboardInterrupt):
                return None
            if ans in ("y", "yes"):
                break
            elif ans in ("n", "no"):
                revert_keys.add((meta_id, test_id))
                break
            elif ans == "a":
                accept_all = True
                break
            elif ans == "q":
                return None

    for meta_id, test_id in added:
        if accept_all:
            continue
        print(f"\n+++ {meta_id}/{test_id} [NEW]")
        while True:
            try:
                ans = input("Accept new snapshot? [y]es/[n]o/[a]ll/[q]uit: ").strip().lower()
            except (EOFError, KeyboardInterrupt):
                return None
            if ans in ("y", "yes"):
                break
            elif ans in ("n", "no"):
                skip_keys.add((meta_id, test_id))
                break
            elif ans == "a":
                accept_all = True
                break
            elif ans == "q":
                return None

    result = []
    for file_snap in new_snapshots:
        accepted_tests = []
        for snap in file_snap.tests:
            key = (file_snap.meta_id, snap.test_id)
            if key in skip_keys:
                continue
            elif key in revert_keys:
                old = store.load(file_snap.meta_id, snap.test_id)
                if old is not None:
                    accepted_tests.append(old)
            else:
                accepted_tests.append(snap)
        if accepted_tests:
            result.append(dataclasses.replace(file_snap, tests=accepted_tests))
    return result


def _cmd_regen_oracle(args: argparse.Namespace) -> int:
    from sxact.adapter.base import AdapterError
    from sxact.adapter.wolfram import WolframAdapter
    from sxact.runner.loader import LoadError, load_test_file
    from sxact.snapshot.runner import run_file
    from sxact.snapshot.store import SnapshotStore
    from sxact.snapshot.writer import write_oracle_dir

    test_dir = Path(args.test_dir)
    oracle_dir = Path(args.oracle_dir)

    if not test_dir.exists():
        print(f"error: test directory not found: {test_dir}", file=sys.stderr)
        return 1
    if not oracle_dir.exists():
        print(f"error: oracle directory not found: {oracle_dir}", file=sys.stderr)
        return 1

    adapter = WolframAdapter(base_url=args.oracle_url, timeout=args.timeout)
    if not adapter._oracle.health():
        print(
            f"error: oracle not reachable at {args.oracle_url}\n"
            "       Start the oracle server before regenerating snapshots.",
            file=sys.stderr,
        )
        return 1

    store = SnapshotStore(oracle_dir)
    version = adapter.get_version()

    toml_files = sorted(test_dir.rglob("*.toml"))
    if not toml_files:
        print(f"warning: no .toml test files found in {test_dir}", file=sys.stderr)
        return 0

    print(f"Running {len(toml_files)} file(s) against live oracle...")

    new_snapshots = []
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
            new_snapshots.append(file_snap)
            print(f"ok ({len(file_snap.tests)} tests)")
        except AdapterError as exc:
            print(f"ADAPTER ERROR: {exc}", file=sys.stderr)
            errors += 1
        except Exception as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            errors += 1

    # ------------------------------------------------------------------
    # Diff: compare new vs existing
    # ------------------------------------------------------------------
    existing_keys = set(store.list_snapshots())
    new_keys = {(fs.meta_id, s.test_id) for fs in new_snapshots for s in fs.tests}

    added = []
    removed = sorted(existing_keys - new_keys)
    changed = []  # list of (key, diff_lines)
    unchanged = 0

    for file_snap in new_snapshots:
        for snap in file_snap.tests:
            key = (file_snap.meta_id, snap.test_id)
            old = store.load(file_snap.meta_id, snap.test_id)
            if old is None:
                added.append(key)
            elif old.normalized_output != snap.normalized_output:
                diff_lines = list(
                    difflib.unified_diff(
                        old.normalized_output.splitlines(keepends=True),
                        snap.normalized_output.splitlines(keepends=True),
                        fromfile=f"{key[0]}/{key[1]} (old)",
                        tofile=f"{key[0]}/{key[1]} (new)",
                        lineterm="",
                    )
                )
                changed.append((key, diff_lines))
            else:
                unchanged += 1

    total_changes = len(added) + len(removed) + len(changed)
    summary_parts = []
    if unchanged:
        summary_parts.append(f"{unchanged} unchanged")
    if changed:
        summary_parts.append(f"{len(changed)} changed")
    if added:
        summary_parts.append(f"{len(added)} new")
    if removed:
        summary_parts.append(f"{len(removed)} deleted")
    print(f"\n{', '.join(summary_parts) if summary_parts else 'No changes detected.'}")

    if total_changes == 0:
        return 0

    for meta_id, test_id in added:
        print(f"  + {meta_id}/{test_id}  [NEW]")
    for meta_id, test_id in removed:
        print(f"  - {meta_id}/{test_id}  [REMOVED]")
    for (meta_id, test_id), diff_lines in changed:
        print(f"  ~ {meta_id}/{test_id}  [CHANGED]")
        if args.diff:
            for line in diff_lines:
                print(f"    {line}")

    if args.dry_run:
        print("\n(dry-run: no files written)")
        return 1 if errors else 0

    print()
    if args.interactive:
        accepted_snapshots = _interactive_review(new_snapshots, added, removed, changed, store)
        if accepted_snapshots is None:
            print("Aborted.")
            return 1
        write_oracle_dir(
            accepted_snapshots,
            oracle_dir,
            oracle_version=f"xAct {version.extra.get('xact_version', '1.2.0')}",
            mathematica_version=version.cas_version,
        )
        total = sum(len(f.tests) for f in accepted_snapshots)
        print(f"Wrote {total} snapshot(s) to {oracle_dir}/")
        return 1 if errors else 0

    if not args.yes:
        try:
            answer = input("Overwrite oracle snapshots? [y/N] ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            print("\nAborted.")
            return 1
        if answer not in ("y", "yes"):
            print("Aborted.")
            return 1

    write_oracle_dir(
        new_snapshots,
        oracle_dir,
        oracle_version=f"xAct {version.extra.get('xact_version', '1.2.0')}",
        mathematica_version=version.cas_version,
    )

    total = sum(len(f.tests) for f in new_snapshots)
    print(f"Wrote {total} snapshot(s) to {oracle_dir}/")
    return 1 if errors else 0
