
# server.py



import os

import time

import hashlib

import tempfile

import traceback
from zoneinfo import ZoneInfo
from pathlib import Path

from typing import Optional, List, Dict

from pydantic_settings import BaseSettings
from pydantic import BaseModel, Field, HttpUrl

import asyncio

import base64

import cv2

import httpx

import json

import logging

import shutil

import subprocess

import sys

import analytics

import numpy as np

import stripe

from dotenv import load_dotenv; load_dotenv("/app/.env")

from apscheduler.schedulers.asyncio import AsyncIOScheduler

from fastapi import (

    FastAPI, APIRouter, Depends, BackgroundTasks, HTTPException, File, Form, UploadFile,

    Request, Response, Header, Path as FPath, Query, Body, status

)
from fastapi import FastAPI
from router.character import router as character_router
from fastapi.middleware.cors import CORSMiddleware

from fastapi.staticfiles import StaticFiles

from fastapi.concurrency import run_in_threadpool

from fastapi.responses import JSONResponse, StreamingResponse, HTMLResponse

from fastapi.templating import Jinja2Templates

import redis.asyncio as aioredis



try:

    # fastapi-cache2 installs a module named `fastapi_cache`

    from fastapi_cache import FastAPICache

    from fastapi_cache.backends.redis import RedisBackend

except ImportError:  # module not installed / not found in this image

    FastAPICache = None



    class RedisBackend:

        """Minimal stub to keep the rest of the code working if fastapi_cache isn't installed."""

        def __init__(self, redis):

            self.redis = redis



    class _DummyCache:

        @staticmethod

        def init(*args, **kwargs):

            # no-op

            pass



        @staticmethod

        def get_backend():

            # mimic the real interface; `.redis` is used on shutdown

            class _Backend:

                redis = None

            return _Backend()



    FastAPICache = _DummyCache

import redis.asyncio as aioredis



from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST



from pydantic import BaseModel, Field

from passlib.context import CryptContext





from sqlalchemy.exc import ProgrammingError

from sqlalchemy.orm import Session



from httpx import AsyncClient, Limits, Timeout

from hashlib import sha1

from datetime import datetime, timedelta, timezone



from scipy.ndimage import maximum_filter, generate_binary_structure, binary_erosion

from pydub import AudioSegment

from pydub.utils import mediainfo



# --- Postgres driver (psycopg3) ---

import psycopg

from psycopg.rows import dict_row

import dejavu.fingerprint as fpmodule

import importlib
import users_discover  

def fixed_get_2D_peaks(arr2D, plot=False, amp_min=80):

    struct       = generate_binary_structure(2, 1)

    neighborhood = maximum_filter(arr2D, footprint=struct)

    local_max    = (arr2D == neighborhood)

    background   = (arr2D < amp_min)

    eroded_bg    = binary_erosion(background, structure=struct, border_value=1)

    detected     = np.logical_xor(local_max, eroded_bg)

    return list(zip(*np.where(detected)))



def fixed_generate_hashes(peaks, fan_value=1):

    for i, (f1, t1) in enumerate(peaks):

        for j in range(1, fan_value):

            if i + j < len(peaks):

                f2, t2 = peaks[i + j]

                raw     = f"{f1}|{f2}|{t2-t1}"

                yield hashlib.sha1(raw.encode("utf-8")).hexdigest(), t1



fpmodule.get_2D_peaks    = fixed_get_2D_peaks

fpmodule.generate_hashes = fixed_generate_hashes

import types

import sys


from fastapi.staticfiles import StaticFiles


# -------------------------------------------------------------------

# Stub out `pyaudio` so Dejavu's recognize.py can import safely.

# We only ever use FileRecognizer (file-based), not MicrophoneRecognizer,

# so these dummy values are never actually used in practice.

# -------------------------------------------------------------------

if "pyaudio" not in sys.modules:

    pyaudio_stub = types.ModuleType("pyaudio")



    # Constants Dejavu expects at class-definition time

    pyaudio_stub.paInt16 = 8          # arbitrary non-zero int

    pyaudio_stub.paContinue = 0       # typical "continue" flag



    # Dummy PyAudio class so accidental usage won't crash hard

    class _DummyStream:

        def start_stream(self): pass

        def stop_stream(self): pass

        def close(self): pass

        def is_active(self): return False

        def read(self, *args, **kwargs): return b""



    class _DummyPyAudio:

        def __init__(self, *args, **kwargs):

            pass



        def open(self, *args, **kwargs):

            # Return a no-op stream

            return _DummyStream()



        def terminate(self):

            pass



    pyaudio_stub.PyAudio = _DummyPyAudio



    sys.modules["pyaudio"] = pyaudio_stub



