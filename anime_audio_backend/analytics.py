# analytics.py



from typing import Dict, List

from datetime import datetime, timedelta, date as pydate



from fastapi import APIRouter, Depends, HTTPException, Path

from sqlalchemy import func, desc, case, or_, literal

from sqlalchemy.orm import Session


from zoneinfo import ZoneInfo
from models import Logs, User, Song, Genre, Anime, Playlist, anime_genre

from database import get_db

from auth_utils import get_current_user

from utils.badge_util import assign_badges
from sqlalchemy import Table
from sqlalchemy.orm import Session
from sqlalchemy import Table, MetaData
from sqlalchemy import String



router = APIRouter()



# Count 102 "reservation" rows as success alongside 200 if True.

INCLUDE_RESERVATIONS = False
EXCLUDED_LEADERBOARD_USER_IDS = {2}

_FILES_TABLE = None

def _files_table(db: Session):
    global _FILES_TABLE
    if _FILES_TABLE is None:
        md = MetaData()
        _FILES_TABLE = Table("files", md, autoload_with=db.bind)
    return _FILES_TABLE

# ----------------------------- Helpers -----------------------------



def _first_existing_attr(model, names):

    for n in names:

        if hasattr(model, n):

            return getattr(model, n)

    return None





def _timestamp_col():

    ts = _first_existing_attr(Logs, ["created_at", "created", "time"])

    if ts is None:

        raise RuntimeError("Logs needs a timestamp column: created_at / created / time")

    return ts





def _success_pred():

    # Prefer explicit HTTP-esque code if present

    if hasattr(Logs, "code"):

        return Logs.code.in_([200, 102]) if INCLUDE_RESERVATIONS else (Logs.code == 200)



    # Fallback to 'status' if present (treat 200/102 as success like above)

    if hasattr(Logs, "status"):

        return Logs.status.in_([200, 102]) if INCLUDE_RESERVATIONS else (Logs.status == 200)



    # Fallback to boolean 'is_match' if present

    if hasattr(Logs, "is_match"):

        return Logs.is_match.is_(True)



    # Last resort: any non-null accuracy treated as success

    if hasattr(Logs, "accuracy"):

        return Logs.accuracy.isnot(None)



    # If none of the above exist, always-false predicate (no successes)

    from sqlalchemy import literal as _lit

    return _lit(False)





def _user_filter_for(user: User):

    """

    Prefer api_key when Logs has it; else fallback to user_id.

    """

    has_api_key = hasattr(Logs, "api_key")

    has_user_id = hasattr(Logs, "user_id")



    if not (has_api_key or has_user_id):

        raise HTTPException(status_code=500, detail="Logs must have api_key or user_id")



    # Prefer api_key if available (and user has one) or if no user_id column exists.

    if has_api_key and (user.api_key or not has_user_id):

        return (Logs.api_key == user.api_key)

    elif has_user_id:

        return (Logs.user_id == user.id)

    else:

        # Shouldn’t happen due to guard above

        raise HTTPException(status_code=500, detail="Cannot construct user filter")





def _normalized_search_type():

    """

    Normalizes search_type for legacy rows:

      - If song_id present -> 'audio', else 'scene'.

      - Coalesce with Logs.search_type if it exists.

    """

    has_search_type = hasattr(Logs, "search_type")

    has_song_id     = hasattr(Logs, "song_id")



    if has_search_type and has_song_id:

        normalized_fallback = case((Logs.song_id.isnot(None), "audio"), else_="scene")

    elif has_search_type and not has_song_id:

        normalized_fallback = literal("scene")

    elif not has_search_type and has_song_id:

        normalized_fallback = case((Logs.song_id.isnot(None), "audio"), else_="scene")

    else:

        normalized_fallback = literal("scene")



    # If Logs.search_type exists, coalesce it; otherwise just use normalized_fallback

    st_col = getattr(Logs, "search_type", None)

    return func.coalesce(st_col, normalized_fallback) if st_col is not None else normalized_fallback





