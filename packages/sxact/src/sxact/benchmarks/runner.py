"""Layer 3 performance benchmark runner.

Times individual TOML test cases against a live adapter and reports
wall-clock statistics.  Supports baseline recording and regression
detection per the three-layer architecture spec.

Public API::

    from sxact.benchmarks.runner import bench_test_case, BenchResult

    result = bench_test_case(adapter, test_file, tc)
    print(result.median_ms)
"""

from __future__ import annotations

import json
import os
import platform
import statistics
import subprocess
import time
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from sxact.adapter.base import TestAdapter
    from sxact.runner.loader import TestCase, TestFile

# ---------------------------------------------------------------------------
# Machine metadata
# ---------------------------------------------------------------------------


@dataclass
class MachineInfo:
    """Hardware and runtime metadata for a benchmark run."""

    cpu_model: str
    cpu_cores: int
    ram_gb: float
    os: str
    python_version: str
    julia_version: str

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "MachineInfo":
        return cls(**d)


def _ram_gb() -> float:
    """Return total RAM in GB using /proc/meminfo (Linux) or platform fallback."""
    try:
        meminfo = Path("/proc/meminfo").read_text(encoding="utf-8")
        for line in meminfo.splitlines():
            if line.startswith("MemTotal:"):
                kb = int(line.split()[1])
                return round(kb / 1_048_576, 1)
    except Exception:
        pass
    # macOS / Windows fallback via sysctl
    try:
        out = subprocess.check_output(
            ["sysctl", "-n", "hw.memsize"], text=True, stderr=subprocess.DEVNULL
        )
        return round(int(out.strip()) / 1_073_741_824, 1)
    except Exception:
        pass
    return 0.0


def _julia_version() -> str:
    """Return Julia version string, or 'unavailable' if not on PATH."""
    try:
        out = subprocess.check_output(
            ["julia", "--version"], text=True, stderr=subprocess.STDOUT, timeout=10
        )
        # "julia version 1.10.2"
        return out.strip().split()[-1]
    except Exception:
        return "unavailable"


def collect_machine_info() -> MachineInfo:
    """Collect hardware and runtime metadata for the current machine."""
    return MachineInfo(
        cpu_model=platform.processor() or platform.machine() or "unknown",
        cpu_cores=os.cpu_count() or 0,
        ram_gb=_ram_gb(),
        os=f"{platform.system()} {platform.release()} {platform.machine()}",
        python_version=platform.python_version(),
        julia_version=_julia_version(),
    )


# Default timing parameters (per spec §Layer 3)
N_WARMUP_DEFAULT = 10
N_MEASURE_DEFAULT = 30

# Regression thresholds: same-adapter, current run vs stored baseline (spec §5.5)
# >50% slower → warning, >100% slower → fail (CI gate), >200% slower → critical
# (relaxed from 1.2/1.5/2.0 — GitHub Actions 2-core VMs have high variance)
THRESHOLD_REGRESSION_WARNING = 1.5
THRESHOLD_REGRESSION_FAIL = 2.0
THRESHOLD_REGRESSION_CRITICAL = 3.0

# Minimum absolute slowdown (ms) to trigger a regression.  Sub-millisecond
# benchmarks on shared CI runners fluctuate by 0.1-0.3 ms routinely; flagging
# these as regressions produces false positives.
MIN_REGRESSION_DELTA_MS = 0.5

# Cross-adapter thresholds: Julia/Python run vs Wolfram baseline (spec §5.5)
# Julia vs Wolfram: >5x warning, >10x fail; Python vs Wolfram: >10x warning, >50x critical
THRESHOLD_CROSS_WARNING = 5.0
THRESHOLD_CROSS_FAIL = 10.0
THRESHOLD_CROSS_CRITICAL = 50.0

# Legacy aliases kept for external callers
THRESHOLD_WARNING = THRESHOLD_CROSS_WARNING
THRESHOLD_FAIL = THRESHOLD_CROSS_FAIL
THRESHOLD_CRITICAL = THRESHOLD_CROSS_CRITICAL


# ---------------------------------------------------------------------------
# Result dataclass
# ---------------------------------------------------------------------------


@dataclass
class BenchResult:
    """Timing statistics for a single test case benchmark run."""

    test_id: str
    adapter: str
    n_warmup: int
    n_measure: int
    median_ms: float
    p95_ms: float
    p99_ms: float
    min_ms: float
    max_ms: float
    timestamp: str

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "BenchResult":
        return cls(**d)


# ---------------------------------------------------------------------------
# Core timing function
# ---------------------------------------------------------------------------