from dejavu.decoder import read

from dejavu.fingerprint import fingerprint

from dejavu import Dejavu

from dejavu.recognize import FileRecognizer





from auth_utils import get_current_user as auth_user

from config import settings

from database import Base, SessionLocal, engine, get_db

from models import (

    AniListMetadata, Anime, Logs, Playlist, PlaylistSong, Song, User,

    AnimeTiers, Follow

)

from metadata_service import store_anime_metadata

from anilist_client import fetch_anime_by_title

from auth_utils import get_current_user

from auth import router as auth_router

from tasks import prune_reset_tokens

from routes.scene_challenge import router as scene_challenge_router

from security import create_token, hash_password, verify_password

from payments.webhook import router as webhook_router

import userendpoints

import Badges

import music

from sqlalchemy import text, func, desc

from routes import wallet, market, admin_market, notifications


os.environ["OMP_NUM_THREADS"] = "4"

os.environ["MKL_NUM_THREADS"] = "4"



app = FastAPI(

    title="Anime Finder API",

    root_path="/fastapi",

    docs_url="/docs",

    openapi_url="/openapi.json",

    redoc_url=None

)
app.include_router(scene_challenge_router)

app.include_router(users_discover.router)

app.include_router(music.router)

app.include_router(auth_router)

app.include_router(webhook_router)

app.include_router(analytics.router)

app.include_router(userendpoints.router)

app.include_router(Badges.router)

os.makedirs("/app/generated_characters", exist_ok=True)

app.mount("/generated_characters", StaticFiles(directory="/app/generated_characters"), name="generated_characters",)

app.include_router(character_router)

app.include_router(wallet.router)

app.include_router(market.router)

app.include_router(admin_market.router)

app.include_router(notifications.router)

app.mount("/static", StaticFiles(directory="/app/static"), name="static")


stripe.api_key = settings.STRIPE_SECRET_KEY

templates = Jinja2Templates(directory="templates")





BASE_DIR = os.getcwd()

UPLOAD_DIR = os.path.join(BASE_DIR, "uploads")

STATIC_DIR = os.path.join(BASE_DIR, "static")

COVER_DIR  = os.path.join(BASE_DIR, "assets", "Album_Cover")


os.makedirs(UPLOAD_DIR, exist_ok=True)

os.makedirs(COVER_DIR, exist_ok=True)

os.makedirs(os.path.join(UPLOAD_DIR, "user_avatars"), exist_ok=True)



app.mount("/uploads", StaticFiles(directory="/app/uploads"), name="uploads")

app.mount("/audio",   StaticFiles(directory=UPLOAD_DIR),    name="audio")

app.mount("/covers",  StaticFiles(directory=COVER_DIR),     name="covers")

app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")


app.add_middleware(

    CORSMiddleware,

    allow_origins=[

        "https://41265f55.anime-pricing.pages.dev",

        settings.FRONTEND_URL,

    ],

    allow_credentials=True,

    allow_methods=["*"],

    allow_headers=["*"],

)





postgres_url = os.getenv("SQLALCHEMY_DATABASE_URL_POSTGRES")

if not postgres_url:

    raise RuntimeError("SQLALCHEMY_DATABASE_URL_POSTGRES is not set. Check your env.")





@app.on_event("startup")

async def startup_event():

    global _redis

    redis_host = os.getenv("REDIS_HOST", "localhost")

    redis_port = os.getenv("REDIS_PORT", "6379")

    redis_url  = f"redis://{redis_host}:{redis_port}"

    _redis = aioredis.from_url(redis_url, encoding="utf8", decode_responses=True)

    FastAPICache.init(RedisBackend(_redis), prefix="anime_finder_cache")



    # schedule Sat 7:00 AM ET

    register_weekly_top_scheduler()


@app.on_event("shutdown")

async def shutdown_event():

    cache_backend = FastAPICache.get_backend()

    if cache_backend and hasattr(cache_backend, "redis"):

        await cache_backend.redis.close()





