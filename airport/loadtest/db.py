"""Connections to the airport database."""

from __future__ import annotations

import logging
import os
import queue
import threading
from collections.abc import Iterator
from contextlib import contextmanager

import psycopg2

log = logging.getLogger(__name__)

_idle: queue.Queue[psycopg2.extensions.connection] = queue.Queue(maxsize=16)
_lock = threading.Lock()
_open = 0
_MAX = 16


def pool_size() -> int:
    """How many connections this process may keep open."""
    return _MAX


@contextmanager
def connection() -> Iterator[psycopg2.extensions.connection]:
    """Borrow a connection and commit, or roll back on failure."""
    conn = _borrow()
    try:
        yield conn
        if not conn.autocommit:
            conn.commit()
    except Exception:
        if not conn.autocommit:
            conn.rollback()
        raise
    finally:
        _release(conn)


def _borrow() -> psycopg2.extensions.connection:
    global _open
    try:
        return _idle.get_nowait()
    except queue.Empty:
        pass
    with _lock:
        if _open < _MAX:
            _open += 1
            return psycopg2.connect(os.environ["AIRPORT_DSN"])
    try:
        return _idle.get(timeout=5)
    except queue.Empty:
        log.warning("airport connection pool is exhausted")
        raise


def _release(conn: psycopg2.extensions.connection) -> None:
    global _open
    if conn.closed:
        with _lock:
            _open = max(0, _open - 1)
        return
    try:
        _idle.put_nowait(conn)
    except queue.Full:
        conn.close()
        with _lock:
            _open = max(0, _open - 1)
