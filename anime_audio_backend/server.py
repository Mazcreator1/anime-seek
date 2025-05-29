# server.py
import os
import shutil
import tempfile
import traceback
import logging
from hashlib import sha1
from typing import Optional, List
from fastapi import (
    FastAPI, Request, UploadFile, File, Form,
    HTTPException, Depends, status, Body, Query, Path
)
from fastapi.responses import JSONResponse, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
import redis
import aiohttp
import cv2
from dejavu.recognize import FileRecognizer
from dejavu import Dejavu
from pydub import AudioSegment
from database import get_db
from models import Playlist, PlaylistSong, Anime
from anilist_client import fetch_anime_by_title
from metadata_service import store_anime_metadata
from auth import router as auth_router
import stripe
import time
from models import User
from sqlalchemy.orm import Session
from fastapi import Header, Request
from payments.webhook import router as webhook_router
from pydantic import BaseSettings, BaseModel
from prometheus_client import Histogram
from fastapi import APIRouter, Depends, HTTPException, status, Body
from fastapi.security import OAuth2PasswordRequestForm, OAuth2PasswordBearer
from datetime import datetime, timedelta
from jose import JWTError, jwt
from security import hash_password, verify_password, create_token
from config import settings
import pymysql
from passlib.context import CryptContext
from auth import get_current_user
from fastapi.staticfiles import StaticFiles
from config import settings
from pathlib import Path as FSPath

# ─── App & Middleware ──────────────────────────────────────────────────────────
REQUEST_LATENCY = Histogram(
    "http_request_latency_seconds",
    "HTTP request latency in seconds",
    ["method", "endpoint", "http_status"]
)

# 1) Define the function
async def metrics_middleware(request: Request, call_next):
    start = time.time()
    response = await call_next(request)
    elapsed = time.time() - start
    REQUEST_LATENCY.labels(
        request.method,
        request.url.path,
        response.status_code
    ).observe(elapsed)
    return response

app = FastAPI()
app.include_router(auth_router)
app.include_router(webhook_router)
app.middleware("http")(metrics_middleware)
SECRET_KEY = settings.SECRET_KEY

stripe.api_key = settings.STRIPE_API_KEY

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.mount("/static", StaticFiles(directory=settings.STATIC_DIR), name="static")

# ─── Configuration ────────────────────────────────────────────────────────────

@app.post("/payments/create-checkout-session", dependencies=[Depends(get_current_user)])
def create_checkout_session(
        current_user: User = Depends(get_current_user),
        db: Session = Depends(get_db),
):
    # 1) Ensure Stripe Customer exists
    if not current_user.stripe_customer_id:
        customer = stripe.Customer.create(email=current_user.email)
        current_user.stripe_customer_id = customer.id
        db.commit()
    else:
        customer = stripe.Customer.retrieve(current_user.stripe_customer_id)

    # 2) Build the session
    session = stripe.checkout.Session.create(
        customer=customer.id,
        payment_method_types=["card"],
        mode="subscription",
        line_items=[{"price": settings.STRIPE_PRICE_ID, "quantity": 1}],
        success_url="https://anime-seek.com/subscription/success?session_id={CHECKOUT_SESSION_ID}",
        cancel_url="https://anime-seek.com/subscription/cancel",
    )
    return {"url": session.url}

pwd_ctx = CryptContext(schemes=["bcrypt"], deprecated="auto")

#____________________STATIC FOLDER_____________
# Calculate absolute path to your static dir:
static_path = FSPath(__file__).parent / settings.STATIC_DIR
static_path.mkdir(exist_ok=True)
app.mount("/static", StaticFiles(directory=str(static_path)), name="static")

# ─── Logging & Metrics ────────────────────────────────────────────────────────
logging.basicConfig(level=logging.INFO, format="%(message)s")
logger = logging.getLogger("uvicorn")