try:

    from tasks import start_sync, stop_sync

except Exception:

    start_sync = stop_sync = None



@app.on_event("startup")

def _startup():

    if start_sync:

        start_sync(60)



@app.on_event("shutdown")

def _shutdown():

    if stop_sync:

        stop_sync()


Base.metadata.create_all(bind=engine)

class PromptFilters(BaseModel):

    title: Optional[str] = None          # anime title / synonym

    genres: List[str] = []

    studios: List[str] = []

    season_year: Optional[int] = None

    is_adult: Optional[bool] = None



class ParsedPrompt(BaseModel):

    query: str                           # the remaining "scene intent" text

    filters: PromptFilters

    # optional: hints you can use for lightweight features

    hints: List[str] = []                # e.g. ["night", "rain", "fight"]



class SubscribeRequest(BaseModel):

    tier: str  # watcher | otaku | senpai | kami



PRICE_IDS = {

    "watcher": settings.STRIPE_PRICE_WATCHER,

    "otaku":   settings.STRIPE_PRICE_OTAKU,

    "senpai":  settings.STRIPE_PRICE_SENPAI,

    "kami":    settings.STRIPE_PRICE_KAMISAMA,

}



@app.post("/subscribe")

async def create_checkout_session(

    req: SubscribeRequest,

    db: Session = Depends(get_db),

    user: User = Depends(get_current_user),

):

    price_id = PRICE_IDS.get(req.tier)

    if price_id is None:

        raise HTTPException(status_code=400, detail="Invalid tier")



    if not user.stripe_customer_id:

        cust = stripe.Customer.create(email=user.email, metadata={"user_id": str(user.id)})

        user.stripe_customer_id = cust.id

        db.add(user)

        db.commit()



    session = stripe.checkout.Session.create(

        customer=user.stripe_customer_id,

        client_reference_id=str(user.id),

        payment_method_types=["card"],

        line_items=[{"price": price_id, "quantity": 1}],

        mode="subscription",

        success_url=f"{settings.FRONTEND_URL}/subscribe/success?session_id={{CHECKOUT_SESSION_ID}}",

        cancel_url=f"{settings.FRONTEND_URL}/subscribe/cancel",

        expand=["subscription"],

    )



    sub = session.subscription

    user.stripe_subscription_id = sub.id

    user.cancel_at_period_end   = False

    user.is_subscribed          = True

    user.subscription_expires   = datetime.utcfromtimestamp(sub.current_period_end)

    db.commit()



    return {"checkout_url": session.url}





# ---------- FastAPI endpoint ----------


def get_user_tier_info(user_id: int, db: Session):

    sql = text("""

        SELECT t.quota, t.concurrency, t.notes

          FROM users u

          JOIN tiers t ON u.anime_tier_id = t.id

         WHERE u.id = :uid

    """)


ET = ZoneInfo("America/New_York")

def is_over_quota(user_id: int, quota: int, db: Session):

    sql = text("""

        SELECT COUNT(*)::int AS cnt

          FROM logs

         WHERE user_id = :uid

           AND time >= NOW() - INTERVAL '1 day'

    """)

    cnt = db.execute(sql, {"uid": user_id}).scalar() or 0

    return cnt >= quota





logging.basicConfig(level=logging.INFO, format="%(message)s")

logger = logging.getLogger("uvicorn")



REQUEST_COUNT = Counter("app_requests_total", "Total HTTP requests", ["method", "endpoint", "http_status"])

REQUEST_LATENCY = Histogram("app_request_latency_seconds", "Latency for HTTP requests", ["method", "endpoint", "http_status"])



@app.exception_handler(HTTPException)

async def http_exception_handler(request: Request, exc: HTTPException):

    if exc.status_code in (304, 204):

        return Response(status_code=exc.status_code)

    return JSONResponse(

        status_code=exc.status_code,

        content={"error": {"code": exc.status_code, "message": exc.detail}},

    )



@app.exception_handler(Exception)

async def unhandled_exception_handler(request: Request, exc: Exception):

    tb = traceback.format_exc()

    logger.error(tb)

    return JSONResponse(status_code=500, content={"error": {"code": 500, "message": "Internal server error"}})



@app.get("/metrics")