def _compute_analytics_for(user: User, db: Session) -> Dict[str, object]:
    excluded_ids = tuple(EXCLUDED_LEADERBOARD_USER_IDS)

    ts = _timestamp_col()

    ok = _success_pred()

    me_filter = _user_filter_for(user)

    normalized_type = _normalized_search_type()
 


    has_song_id  = hasattr(Logs, "song_id")

    has_anime_id = hasattr(Logs, "anime_id")

    has_user_id  = hasattr(Logs, "user_id")



    # Local-day bucketing (America/New_York), via DB (Postgres-friendly)

    tz_ts     = func.timezone('America/New_York', ts)

    day_expr  = func.date(tz_ts).label("day")

    date_expr = func.date(tz_ts).label("date")



    # ---- Totals / Successes (all-time) ----

    total_scene   = db.query(Logs).filter(me_filter, normalized_type == "scene").count()

    success_scene = db.query(Logs).filter(me_filter, normalized_type == "scene", ok).count()



    total_audio   = db.query(Logs).filter(me_filter, normalized_type == "audio").count()

    success_audio = db.query(Logs).filter(me_filter, normalized_type == "audio", ok).count()



    # ---- Average confidence (scene) ----

    avg_conf = (

        db.query(func.avg(Logs.accuracy))

        .filter(me_filter, normalized_type == "scene", Logs.accuracy.isnot(None))

        .scalar() or 0.0

    )



    # ---- Longest success streak (by local day) ----

