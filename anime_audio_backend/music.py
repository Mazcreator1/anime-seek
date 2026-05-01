# app/music.py
from fastapi import APIRouter, HTTPException, Query, Depends
import httpx
from pydantic import BaseModel
from typing import List, Optional, Any
from datetime import datetime
from sqlalchemy.orm import Session

# ——— adjust these imports to your project ———
try:
    from database import get_db
    from auth_utils import get_current_user
except Exception:  # pragma: no cover
    from database import get_db  # type: ignore
    from auth_utils import get_current_user  # type: ignore
try:
    from models import User
except Exception:  # pragma: no cover
    from models import User  # type: ignore
# ——————————————————————————————————————————————

ITUNES_SEARCH = "https://itunes.apple.com/search"
ITUNES_LOOKUP = "https://itunes.apple.com/lookup"

router = APIRouter(prefix="/music", tags=["music"])

# ---------- Pydantic v1/v2 compatibility helpers ----------
def _dump_json(model: BaseModel) -> str:
    """Return JSON string for a Pydantic model across v1/v2."""
    try:
        return model.model_dump_json()  # pydantic v2
    except AttributeError:
        return model.json()             # pydantic v1

def _as_obj(model: BaseModel) -> dict:
    """Return dict for a Pydantic model across v1/v2."""
    try:
        return model.model_dump()  # pydantic v2
    except AttributeError:
        return model.dict()        # pydantic v1

def _validate_json(cls, s: str):
    """Parse JSON string into a Pydantic model across v1/v2."""
    try:
        return cls.model_validate_json(s)  # pydantic v2
    except AttributeError:
        return cls.parse_raw(s)            # pydantic v1

def _validate_obj(cls, obj: Any):
    """Parse a Python object (dict) into a Pydantic model across v1/v2."""
    try:
        return cls.model_validate(obj)  # pydantic v2
    except AttributeError:
        return cls.parse_obj(obj)       # pydantic v1
# ----------------------------------------------------------

class Track(BaseModel):
    id: str
    title: str
    artist: str
    album: Optional[str]
    preview_url: Optional[str]
    artwork_url: Optional[str]
    duration_ms: Optional[int]
    external_url: Optional[str]
    platform: str = "itunes"

def _map_track(it) -> Track:
    return Track(
        id=str(it.get("trackId") or it.get("collectionId")),
        title=it.get("trackName") or it.get("collectionName"),
        artist=it.get("artistName"),
        album=it.get("collectionName"),
        preview_url=it.get("previewUrl"),
        artwork_url=it.get("artworkUrl100") or it.get("artworkUrl60"),
        duration_ms=it.get("trackTimeMillis"),
        external_url=it.get("trackViewUrl") or it.get("collectionViewUrl"),
    )

@router.get("/search", response_model=List[Track])
async def search_tracks(
    q: str = Query(..., min_length=1),
    limit: int = Query(20, ge=1, le=50),
    country: str = Query("US", min_length=2, max_length=2),
):
    params = {"term": q, "entity": "musicTrack", "limit": limit, "country": country}
    async with httpx.AsyncClient(timeout=10) as client:
        r = await client.get(ITUNES_SEARCH, params=params)
    if r.status_code != 200:
        raise HTTPException(r.status_code, r.text)
    results = r.json().get("results", [])
    return [_map_track(it) for it in results]

@router.get("/lookup", response_model=Optional[Track])
async def lookup_track(
    id: str,
    country: str = Query("US", min_length=2, max_length=2),
):
    params = {"id": id, "entity": "song", "country": country}
    async with httpx.AsyncClient(timeout=10) as client:
        r = await client.get(ITUNES_LOOKUP, params=params)
    if r.status_code != 200:
        raise HTTPException(r.status_code, r.text)
    results = r.json().get("results", [])
    if not results:
        return None
    return _map_track(results[0])

# ---------- persist & expose pinned tracks ----------

class PinIn(BaseModel):
    track_id: str
    country: str = "US"

@router.post("/pin")
async def pin_track(
    payload: PinIn,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    # fetch canonical metadata from iTunes
    params = {"id": payload.track_id, "entity": "song", "country": payload.country}
    async with httpx.AsyncClient(timeout=10) as client:
        r = await client.get(ITUNES_LOOKUP, params=params)
    if r.status_code != 200:
        raise HTTPException(r.status_code, r.text)
    results = r.json().get("results", [])
    if not results:
        raise HTTPException(404, "Track not found")

    track = _map_track(results[0])

    # Store as a Python dict so it fits a Postgres JSON/JSONB column cleanly
    user.profile_song_json = _as_obj(track)

    # Optionally set a timestamp if your model defines this column
    if hasattr(User, "profile_song_set_at"):
        try:
            setattr(user, "profile_song_set_at", datetime.utcnow())
        except Exception:
            # Column not present at runtime or other edge-case — ignore silently
            pass

    db.add(user)
    db.commit()
    db.refresh(user)

    return {"ok": True, "profile_song": track}

@router.get("/me", response_model=Optional[Track])
async def my_pinned_track(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    v = user.profile_song_json
    if not v:
        return None
    try:
        # Support both historical stringified JSON and new dict storage
        if isinstance(v, str):
            return _validate_json(Track, v)
        return _validate_obj(Track, v)
    except Exception:
        return None

@router.delete("/me")
async def clear_my_pinned_track(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    user.profile_song_json = None
    if hasattr(User, "profile_song_set_at"):
        try:
            setattr(user, "profile_song_set_at", None)
        except Exception:
            pass
    db.add(user)
    db.commit()
    return {"ok": True}

@router.get("/user/{user_id}", response_model=Optional[Track])
async def pinned_track_for_user(
    user_id: int,
    db: Session = Depends(get_db),
):
    u = db.get(User, user_id)
    if not u:
        raise HTTPException(404, "User not found")
    v = u.profile_song_json
    if not v:
        return None
    try:
        if isinstance(v, str):
            return _validate_json(Track, v)
        return _validate_obj(Track, v)
    except Exception:
        return None