def metrics():

    data = generate_latest()

    return Response(data, media_type=CONTENT_TYPE_LATEST)





DATABASE_CONFIG = {

    "database": {

        "host": settings.DB_HOST,

        "user": settings.DB_USER,

        "password": settings.DB_PASSWORD,

        "database": settings.DB_NAME,

    },

    "database_type": "mysql",

}

djv = Dejavu(DATABASE_CONFIG)


_scheduler: AsyncIOScheduler | None = None



def register_weekly_top_scheduler():

    """Call this once on app startup (e.g., in main.py) to schedule Saturdays 7:00 AM ET."""

    global _scheduler

    if _scheduler:

        return _scheduler

    _scheduler = AsyncIOScheduler(timezone="America/New_York")

    _scheduler.add_job(run_weekly_top_job, "cron", day_of_week="sat", hour=7, minute=0, id="weekly_top_sat_7am")

    _scheduler.start()

    print("[weekly-top] Scheduled: Saturdays 07:00 America/New_York")

    return _scheduler
    
MIN_HITS = 5

def run_weekly_top_job() -> dict:

    with SessionLocal() as db:

        top = _pick_weekly_top(db)

        if not top:

            return {"status": "no_data"}

        if top["hits"] < MIN_HITS:

            return {"status": "below_threshold", "top": top}

        out = _create_weekly_post_and_discord(db, top)

        return {"status": "ok", "top": top, **out}

MIN_HITS = 3 

def _pick_weekly_top(db: Session) -> dict | None:

    start_utc, end_utc, _ = _week_bounds_prev_sat_to_this_sat()



    acc_expr = func.coalesce(Logs.accuracy, 0.0)



    q = (

        db.query(

            Logs.anime_id.label("anime_id"),

            func.count(Logs.id).label("hits"),

            func.avg(acc_expr).label("avg_conf"),

            func.min(Logs.created_at).label("first_hit"),

        )

        .filter(Logs.anime_id.isnot(None))

        .filter(Logs.created_at >= start_utc, Logs.created_at < end_utc)

        .group_by(Logs.anime_id)

        .order_by(desc("hits"), desc("avg_conf"), "first_hit")

    )




    top = q.first()

    if not top:

        return None



    # Basic metadata from Anime (optional AniListMetadata if your row has it)

    anime = db.query(Anime).get(int(top.anime_id)) if top.anime_id is not None else None

    title = None

    cover = None

    season = None

    year = None

    try:

        # Try AniListMetadata first if present & linked by anime_id

        if hasattr(AniListMetadata, "anime_id"):

            meta = db.query(AniListMetadata).filter(AniListMetadata.anime_id == int(top.anime_id)).first()

        else:

            meta = None

    except Exception:

        meta = None



    # Title/cover fallbacks

    title = (getattr(meta, "title_romaji", None) or getattr(anime, "title_romaji", None)

             or getattr(anime, "title", None) or f"Anime #{top.anime_id}")

    cover = (getattr(meta, "cover_image", None) or getattr(anime, "cover_image", None)

             or (f"https://img.anili.st/media/{int(top.anime_id)}.jpg" if top.anime_id else None))

    season = getattr(meta, "season", None) or getattr(anime, "season", None)

    year = getattr(meta, "season_year", None) or getattr(anime, "year", None)



    return {

        "anime_id": int(top.anime_id),

        "hits": int(top.hits or 0),

        "avg_conf": float(top.avg_conf or 0.0),

        "title": title,

        "cover": cover,

        "season": season,

        "year": year,

    }

def _week_bounds_prev_sat_to_this_sat(now_et: datetime | None = None) -> tuple[datetime, datetime, datetime]:

    """Return (start_utc, end_utc, week_start_et) where window = [last Sat 00:00, this Sat 00:00)."""

    now_et = now_et or datetime.now(ET)

    # weekday: Mon=0..Sat=5 Sun=6

    days_back_to_sat = (now_et.weekday() - 5) % 7

    this_sat_0000 = (now_et - timedelta(days=days_back_to_sat)).replace(hour=0, minute=0, second=0, microsecond=0)

    last_sat_0000 = this_sat_0000 - timedelta(days=7)

    return last_sat_0000.astimezone(timezone.utc), this_sat_0000.astimezone(timezone.utc), last_sat_0000



