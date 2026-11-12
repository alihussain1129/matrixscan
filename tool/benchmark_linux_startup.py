#!/usr/bin/env python3
"""Measure Linux process start through Flutter's first-frame log marker.

Build first with `flutter build linux --release`, then run this script from the
repository root. It reports process-to-frame wall time separately from the
in-app Dart-entry timing marker because the latter excludes native engine load.
"""

import argparse
import math
import os
import queue
import re
import statistics
import subprocess
import threading
import time
from pathlib import Path


MARKER = "[EXALTED][STARTUP] first frame after Dart entry in"
TIMING_MARKER = "[EXALTED][STARTUP] first frame build"


def resident_memory_mb(pid: int) -> float | None:
    try:
        for line in Path(f"/proc/{pid}/status").read_text().splitlines():
            if line.startswith("VmRSS:"):
                return int(line.split()[1]) / 1024
    except (OSError, ValueError, IndexError):
        pass
    return None


def launch(
    binary: Path, timeout: float, renderer: str
) -> tuple[float, float | None, str, list[str]]:
    env = os.environ.copy()
    env.setdefault("GDK_BACKEND", "wayland")
    if renderer != "default":
        env["FLUTTER_ENGINE_SWITCHES"] = "1"
        env["FLUTTER_ENGINE_SWITCH_1"] = (
            "enable-impeller=true" if renderer == "impeller" else "enable-impeller=false"
        )
    output: queue.Queue[str] = queue.Queue()
    started = time.perf_counter_ns()
    process = subprocess.Popen(
        [str(binary)],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        env=env,
    )

    def read_output() -> None:
        assert process.stdout is not None
        for line in process.stdout:
            output.put(line.rstrip())

    threading.Thread(target=read_output, daemon=True).start()
    deadline = time.monotonic() + timeout
    marker_line = None
    timing_line = None
    first_frame_elapsed_ms = None
    rss_mb = None
    startup_lines = []
    while time.monotonic() < deadline and process.poll() is None:
        try:
            line = output.get(timeout=0.1)
        except queue.Empty:
            continue
        if "[EXALTED][STARTUP]" in line or "rendering backend" in line:
            startup_lines.append(line)
        if MARKER in line:
            marker_line = line
            first_frame_elapsed_ms = (time.perf_counter_ns() - started) / 1_000_000
            rss_mb = resident_memory_mb(process.pid)
        if TIMING_MARKER in line:
            timing_line = line
        if marker_line is not None and timing_line is not None:
            break

    elapsed_ms = (time.perf_counter_ns() - started) / 1_000_000
    if marker_line is None:
        process.kill()
        process.wait()
        raise RuntimeError(f"No first-frame marker within {timeout:g}s")

    process.terminate()
    try:
        process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
    if timing_line is None:
        startup_lines.append("first-frame build/raster timing unavailable")
    return (
        first_frame_elapsed_ms or elapsed_ms,
        rss_mb,
        marker_line,
        startup_lines,
    )


def percentile95(values: list[float]) -> float:
    ordered = sorted(values)
    index = max(0, min(len(ordered) - 1, math.ceil(0.95 * len(ordered)) - 1))
    return ordered[index]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--binary",
        type=Path,
        default=Path("build/linux/x64/release/bundle/exalted"),
    )
    parser.add_argument("--runs", type=int, default=10)
    parser.add_argument("--timeout", type=float, default=20)
    parser.add_argument(
        "--renderer",
        choices=("default", "impeller", "skia"),
        default="default",
        help="Profile builds only: override Flutter's Linux renderer.",
    )
    args = parser.parse_args()
    if args.runs < 2:
        parser.error("--runs must be at least 2 to compare first and warm runs")
    binary = args.binary.resolve()
    if not binary.is_file():
        parser.error(f"Application binary not found: {binary}")

    samples = []
    rss_samples = []
    build_samples = []
    raster_samples = []
    for index in range(args.runs):
        elapsed, rss_mb, marker, phases = launch(
            binary, args.timeout, args.renderer
        )
        samples.append(elapsed)
        if rss_mb is not None:
            rss_samples.append(rss_mb)
        rss = "unavailable" if rss_mb is None else f"{rss_mb:.1f}"
        print(
            f"run={index + 1} process_to_first_frame_ms={elapsed:.1f} "
            f"rss_after_first_frame_mb={rss} {marker}"
        )
        for phase in phases:
            if phase != marker:
                print(f"  {phase}")
            match = re.search(r"first frame build (\d+)µs, raster (\d+)µs", phase)
            if match:
                build_samples.append(int(match.group(1)) / 1000)
                raster_samples.append(int(match.group(2)) / 1000)

    warm = samples[1:]
    print(f"first_process_ms={samples[0]:.1f}")
    print(
        "subsequent_processes_ms="
        f"median:{statistics.median(warm):.1f} "
        f"p95:{percentile95(warm):.1f} min:{min(warm):.1f} max:{max(warm):.1f}"
    )
    if rss_samples:
        print(
            "rss_after_first_frame_mb="
            f"median:{statistics.median(rss_samples):.1f} "
            f"min:{min(rss_samples):.1f} max:{max(rss_samples):.1f}"
        )
    if build_samples and raster_samples:
        print(
            "first_frame_build_raster_ms="
            f"build_median:{statistics.median(build_samples):.2f} "
            f"raster_median:{statistics.median(raster_samples):.2f} "
            f"raster_p95:{percentile95(raster_samples):.2f}"
        )
    print(
        "scope=process-start-to-first-frame; first run is a fresh app process, "
        "not a guaranteed cold operating-system page cache"
    )


if __name__ == "__main__":
    main()
