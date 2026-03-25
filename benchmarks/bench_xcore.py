"""Layer 3 performance benchmarks for Julia XCore.

Protocol (per specs/2026-01-22-design-framework-gaps.md §5.5):
  - 3 warm-up runs (JIT compilation)
  - 10 measurement runs
  - Report median and IQR
  - First-run JIT overhead reported separately

Usage:
    uv run python benchmarks/bench_xcore.py [--output benchmarks/xcore_baseline.json]

Stores results in benchmarks/xcore_baseline.json.
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
import time
import uuid
from collections.abc import Callable
from pathlib import Path
from typing import Any

# ── constants ────────────────────────────────────────────────────────────────

N_WARMUP = 3
N_MEASURE = 10
BASELINE_PATH = Path(__file__).parent / "xcore_baseline.json"

# ── benchmark harness ────────────────────────────────────────────────────────


def _bench(
    func: Callable[[], Any], n_warmup: int = N_WARMUP, n_measure: int = N_MEASURE
) -> dict[str, Any]:
    """Run func and return timing statistics (ms)."""
    # First call: JIT
    t0 = time.perf_counter()
    func()
    jit_ms = (time.perf_counter() - t0) * 1_000

    # Warm-up (not measured)
    for _ in range(n_warmup):
        func()

    # Measurement
    times: list[float] = []
    for _ in range(n_measure):
        t0 = time.perf_counter()
        func()
        times.append((time.perf_counter() - t0) * 1_000)

    times_sorted = sorted(times)
    q1 = times_sorted[n_measure // 4]
    q3 = times_sorted[(3 * n_measure) // 4]

    return {
        "jit_overhead_ms": round(jit_ms, 4),
        "median_ms": round(statistics.median(times), 4),
        "iqr_ms": round(q3 - q1, 4),
        "min_ms": round(min(times), 4),
        "max_ms": round(max(times), 4),
    }


# ── benchmark definitions ────────────────────────────────────────────────────


def _fresh() -> str:
    """Return a fresh symbol name that won't collide in the registry."""
    return "Bench" + uuid.uuid4().hex[:12]


def bench_validate_symbol(xcore_mod: Any) -> dict[str, Any]:
    """Throughput of ValidateSymbol (single call on a fresh name, no registry hit)."""
    # Each call uses a different name so ValidateSymbol never throws.
    names = [_fresh() for _ in range(N_WARMUP + N_MEASURE + 1)]
    idx = [0]

    def _call() -> None:
        xcore_mod.ValidateSymbol(xcore_mod.Symbol(names[idx[0]]))
        idx[0] += 1

    return _bench(_call)


def bench_register_symbol(jl: Any, xcore_mod: Any) -> dict[str, Any]:
    """Throughput of register_symbol (fresh name each call)."""
    names = [_fresh() for _ in range(N_WARMUP + N_MEASURE + 1)]
    idx = [0]

    def _call() -> None:
        xcore_mod.register_symbol(names[idx[0]], "XTensor")
        idx[0] += 1

    result = _bench(_call)
    # Clean up registry after benchmark
    jl.seval("empty!(XCore._symbol_registry); empty!(XCore.xTensorNames)")
    return result


def bench_xtension_dispatch(jl: Any, xcore_mod: Any) -> dict[str, Any]:
    """Latency of MakexTensions with 10 registered hooks."""
    # Register 10 hooks
    jl.seval("empty!(XCore._xtensions)")
    for i in range(10):
        jl.seval(f'XCore.xTension!("Pkg{i}", :BenchCmd, "Beginning", (_...) -> nothing)')

    def _call() -> None:
        xcore_mod.MakexTensions(xcore_mod.Symbol("BenchCmd"), "Beginning")

    result = _bench(_call)
    jl.seval("empty!(XCore._xtensions)")
    return result


def bench_symbol_join(xcore_mod: Any) -> dict[str, Any]:
    """Throughput of SymbolJoin with 3 components."""

    def _call() -> None:
        xcore_mod.SymbolJoin("Alpha", "Beta", "Gamma")

    return _bench(_call)


def bench_has_dagger(xcore_mod: Any) -> dict[str, Any]:
    """Throughput of HasDaggerCharacterQ on a plain symbol."""
    s = xcore_mod.Symbol("MyTensor")

    def _call() -> None:
        xcore_mod.HasDaggerCharacterQ(s)

    return _bench(_call)


# ── main ─────────────────────────────────────────────────────────────────────


def main() -> None:
    parser = argparse.ArgumentParser(description="xCore Layer 3 benchmarks")
    parser.add_argument(
        "--output",
        default=str(BASELINE_PATH),
        help="Output JSON path (default: benchmarks/xcore_baseline.json)",
    )
    parser.add_argument(
        "--compare",
        default=None,
        help="Compare against this baseline JSON (warn if >2x, error if >5x)",
    )
    args = parser.parse_args()

    print("Initialising Julia + XCore …", flush=True)
    from xact.xcore._runtime import get_julia, get_xcore

    jl = get_julia()
    xc = get_xcore()

    suites: list[tuple[str, Callable[[], dict[str, Any]]]] = [
        ("validate_symbol", lambda: bench_validate_symbol(xc)),
        ("register_symbol", lambda: bench_register_symbol(jl, xc)),
        ("xtension_dispatch_10hooks", lambda: bench_xtension_dispatch(jl, xc)),
        ("symbol_join", lambda: bench_symbol_join(xc)),
        ("has_dagger_character_q", lambda: bench_has_dagger(xc)),
    ]

    results: dict[str, Any] = {
        "metadata": {
            "n_warmup": N_WARMUP,
            "n_measure": N_MEASURE,
        },
        "benchmarks": {},
    }

    for name, func in suites:
        print(f"  {name} …", end=" ", flush=True)
        stats = func()
        results["benchmarks"][name] = stats
        print(
            f"median={stats['median_ms']:.3f}ms  IQR={stats['iqr_ms']:.3f}ms  JIT={stats['jit_overhead_ms']:.1f}ms"
        )

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(results, indent=2) + "\n")
    print(f"\nBaseline written to {output}")

    # Optional regression check against a stored baseline
    if args.compare:
        _check_regression(results, Path(args.compare))


def _check_regression(current: dict[str, Any], baseline_path: Path) -> None:
    if not baseline_path.exists():
        print(f"Baseline not found at {baseline_path}; skipping regression check.")
        return

    baseline = json.loads(baseline_path.read_text())
    warn_factor = 2.0
    error_factor = 5.0
    had_error = False

    for name, stats in current["benchmarks"].items():
        if name not in baseline.get("benchmarks", {}):
            continue
        base_median = baseline["benchmarks"][name]["median_ms"]
        curr_median = stats["median_ms"]
        if base_median == 0:
            continue
        ratio = curr_median / base_median
        if ratio >= error_factor:
            print(
                f"ERROR  {name}: {ratio:.1f}x slower than baseline ({curr_median:.3f}ms vs {base_median:.3f}ms)"
            )
            had_error = True
        elif ratio >= warn_factor:
            print(
                f"WARN   {name}: {ratio:.1f}x slower than baseline ({curr_median:.3f}ms vs {base_median:.3f}ms)"
            )

    if had_error:
        sys.exit(1)


if __name__ == "__main__":
    main()
