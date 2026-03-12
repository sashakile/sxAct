"""xact-test CLI entry point.

Usage::

    xact-test snapshot tests/ --output oracle/
    xact-test snapshot tests/ --output oracle/ --oracle-url http://localhost:8765

    xact-test run tests/
    xact-test run tests/ --oracle-mode=snapshot --oracle-dir=oracle/ --adapter=julia
    xact-test run tests/ --filter tag:smoke --format=json

    xact-test regen-oracle tests/ --oracle-dir oracle/
    xact-test regen-oracle tests/ --oracle-dir oracle/ --diff --yes
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

# Re-export everything the tests import from sxact.cli
from .run import (
    _RunResult as _RunResult,
    _REF_RE as _REF_RE,
    _make_adapter,
    _make_adapter_by_name,
    _tc_matches_tag,
    _sub_bindings as _sub_bindings,
    _run_file_live as _run_file_live,
    _run_file_snapshot as _run_file_snapshot,
    _STATUS_LABEL as _STATUS_LABEL,
    _print_terminal_run as _print_terminal_run,
    _print_json_run as _print_json_run,
    _cmd_run,
)
from .snapshot import _cmd_snapshot
from .regen import _interactive_review as _interactive_review, _cmd_regen_oracle
from .property import _cmd_property


# ---------------------------------------------------------------------------
# Subcommand: benchmark
# ---------------------------------------------------------------------------

_BASELINE_PATH = Path("benchmarks/baseline.json")


def _cmd_benchmark(args: argparse.Namespace) -> int:
    from sxact.benchmarks.runner import (
        BenchResult,
        bench_test_case,
        check_regression,
        load_baseline,
        save_baseline,
    )
    from sxact.runner.loader import load_test_file, LoadError

    adapter_name = args.adapter
    adapter = _make_adapter(args)

    baseline_path = Path(args.baseline)

    # --compare: run all available adapters, print table
    if args.compare:
        return _cmd_benchmark_compare(args, adapter_name, baseline_path)

    test_files_paths = sorted(Path(args.test_dir).rglob("*.toml"))
    if not test_files_paths:
        print(f"warning: no .toml test files found in {args.test_dir}", file=sys.stderr)
        return 0

    results: list[BenchResult] = []

    for toml_path in test_files_paths:
        try:
            test_file = load_test_file(toml_path)
        except LoadError as exc:
            print(f"LOAD ERROR {toml_path}: {exc}", file=sys.stderr)
            continue

        for tc in test_file.tests:
            tag_filter = args.tag
            if tag_filter and not _tc_matches_tag(
                tc.tags, test_file.meta.tags, tag_filter
            ):
                continue

            print(
                f"  {test_file.meta.id}/{tc.id} ({adapter_name}) ... ",
                end="",
                flush=True,
            )
            try:
                result = bench_test_case(
                    adapter,
                    test_file,
                    tc,
                    n_warmup=args.n_warmup,
                    n_measure=args.n_measure,
                    adapter_name=adapter_name,
                )
            except Exception as exc:
                print(f"ERROR: {exc}", file=sys.stderr)
                continue

            results.append(result)
            print(
                f"median={result.median_ms:.3f}ms  "
                f"p95={result.p95_ms:.3f}ms  "
                f"min={result.min_ms:.3f}ms  "
                f"max={result.max_ms:.3f}ms"
            )

    if not results:
        return 0

    if args.record:
        from sxact.benchmarks.runner import collect_machine_info

        m = collect_machine_info()
        save_baseline(baseline_path, results, machine=m)
        print(f"\nBaseline written to {baseline_path}")
        print(f"  machine : {m.os}")
        print(f"  cpu     : {m.cpu_model} ({m.cpu_cores} cores)")
        print(f"  ram     : {m.ram_gb} GB")
        print(f"  python  : {m.python_version}")
        print(f"  julia   : {m.julia_version}")

    if args.check:
        baseline, baseline_machine = load_baseline(baseline_path)
        if not baseline:
            print(
                f"warning: no baseline found at {baseline_path}; run with --record first",
                file=sys.stderr,
            )
            return 0

        if baseline_machine:
            print(
                f"baseline machine: {baseline_machine.os}  "
                f"{baseline_machine.cpu_model} ({baseline_machine.cpu_cores}c)  "
                f"{baseline_machine.ram_gb}GB RAM"
            )

        regressions = check_regression(results, baseline)
        had_fail = False
        for reg in regressions:
            if reg.level == "ok":
                continue
            label = reg.level.upper()
            print(
                f"{label:<8} {reg.adapter}/{reg.test_id}: "
                f"{reg.ratio:.1f}x ({reg.current_median_ms:.3f}ms vs baseline {reg.baseline_median_ms:.3f}ms)"
            )
            if reg.level in ("fail", "critical"):
                had_fail = True

        if had_fail:
            return 1

    return 0


def _cmd_benchmark_compare(
    args: argparse.Namespace, primary_adapter_name: str, baseline_path: Path
) -> int:
    """Run all available adapters on the test dir and print a comparison table."""
    from sxact.benchmarks.runner import bench_test_case, BenchResult
    from sxact.runner.loader import load_test_file, LoadError

    adapter_names = ["wolfram", "julia", "python"]
    adapter_results: dict[str, list[BenchResult]] = {}

    test_files_paths = sorted(Path(args.test_dir).rglob("*.toml"))
    if not test_files_paths:
        print(f"warning: no .toml test files found in {args.test_dir}", file=sys.stderr)
        return 0

    for name in adapter_names:
        try:
            adapter = _make_adapter_by_name(name, args)
        except Exception as exc:
            print(f"  skip {name}: {exc}")
            continue

        print(f"\nRunning {name} adapter...")
        adapter_results[name] = []

        for toml_path in test_files_paths:
            try:
                test_file = load_test_file(toml_path)
            except LoadError:
                continue

            for tc in test_file.tests:
                print(f"  {test_file.meta.id}/{tc.id} ... ", end="", flush=True)
                try:
                    result = bench_test_case(
                        adapter,
                        test_file,
                        tc,
                        n_warmup=args.n_warmup,
                        n_measure=args.n_measure,
                        adapter_name=name,
                    )
                    adapter_results[name].append(result)
                    print(f"median={result.median_ms:.3f}ms")
                except Exception as exc:
                    print(f"ERROR: {exc}")

    # Print cross-adapter table
    all_test_ids = sorted({r.test_id for rs in adapter_results.values() for r in rs})

    print("\n" + "=" * 70)
    print(
        f"{'test_id':<30} {'wolfram':>10} {'julia':>10} {'python':>10} {'j/w':>6} {'p/w':>6}"
    )
    print("-" * 70)

    for tid in all_test_ids:
        row = f"{tid:<30}"
        wms = next(
            (
                r.median_ms
                for r in adapter_results.get("wolfram", [])
                if r.test_id == tid
            ),
            None,
        )
        jms = next(
            (r.median_ms for r in adapter_results.get("julia", []) if r.test_id == tid),
            None,
        )
        pms = next(
            (
                r.median_ms
                for r in adapter_results.get("python", [])
                if r.test_id == tid
            ),
            None,
        )

        row += f" {f'{wms:.3f}ms':>10}" if wms is not None else f" {'—':>10}"
        row += f" {f'{jms:.3f}ms':>10}" if jms is not None else f" {'—':>10}"
        row += f" {f'{pms:.3f}ms':>10}" if pms is not None else f" {'—':>10}"

        jw = f"{jms / wms:.1f}x" if jms is not None and wms else "—"
        pw = f"{pms / wms:.1f}x" if pms is not None and wms else "—"
        row += f" {jw:>6} {pw:>6}"
        print(row)

    print("=" * 70)
    return 0


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="xact-test",
        description="sxAct test harness CLI",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    # --- snapshot subcommand ---
    snap = subparsers.add_parser(
        "snapshot",
        help="Run test files against the live Wolfram oracle and save snapshots",
    )
    snap.add_argument("test_dir", help="Directory containing .toml test files")
    snap.add_argument(
        "--output",
        required=True,
        metavar="ORACLE_DIR",
        help="Output directory for oracle snapshots",
    )
    snap.add_argument(
        "--oracle-url",
        default="http://localhost:8765",
        metavar="URL",
        dest="oracle_url",
        help="Oracle HTTP server URL (default: http://localhost:8765)",
    )
    snap.add_argument(
        "--timeout",
        type=int,
        default=60,
        metavar="SECONDS",
        help="Per-evaluation timeout in seconds (default: 60)",
    )
    snap.set_defaults(func=_cmd_snapshot)

    # --- run subcommand ---
    run = subparsers.add_parser(
        "run",
        help="Run test files and report pass/fail results",
    )
    run.add_argument(
        "test_path",
        help="Path to a .toml file or directory containing .toml files",
    )
    run.add_argument(
        "--oracle-mode",
        choices=["live", "snapshot"],
        default="live",
        dest="oracle_mode",
        help="Reference mode: live=WolframAdapter, snapshot=stored oracle (default: live)",
    )
    run.add_argument(
        "--adapter",
        choices=["wolfram", "julia", "python"],
        default="wolfram",
        help="Adapter under test (default: wolfram)",
    )
    run.add_argument(
        "--oracle-dir",
        default="oracle",
        metavar="ORACLE_DIR",
        dest="oracle_dir",
        help="Oracle snapshot directory for snapshot mode (default: oracle)",
    )
    run.add_argument(
        "--oracle-url",
        default="http://localhost:8765",
        metavar="URL",
        dest="oracle_url",
        help="Oracle HTTP server URL for live mode (default: http://localhost:8765)",
    )
    run.add_argument(
        "--timeout",
        type=int,
        default=60,
        metavar="SECONDS",
        help="Per-evaluation timeout in seconds (default: 60)",
    )
    run.add_argument(
        "--filter",
        action="append",
        metavar="tag:<TAG>",
        help="Filter tests by tag (e.g. --filter tag:smoke). May be repeated.",
    )
    run.add_argument(
        "--format",
        choices=["terminal", "json"],
        default="terminal",
        help="Output format (default: terminal)",
    )
    run.set_defaults(func=_cmd_run)

    # --- regen-oracle subcommand ---
    regen = subparsers.add_parser(
        "regen-oracle",
        help="Regenerate oracle snapshots from the live oracle, showing a diff first",
    )
    regen.add_argument("test_dir", help="Directory containing .toml test files")
    regen.add_argument(
        "--oracle-dir",
        required=True,
        metavar="ORACLE_DIR",
        dest="oracle_dir",
        help="Existing oracle snapshot directory to update",
    )
    regen.add_argument(
        "--oracle-url",
        default="http://localhost:8765",
        metavar="URL",
        dest="oracle_url",
        help="Oracle HTTP server URL (default: http://localhost:8765)",
    )
    regen.add_argument(
        "--timeout",
        type=int,
        default=60,
        metavar="SECONDS",
        help="Per-evaluation timeout in seconds (default: 60)",
    )
    regen.add_argument(
        "--diff",
        action="store_true",
        default=False,
        help="Show full unified diff for changed snapshots",
    )
    regen.add_argument(
        "--dry-run",
        action="store_true",
        default=False,
        dest="dry_run",
        help="Show diffs without writing any files",
    )
    regen.add_argument(
        "--interactive",
        "-i",
        action="store_true",
        default=False,
        help="Review each changed snapshot interactively (y/n/a/q)",
    )
    regen.add_argument(
        "--yes",
        "-y",
        action="store_true",
        default=False,
        help="Skip confirmation prompt and overwrite immediately",
    )
    regen.set_defaults(func=_cmd_regen_oracle)

    # --- benchmark subcommand ---
    bench = subparsers.add_parser(
        "benchmark",
        help="Layer 3: time test cases and track performance regressions",
    )
    bench.add_argument("test_dir", help="Directory containing .toml test files")
    bench.add_argument(
        "--adapter",
        default="wolfram",
        choices=["wolfram", "julia", "python"],
        help="Adapter to benchmark (default: wolfram)",
    )
    bench.add_argument(
        "--oracle-url",
        default="http://localhost:8765",
        metavar="URL",
        dest="oracle_url",
        help="Oracle HTTP server URL (default: http://localhost:8765)",
    )
    bench.add_argument(
        "--timeout",
        type=int,
        default=60,
        metavar="SECONDS",
        dest="timeout",
        help="Per-evaluation timeout in seconds (default: 60)",
    )
    bench.add_argument(
        "--n-warmup",
        type=int,
        default=10,
        metavar="N",
        dest="n_warmup",
        help="Warmup iterations (default: 10)",
    )
    bench.add_argument(
        "--n-measure",
        type=int,
        default=30,
        metavar="N",
        dest="n_measure",
        help="Measured iterations (default: 30)",
    )
    bench.add_argument(
        "--baseline",
        default=str(_BASELINE_PATH),
        metavar="PATH",
        help=f"Baseline JSON path (default: {_BASELINE_PATH})",
    )
    bench.add_argument(
        "--record",
        action="store_true",
        default=False,
        help="Record current run as new baseline",
    )
    bench.add_argument(
        "--check",
        action="store_true",
        default=False,
        help="Compare against baseline and fail if regression threshold exceeded",
    )
    bench.add_argument(
        "--compare",
        action="store_true",
        default=False,
        help="Run all available adapters and print cross-adapter comparison table",
    )
    bench.add_argument(
        "--tag",
        default=None,
        metavar="TAG",
        help="Filter tests by tag",
    )
    bench.set_defaults(func=_cmd_benchmark)

    # --- property subcommand ---
    prop = subparsers.add_parser(
        "property",
        help="Layer 2: run property-based tests and report pass/fail/counterexamples",
    )
    prop.add_argument(
        "test_path",
        help="Path to a property .toml file or directory containing property .toml files",
    )
    prop.add_argument(
        "--adapter",
        choices=["wolfram", "julia", "python"],
        default="wolfram",
        help="Adapter under test (default: wolfram)",
    )
    prop.add_argument(
        "--oracle-url",
        default="http://localhost:8765",
        metavar="URL",
        dest="oracle_url",
        help="Oracle HTTP server URL (default: http://localhost:8765)",
    )
    prop.add_argument(
        "--timeout",
        type=int,
        default=60,
        metavar="SECONDS",
        help="Per-evaluation timeout in seconds (default: 60)",
    )
    prop.add_argument(
        "--filter",
        action="append",
        metavar="tag:<TAG>",
        help="Filter properties by tag (e.g. --filter tag:critical). May be repeated.",
    )
    prop.add_argument(
        "--compare-adapter",
        choices=["wolfram", "julia", "python"],
        default=None,
        dest="compare_adapter",
        metavar="ADAPTER",
        help="Secondary adapter to compare against (default: none). Runs both adapters and reports disagreements.",
    )
    prop.add_argument(
        "--format",
        choices=["terminal", "json"],
        default="terminal",
        help="Output format (default: terminal)",
    )
    prop.set_defaults(func=_cmd_property)

    args = parser.parse_args()
    sys.exit(args.func(args))


if __name__ == "__main__":
    main()
