#!/usr/bin/env python3
"""Generate oracle snapshots for butler_examples using the Julia adapter.

Runs each butler test via the Julia adapter (which implements XPerm.jl) and
writes the results as oracle snapshots in oracle/xperm/butler_examples/.

Each TOML file is processed in an isolated subprocess so that a hanging group
computation (e.g. intractable Schreier-Sims) cannot block the whole run.

Usage:
    uv run python scripts/gen_butler_snapshots.py [--dry-run]
    uv run python scripts/gen_butler_snapshots.py --single-file <path> [--dry-run]
"""

import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

TEST_DIR = Path("tests/xperm/butler_examples")
ORACLE_DIR = Path("oracle")

ORACLE_VERSION = "julia-axiom"
MATH_VERSION = "N/A"

# Per-file timeout: Julia init (~15 s) + generous computation budget.
FILE_TIMEOUT = 90


def _sub_bindings(args: dict, bindings: dict) -> dict:
    """Replace $varname references in args values with their bound values."""
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


def process_single_file(toml_path: Path, dry_run: bool) -> dict:
    """Process one TOML file and return a result dict (written to stdout as JSON
    when run as --single-file subprocess)."""
    from sxact.adapter.julia_stub import JuliaAdapter
    from sxact.runner.loader import load_test_file, LoadError

    timestamp = datetime.now(timezone.utc).isoformat()

    try:
        test_file = load_test_file(toml_path)
    except LoadError as exc:
        return {"load_error": str(exc)}

    skip_val = getattr(test_file.meta, "skip", False)
    if skip_val:
        return {"skipped": True, "reason": str(skip_val)}

    meta_id = test_file.meta.id
    adapter = JuliaAdapter()
    ctx = adapter.initialize()
    snapshots: list = []
    file_pass = file_fail = file_err = 0

    try:
        bindings: dict[str, str] = {}
        # setup_ok tracking removed
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
            else:
                file_fail += 1

    finally:
        adapter.teardown(ctx)

    return {
        "meta_id": meta_id,
        "pass": file_pass,
        "fail": file_fail,
        "error": file_err,
        "snapshots": snapshots if not dry_run else [],
        "failures": [s["id"] for s in snapshots if s["raw"] != "True"],
    }


def run_butler_tests(dry_run: bool = False) -> None:
    toml_files = sorted(TEST_DIR.rglob("*.toml"))
    if not toml_files:
        print(f"No .toml files found in {TEST_DIR}", file=sys.stderr)
        sys.exit(1)

    total_pass = 0
    total_fail = 0
    total_error = 0
    written = []

    for toml_path in toml_files:
        cmd = [sys.executable, __file__, "--single-file", str(toml_path)]
        if dry_run:
            cmd.append("--dry-run")

        try:
            proc = subprocess.run(
                cmd, capture_output=True, text=True, timeout=FILE_TIMEOUT
            )
            if proc.returncode != 0 or not proc.stdout.strip():
                stderr_snippet = (proc.stderr or "")[:300]
                print(
                    f"  ERROR   {toml_path.name}: subprocess failed\n    {stderr_snippet}"
                )
                continue
            result = json.loads(proc.stdout)
        except subprocess.TimeoutExpired:
            print(
                f'  TIMEOUT {toml_path.name}: exceeded {FILE_TIMEOUT}s — add skip="slow" to skip'
            )
            continue
        except Exception as exc:
            print(f"  ERROR   {toml_path.name}: {exc}")
            continue

        if "load_error" in result:
            print(
                f"  LOAD ERROR {toml_path.name}: {result['load_error']}",
                file=sys.stderr,
            )
            continue

        if result.get("skipped"):
            print(f"  SKIP    {toml_path.name}: {result.get('reason', '')}")
            continue

        if "setup_error" in result:
            print(f"  SETUP ERROR {toml_path.name}: {result['setup_error']}")
            total_error += result.get("error", 0)
            continue

        file_pass = result["pass"]
        file_fail = result["fail"]
        file_err = result["error"]
        snapshots = result.get("snapshots", [])

        for s in result.get("failures", []):
            print(f"    FAIL  {s}")

        if not dry_run and snapshots:
            meta_id = result["meta_id"]
            out_dir = ORACLE_DIR / meta_id
            out_dir.mkdir(parents=True, exist_ok=True)
            for snap_item in snapshots:
                raw = snap_item["raw"]
                snap = snap_item["snap"]
                tid = snap_item["id"]
                json_path = out_dir / f"{tid}.json"
                wl_path = out_dir / f"{tid}.wl"
                json_path.write_text(json.dumps(snap, indent=2), encoding="utf-8")
                wl_path.write_text(raw, encoding="utf-8")
                written.extend([json_path, wl_path])

        status = f"pass={file_pass} fail={file_fail} err={file_err}"
        print(f"  {toml_path.name}: {status} → {len(snapshots)} snapshots")
        total_pass += file_pass
        total_fail += file_fail
        total_error += file_err

    print(f"\nTotal: pass={total_pass}, fail={total_fail}, error={total_error}")
    print(f"Wrote {len(written) // 2} snapshots to {ORACLE_DIR}/")


if __name__ == "__main__":
    dry_run = "--dry-run" in sys.argv

    if "--single-file" in sys.argv:
        idx = sys.argv.index("--single-file")
        toml_path = Path(sys.argv[idx + 1])
        result = process_single_file(toml_path, dry_run)
        print(json.dumps(result))
    else:
        run_butler_tests(dry_run=dry_run)