class SceneLogEntry(BaseModel):

    status: int

    accuracy: float

    search_type: str

    search_time: int

    song_id: int | None = None

    anime_id: int | None = None



class PlaylistCreate(BaseModel):

    name: str

    theme: str

    description: str



class SongEntry(BaseModel):

    playlist_id: int

    song_name: str

    duration: float



async def validate_file_size(file: UploadFile = File(...)) -> UploadFile:

    contents = await file.read()

    if len(contents) > settings.MAX_UPLOAD_SIZE:

        raise HTTPException(status_code=413, detail="File too large")

    file.file.seek(0)

    return file



async def save_file_as_wav(upload_file: UploadFile) -> str:

    upload_dir = "uploads"

    os.makedirs(upload_dir, exist_ok=True)

    raw = os.path.join(upload_dir, upload_file.filename)

    with open(raw, "wb") as f:

        shutil.copyfileobj(upload_file.file, f)



    wav = raw.rsplit(".", 1)[0] + "_clean.wav"

    subprocess.run(

        ["ffmpeg", "-y", "-i", raw, "-ac", "1", "-ar", "22050", "-af", "loudnorm", "-c:a", "pcm_s16le", wav],

        check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL

    )



    os.remove(raw)

    return wav



# Upsert song metadata (Postgres)

def update_song_metadata(

    song_name: str,

    anime_title: str,

    artist: str,

    streaming_service: str,

    op_ed_type: Optional[str] = None,

    audio_url: Optional[str] = None,

    cover_url: Optional[str] = None,

    youtube_url: Optional[str] = None,

    spotify_url: Optional[str] = None,

    video_url: Optional[str] = None,

):

    normalized = song_name.strip().lower()

    file_sha1 = sha1(normalized.encode()).digest()



    cols = ["song_name", "anime_title", "artist", "streaming_service", "file_sha1"]

    params = [normalized, anime_title, artist, streaming_service, file_sha1]

    update_pairs = ["anime_title=EXCLUDED.anime_title",

                    "artist=EXCLUDED.artist",

                    "streaming_service=EXCLUDED.streaming_service",

                    "file_sha1=EXCLUDED.file_sha1"]



    def add(col, val):

        cols.append(col)

        params.append(val)

        update_pairs.append(f"{col}=EXCLUDED.{col}")



    for key, val in [

        ("op_ed_type", op_ed_type),

        ("audio_url", audio_url),

        ("cover_url", cover_url),

        ("youtube_url", youtube_url),

        ("spotify_url", spotify_url),

        ("video_url", video_url),

    ]:

        if val is not None:

            add(key, val)



    placeholders = ", ".join(["%s"] * len(cols))

    col_list     = ", ".join(cols)

    update_sql   = ", ".join(update_pairs)



    sql = f"""

        INSERT INTO songs ({col_list})

        VALUES ({placeholders})

        ON CONFLICT (song_name) DO UPDATE SET {update_sql}

    """



    with psycopg.connect(

        host=settings.DB_HOST,

        user=settings.DB_USER,

        password=settings.DB_PASSWORD,

        dbname=settings.DB_NAME,

    ) as conn:

        with conn.cursor() as cur:

            cur.execute(sql, params)

        conn.commit()



# Fetch song metadata by name

def fetch_song_metadata(key: str) -> dict:

    sql = """

        SELECT song_name, anime_title, artist, op_ed_type,

               audio_url, cover_url, youtube_url, spotify_url, video_url

          FROM songs

         WHERE LOWER(song_name)=LOWER(%s)

        LIMIT 1

    """

    with psycopg.connect(

        host=settings.DB_HOST,

        user=settings.DB_USER,

        password=settings.DB_PASSWORD,

        dbname=settings.DB_NAME,

        row_factory=dict_row,

    ) as conn:

        with conn.cursor() as cur:

            cur.execute(sql, (key,))

            row = cur.fetchone()

            return dict(row) if row else {}




@app.post("/playlists")

async def create_playlist(

    payload: PlaylistCreate,

    db: Session = Depends(get_db),

    current_user: User = Depends(get_current_user),

):

    playlist = Playlist(

        name=payload.name,

        theme=payload.theme,

        description=payload.description,

        user_id=current_user.id,

    )

    db.add(playlist)

    db.commit()

    db.refresh(playlist)

    return {"message": "Playlist created", "id": playlist.id}



