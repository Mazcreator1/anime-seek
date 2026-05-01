# weekly_top.py
from datetime import datetime, timedelta
import pytz
from sqlalchemy import func, desc

ET = pytz.timezone("America/New_York")

def week_bounds_now():
    now_et = datetime.now(ET)
    # last full week (Mon 00:00 → Mon 00:00)
    last_monday = (now_et - timedelta(days=now_et.weekday()+7)).replace(hour=0, minute=0, second=0, microsecond=0)
    this_monday = last_monday + timedelta(days=7)
    # return UTC times for DB
    return last_monday.astimezone(pytz.UTC), this_monday.astimezone(pytz.UTC)

def pick_top_anime(db, Logs, Anime):
    start_utc, end_utc = week_bounds_now()
    q = (db.query(
            Logs.anime_id.label("anime_id"),
            func.count(Logs.anime_id).label("hits"),
            func.avg(Logs.status).label("avg_conf"),
            func.min(Logs.created_at).label("first_hit"))
         .filter(Logs.created_at >= start_utc, Logs.created_at < end_utc)
         .group_by(Logs.anime_id)
         .order_by(desc("hits"), desc("avg_conf"), "first_hit"))
    top = q.first()
    if not top: return None
    anime = db.query(Anime).get(top.anime_id)  # or join in the q
    return {
        "anime_id": top.anime_id,
        "hits": int(top.hits),
        "avg_conf": float(top.avg_conf or 0),
        "first_hit": top.first_hit,
        "title": getattr(anime, "title", f"Anime #{top.anime_id}"),
        "metadata": {
            "season": getattr(anime, "season", None),
            "op_ed_type": getattr(anime, "op_ed_type", None),
            "year": getattr(anime, "year", None),
        }
    }