REQUEST_COUNT = Counter(
    "app_requests_total", "Total HTTP requests", ["method", "endpoint", "http_status"]
)


@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    return JSONResponse(
        status_code=exc.status_code,
        content={"error": {"code": exc.status_code, "message": exc.detail}},
    )

@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    tb = traceback.format_exc()
    logger.error(tb)
    return JSONResponse(
        status_code=500,
        content={"error": {"code": 500, "message": "Internal server error"}},
    )

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

BASE_DIR = os.getcwd()
UPLOAD_DIR = os.path.join(BASE_DIR, "uploads")
COVER_DIR = os.path.join(BASE_DIR, "assets", "Album_Cover")
os.makedirs(UPLOAD_DIR, exist_ok=True)
os.makedirs(COVER_DIR, exist_ok=True)
app.mount("/audio", StaticFiles(directory=UPLOAD_DIR), name="audio")
app.mount("/covers", StaticFiles(directory=COVER_DIR), name="covers")

@app.get("/metrics")
def metrics():
    data = generate_latest()
    return Response(data, media_type=CONTENT_TYPE_LATEST)
# ─── Dejavu, Schemas & Helpers ────────────────────────────────────────────────
# Dejavu config
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

# Pydantic schemas
class PlaylistCreate(BaseModel):
    name: str
    theme: str
    description: str

class SongEntry(BaseModel):
    playlist_id: int
    song_name: str
    duration: float

# Validate upload size
async def validate_file_size(file: UploadFile = File(...)) -> UploadFile:
    contents = await file.read()
    if len(contents) > settings.MAX_UPLOAD_SIZE:
        raise HTTPException(status_code=413, detail="File too large")
    file.file.seek(0)
    return file

# Convert any upload to WAV
async def save_file_as_wav(upload_file: UploadFile) -> str:
    raw_path = os.path.join(UPLOAD_DIR, upload_file.filename)
    with open(raw_path, "wb") as f:
        shutil.copyfileobj(upload_file.file, f)
    if raw_path.lower().endswith(".wav"):
        return raw_path
    wav_path = raw_path.rsplit(".", 1)[0] + "_clean.wav"
    audio = AudioSegment.from_file(raw_path).set_frame_rate(44100).set_channels(1).set_sample_width(2)
    audio.export(wav_path, format="wav")
    os.remove(raw_path)
    return wav_path

# Upsert song metadata
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
    conn = pymysql.connect(
        host=settings.DB_HOST,
        user=settings.DB_USER,
        password=settings.DB_PASSWORD,
        database=settings.DB_NAME,
        cursorclass=pymysql.cursors.DictCursor,
    )
    try:
        cursor = conn.cursor()
        cols = ["song_name", "anime_title", "artist", "streaming_service", "file_sha1"]
        vals = ["%s", "%s", "%s", "%s", "%s"]
        params = [normalized, anime_title, artist, streaming_service, file_sha1]
        updates = [
            "anime_title=VALUES(anime_title)",
            "artist=VALUES(artist)",
            "streaming_service=VALUES(streaming_service)",
            "file_sha1=VALUES(file_sha1)",
        ]
        def add(col, val):
            cols.append(col); vals.append("%s"); params.append(val)
            updates.append(f"{col}=VALUES({col})")
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
        sql = f"""
            INSERT INTO songs ({','.join(cols)})
            VALUES ({','.join(vals)})
            ON DUPLICATE KEY UPDATE {','.join(updates)}
        """
        cursor.execute(sql, params)
        conn.commit()
    finally:
        conn.close()