@app.delete("/playlists/{playlist_id}", dependencies=[Depends(get_current_user)])

def delete_playlist(

    playlist_id: int = FPath(...),

    db: Session = Depends(get_db),

    current_user: User = Depends(get_current_user),

):

    playlist = db.get(Playlist, playlist_id)

    if not playlist:

        raise HTTPException(status_code=404, detail="Playlist not found")

    if playlist.user_id != current_user.id:

        raise HTTPException(status_code=403, detail="Not authorized")

    db.query(PlaylistSong).filter_by(playlist_id=playlist_id).delete()

    db.delete(playlist)

    db.commit()

    return {"message": "Playlist deleted"}



@app.post("/playlists/add", dependencies=[Depends(get_current_user)])

def add_song_to_playlist(

    entry: SongEntry,

    db: Session = Depends(get_db),

    current_user: User = Depends(get_current_user),

):

    playlist = db.get(Playlist, entry.playlist_id)

    if not playlist:

        raise HTTPException(status_code=404, detail="Playlist not found")

    if playlist.user_id != current_user.id:

        raise HTTPException(status_code=403, detail="Not authorized")

    song_entry = PlaylistSong(

        playlist_id=entry.playlist_id,

        song_name=entry.song_name,

        duration=entry.duration,

    )

    db.add(song_entry)

    db.commit()

    return {"message": "Song added to playlist"}



@app.get("/playlists/{playlist_id}/songs", dependencies=[Depends(get_current_user)])

def get_playlist_songs(

    playlist_id: int = FPath(...),

    db: Session = Depends(get_db),

    current_user: User = Depends(get_current_user),

):

    playlist = db.get(Playlist, playlist_id)

    if not playlist:

        raise HTTPException(status_code=404, detail="Playlist not found")

    if playlist.user_id != current_user.id:

        raise HTTPException(status_code=403, detail="Not authorized")



    # NOTE: assumes table name `playlist_entries`; adjust if your actual name differs.

    sql = """

        SELECT pe.id, pe.song_name, pe.duration,

               s.artist, s.streaming_service, s.audio_url, s.cover_url

          FROM playlist_entries pe

     LEFT JOIN songs s ON pe.song_name = s.song_name

         WHERE pe.playlist_id = %s

         ORDER BY pe.id ASC

    """

    with psycopg.connect(

        host=settings.DB_HOST,

        user=settings.DB_USER,

        password=settings.DB_PASSWORD,

        dbname=settings.DB_NAME,

        row_factory=dict_row,

    ) as conn:

        with conn.cursor() as cur:

            cur.execute(sql, (playlist_id,))

            rows = cur.fetchall()

            return [dict(r) for r in rows]



@app.delete("/playlists/{playlist_id}/songs/{entry_id}", dependencies=[Depends(get_current_user)])

def remove_song(

    playlist_id: int = FPath(...),

    entry_id: int = FPath(...),

    db: Session = Depends(get_db),

    current_user: User = Depends(get_current_user),

):

    playlist = db.get(Playlist, playlist_id)

    if not playlist or playlist.user_id != current_user.id:

        raise HTTPException(status_code=403, detail="Not authorized")

    entry = db.query(PlaylistSong).filter_by(id=entry_id, playlist_id=playlist_id).first()

    if not entry:

        raise HTTPException(status_code=404, detail="Entry not found")

    db.delete(entry)

    db.commit()

    return {"detail": "removed"}



@app.put("/playlists/{playlist_id}", dependencies=[Depends(get_current_user)])

def rename_playlist(

    playlist_id: int = FPath(...),

    payload: PlaylistCreate = Body(...),

    db: Session = Depends(get_db),

    current_user: User = Depends(get_current_user),

):

    playlist = db.get(Playlist, playlist_id)

    if not playlist:

        raise HTTPException(status_code=404, detail="Playlist not found")

    if playlist.user_id != current_user.id:

        raise HTTPException(status_code=403, detail="Not authorized")

    playlist.name = payload.name

    playlist.theme = payload.theme

    playlist.description = payload.description

    db.commit()

    return {"message": "Playlist renamed"}



@app.get("/playlists/themes/{theme}", dependencies=[Depends(get_current_user)])

