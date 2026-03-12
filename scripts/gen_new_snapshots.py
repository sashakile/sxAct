#!/usr/bin/env python3
"""Generate oracle snapshots for new xtensor/xperm test files using the Julia adapter.

Processes TOML test files that don't have oracle snapshots yet and writes
snapshot JSON files.

Usage:
    uv run python scripts/gen_new_snapshots.py [--dry-run] [PATH ...]

If no paths are given, defaults to processing:
    tests/xtensor/covd_basics.toml
    tests/xtensor/contraction_extended.toml
    tests/xperm/higher_rank_symmetry.toml
    tests/xperm/product_symmetry.toml
"""

import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

ORACLE_DIR = Path("oracle")
ORACLE_VERSION = "julia-axiom"
MATH_VERSION = "N/A"

DEFAULT_PATHS = [
    Path("tests/xtensor/covd_basics.toml"),
    Path("tests/xtensor/contraction_extended.toml"),
    Path("tests/xperm/higher_rank_symmetry.toml"),
    Path("tests/xperm/product_symmetry.toml"),
]


def _sub_bindings(args: dict, bindings: dict) -> dict:
    REF_RE = re.compile(r"\$(\w+)")

    def sub_val(v):
        if isinstance(v, str):
            return REF_RE.sub(lambda m: bindings.get(m.group(1), m.group(0)), v)
        if isinstance(v, list):
            return [sub_val(x) for x in v]
        return v

    return {k: sub_val(v) for k, v in args.items()}


def _sha_prefix(normalized_output: str, properties: dict = None) -> str:
    import hashlib

    if properties is None:
        properties = {}
    canonical = json.dumps(
        {"normalized_output": normalized_output, "properties": properties},
        sort_keys=True,
    )
    h = hashlib.sha256(canonical.encode()).hexdigest()
    return f"sha256:{h[:12]}"


def process_file(toml_path: Path, adapter, dry_run: bool) -> dict:
    """Process one TOML file with the given adapter and return results."""
    from sxact.runner.loader import load_test_file, LoadError

    timestamp = datetime.now(timezone.utc).isoformat()

    try:
        test_file = load_test_file(toml_path)
    except LoadError as exc:
        return {"load_error": str(exc)}

    meta_id = test_file.meta.id
    ctx = adapter.initialize()
    snapshots = []
    file_pass = file_fail = file_err = 0

    try:
        bindings: dict[str, str] = {}
        for op in test_file.setup:
            try:
                resolved = _sub_bindings(op.args, bindings)
                res = adapter.execute(ctx, op.action, resolved)
                if op.store_as and res.repr:
                    bindings[op.store_as] = res.repr
            except Exception as exc:
                return {
                    "setup_error": str(exc),
                    "pass": 0,
                    "fail": 0,
                    "error": len(test_file.tests),
                    "snapshots": [],
                }

        for tc in test_file.tests:
            if tc.skip:
                continue

            local = dict(bindings)
            last_repr = None
            error_msg = None
            try:
                for op in tc.operations:
                    resolved = _sub_bindings(op.args, local)
                    res = adapter.execute(ctx, op.action, resolved)
                    if op.store_as and res.repr:
                        local[op.store_as] = res.repr
                    last_repr = res.repr
            except Exception as exc:
                error_msg = str(exc)

            if error_msg:
                print(f"    ERROR  {tc.id}: {error_msg}")
                file_err += 1
                continue

            raw = last_repr or ""
            props: dict = {}
            snap = {
                "test_id": tc.id,
                "oracle_version": ORACLE_VERSION,
                "mathematica_version": MATH_VERSION,
                "timestamp": timestamp,
                "commands": "[julia-adapter]",
                "raw_output": raw,
                "normalized_output": raw,
                "properties": props,
                "hash": _sha_prefix(raw, props),
            }
            snapshots.append({"id": tc.id, "raw": raw, "snap": snap})

            if raw == "True":
                file_pass += 1
            elif raw == "False":
                print(f"    FAIL   {tc.id}: returned False")
                file_fail += 1
            else:
                print(f"    RESULT {tc.id}: {raw!r}")
                # Non-boolean result: still a valid snapshot
                file_pass += 1

    finally:
        adapter.teardown(ctx)

    if not dry_run and snapshots:
        out_dir = ORACLE_DIR / meta_id
        out_dir.mkdir(parents=True, exist_ok=True)
        written = 0
        for snap_item in snapshots:
            raw = snap_item["raw"]
            snap = snap_item["snap"]
            tid = snap_item["id"]
            json_path = out_dir / f"{tid}.json"
            wl_path = out_dir / f"{tid}.wl"
            json_path.write_text(json.dumps(snap, indent=2), encoding="utf-8")
            wl_path.write_text(raw, encoding="utf-8")
            written += 1
        print(f"    Wrote {written} snapshots to {out_dir}/")

    return {
        "meta_id": meta_id,
        "pass": file_pass,
        "fail": file_fail,
        "error": file_err,
        "snapshots": snapshots,
    }


def main() -> None:
    dry_run = "--dry-run" in sys.argv
    args = [a for a in sys.argv[1:] if not a.startswith("--")]

    if args:
        paths = [Path(a) for a in args]
    else:
        paths = DEFAULT_PATHS

    # Check all paths exist
    missing = [p for p in paths if not p.exists()]
    if missing:
        for m in missing:
            print(f"error: not found: {m}", file=sys.stderr)
        sys.exit(1)

    # Expand directories to .toml files
    toml_files: list[Path] = []
    for p in paths:
        if p.is_dir():
            toml_files.extend(sorted(p.rglob("*.toml")))
        else:
            toml_files.append(p)

    if not toml_files:
        print("No .toml files found.", file=sys.stderr)
        sys.exit(1)

    print(f"Processing {len(toml_files)} file(s) with Julia adapter...")
    if dry_run:
        print("(dry-run: no files will be written)")

    from sxact.adapter.julia_stub import JuliaAdapter

    adapter = JuliaAdapter()

    total_pass = total_fail = total_err = 0
    for toml_path in toml_files:
        print(f"\n{toml_path}")
        result = process_file(toml_path, adapter, dry_run)

        if "load_error" in result:
            print(f"  LOAD ERROR: {result['load_error']}")
            continue

        if "setup_error" in result:
            print(f"  SETUP ERROR: {result['setup_error']}")
            total_err += result.get("error", 0)
            continue

        fp = result["pass"]
        ff = result["fail"]
        fe = result["error"]
        total_pass += fp
        total_fail += ff
        total_err += fe
        print(f"  pass={fp} fail={ff} error={fe}")

    print(f"\nTotal: pass={total_pass} fail={total_fail} error={total_err}")
    if total_fail > 0 or total_err > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