# Fetch song metadata by name
def fetch_song_metadata(key: str) -> dict:
    conn = pymysql.connect(
        host=settings.DB_HOST,
        user=settings.DB_USER,
        password=settings.DB_PASSWORD,
        database=settings.DB_NAME,
        cursorclass=pymysql.cursors.DictCursor,
    )
    try:
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT song_name, anime_title, artist, op_ed_type,
                   audio_url, cover_url, youtube_url, spotify_url, video_url
              FROM songs
             WHERE LOWER(song_name)=LOWER(%s)
            """,
            (key,),
        )
        return cursor.fetchone() or {}
    finally:
        conn.close()

# Rate limiter using Redis
redis_client = redis.Redis(host=settings.REDIS_HOST, port=settings.REDIS_PORT, decode_responses=True)
def rate_limiter():
    async def limiter(
            request: Request,
            current_user: User = Depends(get_current_user),
            db: Session = Depends(get_db),
    ):
        # 1) Expire subscription if past its due date
        now = datetime.utcnow()
        if current_user.subscription_expires and current_user.subscription_expires < now:
            current_user.is_subscribed = False
            current_user.subscription_expires = None
            db.commit()

        # 2) Subscribed users get unlimited access
        if current_user.is_subscribed:
            return

        # 3) Only throttle these endpoints (free tier)
        limited_paths = {"/recognize", "/search"}  # covers both image-search and song-search
        if request.url.path not in limited_paths:
            return

        # 4) Rate-limit key per user
        key = f"rl:{current_user.id}"
        count = redis_client.incr(key)
        if count == 1:
            # first hit in this window → set TTL
            redis_client.expire(key, settings.RATE_LIMIT_WINDOW)

        if count > settings.RATE_LIMIT_COUNT:
            # 5+ hits in window → block
            raise HTTPException(
                status_code=429,
                detail=(
                    f"Rate limit exceeded "
                    f"({settings.RATE_LIMIT_COUNT} per {settings.RATE_LIMIT_WINDOW//60} min). "
                    "Subscribe for unlimited access."
                ),
            )

    return Depends(limiter)

# ─── Secured Playlist Endpoints ────────────────────────────────────────────────
@app.post("/playlists", dependencies=[Depends(get_current_user)])
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
    return {"message": "Playlist created", "id": playlist.id}

@app.delete("/playlists/{playlist_id}", dependencies=[Depends(get_current_user)])
def delete_playlist(
        playlist_id: int = Path(...),
        db: Session = Depends(get_db),
        current_user: User = Depends(get_current_user),
):
    playlist = db.query(Playlist).get(playlist_id)
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
    playlist = db.query(Playlist).get(entry.playlist_id)
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
        playlist_id: int = Path(...),
        db: Session = Depends(get_db),
        current_user: User = Depends(get_current_user),
):
    playlist = db.query(Playlist).get(playlist_id)
    if not playlist:
        raise HTTPException(status_code=404, detail="Playlist not found")
    if playlist.user_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not authorized")
    conn = pymysql.connect(
        host=settings.DB_HOST,
        user=settings.DB_USER,
        password=settings.DB_PASSWORD,
        database=settings.DB_NAME,
        cursorclass=pymysql.cursors.DictCursor,
    )
    try:
        cursor = conn.cursor()
        cursor.execute("""
            SELECT pe.id, pe.song_name, pe.duration,
                   s.artist, s.streaming_service, s.audio_url, s.cover_url
              FROM playlist_entries pe
         LEFT JOIN songs s ON pe.song_name = s.song_name
             WHERE pe.playlist_id = %s
        """, (playlist_id,))
        return cursor.fetchall()
    finally:
        conn.close()

@app.delete("/playlists/{playlist_id}/songs/{entry_id}", dependencies=[Depends(get_current_user)])
def remove_song(
        playlist_id: int = Path(...),
        entry_id: int = Path(...),
        db: Session = Depends(get_db),
        current_user: User = Depends(get_current_user),
):
    playlist = db.query(Playlist).get(playlist_id)
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
        playlist_id: int = Path(...),
        payload: PlaylistCreate = Body(...),
        db: Session = Depends(get_db),
        current_user: User = Depends(get_current_user),
):
    playlist = db.query(Playlist).get(playlist_id)
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
# ─── Recognize, Search, Fingerprint & Health ─────────────────────────────────
@app.post("/recognize", dependencies=[rate_limiter(), Depends(validate_file_size)])
async def recognize_audio(
        file: UploadFile = File(...),
        db: Session = Depends(get_db),
):
    logger.info("👉 /recognize fired")
    try:
        wav_path = await save_file_as_wav(file)
        recognizer = FileRecognizer(djv)
        results = recognizer.recognize_file(wav_path)
        raw_key = results["metadata"]["filename"]
        song_meta = fetch_song_metadata(raw_key)
        match = max(results["results"], key=lambda r: r["confidence"])
        anime_title = song_meta.get("anime_title") or raw_key.split("-", 1)[0].strip()
        media = None
        try:
            raw_data = await fetch_anime_by_title(anime_title)
            store_anime_metadata(raw_data, db)
            media = raw_data["data"]["Media"]
        except Exception as e:
            logger.warning(f"AniList lookup failed: {e}")
        if media is None:
            media_obj = db.query(Anime).filter(
                Anime.title_romaji.ilike(f"%{anime_title}%")
            ).first()
            if not media_obj:
                return {"status": "error", "message": f"No metadata for '{anime_title}'"}
            media = {
                "title": {
                    "english": media_obj.title_english,
                    "romaji": media_obj.title_romaji,
                    "native": media_obj.title_native,
                },
                "description": media_obj.description,
                "coverImage": {"large": media_obj.cover_url},
                "season": media_obj.season,
                "seasonYear": media_obj.year,
                "format": media_obj.type,
                "genres": media_obj.genres,
                "tags": [{"name": t} for t in media_obj.tags],
            }
        match_meta = fetch_song_metadata(match["metadata"]["filename"])
        result = {
            "anime": {
                "title": media["title"],
                "description": media.get("description"),
                "cover_url": media["coverImage"]["large"],
                "season": media.get("season"),
                "year": media.get("seasonYear"),
                "type": media.get("format"),
                "genres": media.get("genres", []),
                "tags": [t["name"] for t in media.get("tags", [])],
            },
            "song_name":    match_meta.get("song_name"),
            "artist":       match_meta.get("artist"),
            "op_ed_type":   match_meta.get("op_ed_type"),
            "preview_url":  match_meta.get("preview_url"),
            "youtube_url":  match_meta.get("youtube_url"),
            "spotify_url":  match_meta.get("spotify_url"),
            "video_url":    match_meta.get("video_url"),
        }
        logger.info(f"👉 returning match payload: {result!r}")
        return {"status": "match", "result": result}
    except Exception:
        tb = traceback.format_exc()
        logger.error(tb)
        return JSONResponse(status_code=500, content={"error": "internal error"})

@app.post("/search",dependencies=[Depends(get_current_user), rate_limiter()])
async def search_image(
        image: UploadFile = File(...),
        anilistInfo: bool = Query(False),
        cutBorders: bool = Query(False),
):
    with tempfile.NamedTemporaryFile(delete=False, suffix=".jpg") as tmp:
        temp_path = tmp.name
        with open(temp_path, "wb") as f:
            shutil.copyfileobj(image.file, f)

    img = cv2.imread(temp_path)
    if img is None:
        os.remove(temp_path)
        raise HTTPException(status_code=400, detail="Invalid image")

    if cutBorders:
        h, w, _ = img.shape
        crop = img[int(h * 0.1):int(h * 0.9), int(w * 0.1):int(w * 0.9)]
        cv2.imwrite(temp_path, crop)

    with open(temp_path, "rb") as f:
        img_bytes = f.read()

    params = {
        "field": "cl_ha",
        "accuracy": "0.02",
        "candidates": "1000000",
        "rows": "30",
        "ms": "false",
    }
    headers = {"Content-Type": "image/jpeg"}
    async with aiohttp.ClientSession() as session:
        async with session.post(settings.SOLR_URL, params=params, data=img_bytes, headers=headers) as resp:
            if resp.status != 200:
                os.remove(temp_path)
                raise HTTPException(status_code=503, detail="Solr query failed")
            solr_result = await resp.json()

    docs = solr_result.get("response", {}).get("docs", [])
    frame_count = solr_result.get("RawDocsCount", 0)

    if not docs:
        os.remove(temp_path)
        return {"frameCount": frame_count, "result": []}

    results = []
    ids_seen = set()
    for doc in docs:
        id_parts = doc["id"].split("/")
        if len(id_parts) < 3:
            continue
        anilist_id = id_parts[0]
        if anilist_id in ids_seen:
            continue
        ids_seen.add(anilist_id)
        results.append({
            "anilist":    anilist_id,
            "filename":   id_parts[1],
            "timestamp":  id_parts[2],
            "score":      doc.get("score"),
        })

    if anilistInfo and results:
        media_ids = [int(r["anilist"]) for r in results]
        query = {
            "query": f"""
                {{ Page(page:1, perPage:{len(media_ids)}) {{
                    media(id_in:{media_ids}) {{
                        id title {{ english romaji native }} coverImage {{ large }}
                    }}
                }} }}
            """
        }
        async with aiohttp.ClientSession() as session:
            async with session.post(settings.ANILIST_API, json=query) as resp:
                if resp.status == 200:
                    data = await resp.json()
                    meta_map = {m["id"]: m for m in data["data"]["Page"]["media"]}
                    for r in results:
                        mid = int(r["anilist"])
                        if mid in meta_map:
                            r["meta"] = meta_map[mid]

    os.remove(temp_path)
    return {"frameCount": frame_count, "result": results}

@app.get("/search", dependencies=[Depends(get_current_user)])
def search_songs(q: str):
    conn = pymysql.connect(
        host=settings.DB_HOST,
        user=settings.DB_USER,
        password=settings.DB_PASSWORD,
        database=settings.DB_NAME,
        cursorclass=pymysql.cursors.DictCursor
    )
    try:
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT song_name, artist, streaming_service, duration, audio_url, cover_url
              FROM songs
             WHERE LOWER(song_name) LIKE %s OR LOWER(artist) LIKE %s
            """,
            (f"%{q.lower()}%", f"%{q.lower()}%")
        )
        return cursor.fetchall()
    finally:
        conn.close()