def get_playlists_by_theme(

    theme: str,

    db: Session = Depends(get_db),

    current_user: User = Depends(get_current_user),

):

    return db.query(Playlist).filter(

        Playlist.theme == theme,

        Playlist.user_id == current_user.id

    ).all()





def require_admin(current_user: User = Depends(get_current_user)) -> User:

    if not getattr(current_user, "is_admin", False):

        raise HTTPException(status_code=403, detail="Not authorized")

    return current_user



logger = logging.getLogger(__name__)

logging.basicConfig(level=logging.INFO)



class FingerprintForm(BaseModel):

    song_name: str = Field(..., description="Fingerprint key (e.g. OP1_ReawakeR)", example="OP1_ReawakeR")

    anime_title: str = Field(..., description="Anime title sent to AniList", example="123")

    artist: str = Field(..., example="Artist Name")

    streaming_service: str = Field(..., example="Crunchyroll")

    op_ed_type: Optional[str] = Field(None, description="OP or ED", example="OP")



def compute_hashes(args):

    wav_path, start_ms, duration_ms = args

    clip = AudioSegment.from_file(wav_path)[start_ms:start_ms + duration_ms]

    clip = (clip.set_frame_rate(22050).set_channels(1).set_sample_width(2))

    tmp_fd, tmp_path = tempfile.mkstemp(suffix=".wav")

    os.close(tmp_fd)

    clip.export(tmp_path, format="wav")

    channels, *_ = read(tmp_path, limit=None)

    hashes = [(h, t) for channel in channels for h, t in fingerprint(channel)]

    os.remove(tmp_path)

    return hashes

@app.get("/admin/weekly-top/preview")

def weekly_top_preview(db: Session = Depends(get_db), current_user: User = Depends(require_admin)):

    # (Optionally restrict to admins)

    top = _pick_weekly_top(db)

    return {"top": top}



@app.post("/admin/weekly-top/run")

def weekly_top_run(
    background_tasks: BackgroundTasks,
    current_user: User = Depends(require_admin)  # <-- note this
):

    # (Optionally restrict to admins)

    return run_weekly_top_job()


@app.post("/recognize")