# ---- Longest success streak (consecutive LOCAL days with ≥1 success) ----
    success_days_rows = (
        db.query(func.date(tz_ts).label("d"))
        .filter(me_filter, ok, normalized_type.in_(["scene", "audio"]))
        .distinct()
        .order_by("d")
        .all()
    )

    success_days: List[pydate] = []
    for r in success_days_rows:
        d = r.d
        # Defensive: some DBs may return datetime; coerce to date
        if hasattr(d, "date"):
            d = d.date()
        success_days.append(d)

    best_streak = 0
    current = 0
    prev: pydate | None = None

    for d in success_days:
        if prev is not None and d == (prev + timedelta(days=1)):
            current += 1
        else:
            current = 1
        if current > best_streak:
            best_streak = current
        prev = d

    # ---- Per-day counts ----

    def per_day(tpe: str) -> List[Dict[str, object]]:

        rows = (

            db.query(date_expr, func.count().label("count"))

            .filter(me_filter, normalized_type == tpe)

            .group_by(date_expr)

            .order_by(date_expr)

            .all()

        )

        return [{"date": r.date.isoformat(), "count": int(r.count)} for r in rows]



    scene_per_day = per_day("scene")

    audio_per_day = per_day("audio")



    # ---- Matches per day (success only) ----

    matches_rows = (

        db.query(date_expr, func.count().label("count"))

        .filter(me_filter, ok, normalized_type.in_(["scene", "audio"]))

        .group_by(date_expr)

        .order_by(date_expr)

        .all()

    )

    matches_per_day = [{"date": r.date.isoformat(), "count": int(r.count)} for r in matches_rows]



    # ---- Confidence trend (scene) ----

    conf_rows = (

        db.query(date_expr, func.avg(Logs.accuracy).label("confidence"))

        .filter(me_filter, normalized_type == "scene", Logs.accuracy.isnot(None))

        .group_by(date_expr)

        .order_by(date_expr)

        .all()

    )

    confidence_trend = [

        {"date": r.date.isoformat(), "confidence": float(r.confidence or 0.0)}

        for r in conf_rows

    ]



    # ---- Top 3 artists (my successful audio) ----

    if has_song_id:

        top_artists = {

            r.artist: int(r.count)

            for r in (

                db.query(Song.artist, func.count().label("count"))

                .join(Logs, Logs.song_id == Song.song_id)

                .filter(me_filter, ok, normalized_type == "audio")

                .group_by(Song.artist)

                .order_by(desc("count"))

                .limit(3)

                .all()

            )

        }

    else:

        top_artists = {}



    # ---- Genre distribution (my successful scene) ----

    if has_anime_id:

        genre_distribution = {

            r.name: int(r.count)

            for r in (

                db.query(Genre.name, func.count().label("count"))

                .join(anime_genre, anime_genre.c.genre_id == Genre.id)

                .join(Logs, Logs.anime_id == anime_genre.c.anime_id)

                .filter(me_filter, ok, normalized_type == "scene")

                .group_by(Genre.name)

                .order_by(desc("count"))

                .all()

            )

        }

    else:

        genre_distribution = {}



    # ---- Playlists created ----

    playlists_created = (

        db.query(func.count(Playlist.id))

        .filter(Playlist.user_id == user.id)

        .scalar() or 0

    )



        # ---- Rank among users (successes only) ----
    # Treat a log as belonging to a user if either user_id matches OR api_key matches.
    # This unifies legacy rows (api_key only) with newer rows (user_id set).
    ownership = []
    if hasattr(Logs, "user_id"):
        ownership.append(Logs.user_id == user.id)
    if hasattr(Logs, "api_key") and getattr(user, "api_key", None):
        ownership.append(Logs.api_key == user.api_key)

    if not ownership:
        user_rank = 0
    else:
        my_success_total = (
            db.query(func.count())
            .select_from(Logs)
            .filter(or_(*ownership), ok, normalized_type.in_(["scene", "audio"]))
            .scalar() or 0
        )

        cohort = (
            db.query(User.id.label("uid"), func.count().label("cnt"))
            .select_from(User)
            .join(
                Logs,
                or_(
                    (hasattr(Logs, "user_id") and Logs.user_id == User.id),
                    (hasattr(Logs, "api_key") and Logs.api_key == User.api_key),
                ),
            )
            .filter(ok, normalized_type.in_(["scene", "audio"]))
            .group_by(User.id)
            .subquery()
        )
        higher = (
            db.query(func.count())
            .select_from(cohort)
            .filter(cohort.c.cnt > my_success_total)
            .scalar() or 0
        )
        user_rank = int(higher) + 1


    # ---- Global top anime (successes) ----

    top_anime = {}

    if has_anime_id:
        ny = ZoneInfo("America/New_York")
        now_ny = datetime.now(ny)

        # Month window in NY local time
        month_start = now_ny.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        if month_start.month == 12:
            next_month_start = month_start.replace(year=month_start.year + 1, month=1)
        else:
            next_month_start = month_start.replace(month=month_start.month + 1)
        
        files = _files_table(db)

        # 1) count by anime_id
        sub = (
            db.query(
                Logs.anime_id.label("aid"),
                func.count().label("count"),
            )
            .filter(
                ok,
                normalized_type == "scene",
                Logs.anime_id.isnot(None),
                tz_ts >= month_start.replace(tzinfo=None),
                tz_ts < next_month_start.replace(tzinfo=None),
            )
            .group_by(Logs.anime_id)
            .subquery()
        )

        # 2) pick a representative path per anime_id (avoid duplicates)
        rep = (
            db.query(
                files.c.anilist_id.label("aid"),
                files.c.path.label("path"),
            )
            .distinct(files.c.anilist_id)
            .order_by(files.c.anilist_id, func.length(files.c.path))  # shortest wins
            .subquery()
        )

        # 3) clean the representative path into a title
        filename = func.regexp_replace(rep.c.path, r"^.*/", "", "g")
        base     = func.regexp_replace(filename, r"\.[^.]+$", "", "g")
        no_grp   = func.regexp_replace(base, r"^\[[^\]]+\]\s*", "", "g")

        # remove everything from the first episode delimiter onward (supports - – —)
        cut_ep   = func.regexp_replace(no_grp, r"\s*[-–—]\s*\d{1,4}.*$", "", "g")

        # if any trailing bracket/paren junk still exists, strip it
        cut_tags = func.regexp_replace(cut_ep, r"(\s*[\(\[].*[\)\]])+\s*$", "", "g")

        # collapse whitespace, trim, and provide a fallback if empty
        collapsed = func.regexp_replace(cut_tags, r"\s+", " ", "g")
        title = func.nullif(func.trim(collapsed), "").label("title")

        rows = (
            db.query(
                sub.c.aid.label("aid"),
                func.coalesce(title, func.concat("AniList ", sub.c.aid.cast(String))).label("title"),
                sub.c.count.label("count"),
            )
            .join(rep, rep.c.aid == sub.c.aid)
            .order_by(desc(sub.c.count))
            .limit(5)
            .all()
        )

        # Keep the original shape: title -> count
        top_anime = {r.title: int(r.count) for r in rows}

        # Add a parallel mapping: title -> url (frontend can look up link by title)
        top_anime_links = {
            r.title: f"/users/discover?q={int(r.aid)}&page=1&per=24"
            for r in rows
        }


    # ---- Global top users (successes) ----
   
    if has_user_id:

        top_users = {

            r.user: int(r.count)

            for r in (

                db.query(User.display_name.label("user"), func.count().label("count"))

                .join(Logs, Logs.user_id == User.id)

                .filter(ok)

                .filter(~User.id.in_(excluded_ids))

                .group_by(User.id, User.display_name)

                .order_by(desc("count"))

                .limit(5)

                .all()

            )

        }

    elif hasattr(Logs, "api_key"):
        top_users = {
            r.user: int(r.count)
            for r in (
                db.query(User.display_name.label("user"), func.count().label("count"))
                .join(Logs, Logs.api_key == User.api_key)
                .filter(ok)
                .filter(~User.id.in_(excluded_ids))   # <-- add this
                .group_by(User.api_key, User.display_name)
                .order_by(desc("count"))
                .limit(5)
                .all()
            )
        }

    else:

        top_users = {}



    analytics = {

        "totalSceneSearches": total_scene,

        "successfulSceneMatches": success_scene,

        "totalAudioSearches": total_audio,

        "successfulAudioMatches": success_audio,

        "longestStreakDays": best_streak,

        "averageConfidence": float(avg_conf),

        "sceneSearchesPerDay": scene_per_day,

        "audioSearchesPerDay": audio_per_day,

        "matchesPerDay": matches_per_day,

        "confidenceTrend": confidence_trend,

        "topArtists": top_artists,

        "genreDistribution": genre_distribution,

        "playlistsCreated": playlists_created,

        "userRank": user_rank,

        "topAnime": top_anime,

        "topUsers": top_users,
        
        "topAnimeLinks": top_anime_links,

    }

    return analytics





# ----------------------------- Routes -----------------------------



@router.get("/me/analytics", response_model=Dict[str, object])

def get_my_analytics(

    db: Session = Depends(get_db),

    me: User = Depends(get_current_user),

):

    if not me:

        raise HTTPException(status_code=401, detail="Unauthorized")

    analytics = _compute_analytics_for(me, db)

    assign_badges(me, analytics, db)

    return analytics





@router.get("/users/{user_id}/analytics", response_model=Dict[str, object])

def get_user_analytics(

    user_id: int = Path(..., ge=1),

    db: Session = Depends(get_db),

    me: User = Depends(get_current_user),

):

    """

    Analytics for an arbitrary user by ID.

    You can add permission checks if some profiles should be private.

    """

    user = db.query(User).filter(User.id == user_id).first()

    if not user:

        raise HTTPException(status_code=404, detail="User not found")



    analytics = _compute_analytics_for(user, db)

    assign_badges(user, analytics, db)

    return analytics