@app.post("/fingerprint", summary="Register a new fingerprinted song", dependencies=[Depends(get_current_user)])
async def fingerprint_audio(
        file: UploadFile = File(...),
        song_name: str = Form(...),
        anime_title: str = Form(...),
        artist: str = Form(...),
        streaming_service: str = Form(...),
        op_ed_type: Optional[str] = Form(None),
        youtube_url: Optional[str] = Form(None),
        spotify_url: Optional[str] = Form(None),
        video_url: Optional[str] = Form(None),
):
    try:
        await validate_file_size(file)
        path = await save_file_as_wav(file)
        djv.fingerprint_file(path, song_name=song_name)
        filename = os.path.basename(path)
        audio_url = f"http://{settings.APP_HOST}:{settings.APP_PORT}/audio/{filename}"
        update_song_metadata(
            song_name,
            anime_title,
            artist,
            streaming_service,
            op_ed_type,
            audio_url,
            None,
            youtube_url,
            spotify_url,
            video_url
        )
        return {"status": "success"}
    except Exception as e:
        logger.error(traceback.format_exc())
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/healthz")
def healthz():
    return {"status": "alive"}

@app.get("/readyz")
def readyz():
    try:
        with get_db() as session:
            session.execute("SELECT 1")
        redis_client.ping()
        return {"status": "ready"}
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Not ready: {e}")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "server:app",
        host=settings.APP_HOST,
        port=settings.APP_PORT,
        workers=4
    )
