"""Load test page and one airport read or write."""

from __future__ import annotations

import logging
import os
import random
import subprocess
import sys
from pathlib import Path

from django.http import HttpRequest
from django.http import HttpResponse
from django.http import JsonResponse
from django.shortcuts import redirect
from django.shortcuts import render
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_GET
from django.views.decorators.http import require_POST

from loadtest.cluster import cluster_status
from loadtest.db import connection

log = logging.getLogger(__name__)

MIN_SESSIONS = 5
MAX_SESSIONS = 200
MIN_DURATION_S = 10
MAX_DURATION_S = 120


@require_GET
def health(_request: HttpRequest) -> HttpResponse:
    """Tell HAProxy this guest can serve the airport page."""
    return HttpResponse("ok\n", content_type="text/plain")


@require_GET
def home(request: HttpRequest) -> HttpResponse:
    """Show the form that starts simultaneous airport sessions."""
    _expire_stale_runs()
    return render(
        request,
        "loadtest/home.html",
        {
            "run": _current_run(),
            "min_sessions": MIN_SESSIONS,
            "max_sessions": MAX_SESSIONS,
            "min_duration_s": MIN_DURATION_S,
            "max_duration_s": MAX_DURATION_S,
            "error": request.GET.get("error", ""),
            "servers": cluster_status(),
        },
    )


@require_POST
def start(request: HttpRequest) -> HttpResponse:
    """Start one load run of 5 to 200 sessions."""
    try:
        sessions = int(request.POST.get("sessions", ""))
        duration_s = int(request.POST.get("duration_s", ""))
    except ValueError:
        return redirect("/?error=Enter%20a%20whole%20number%20of%20sessions%20and%20seconds")
    if sessions < MIN_SESSIONS or sessions > MAX_SESSIONS:
        return redirect(f"/?error=Sessions%20must%20be%20{MIN_SESSIONS}%20to%20{MAX_SESSIONS}")
    if duration_s < MIN_DURATION_S or duration_s > MAX_DURATION_S:
        return redirect(
            f"/?error=Duration%20must%20be%20{MIN_DURATION_S}%20to%20{MAX_DURATION_S}%20seconds"
        )
    _expire_stale_runs()
    with connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                insert into load_run (
                    sessions
                    , duration_s
                    , state
                )
                select %s
                 , %s
                 , 'running'
                where not exists (
                    select 1
                    from load_run
                    where state = 'running'
                )
                returning id
                """,
                (sessions, duration_s),
            )
            row = cur.fetchone()
    if row is None:
        return redirect("/?error=A%20load%20run%20is%20already%20going")
    _spawn(int(row[0]))
    return redirect("/")


@require_GET
def cluster(_request: HttpRequest) -> JsonResponse:
    """Return every lane server, its address, its purpose, and its health."""
    return JsonResponse({"servers": cluster_status()})


@require_GET
def status(_request: HttpRequest) -> JsonResponse:
    """Return the latest load run for the page to poll."""
    _expire_stale_runs()
    run = _current_run()
    return JsonResponse({"run": run})


@csrf_exempt
@require_GET
def tick(_request: HttpRequest) -> JsonResponse:
    """Do one airport search or booking. About four of five calls only read."""
    read = random.random() < 0.8
    try:
        with connection() as conn:
            conn.autocommit = read
            with conn.cursor() as cur:
                if read:
                    action = "search"
                    cur.execute(
                        """
                        select f.id
                         , o.code
                         , d.code
                         , f.departs_at
                        from flight f
                        join airport o
                            on o.id = f.origin_id
                        join airport d
                            on d.id = f.dest_id
                        where o.code = (
                            select a.code
                            from airport a
                            order by random()
                            limit 1
                        )
                        order by f.departs_at
                        limit 15
                        """
                    )
                    cur.fetchall()
                else:
                    action = "book"
                    cur.execute(
                        """
                        insert into booking (
                            flight_id
                            , passenger
                            , seats
                        )
                        select f.id
                         , 'load-' || substr(md5(random()::text), 1, 8)
                         , 1
                        from flight f
                        offset floor(random() * (select count(*) from flight))
                        limit 1
                        returning id
                        """
                    )
                    cur.fetchone()
    except Exception:
        log.exception("airport tick failed")
        return JsonResponse({"ok": False}, status=500)
    return JsonResponse({"ok": True, "action": action})


def _current_run() -> dict[str, object] | None:
    with connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                select id
                 , sessions
                 , duration_s
                 , state
                 , requests
                 , errors
                 , p50_ms
                 , p95_ms
                 , note
                 , started_at
                 , finished_at
                from load_run
                order by id desc
                limit 1
                """
            )
            row = cur.fetchone()
    if row is None:
        return None
    return {
        "id": row[0],
        "sessions": row[1],
        "duration_s": row[2],
        "state": row[3],
        "requests": row[4],
        "errors": row[5],
        "p50_ms": None if row[6] is None else float(row[6]),
        "p95_ms": None if row[7] is None else float(row[7]),
        "note": row[8],
        "started_at": row[9].isoformat(),
        "finished_at": None if row[10] is None else row[10].isoformat(),
    }


def _expire_stale_runs() -> None:
    with connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                update load_run
                set state = 'failed'
                 , finished_at = now()
                 , note = 'stopped after the runner went away'
                where state = 'running'
                 and started_at < now() - ((duration_s + 30) * interval '1 second')
                """
            )


def _spawn(run_id: int) -> None:
    root = Path(__file__).resolve().parents[1]
    log_path = Path("/var/log/airport/load.log")
    with log_path.open("a", encoding="utf-8") as log_file:
        subprocess.Popen(
            [sys.executable, str(root / "loadtest" / "runner.py"), str(run_id)],
            cwd=str(root),
            start_new_session=True,
            stdout=log_file,
            stderr=log_file,
            env=os.environ.copy(),
        )