def bench_test_case(
    adapter: "TestAdapter[Any]",
    test_file: "TestFile",
    tc: "TestCase",
    *,
    n_warmup: int = N_WARMUP_DEFAULT,
    n_measure: int = N_MEASURE_DEFAULT,
    adapter_name: str = "wolfram",
) -> BenchResult:
    """Time *tc* by running it N times inside an :class:`IsolatedContext`.

    The adapter is initialized once; warmup runs are discarded.
    Timing covers only the :meth:`~IsolatedContext.run_test` call.

    Args:
        adapter:      Instantiated adapter (Wolfram, Julia, or Python).
        test_file:    Loaded :class:`TestFile` containing *tc*.
        tc:           The specific test case to benchmark.
        n_warmup:     Number of warmup iterations (not measured).
        n_measure:    Number of measured iterations.
        adapter_name: Label stored in the result (e.g. ``"wolfram"``).

    Returns:
        A :class:`BenchResult` with median, p95, p99, min, max in ms.
    """
    from sxact.runner.isolation import IsolatedContext

    with IsolatedContext(adapter, test_file) as ctx:
        for _ in range(n_warmup):
            ctx.run_test(tc)

        times: list[float] = []
        for _ in range(n_measure):
            t0 = time.perf_counter()
            ctx.run_test(tc)
            times.append((time.perf_counter() - t0) * 1_000)

    times_sorted = sorted(times)
    n = len(times_sorted)

    def _percentile(p: float) -> float:
        idx = int(p / 100 * (n - 1))
        return round(times_sorted[idx], 4)

    return BenchResult(
        test_id=f"{test_file.meta.id}/{tc.id}",
        adapter=adapter_name,
        n_warmup=n_warmup,
        n_measure=n_measure,
        median_ms=round(statistics.median(times), 4),
        p95_ms=_percentile(95),
        p99_ms=_percentile(99),
        min_ms=round(min(times), 4),
        max_ms=round(max(times), 4),
        timestamp=datetime.now(timezone.utc).isoformat(),
    )


# ---------------------------------------------------------------------------
# Baseline I/O
# ---------------------------------------------------------------------------


def load_baseline(
    path: Path,
) -> tuple[dict[str, BenchResult], MachineInfo | None]:
    """Load baseline JSON.

    Returns:
        (mapping of ``"adapter/test_id"`` → result, MachineInfo or None)
    """
    if not path.exists():
        return {}, None
    text = path.read_text(encoding="utf-8").strip()
    if not text:
        return {}, None
    raw = json.loads(text)
    out = {}
    for entry in raw.get("benchmarks", []):
        r = BenchResult.from_dict(entry)
        out[_key(r.adapter, r.test_id)] = r
    machine: MachineInfo | None = None
    if "machine" in raw:
        try:
            machine = MachineInfo.from_dict(raw["machine"])
        except Exception:
            pass
    return out, machine


def save_baseline(
    path: Path,
    results: list[BenchResult],
    machine: MachineInfo | None = None,
) -> None:
    """Write (or update) baseline JSON with the given results.

    Existing entries for the same adapter/test_id are replaced; others kept.
    Machine metadata is always refreshed from *machine* (or collected fresh if None).
    """
    existing, _ = load_baseline(path)
    for r in results:
        existing[_key(r.adapter, r.test_id)] = r

    if machine is None:
        machine = collect_machine_info()

    data = {
        "machine": machine.to_dict(),
        "recorded_at": datetime.now(timezone.utc).isoformat(),
        "benchmarks": [r.to_dict() for r in existing.values()],
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def _key(adapter: str, test_id: str) -> str:
    return f"{adapter}/{test_id}"


# ---------------------------------------------------------------------------
# Regression check
# ---------------------------------------------------------------------------


@dataclass
class RegressionResult:
    test_id: str
    adapter: str
    current_median_ms: float
    baseline_median_ms: float
    ratio: float
    level: str  # "ok", "warning", "fail", "critical"


def check_regression(
    current: list[BenchResult],
    baseline: dict[str, BenchResult],
    wolfram_baseline: dict[str, BenchResult] | None = None,
) -> list[RegressionResult]:
    """Compare *current* results against stored baseline.

    Also checks cross-adapter ratio vs. Wolfram if *wolfram_baseline* given.
    Returns a list of :class:`RegressionResult` for every benchmark.
    """
    results = []
    for r in current:
        base = baseline.get(_key(r.adapter, r.test_id))
        if base is None:
            continue
        if base.median_ms == 0:
            continue
        ratio = r.median_ms / base.median_ms
        delta_ms = r.median_ms - base.median_ms
        # Ignore regressions below the minimum absolute delta — sub-ms
        # fluctuations on shared CI runners are noise, not signal.
        if delta_ms < MIN_REGRESSION_DELTA_MS:
            level = "ok"
        else:
            level = _regression_level(ratio)
        results.append(
            RegressionResult(
                test_id=r.test_id,
                adapter=r.adapter,
                current_median_ms=r.median_ms,
                baseline_median_ms=base.median_ms,
                ratio=ratio,
                level=level,
            )
        )

    if wolfram_baseline:
        for r in current:
            if r.adapter == "wolfram":
                continue
            wkey = _key("wolfram", r.test_id)
            wb = wolfram_baseline.get(wkey)
            if wb is None or wb.median_ms == 0:
                continue
            ratio = r.median_ms / wb.median_ms
            level = _cross_adapter_level(ratio)
            results.append(
                RegressionResult(
                    test_id=r.test_id,
                    adapter=f"{r.adapter}/vs_wolfram",
                    current_median_ms=r.median_ms,
                    baseline_median_ms=wb.median_ms,
                    ratio=ratio,
                    level=level,
                )
            )

    return results


def _regression_level(ratio: float) -> str:
    """Same-adapter regression: current run vs stored baseline (spec §5.5)."""
    if ratio >= THRESHOLD_REGRESSION_CRITICAL:
        return "critical"
    if ratio >= THRESHOLD_REGRESSION_FAIL:
        return "fail"
    if ratio >= THRESHOLD_REGRESSION_WARNING:
        return "warning"
    return "ok"


def _cross_adapter_level(ratio: float) -> str:
    """Cross-adapter slowdown: Julia/Python vs Wolfram baseline (spec §5.5)."""
    if ratio >= THRESHOLD_CROSS_CRITICAL:
        return "critical"
    if ratio >= THRESHOLD_CROSS_FAIL:
        return "fail"
    if ratio >= THRESHOLD_CROSS_WARNING:
        return "warning"
    return "ok"
