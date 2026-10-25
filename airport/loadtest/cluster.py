"""Health of each lane guest and client address."""

from __future__ import annotations

import json
import logging
import socket
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

log = logging.getLogger(__name__)

SERVERS_PATH = Path("/etc/airport/servers.json")
_TIMEOUT_S = 1.0
_CACHE_S = 2.0
_cache_lock = threading.Lock()
_cache_at = 0.0
_cache: list[dict[str, object]] = []


def cluster_status() -> list[dict[str, object]]:
    """Return each server with its address, purpose, and latest health."""
    global _cache_at, _cache
    now = time.monotonic()
    with _cache_lock:
        if _cache and now - _cache_at < _CACHE_S:
            return list(_cache)
    rows = _load()
    if not rows:
        return []
    with ThreadPoolExecutor(max_workers=len(rows)) as pool:
        checked = list(pool.map(_check, rows))
    with _cache_lock:
        _cache_at = time.monotonic()
        _cache = checked
    return list(checked)


def _load() -> list[dict[str, object]]:
    try:
        loaded = json.loads(SERVERS_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        log.warning("airport server list is missing or unreadable")
        return []
    if not isinstance(loaded, list):
        return []
    return [row for row in loaded if isinstance(row, dict)]


def _check(server: dict[str, object]) -> dict[str, object]:
    kind = str(server.get("check", ""))
    address = str(server.get("address", ""))
    healthy, detail = _probe(kind, address)
    health = "Up" if healthy else "Down"
    if detail:
        health = f"{health}, {detail}"
    return {
        "name": server.get("name", ""),
        "address": address,
        "purpose": server.get("purpose", ""),
        "healthy": healthy,
        "health": health,
    }


def _probe(kind: str, address: str) -> tuple[bool, str]:
    try:
        if kind == "openbao":
            code, _body = _http(address, 8200, "/v1/sys/health")
            if code == 200:
                return True, "leader"
            if code == 429:
                return True, "standby"
            return False, ""
        if kind == "patroni":
            code, body = _http(address, 8008, "/patroni")
            if code != 200:
                return False, ""
            payload = json.loads(body)
            role = str(payload.get("role", ""))
            return payload.get("state") == "running", role
        if kind == "pgdog":
            return _tcp(address, 6432), ""
        if kind == "app":
            code, body = _http(address, 8080, "/health")
            return code == 200 and body.startswith("ok"), ""
        if kind == "airport":
            code, body = _http(address, 80, "/health")
            return code == 200 and body.startswith("ok"), ""
        if kind == "saas":
            code, _body = _http(address, 80, "/")
            if code == 0:
                return False, ""
            return True, f"HTTP {code}"
        if kind == "guest":
            return _tcp(address, 22), ""
    except (OSError, urllib.error.URLError, json.JSONDecodeError, TimeoutError, ValueError):
        return False, ""
    return False, ""


def _tcp(address: str, port: int) -> bool:
    with socket.create_connection((address, port), timeout=_TIMEOUT_S):
        return True


def _http(address: str, port: int, path: str) -> tuple[int, str]:
    request = urllib.request.Request(f"http://{address}:{port}{path}")
    try:
        with urllib.request.urlopen(request, timeout=_TIMEOUT_S) as response:
            return response.status, response.read(16384).decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        body = exc.read(16384).decode("utf-8", "replace")
        return exc.code, body
