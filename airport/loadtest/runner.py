#!/usr/bin/env python3
"""Run N simultaneous sessions against the airport tick API."""

from __future__ import annotations

import math
import os
import sys
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import psycopg2


def main() -> None:
    """Load one run row and keep that many sessions busy until the duration ends."""
    if len(sys.argv) != 2:
        raise SystemExit("usage: runner.py <run-id>")
    _load_env(Path("/etc/airport/airport.env"))
    run_id = int(sys.argv[1])
    sessions, duration_s = _read_run(run_id)
    url = os.environ["AIRPORT_TICK_URL"]
    latencies: list[float] = []
    counts = {"requests": 0, "errors": 0}
    lock = threading.Lock()
    deadline = time.perf_counter() + duration_s
    next_flush = time.perf_counter() + 2

    def one() -> None:
        while time.perf_counter() < deadline:
            started = time.perf_counter()
            failed = False
            try:
                with urllib.request.urlopen(url, timeout=20) as response:
                    if response.status != 200:
                        failed = True
                    response.read()
            except (urllib.error.URLError, TimeoutError, OSError):
                failed = True
            elapsed_ms = (time.perf_counter() - started) * 1000
            with lock:
                latencies.append(elapsed_ms)
                counts["requests"] += 1
                if failed:
                    counts["errors"] += 1

    try:
        with ThreadPoolExecutor(max_workers=sessions) as pool:
            workers = [pool.submit(one) for _ in range(sessions)]
            while any(not worker.done() for worker in workers):
                time.sleep(0.5)
                if time.perf_counter() >= next_flush:
                    with lock:
                        snapshot_counts = dict(counts)
                        snapshot_latencies = list(latencies)
                    _save(run_id, "running", snapshot_counts, snapshot_latencies, "")
                    next_flush = time.perf_counter() + 2
            for worker in workers:
                worker.result()
        with lock:
            snapshot_counts = dict(counts)
            snapshot_latencies = list(latencies)
        _save(run_id, "done", snapshot_counts, snapshot_latencies, "")
    except Exception as exc:
        with lock:
            snapshot_counts = dict(counts)
            snapshot_latencies = list(latencies)
        _save(run_id, "failed", snapshot_counts, snapshot_latencies, str(exc))
        raise


def _load_env(path: Path) -> None:
    if not path.is_file():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key, value)


def _read_run(run_id: int) -> tuple[int, int]:
    with psycopg2.connect(os.environ["AIRPORT_DSN"]) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                select sessions
                 , duration_s
                from load_run
                where id = %s
                """,
                (run_id,),
            )
            row = cur.fetchone()
    if row is None:
        raise SystemExit(f"load run {run_id} does not exist")
    return int(row[0]), int(row[1])


def _save(
    run_id: int,
    state: str,
    counts: dict[str, int],
    latencies: list[float],
    note: str,
) -> None:
    finished = state in {"done", "failed"}
    with psycopg2.connect(os.environ["AIRPORT_DSN"]) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                update load_run
                set state = %s
                 , requests = %s
                 , errors = %s
                 , p50_ms = %s
                 , p95_ms = %s
                 , note = %s
                 , finished_at = case when %s then now() else finished_at end
                where id = %s
                """,
                (
                    state,
                    counts["requests"],
                    counts["errors"],
                    _percentile(latencies, 50) if finished else None,
                    _percentile(latencies, 95) if finished else None,
                    note[:500],
                    finished,
                    run_id,
                ),
            )


def _percentile(values: list[float], pct: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, math.ceil(pct / 100 * len(ordered)) - 1))
    return round(ordered[index], 1)


if __name__ == "__main__":
    main()