async def recognize_audio(

    request: Request,

    file: UploadFile = File(...),

    db: Session = Depends(get_db),

    current_user: User = Depends(get_current_user),

):

    tier = db.get(AnimeTiers, current_user.anime_tier_id)

    if not tier:

        return JSONResponse(status_code=403, content={"error": "No tier assigned"})

    quota, tier_name = tier.quota, tier.notes



    cutoff = datetime.now(timezone.utc) - timedelta(days=1)

    used = db.query(func.count(Logs.id)).filter(

    Logs.user_id == current_user.id,

    Logs.search_type == "audio",

    Logs.created_at >= cutoff).scalar() or 0



    remaining = max(0, quota - used)

    if remaining <= 0:

       return JSONResponse(

           status_code=429,

           content={

               "error": f"Quota exceeded for your tier ({tier_name}).",

               "remaining_searches": 0,

               "tier": tier_name,

        },

    )
    try:
        wav_path = await save_file_as_wav(file)
        results = djv.recognize(FileRecognizer, wav_path)

        # ---- NO MATCH ----
        if not results or "song_name" not in results:
            db.add(Logs(
                user_id=current_user.id,
                ip=request.client.host,
                api_key=current_user.api_key,
                created_at=datetime.now(timezone.utc),
                status=404,
                accuracy=None,
                search_type="audio",
                search_time=0,
                song_id=None,
                anime_id=None,
            ))
            db.commit()

            return JSONResponse(
                status_code=200,
                content={"status": "no_match", "remaining_searches": remaining - 1, "tier": tier_name}
            )

        raw_key = results["song_name"]
        song_meta = fetch_song_metadata(raw_key)

        anime_title = song_meta.get("anime_title") or raw_key.split("-", 1)[0].strip()

        media = None
        try:
            raw_data = await fetch_anime_by_title(anime_title)
            store_anime_metadata(raw_data, db)
            media = raw_data.get("data", {}).get("Media")
        except Exception:
            pass

        if media is None:
            fallback = db.query(Anime).filter(Anime.title_romaji.ilike(f"%{anime_title}%")).first()
            if fallback:
                media = {
                    "id": fallback.anilist_id if hasattr(fallback, "anilist_id") else None,  # optional
                    "title": {
                        "english": fallback.title_english,
                        "romaji":  fallback.title_romaji,
                        "native":  fallback.title_native,
                    },
                    "description": fallback.description,
                    "coverImage": {"large": fallback.cover_url},
                    "season": fallback.season,
                    "seasonYear": fallback.year,
                    "format": fallback.type,
                    "genres": fallback.genres,
                    "tags": [{"name": t} for t in fallback.tags],
                }
            else:
                return JSONResponse(
                    status_code=200,
                    content={
                        "status": "error",
                        "message": f"No metadata for '{anime_title}'",
                        "remaining_searches": remaining - 1,
                        "tier": tier_name
                    }
                )

        # ✅ compute anime_id ONLY after media is known
        anime_id = None
        try:
            anime_id = int(media.get("id")) if isinstance(media, dict) and media.get("id") else None
        except Exception:
            anime_id = None

        match = {
            "anime_title":    anime_title,
            "confidence":     results["confidence"],
            "offset":         results["offset"],
            "offset_seconds": results["offset_seconds"],
            "anime": {
                "title":        media["title"]["english"] or media["title"]["romaji"] or media["title"]["native"],
                "title_romaji": media["title"]["romaji"],
                "title_native": media["title"]["native"],
                "description":  media.get("description", ""),
                "cover_url":    media["coverImage"]["large"],
                "season":       media.get("season"),
                "year":         media.get("seasonYear"),
                "type":         media.get("format"),
                "genres":       media.get("genres", []),
                "tags":         [t["name"] for t in media.get("tags", [])],
            },
            "song_name":    song_meta.get("song_name"),
            "artist":       song_meta.get("artist"),
            "op_ed_type":   song_meta.get("op_ed_type"),
            "preview_url":  song_meta.get("preview_url"),
            "youtube_url":  song_meta.get("youtube_url"),
            "spotify_url":  song_meta.get("spotify_url"),
            "video_url":    song_meta.get("video_url"),
        }

        # ✅ log success with anime_id populated
        db.add(Logs(
            user_id=current_user.id,
            ip=request.client.host,
            api_key=current_user.api_key,
            created_at=datetime.now(timezone.utc),
            status=200,
            accuracy=results.get("confidence"),
            search_type="audio",
            search_time=int(results.get("offset_seconds", 0) * 1000),
            song_id=results.get("song_id"),
            anime_id=anime_id,
        ))
        db.commit()

        return JSONResponse(
            status_code=200,
            content={"status": "match", "result": match, "remaining_searches": remaining - 1, "tier": tier_name}
        )


    except Exception:

        tb = traceback.format_exc()

        logger.error("Exception in /recognize:\n" + tb)

        db.add(Logs(

            ip=request.client.host,

            api_key=current_user.api_key,

            time=datetime.utcnow(),

            status=500,

            accuracy=None,

            search_type="audio",

            search_time=0,

            song_id=None,

            anime_id=None,

        ))

        db.commit()

        return JSONResponse(

            status_code=500,

            content={"error": "internal error", "tier": tier_name, "remaining_searches": remaining}

        )



@app.delete("/cancel-subscription")

def cancel_subscription(

    db: Session = Depends(get_db),

    current_user: User = Depends(get_current_user),

):

    sub_id = current_user.stripe_subscription_id

    if not sub_id:

        raise HTTPException(status_code=400, detail="No active subscription to cancel")



    try:

        stripe.Subscription.modify(sub_id, cancel_at_period_end=True)

    except stripe.error.StripeError as e:

        raise HTTPException(status_code=502, detail=f"Stripe error: {e.user_message or str(e)}")



    current_user.cancel_at_period_end = True

    db.add(current_user)

    db.commit()

    return {"detail": "Subscription will cancel at period end"}



#Reset-token cleanup on startup 

@app.on_event("startup")

def cleanup_on_startup():

    db = SessionLocal()

    try:

        prune_reset_tokens(db)

    except ProgrammingError:

        print("Skipping reset-token cleanup; table not found.")

    finally:

        db.close()



#  Main 

if __name__ == "__main__":

    import uvicorn

    uvicorn.run(

        "server:app",

        host=settings.APP_HOST,

        port=settings.APP_PORT,

        workers=4

    )

