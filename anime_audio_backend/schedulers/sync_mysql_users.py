import logging, time
from threading import Event, Thread
from sqlalchemy import text
from database import engine 
  # <-- use your existing engine

_STOP = Event()
_WORKER = None
_LOCK_KEY = 8420001  # unique bigint key for advisory lock

def _loop(interval: int):
    while not _STOP.is_set():
        try:
            with engine.begin() as conn:
                got = conn.execute(text("SELECT pg_try_advisory_lock(:k)"), {"k": _LOCK_KEY}).scalar()
            if not got:
                _STOP.wait(interval); continue

            try:
                while not _STOP.is_set():
                    try:
                        with engine.begin() as conn:
                            conn.execute(text("SELECT sync_mysql_users();"))
                    except Exception:
                        logging.exception("sync_mysql_users() failed")
                    _STOP.wait(interval)
            finally:
                with engine.begin() as conn:
                    conn.execute(text("SELECT pg_advisory_unlock(:k)"), {"k": _LOCK_KEY})
        except Exception:
            logging.exception("scheduler outer loop error")
            _STOP.wait(interval)

def start(interval: int = 60):
    global _WORKER
    if _WORKER and _WORKER.is_alive(): 
        return
    _STOP.clear()
    _WORKER = Thread(target=_loop, args=(interval,), daemon=True)
    _WORKER.start()

def stop():
    _STOP.set()
