## userendpoints.py
from __future__ import annotations
import os
from sqlalchemy import text as sql_text
import shutil
from pydantic import (

    BaseModel,

    Field,

    EmailStr,

    validator,

    root_validator,

    conlist,

)
import uuid
from models import Poll
import json
from pydantic import BaseModel, ConfigDict
import time
import re, requests
import subprocess
import requests
from sqlalchemy import and_, tuple_
from sqlalchemy.orm import selectinload
from datetime import datetime, timedelta, date, timezone
from typing import List, Optional, Dict, Iterable, Literal, Union
import logging, json as _json 
logging.basicConfig(level=logging.INFO)
from fastapi import (

    APIRouter, Depends, HTTPException, Query,

    Form, File, UploadFile, Request, Response, Body, status

)
from typing import Optional, Any, Dict, List, Tuple
import os
from sqlalchemy import desc, func, cast, String
from sqlalchemy.sql import literal_column
import uuid
import shutil
import time
from typing import Optional
from apscheduler.schedulers.asyncio import AsyncIOScheduler
import pytz
import httpx
from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy.orm import Session
from fastapi import BackgroundTasks
from sqlalchemy import select, func, or_
from PIL import Image
from sqlalchemy import desc, func, select, Index, text, bindparam
from sqlalchemy.orm import Session, joinedload
from pydantic_settings import BaseSettings
from pydantic import EmailStr, Field, validator
from sqlalchemy.exc import IntegrityError
from database import Base, SessionLocal, engine, get_db
from auth_utils import get_current_user
from models import (

    User, Follow, Logs, Notification, PostLike, UserLike, Post, Comment, Reply,

    Anime, Song, Playlist, AniListMetadata, PostReshare

)
from typing import Annotated

from pydantic import Field
from models import AniListMetadata as AniListMetadataORM
import re
from datetime import timezone
log = logging.getLogger(__name__)
# 

#  Upload dirs

# 



BASE_DIR = os.path.dirname(os.path.abspath(__file__))   # /app

UPLOAD_ROOT = os.path.join(BASE_DIR, "uploads")

AVATAR_DIR = os.path.join(UPLOAD_ROOT, "user_avatars")

FAVORITES_DIR = os.path.join(UPLOAD_ROOT, "favorites")



os.makedirs(AVATAR_DIR, exist_ok=True)

os.makedirs(FAVORITES_DIR, exist_ok=True)



# Use explicit table columns for the index (Postgres-safe)

Index(

    "ix_logs_user_anime_time",

    Logs.__table__.c.api_key,

    Logs.__table__.c.anime_id,

    Logs.__table__.c.created_at.desc(),

    Logs.__table__.c.search_type,

)



UPLOAD_DIR = UPLOAD_ROOT



class Ok(BaseModel):

    ok: bool = True

    id: int | None = None

    soft_deleted: bool | None = None



def _can_delete(requester_id: int, comment_owner_id: int | None, post_owner_id: int | None, is_admin: bool) -> bool:

    return bool(is_admin) or requester_id == comment_owner_id or requester_id == post_owner_id



def _log_auth_decision(action: str, requester_id: int, item_kind: str, item_owner_id: int | None,

                       post_owner_id: int | None, is_admin: bool, allowed: bool) -> None:

    try:

        print(f"[auth] {action}: kind={item_kind} req={requester_id} item_owner={item_owner_id} "

              f"post_owner={post_owner_id} admin={is_admin} -> allowed={allowed}")

    except Exception:

        pass


class ReshareResponse(BaseModel):

    reshared: bool

    reshare_count: int


class RecentItem(BaseModel):

    log_id: int

    ts: datetime

    type: Literal["audio", "scene"]

    songs_id: Optional[int] = None

    anime_id: Optional[int] = None

    accuracy: Optional[float] = None

    # extra fields the Flutter UI reads

    song_name: Optional[str] = None

    artist: Optional[str] = None

    anime_title: Optional[str] = None

    image_url: Optional[str] = None

    episode: Optional[str] = None



class RecentResp(BaseModel):

    version: int

    items: List[RecentItem]



def _httpdate(dt: datetime) -> str:

    return dt.astimezone(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S GMT")



class LikeResponse(BaseModel):

    liked: bool

    like_count: int



class ActivityEntry(BaseModel):

    id: int

    search_type: Optional[str] = 'unknown'

    anime_id: Optional[int] = 0

    song_id: Optional[int] = None

    accuracy: Optional[float] = None

    code: Optional[int] = None

    status: Optional[int] = None



    ip: str = ''                  # ensure string

    time: datetime                # REQUIRED by frontend

    created_at: Optional[datetime] = None  # passthrough if present



    @validator('ip', pre=True, always=True)

    def _ip_to_str(cls, v):

        return '' if v is None else str(v)



    @root_validator(pre=True)

    def _fill_time(cls, values):

        # allow DB rows to lack 'time' and derive it from created_at/created

        if not values.get('time'):

            values['time'] = values.get('created_at') or values.get('created')

        return values




class Config:

    orm_mode = True




class VoteBody(BaseModel):

    option_ids: list[int] = []

    option_idxs: list[int] = []
    

def _parse_iso_dt_z(s: str | None) -> datetime | None:

    if not s:

        return None

    s = s.strip()

    if not s:

        return None

    # accept trailing Z

    if s.endswith("Z"):

        s = s[:-1] + "+00:00"

    try:

        dt = datetime.fromisoformat(s)

        if dt.tzinfo is None:

            dt = dt.replace(tzinfo=timezone.utc)

        return dt

    except Exception:

        return None


class CommentOut(BaseModel):

    id: int

    post_id: int

    user_id: int

    content: str

    created_at: datetime

    user: dict



    class Config:

        orm_mode = True



class CommentIn(BaseModel):

    content: str



class UserProfileOut(BaseModel):

    id: int

    display_name: str

    avatar_url: Optional[str] = None

    top_line: Optional[str] = None

    bio: Optional[str] = None

    is_private: bool

    follower_count: int

    following_count: int

    like_count: int

    matches: int

    created_at: datetime



    class Config:

        orm_mode = True



class CommentCreate(BaseModel):

    content: str = Field(min_length=1, max_length=10_000)



class CommentUpdate(BaseModel):

    content: str = Field(min_length=1, max_length=10_000)



class ReplyUpdate(BaseModel):

    content: str = Field(min_length=1, max_length=10_000)






class PostCountsIn(BaseModel):

    ids: List[int] = Field(default_factory=list)




# ---- Helpers ----

_HEX_RE = re.compile(r"^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$")

def _load_comment_item(db: Session, item_id: int):

    """

    Try to resolve the given id as a Comment first, then as a Reply.

    Returns a tuple: ("comment", Comment, Post) or ("reply", Reply, Post) or (None, None, None)

    """

    c = db.get(Comment, item_id)

    if c:

        post = db.get(Post, c.post_id) if c.post_id else None

        return "comment", c, post

    r = db.get(Reply, item_id)

    if r:

        # need the parent comment to derive the post

        parent = db.get(Comment, r.comment_id) if r.comment_id else None

        post = db.get(Post, parent.post_id) if parent and parent.post_id else None

        return "reply", r, post

    return None, None, None
    
def _post_of_comment(db: Session, comment_id: int) -> Post | None:

    c = db.get(Comment, comment_id)

    return db.get(Post, c.post_id) if c else None

def _dbg(tag: str, obj):

    """Safe, trimmed JSON-ish logger to help trace poll lifecycles."""

    try:

        logging.info("%s: %s", tag, _json.dumps(obj, default=str)[:4000])

    except Exception:

        logging.info("%s: %r", tag, obj)

def _post_of_reply(db: Session, reply_id: int) -> Post | None:

    r = db.get(Reply, reply_id)

    if not r: return None

    c = db.get(Comment, r.comment_id)

    return db.get(Post, c.post_id) if c and c.post_id else None
    
def _no_store(resp: Response | None):

    if resp is None:

        return

    resp.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0, private"

    resp.headers["Pragma"] = "no-cache"

    resp.headers["Expires"] = "0"

    resp.headers["Vary"] = "Authorization" 
       
def hex_to_int(h: str | None, default=0x10B981) -> int:

    if not h: return default

    h = h.strip()

    if not h.startswith("#"): h = "#" + h

    return int(h[1:], 16)
    
def _normalize_hex_color(s: str | None) -> str | None:

    if not s:

        return None

    s = s.strip()

    if _HEX_RE.match(s):

        # uppercase for consistency

        return "#" + s[1:].upper()

    return None



def _is_premium(u: User) -> bool:

    tier_ok = (getattr(u, "anime_tier_id", 0) or 0) >= 1

    sub_ok = bool(getattr(u, "is_subscribed", False))

    # If you want to also enforce expiry:

    exp = getattr(u, "subscription_expires", None)

    if sub_ok and exp and isinstance(exp, datetime):

        sub_ok = exp.replace(tzinfo=timezone.utc) > datetime.now(timezone.utc)

    return tier_ok or sub_ok

async def _clear_comment_caches():

    try:

        await FastAPICache.clear(namespace="comments")

    except Exception:

        pass

    try:

        await FastAPICache.clear(namespace="replies")

    except Exception:

        pass
        
def _abs_avatar(u: str | None) -> str | None:

    if not u:

        return u

    u = u.strip()

    if not u:

        return None

    return f"https://anime-seek.com{u}" if u.startswith("/uploads") else u
    
def _iso(dt):

    if not dt:

        return datetime.now(timezone.utc).isoformat()

    if dt.tzinfo is None:

        dt = dt.replace(tzinfo=timezone.utc)

    return dt.isoformat()

# Map /uploads/<file> â filesystem path

def _public_to_fs(public_url: Optional[str]) -> Optional[str]:

    if not public_url or not public_url.startswith("/uploads/"):

        return None

    return os.path.join(UPLOAD_DIR, os.path.basename(public_url))



def _delete_if_exists(fs_path: Optional[str]) -> None:

    if not fs_path:

        return

    try:

        if os.path.exists(fs_path):

            os.remove(fs_path)

    except Exception as e:

        print(f"[uploads] delete failed for {fs_path}: {e}")



def _cleanup_post_media(image_url: Optional[str]) -> None:

    """

    Remove the post's poster/still and its sibling .mp4 (if present).

    """

    if not image_url:

        return

    # delete poster/still

    fs = _public_to_fs(image_url)

    _delete_if_exists(fs)

    # delete sibling mp4 (/uploads/<uuid>.mp4)

    base, _ = os.path.splitext(image_url)

    mp4_fs = _public_to_fs(base + ".mp4")

    _delete_if_exists(mp4_fs)

def _comment_payload(db: Session, c: Comment) -> dict:

    u = db.get(User, c.user_id)

    # detect soft-deleted

    is_soft = (getattr(c, "deleted_at", None) is not None) or (c.content == "[deleted]")



    reply_count = db.scalar(select(func.count(Reply.id)).where(Reply.comment_id == c.id)) or 0

    return {

        "id": c.id,

        "post_id": c.post_id,

        "user_id": c.user_id,

        "content": "" if is_soft else c.content,

        "created_at": c.created_at,

        "updated_at": getattr(c, "updated_at", None),

        "reply_count": int(reply_count),

        "is_deleted": bool(is_soft),

        "user": {

            "id": u.id if u else None,

            "display_name": u.display_name if u else "User",

            "avatar_url": _abs_avatar(u.avatar_url if u else None),

        },

    }



def _cleanup_post_files(image_url: str | None) -> None:

    if not image_url:

        return

    # strip any query

    public = image_url.split("?", 1)[0]

    if not public.startswith("/uploads/"):

        return

    base_no_ext, _ = os.path.splitext(os.path.basename(public))

    # try common siblings

    for ext in (".jpg", ".jpeg", ".png", ".webp", ".gif", ".mp4"):

        fs = os.path.join(UPLOAD_ROOT, base_no_ext + ext)

        try:

            if os.path.exists(fs):

                os.remove(fs)

        except Exception as e:

            print(f"[delete] failed to remove {fs}: {e}")

def serialize_poll(poll, viewer_id):

    voted_ids = {v.option_id for v in getattr(poll, "votes", []) if v.user_id == viewer_id}

    opts = [{

        "id": o.id,

        "idx": o.idx if o.idx is not None else o.position,

        "text": o.text,

        "vote_count": int(getattr(o, "vote_count", 0) or 0),

    } for o in getattr(poll, "options", [])]

    return {

        "question": getattr(poll, "question", None),

        "multiple": bool(getattr(poll, "multiple", False)),

        "allow_change": bool(getattr(poll, "allow_change", True)),

        "options": opts,

        "voted_option_ids": list(voted_ids),

        "total_votes": sum(o["vote_count"] for o in opts),

        "closes_at": getattr(poll, "closes_at", None).isoformat() if getattr(poll, "closes_at", None) else None,

    }





def serialize_post(post, viewer_id):

    d = {

        "id": post.id,

        "text": post.text,

        "image_url": post.image_url,

        "image_preview_url": post.image_preview_url,

        "video_url": post.video_url,

        "background_color": post.background_color,

        "created_at": post.created_at.isoformat(),

        "updated_at": post.updated_at.isoformat(),

        "like_count": post.like_count,

        "comment_count": post.comment_count,

        "liked_by_me": post.liked_by_me(viewer_id),

        "reshare_count": post.reshare_count,

        "reshared_by_me": post.reshared_by_me(viewer_id),

        "user": {"id": post.user.id, "display_name": post.user.display_name, "avatar_url": post.user.avatar_url},

    }

    if post.poll is not None:

        d["type"] = "poll"

        d["poll"] = serialize_poll(post.poll, viewer_id)

    return d



def _extract_poll_from_request(

    *,

    content_type: str | None,

    json_body: Optional[Dict[str, Any]],

    form_body: Optional[Dict[str, Any]]

) -> Tuple[bool, str, List[str]]:

    """

    Returns (is_poll, question, options).



    Understands:

      - JSON:

          {"type":"poll","question":"...","options":[...]}

          {"type":"poll","poll":{"question":"...","options":[...]}}

      - x-www-form-urlencoded:

          type=poll&question=...&options[]=A&options[]=B

          type=poll&question=...&options=A,B

      - multipart/form-data:

          type=poll, question=..., repeated "options" fields

    """

    def norm_str(v) -> str:

        if v is None:

            return ""

        if isinstance(v, (str, int, float)):

            return str(v).strip()

        return str(v)



    def list_of_strings(v) -> List[str]:

        if v is None:

            return []

        if isinstance(v, list):

            out: List[str] = []

            for e in v:

                if isinstance(e, (str, int, float)):

                    s = str(e).strip()

                    if s:

                        out.append(s)

                elif isinstance(e, dict):

                    # allow {"text":"..."} style

                    s = norm_str(e.get("text") or e.get("label") or e.get("value") or e.get("option"))

                    if s:

                        out.append(s)

                else:

                    s = norm_str(e)

                    if s:

                        out.append(s)

            return out

        if isinstance(v, str) and "," in v:

            return [s.strip() for s in v.split(",") if s.strip()]

        s = norm_str(v)

        return [s] if s else []



    # JSON branch

    if json_body is not None:

        jb = json_body

        jtype = norm_str(jb.get("type")).lower()

        poll_map = jb.get("poll") if isinstance(jb.get("poll"), dict) else None

        question = (

            norm_str(jb.get("question"))

            or (norm_str(poll_map.get("question")) if poll_map else "")

            or norm_str(jb.get("poll_question"))

        )

        options = []

        raw_opts = (

            jb.get("options")

            or jb.get("choices")

            or jb.get("answers")

            or (poll_map.get("options") if poll_map else None)

            or (poll_map.get("choices") if poll_map else None)

            or (poll_map.get("answers") if poll_map else None)

        )

        options = list_of_strings(raw_opts)



        looks_like_poll = jtype == "poll" or bool(poll_map) or bool(question) or bool(options)

        is_poll = looks_like_poll and question != "" and len(options) >= 2

        return (is_poll, question, options)



    # FORM / MULTIPART branch

    if form_body is not None:

        fb = form_body

        ftype = norm_str(fb.get("type")).lower()

        question = norm_str(fb.get("question") or fb.get("poll_question") or fb.get("title") or fb.get("text"))



        # collect options from common patterns

        options: List[str] = []

        # 1) options[] style

        if "options[]" in fb:

            raw = fb.get("options[]")

            if isinstance(raw, list):

                options.extend(list_of_strings(raw))

            else:

                options.extend(list_of_strings([raw]))

        # 2) repeated "options" parts (multipart) or single "options" possibly comma-separated

        if "options" in fb:

            raw = fb.get("options")

            options.extend(list_of_strings(raw))



        # dedupe + strip empties

        opts_final = []

        seen = set()

        for o in options:

            if o and o not in seen:

                seen.add(o)

                opts_final.append(o)



        looks_like_poll = ftype == "poll" or bool(question) or len(opts_final) >= 2

        is_poll = looks_like_poll and question != "" and len(opts_final) >= 2

        return (is_poll, question, opts_final)



    return (False, "", [])
    
def _post_payload(db: Session, post: Post, viewer_id: int | None = None) -> dict:

    """Single source of truth for post JSON (null-safe timestamps) + poll state."""

    like_count = db.scalar(select(func.count(PostLike.id)).where(PostLike.post_id == post.id)) or 0

    comment_count = db.scalar(

        select(func.count(Comment.id)).where(

            Comment.post_id == post.id,

            (Comment.content != "[deleted]"),

            Comment.deleted_at.is_(None) if hasattr(Comment, "deleted_at") else text("1=1"),

        )

    ) or 0



    liked_by_me = False

    if viewer_id is not None:

        liked_by_me = (

            db.scalar(

                select(func.count(PostLike.id)).where(

                    PostLike.post_id == post.id,

                    PostLike.user_id == viewer_id,

                )

            ) == 1

        )



    reshare_count = db.scalar(select(func.count(PostReshare.id)).where(PostReshare.post_id == post.id)) or 0

    reshared_by_me = False

    if viewer_id is not None:

        reshared_by_me = (

            db.scalar(

                select(func.count(PostReshare.id)).where(

                    PostReshare.post_id == post.id,

                    PostReshare.user_id == viewer_id,

                )

            ) == 1

        )



    poster = post.image_url

    vid = _guess_video_sibling(poster)



    # ---------- poll snapshot ----------

    poll_json = None

    if getattr(post, "poll", None):

        p = post.poll

        # load options in stable order

        options = []

        total_votes = 0

        if getattr(p, "options", None):
            ordered = sorted(
                p.options,
                key=lambda o: (
                    getattr(o, "idx", None)
                    if getattr(o, "idx", None) is not None
                    else o.id
                )
            )

            for o in ordered:
                vc = int(getattr(o, "vote_count", 0) or 0)
                total_votes += vc
                options.append({
                    "id": o.id,
                    "idx": getattr(o, "idx", None),
                    "text": o.text,
                    "vote_count": vc,
                })

        closes_at = getattr(p, "closes_at", None)

        is_closed = bool(closes_at and datetime.now(timezone.utc) >= closes_at)



        voted_ids = []

        if viewer_id is not None:

            # PollVote model assumed: poll_id, user_id, option_id

            try:

                from models import PollVote

                voted_ids = [

                    r[0] for r in db.execute(

                        select(PollVote.option_id).where(

                            PollVote.poll_id == p.id,

                            PollVote.user_id == viewer_id,

                        )

                    ).all()

                ]

            except Exception:

                voted_ids = []



        poll_json = {

            "id": p.id,

            "question": getattr(p, "question", None) or (post.text or ""),

            "multiple": bool(getattr(p, "multiple", False)),

            "allow_change": bool(getattr(p, "allow_change", True)),

            "closes_at": _iso(closes_at),

            "is_closed": is_closed,

            "total_votes": int(total_votes),

            "options": options,

            "voted_option_ids": [int(x) for x in voted_ids],

        }



        #  log poll snapshot once per payload build (super helpful in feed & detail) 
        _dbg("POLL_SNAPSHOT/_post_payload", {

            "post_id": post.id,

            "question": poll_json["question"],

            "options": poll_json["options"],

            "total_votes": poll_json["total_votes"],

            "voted_option_ids": poll_json["voted_option_ids"],

        })



    payload = {

        "id":                post.id,

        "text":              post.text or "",

        "image_url":         poster,

        "image_preview_url": poster,

        "video_url":         vid,

        "background_color":  getattr(post, "background_color", None),

        "created_at":        _iso(getattr(post, "created_at", None)),

        "updated_at":        _iso(getattr(post, "updated_at", None)),

        "like_count":        like_count,

        "comment_count":     comment_count,

        "liked_by_me":       liked_by_me,

        "reshare_count":     reshare_count,

        "reshared_by_me":    reshared_by_me,

        "user": {

            "id":           post.user.id,

            "display_name": post.user.display_name,

            "avatar_url":   post.user.avatar_url,

        },

    }



    if poll_json:

        payload["type"] = "poll"

        payload["poll"] = poll_json

        payload["question"] = poll_json["question"]

        payload["options"]  = [o["text"] for o in poll_json["options"]]



    return payload



router = APIRouter()




# =========================

# Poll voting

# =========================

@router.post("/posts/{post_id}/poll/vote")

def vote_poll(

    post_id: int,

    body: VoteBody,

    db: Session = Depends(get_db),

    current_user: User = Depends(get_current_user),

):

    from models import Post, Poll, PollOption, PollVote



    post = db.get(Post, post_id)

    if not post or not getattr(post, "poll", None):

        raise HTTPException(404, "Poll not found")



    poll = post.poll



    # closed?

    if poll.closes_at and datetime.now(timezone.utc) >= poll.closes_at:

        raise HTTPException(400, "Poll is closed")



    # If client passed option indexes instead of IDs, translate by either idx or position.

    if getattr(body, "option_idxs", None):

        idx_to_id = {getattr(o, "idx", None): o.id for o in db.scalars(select(PollOption).where(PollOption.poll_id == poll.id)).all() if getattr(o, "idx", None) is not None}

        # keep only those we can map

        mapped = [idx_to_id[i] for i in body.option_idxs if i in idx_to_id]

        if mapped:

            body.option_ids = mapped



    # Optional: support "option_positions" if your client sends that (won't break if not present)

    if not body.option_ids and isinstance(getattr(body, "option_idxs", []), list) and not any(getattr(o, "idx", None) is not None for o in getattr(poll, "options", [])):

        # No idx in schema; try mapping the given numbers as "position" instead

        pos_to_id = {getattr(o, "position", None): o.id for o in db.scalars(select(PollOption).where(PollOption.poll_id == poll.id)).all() if getattr(o, "position", None) is not None}

        mapped = [pos_to_id[i] for i in body.option_idxs if i in pos_to_id]

        if mapped:

            body.option_ids = mapped



    if not body.option_ids:

        raise HTTPException(400, "No valid options")



    # validate options belong to poll

    valid_opts = db.scalars(

        select(PollOption).where(PollOption.poll_id == poll.id, PollOption.id.in_(body.option_ids))

    ).all()

    valid_ids = {o.id for o in valid_opts}

    if not valid_ids:

        raise HTTPException(400, "No valid options")



    # multiple?

    if not poll.multiple and len(valid_ids) > 1:

        raise HTTPException(400, "This poll allows a single choice")



    # existing votes

    existing = db.scalars(

        select(PollVote).where(PollVote.poll_id == poll.id, PollVote.user_id == current_user.id)

    ).all()



    # if not allow_change and already voted, block

    if existing and not poll.allow_change:

        raise HTTPException(400, "Changing vote is not allowed")



    # remove previous votes (when changing), decrement cached counts

    for v in existing:

        try:

            opt = db.get(PollOption, v.option_id)

            if opt and getattr(opt, "vote_count", None) is not None:

                opt.vote_count = max(0, int(opt.vote_count or 0) - 1)

        except Exception:

            pass

        db.delete(v)



    # add new votes (+ increment cached counts)

    for oid in valid_ids:

        db.add(PollVote(poll_id=poll.id, user_id=current_user.id, option_id=oid))

        opt = db.get(PollOption, oid)

        if opt and getattr(opt, "vote_count", None) is not None:

            opt.vote_count = int(opt.vote_count or 0) + 1



    db.commit()

    db.refresh(post)

    return {"status": "ok", "post": _post_payload(db, post, current_user.id)}




@router.post("/users/{user_id}/follow")

def follow_user(

    user_id: int,

    db: Session = Depends(get_db),

    current_user: User = Depends(get_current_user)

):

    if user_id == current_user.id:

        raise HTTPException(400, "Cannot follow yourself")

    exists = db.query(Follow).filter_by(

        follower_id=current_user.id,

        following_id=user_id

    ).first()

    if exists:

        raise HTTPException(409, "Already following")



    db.add(Follow(follower_id=current_user.id, following_id=user_id))

    db.add(Notification(

        user_id=user_id,

        actor_id=current_user.id,

        type="follow",

        message=f"{current_user.display_name} followed you"

    ))

    db.commit()

    return {"status": "ok"}



@router.delete("/users/{user_id}/unfollow")

def unfollow_user(

    user_id: int,

    db: Session = Depends(get_db),

    current_user: User = Depends(get_current_user)

):

    f = db.query(Follow).filter_by(

        follower_id=current_user.id,

        following_id=user_id

    ).first()

    if not f:

        raise HTTPException(404, "Not following")

    db.delete(f)

    db.commit()

    return {"status": "ok"}



# 

# Helpers (place near other helpers/imports)

def _preview_url_for(image_url: Optional[str]) -> Optional[str]:

    if not image_url:

        return None

    url = image_url.strip()

    if not url.startswith("/uploads/"):

        return url



    base, ext = os.path.splitext(url.lower())

    if ext in (".gif", ".webp"):

        # if we already have a poster next to it, use it

        poster = f"{base}.jpg"

        poster_fs = os.path.join(UPLOAD_ROOT, os.path.basename(poster))

        if os.path.exists(poster_fs):

            return poster

    return url  # jpg/png or no poster found



def _video_url_for(image_url: Optional[str]) -> Optional[str]:

    """

    If the stored image_url is a poster like /uploads/<uuid>.jpg,

    return /uploads/<uuid>.mp4 when that file exists on disk.

    """

    if not image_url or not isinstance(image_url, str):

        return None

    image_url = image_url.strip()

    if not image_url.startswith("/uploads/"):

        return None

    base, _ = os.path.splitext(image_url)  # "/uploads/<uuid>", ".jpg"

    mp4_name = os.path.basename(base) + ".mp4"

    mp4_fs   = os.path.join(UPLOAD_ROOT, mp4_name)   # UPLOAD_ROOT already defined above

    return f"/uploads/{mp4_name}" if os.path.exists(mp4_fs) else None



@router.get("/feed-follow")

def get_feed(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):



    followee_ids = select(Follow.following_id).where(Follow.follower_id == current_user.id)



    posts = (

        db.query(Post)

        .options(

            selectinload(Post.poll)

            .selectinload(Poll.options)

        )

        .filter(Post.user_id.in_(followee_ids.scalar_subquery()))

        .order_by(Post.created_at.desc(), Post.id.desc())

        .limit(50)

        .all()

    )



    return [_post_payload(db, p, current_user.id) for p in posts]



class PollOption(BaseModel):

    id: int

    idx: int

    text: str

    vote_count: int = 0



class PollPayload(BaseModel):

    question: str

    options: List[str]              



class PollState(BaseModel):

    question: str

    multiple: bool = False

    allow_change: bool = True

    is_closed: bool = False

    voted_option_ids: List[int] = []

    options: List[PollOption]
    


class PostOut(BaseModel):

    id: int

    text: str | None

    type: str | None

    poll: PollOut | None



    model_config = ConfigDict(from_attributes=True)
    
class PollCreateIn(BaseModel):

    # You can send either `text` or `question` (text defaults to question)

    text: str | None = None

    question: str = Field(..., min_length=1, max_length=280)

    options: Annotated[list[str], Field(min_length=2, max_length=8)]

    bg_color: str | None = None

    closes_at: str | None = None        # ISO8601, e.g. "2025-12-31T23:59:00Z"

    multiple: bool = False

    allow_change: bool = True

@router.get("/feed/global")

def get_global_feed(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):



    posts = (

        db.query(Post)

        .options(

            selectinload(Post.poll)

            .selectinload(Poll.options)

        )

        .order_by(Post.created_at.desc(), Post.id.desc())

        .limit(50)

        .all()

    )



    return [_post_payload(db, p, current_user.id) for p in posts]



@router.put("/users/me")

def update_me(

    top_line: str = Form(...),

    bio: str = Form(...),

    db: Session = Depends(get_db),

    current_user: User = Depends(get_current_user),

    

):

    # update

    current_user.top_line = top_line

    current_user.bio = bio

    db.commit()

    db.refresh(current_user)



    # build full profile payload

    matches_count   = db.query(Logs).filter(Logs.api_key == current_user.api_key).count()

    follower_count  = db.query(Follow).filter_by(following_id=current_user.id).count()

    following_count = db.query(Follow).filter_by(follower_id=current_user.id).count()

    like_count = db.query(UserLike).filter_by(target_user_id=current_user.id).count()



    return {

        "id":              current_user.id,

        "display_name":    current_user.display_name or f"User{current_user.id}",

        "avatar_url":      current_user.avatar_url or "/uploads/user_avatars/default_avatar.jpg",

        "top_line":        (current_user.top_line or "").strip(),

        "bio":             (current_user.bio or "").strip(),

        "is_private":      bool(current_user.is_private),

        "follower_count":  follower_count,

        "following_count": following_count,

        "like_count":      like_count,

        "matches":         matches_count,

        "created_at":      current_user.created_at,

        "is_admin": bool(getattr(current_user, "is_admin", False)),

    }



# 



@router.get("/users/{user_id}/logs")

def get_user_logs(

    user_id: int,

    limit: int = Query(20, ge=1, le=100),

    before_id: int | None = Query(None, description="keyset: older than this log id"),

    response: Response = None,

    db: Session = Depends(get_db),

    current_user: User = Depends(get_current_user),

):

    _no_store(response)



    u = db.query(User).filter_by(id=user_id).first()

    if not u:

        raise HTTPException(404, "User not found")



    base = db.query(Logs).filter(Logs.api_key == u.api_key)



    if before_id is not None:

        cur = db.get(Logs, before_id)

        if not cur or cur.api_key != u.api_key:

            raise HTTPException(400, "Invalid cursor")

        base = base.filter(tuple_(Logs.created_at, Logs.id) < tuple_(cur.created_at, cur.id))



    rows = (

        base.order_by(desc(Logs.created_at), desc(Logs.id))

            .limit(limit)

            .all()

    )



    items = [{

        "id":       l.id,

        "type":     l.search_type,

        "time":     l.created_at,

        "status":   l.status,

        "accuracy": l.accuracy,

    } for l in rows]



    has_more = False

    if rows:

        tail = rows[-1]

        has_more = bool(db.scalar(

            select(func.count(Logs.id))

            .where(Logs.api_key == u.api_key,

                   tuple_(Logs.created_at, Logs.id) < tuple_(tail.created_at, tail.id))

        ))



    return {

        "items": items,

        "has_more": has_more,

        "next_before_id": rows[-1].id if rows else None,

    }


@router.get("/users/{user_id}/followers")

def get_followers(

    user_id: int,

    skip:   int     = Query(0, ge=0),

    limit:  int     = Query(20, le=100),

    db:     Session = Depends(get_db),

):

    rows = db.query(Follow).filter_by(following_id=user_id).offset(skip).limit(limit).all()

    return [{"id": f.follower_id} for f in rows]



@router.get("/users/{user_id}/following")

def get_following(

    user_id: int,

    skip:   int     = Query(0, ge=0),

    limit:  int     = Query(20, le=100),

    db:     Session = Depends(get_db),

):

    rows = db.query(Follow).filter_by(follower_id=user_id).offset(skip).limit(limit).all()

    return [{"id": f.following_id} for f in rows]






def _timestamp_expr(Logs):

    """

    Prefer coalesce(created_at, created) when the ORM has both;

    fall back to created_at only if 'created' isn't mapped.

    """

    has_created_attr = hasattr(Logs, 'created')

    if has_created_attr:

        return func.coalesce(Logs.created_at, Logs.created)

    # If the physical column exists but isn't mapped, last resort:

    # return func.coalesce(Logs.created_at, literal_column('created'))

    return Logs.created_at



@router.get("/users/{user_id}/activity", response_model=list[ActivityEntry])

def get_activity(

    user_id: int,

    limit: int = Query(6, ge=1, le=50),

    db: Session = Depends(get_db),

    current_user: User = Depends(get_current_user),

    response: Response = None,

):

    if response is not None:

        response.headers["Cache-Control"] = "no-store, must-revalidate"

        response.headers["Vary"] = "Authorization"



    u = db.query(User).filter_by(id=user_id).first()

    if not u:

        raise HTTPException(status_code=404, detail="User not found")



    ts_expr = _timestamp_expr(Logs)



    rows = (

        db.query(

            Logs.id.label('id'),

            Logs.search_type.label('search_type'),

            Logs.anime_id.label('anime_id'),

            Logs.song_id.label('song_id'),

            Logs.accuracy.label('accuracy'),

            Logs.code.label('code'),

            Logs.status.label('status'),

            cast(Logs.ip, String).label('ip'),      # ensure string for Pydantic

            ts_expr.label('time'),                  # normalized timestamp

            Logs.created_at.label('created_at'),

        )

        .filter(Logs.api_key == u.api_key)

        .order_by(desc(ts_expr), desc(Logs.id))

        .limit(limit)

        .all()

    )



    return [dict(r._mapping) for r in rows]



@router.get("/users/me/activity", response_model=list[ActivityEntry])

def get_my_activity(

    limit: int = Query(6, ge=1, le=50),

    db: Session = Depends(get_db),

    current_user: User = Depends(get_current_user),

    response: Response = None,

):

    if response is not None:

        response.headers["Cache-Control"] = "no-store, must-revalidate"

        response.headers["Vary"] = "Authorization"



    ts_expr = _timestamp_expr(Logs)



    rows = (

        db.query(

            Logs.id.label('id'),

            Logs.search_type.label('search_type'),

            Logs.anime_id.label('anime_id'),

            Logs.song_id.label('song_id'),

            Logs.accuracy.label('accuracy'),

            Logs.code.label('code'),

            Logs.status.label('status'),

            cast(Logs.ip, String).label('ip'),

            ts_expr.label('time'),

            Logs.created_at.label('created_at'),

        )

        .filter(Logs.api_key == current_user.api_key)

        .order_by(desc(ts_expr), desc(Logs.id))

        .limit(limit)

        .all()

    )



    return [dict(r._mapping) for r in rows]



@router.post("/users/me/upload-avatar")

def upload_avatar(

    file: UploadFile = File(...),

    db: Session = Depends(get_db),

    current_user: User = Depends(get_current_user)

):

    # --- 1) Validate extension ---

    _, ext = os.path.splitext(file.filename.lower())

    ext = ext.strip().lower()

    if ext not in {".jpg", ".jpeg", ".png"}:

        raise HTTPException(400, detail="Only .jpg, .jpeg or .png files allowed")



    # --- 2) Check size (â¤ 5 MB) ---

    file.file.seek(0, os.SEEK_END)

    size = file.file.tell()

    file.file.seek(0)

    if size > 5 * 1024 * 1024:

        raise HTTPException(400, detail="File too large (max 5 MB)")



    # --- 3) Save to disk ---

    filename = f"user_{current_user.id}{ext}"

    filepath = os.path.join(AVATAR_DIR, filename)

    os.makedirs(AVATAR_DIR, exist_ok=True)

    with open(filepath, "wb") as buf:

        shutil.copyfileobj(file.file, buf)



    # --- 4) Update user record ---

    u = db.query(User).filter_by(id=current_user.id).first()

    u.avatar_url = f"/uploads/user_avatars/{filename}"

    db.commit()

    db.refresh(u)



    # --- 5) Return full URL with fallback ---

    avatar_url = u.avatar_url or "/uploads/user_avatars/default_avatar.jpg"

    if avatar_url.startswith("/uploads"):

        avatar_url = f"https://anime-seek.com{avatar_url}"



    return {"avatar_url": avatar_url}



#_______________________POSTS__________________





# Max render size for feed images

MAX_W, MAX_H = 1080, 1080

FFMPEG_BIN = os.environ.get("FFMPEG_BIN", "ffmpeg")



def _run_ffmpeg(args: list[str]) -> None:

    """Run ffmpeg, raising on error."""

    proc = subprocess.run([FFMPEG_BIN, *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    if proc.returncode != 0:

        raise RuntimeError(f"ffmpeg failed: {proc.stderr.decode(errors='ignore')[:4000]}")



def _resize_still_inplace(path: str, max_w: int, max_h: int) -> None:

    """Resizes JPG/PNG/WebP stills (keeps aspect)."""

    try:

        im = Image.open(path)

        im = im.convert("RGB") if im.mode not in ("RGB", "RGBA") else im

        im.thumbnail((max_w, max_h), Image.LANCZOS)

        # keep original extension; if PNG with alpha, convert to RGB JPG

        ext = os.path.splitext(path)[1].lower()

        if ext in (".png", ".webp") and im.mode == "RGBA":

            from PIL import Image as _Image  # local import for RGBA handling

            bg = _Image.new("RGB", im.size, (0, 0, 0))

            bg.paste(im, mask=im.split()[-1])

            im = bg

            path = os.path.splitext(path)[0] + ".jpg"

        im.save(path, quality=85, optimize=True)

    except Exception as e:

        print(f"[uploads] still resize failed for {path}: {e}")



def _animated_to_mp4_and_poster(src_path: str, base_uuid: str) -> tuple[str, str]:

    mp4_name    = f"{base_uuid}.mp4"

    poster_name = f"{base_uuid}.jpg"

    mp4_path    = os.path.join(UPLOAD_DIR, mp4_name)

    poster_path = os.path.join(UPLOAD_DIR, poster_name)



    # scale to fit, then pad to even, then normalize SAR

    vf_base = f"scale='min({MAX_W},iw)':'min({MAX_H},ih)':force_original_aspect_ratio=decrease"

    vf      = f"{vf_base},pad=ceil(iw/2)*2:ceil(ih/2)*2,setsar=1"



    _run_ffmpeg([

        "-y", "-i", src_path,

        "-an",

        "-movflags", "+faststart",

        "-pix_fmt", "yuv420p",

        "-vsync", "vfr",

        "-vf", vf,

        "-c:v", "libx264", "-crf", "23", "-preset", "veryfast",

        mp4_path

    ])



    _run_ffmpeg([

        "-y", "-i", src_path,

        "-vf", f"thumbnail,{vf}",

        "-frames:v", "1",

        poster_path

    ])



    return (f"/uploads/{mp4_name}", f"/uploads/{poster_name}")



def _guess_video_sibling(public_image_url: str) -> str | None:

    """

    If your DB only stores image_url (poster), derive a sibling .mp4 path with same base.

    Return that path only if the file exists.

    """

    try:

        if not public_image_url or not public_image_url.startswith("/uploads/"):

            return None

        base, _ = os.path.splitext(public_image_url)

        candidate = base + ".mp4"

        if os.path.exists(os.path.join(UPLOAD_DIR, os.path.basename(candidate))):

            return candidate

    except Exception:

        pass

    return None







ALLOWED = {"image/jpeg", "image/png", "image/gif", "image/webp"}

EXT_MAP = {"image/jpeg": ".jpg", "image/png": ".png", "image/gif": ".gif", "image/webp": ".webp"}



BOT_TOKEN = os.getenv("DISCORD_BOT_TOKEN")

FORUM_CHANNEL_ID = os.getenv("DISCORD_FORUM_CHANNEL_ID")

PUBLIC_BASE = os.getenv("PUBLIC_BASE_URL", "https://anime-seek.com")

DISCORD_API_BASE = "https://discord.com/api/v10"
DISCORD_HEADERS = {"Authorization": f"Bot {BOT_TOKEN}"}



PUBLIC_BASE = os.getenv("PUBLIC_BASE_URL", "https://anime-seek.com")  # for absolute media URLs



def _truncate(s: str, n: int) -> str:

    return s if not s or len(s) <= n else s[: n - 1] + "…"



def _sanitize(s: Optional[str]) -> str:

    s = (s or "").strip()

    return s.replace("@everyone", "[@everyone]").replace("@here", "[@here]")



def _abs_url(u: Optional[str]) -> Optional[str]:

    if not u: return None

    if u.startswith("http://") or u.startswith("https://"): return u

    if u.startswith("/"): return f"{PUBLIC_BASE}{u}"

    return f"{PUBLIC_BASE}/{u}"



def _username_from(user: Optional[User]) -> str:

    if not user: return "user"

    for k in ("username", "display_name", "handle"):

        v = getattr(user, k, None)

        if v: return v

    email = getattr(user, "email", None)

    return (email.split("@", 1)[0] if email else "user")



def _hex_to_int(h: Optional[str], default=0x10B981) -> int:

    if not h: return default

    h = h.strip()

    if not h.startswith("#"): h = "#" + h

    try: return int(h[1:], 16)

    except: return default
        

def _discord_patch_thread_name(thread_id: str, name: str) -> None:

    if not BOT_TOKEN or not thread_id: return

    name = _truncate(_sanitize(name), 100)

    httpx.patch(f"{DISCORD_API_BASE}/channels/{thread_id}",

                json={"name": name},

                headers=DISCORD_HEADERS,

                timeout=15)



def _discord_send_in_thread(thread_id: str, content: str, *, color: int, image_url: Optional[str]) -> None:

    if not BOT_TOKEN or not thread_id: return

    embed = {

        "title": "Post updated",

        "description": content,

        "color": color,

        "allowed_mentions": {"parse": []},

    }

    e = {"content": _sanitize(content), "embeds": [{"title": "Post updated", "description": _sanitize(content), "color": color}]}

    if image_url:

        e["embeds"][0]["image"] = {"url": image_url}

    httpx.post(f"{DISCORD_API_BASE}/channels/{thread_id}/messages",

               json=e, headers=DISCORD_HEADERS, timeout=20)



def _build_forum_payload(
    *,
    title: str,
    body: str = "",
    meta: str = "",
    image_url: Optional[str] = None,
    request_id: Optional[str] = None,
    color_int: int = 0x10B981,
) -> dict:
    name = _truncate(_sanitize(title), 100)

    full_desc = _sanitize(body or "")
    if meta:
        full_desc = f"{full_desc}\n\n---\n{_sanitize(meta)}" if full_desc else _sanitize(meta)

    # Discord embed description limit is 4096
    full_desc = _truncate(full_desc, 4096)

    embed = {
        "title": _truncate(_sanitize(title), 256),
        "description": full_desc,
        "color": color_int,
        "footer": {"text": f"Post ID: {request_id or ''}".strip()},
    }

    if image_url:
        embed["image"] = {"url": image_url}

    return {
        "name": name,
        "auto_archive_duration": 4320,
        "rate_limit_per_user": 2,
        "applied_tags": [],
        "message": {
            "content": "",
            "embeds": [embed],
            "allowed_mentions": {"parse": []},
        },
    }
def discord_edit_message(thread_id: str, message_id: str, new_content: str):

    r = httpx.patch(f"{DISCORD_API}/channels/{thread_id}/messages/{message_id}",

                    json={"content": new_content[:2000]}, headers=HEADERS, timeout=20)

    r.raise_for_status()
def discord_delete_message(thread_id: str, message_id: str):

    # Bot can delete its OWN messages without extra perms.

    r = httpx.delete(f"{DISCORD_API}/channels/{thread_id}/messages/{message_id}",

                     headers=HEADERS, timeout=20)

    if r.status_code not in (200, 204):

        r.raise_for_status()
        




def discord_send_in_thread(thread_id: str, content: str) -> str:

    payload = {"content": content, "allowed_mentions": {"parse": []}}

    r = httpx.post(f"{DISCORD_API}/channels/{thread_id}/messages",

                   json=payload, headers=HEADERS, timeout=20)

    r.raise_for_status()

    return r.json()["id"]
    

def discord_delete_thread(thread_id: str) -> None:

    if not (BOT_TOKEN and thread_id):

        return

    try:

        r = httpx.delete(f"{DISCORD_API_BASE}/channels/{thread_id}",

                         headers=DISCORD_HEADERS, timeout=20)

        # 200/204 = deleted; 404 = already gone; anything else = raise

        if r.status_code in (200, 204, 404):

            return

        r.raise_for_status()

    except Exception as e:

        # non-fatal: app delete should still succeed

        print(f"[discord] thread delete failed ({thread_id}):", getattr(e, "response", e))

def _hours_until(dt_utc):

    if not dt_utc:

        return 24

    from datetime import datetime, timezone

    now = datetime.now(timezone.utc)

    secs = (dt_utc - now).total_seconds()

    return max(1, min(168, int(secs // 3600)))  # clamp 1..168



def _discord_poll_from_orm(post) -> dict | None:

    """

    Convert ORM poll -> Discord poll payload.

    Requires poll answers in form:

      {"poll_media": {"text": "...", "type": 0}}

    """

    p = getattr(post, "poll", None)

    if not p:

        return None



    q = getattr(p, "question", None) or getattr(post, "text", None) or "Poll"



    # stable order by idx/position

    opts = getattr(p, "options", []) or []

    def _ord(o):

        return getattr(o, "idx", None) if getattr(o, "idx", None) is not None else getattr(o, "position", 0) or 0



    answers = []

    for o in sorted(opts, key=_ord):

        if getattr(o, "text", None):

            answers.append({

                "poll_media": {

                    "text": str(o.text),

                    "type": 0,  # 0 = text

                }

            })



    if len(answers) < 2:

        return None  # Discord needs ≥2 answers



    closes_at = getattr(p, "closes_at", None)

    duration_hours = _hours_until(closes_at) if closes_at else 24



    return {

        "question": {"text": str(q)},

        "answers": answers,

        "allow_multiselect": bool(getattr(p, "multiple", False)),

        "duration": duration_hours,  # hours

    }



        

def publish_to_discord_forum_sync(post_id: int, image_preview_url: Optional[str]) -> None:

    if not (BOT_TOKEN and FORUM_CHANNEL_ID):

        return

    db: Session = SessionLocal()

    try:

        post: Optional[Post] = db.query(Post).get(post_id)

        if not post or getattr(post, "discord_thread_id", None):

            return



        user: Optional[User] = db.query(User).get(post.user_id)

        uname = _username_from(user)


        full_text = (post.text or "").strip()
        title = _truncate(full_text or f"Post #{post.id}", 100)
        meta = f"by {uname} • {post.created_at:%Y-%m-%d %H:%M}" if getattr(post, "created_at", None) else f"by {uname}"


        color_int = _hex_to_int(getattr(post, "background_color", None))

        embed_img = _fix_anilist_cdn(_abs_url(image_preview_url or post.image_url))

        base_payload = _build_forum_payload(
            title=title,
            body=full_text,
            meta=meta,
            image_url=embed_img,
            request_id=str(post.id),
            color_int=color_int,
            )


        # Try to attach a native poll on the first message

        poll_obj = _discord_poll_from_orm(post)

        if poll_obj:

            base_payload.setdefault("message", {})["poll"] = poll_obj



        headers = {"Authorization": f"Bot {BOT_TOKEN}"}

        api_url = f"{DISCORD_API_BASE}/channels/{FORUM_CHANNEL_ID}/threads"



        for attempt in range(3):

            try:

                r = httpx.post(api_url, json=base_payload, headers=headers, timeout=20)

                if r.status_code == 429:

                    time.sleep(float(r.json().get("retry_after", 1.0))); continue

                if r.status_code >= 400:

                    print("[discord] forum create error:", r.text)

                    print("[discord] payload:", json.dumps(base_payload)[:4000])

                r.raise_for_status()

                data = r.json()

                thread_id = data.get("id")

                # Save thread id

                if thread_id:

                    post.discord_thread_id = thread_id

                    db.commit()



                    # If we intended a poll but the created message has none, post it as a separate message

                    if poll_obj:

                        created_msg = data.get("message") or {}

                        has_poll = bool(created_msg.get("poll"))

                        if not has_poll:

                            try:

                                resp2 = httpx.post(

                                    f"{DISCORD_API_BASE}/channels/{thread_id}/messages",

                                    json={

                                        "content": "",                  # no text; just the poll

                                        "poll": poll_obj,

                                        "allowed_mentions": {"parse": []},

                                    },

                                    headers=headers, timeout=20

                                )

                                if resp2.status_code >= 400:

                                    print("[discord] fallback poll post error:", resp2.text)

                            except Exception as e:

                                print("[discord] fallback poll post exception:", e)

                break

            except httpx.HTTPError as e:

                if attempt == 2:

                    print("[discord] publish failed:", getattr(e.response, "text", str(e)))

                else:

                    time.sleep(1.0)

                    continue

    finally:

        db.close()





# =========================

# Posts endpoint

# =========================


@router.get("/posts/me")

def get_my_posts(

    db: Session = Depends(get_db),

    current_user: User = Depends(get_current_user),

):

    posts = (

        db.query(Post).filter(Post.user_id == current_user.id).order_by(Post.created_at.desc()).all()

    )

    return [

        {

            "id": post.id,

            "text": post.text,

            "image_url": post.image_url,

            "created_at": post.created_at,

            "user": {

                "id": current_user.id,

                "display_name": current_user.display_name,

                "avatar_url": current_user.avatar_url,

            }

        }

        for post in posts

    ]

@router.get("/users/{user_id}/posts/count")

def get_post_count(

    user_id: int,

    since: datetime | None = Query(None),

    until: datetime | None = Query(None),

    visible_only: bool = Query(True, description="Exclude drafts/soft-deleted if your feed does"),

    db: Session = Depends(get_db),

    response: Response = None,

):

    # 1) Anti-cache headers (request headers from the client don't force edge caches)

    if response is not None:

        response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"

        response.headers["Pragma"] = "no-cache"

        response.headers["Vary"] = "Authorization"



    # 2) Ensure user exists

    exists = db.query(User.id).filter(User.id == user_id).first()

    if not exists:

        raise HTTPException(status_code=404, detail="User not found")



    # 3) created_at vs created safety

    created_ts = getattr(Post, "created_at", None) or getattr(Post, "created", None)

    if created_ts is None:

        # Fallback to a literal if the column exists but isn’t mapped

        created_ts = literal_column("created_at")



    q = db.query(func.count(Post.id)).filter(Post.user_id == user_id)



    # 4) Match your feed’s visibility rules (toggle via visible_only)

    if visible_only:

        if hasattr(Post, "is_deleted"):

            q = q.filter(Post.is_deleted.is_(False))

        if hasattr(Post, "deleted_at"):

            q = q.filter(Post.deleted_at.is_(None))

        if hasattr(Post, "status"):

            # assume 'published' is what your feed shows

            q = q.filter(Post.status == "published")



    if since:

        q = q.filter(created_ts >= since)

    if until:

        q = q.filter(created_ts < until)



    # 5) If you use replicas, force primary read or a fresh session

    #    Option A: If you have a primary bind, use it:

    # q = q.execution_options(schema_translate_map={"replica": "primary"})

    #    Option B: expire session to avoid stale identity map:

    db.expire_all()



    count = q.scalar() or 0

    return {

        "user_id": user_id,

        "posts": int(count),

        "since": since,

        "until": until,

    }



@router.delete("/users/{user_id}/like", response_model=LikeResponse)

def unlike_user(

    user_id: int,

    db: Session = Depends(get_db),

    current_user: User = Depends(get_current_user),

):

    db.query(UserLike).filter(

        UserLike.liker_user_id == current_user.id,

        UserLike.target_user_id == user_id,

    ).delete(synchronize_session=False)

    db.commit()



    like_count = db.scalar(

        select(func.count(UserLike.id)).where(UserLike.target_user_id == user_id)

    ) or 0

    return LikeResponse(liked=False, like_count=like_count)



@router.put("/posts/{post_id}")

def update_post(

    post_id: int,

    text: Optional[str] = Form(None),

    file: Optional[UploadFile] = File(None),

    db: Session = Depends(get_db),

    current_user: User = Depends(get_current_user),

    bg_color: Optional[str] = Form(None),

):

    post = db.query(Post).filter(Post.id == post_id).first()

    if not post:

        raise HTTPException(status_code=404, detail="Post not found")

    if post.user_id != current_user.id and not getattr(current_user, "is_admin", False):

        raise HTTPException(status_code=403, detail="Not authorized to edit this post")



    # updates

    if text is not None:

        post.text = text



    if bg_color is not None:

        color = _normalize_hex_color(bg_color)

        post.background_color = color if (_is_premium(current_user) and color) else None



    updated_image_url: Optional[str] = None



    if file is not None:

        old_media = post.image_url

        ct = (file.content_type or "").lower()

        if ct not in ALLOWED:

            raise HTTPException(400, "Unsupported media type")



        os.makedirs(UPLOAD_DIR, exist_ok=True)

        ext = EXT_MAP[ct]

        base_uuid = str(uuid.uuid4())

        raw_name = f"{base_uuid}{ext}"

        raw_path = os.path.join(UPLOAD_DIR, raw_name)



        with open(raw_path, "wb") as buf:

            shutil.copyfileobj(file.file, buf)



        try:

            if ct in ("image/gif", "image/webp"):

                _, poster_url = _animated_to_mp4_and_poster(raw_path, base_uuid)

                post.image_url = poster_url

                updated_image_url = poster_url

                try: os.remove(raw_path)

                except Exception: pass

            else:

                _resize_still_inplace(raw_path, MAX_W, MAX_H)

                post.image_url = f"/uploads/{raw_name}"

                updated_image_url = post.image_url

        except Exception as e:

            print(f"[uploads] update processing failed: {e}")

            post.image_url = f"/uploads/{raw_name}"

            updated_image_url = post.image_url



        db.commit(); db.refresh(post)

        try:

            _cleanup_post_media(old_media)

        except Exception as e:

            print(f"[uploads] update cleanup error for post {post_id}: {e}")

    else:

        db.commit(); db.refresh(post)



    # -------- Discord sync (if thread exists) --------

    try:

        thread_id = getattr(post, "discord_thread_id", None)

        if thread_id:

            # 1) update thread name (use post.text or fallback)

            thread_name = post.text or f"Post #{post.id}"

            _discord_patch_thread_name(thread_id, thread_name)



            # 2) post an "updated" message with color + image (no links)

            user = db.query(User).get(post.user_id)

            uname = _username_from(user)

            meta = f"by {uname}"

            if getattr(post, "created_at", None):

                meta += f" • {post.created_at:%Y-%m-%d %H:%M}"



            color_int = _hex_to_int(post.background_color)

            img_abs = _fix_anilist_cdn(_abs_url(updated_image_url or post.image_url))



            # content is concise: title + meta, no URL
            full_text = (post.text or "").strip()
            content = _sanitize(
                f"{thread_name}\n\n{full_text}\n\n---\n{meta}"
            )
            _discord_send_in_thread(thread_id, _truncate(content, 1900), color=color_int, image_url=img_abs)

    except Exception as e:

        # Never break the app if Discord fails

        print(f"[discord] update sync error for post {post_id}: {e}")



    # fresh payload to client

    payload = _post_payload(db, post, current_user.id)

    payload["background_color"] = post.background_color

    return {"status": "updated", "post": payload}


def get_public_analytics(db: Session, user: User):

    api_key = user.api_key



    # Scene searches

    total_scene_searches = db.query(Logs).filter(

        Logs.api_key == api_key, Logs.search_type == "scene"

    ).count()

    successful_scene_matches = db.query(Logs).filter(

        Logs.api_key == api_key, Logs.search_type == "scene", Logs.code == 200

    ).count()



    # Audio searches

    total_audio_searches = db.query(Logs).filter(

        Logs.api_key == api_key, Logs.search_type == "audio"

    ).count()

    successful_audio_matches = db.query(Logs).filter(

        Logs.api_key == api_key, Logs.search_type == "audio", Logs.code == 200

    ).count()



    # Longest streak

    dates = db.query(func.date(Logs.created_at)).filter(Logs.api_key == api_key).distinct().all()

    dates = sorted([d[0] for d in dates])

    longest_streak = current_streak = 0

    for i, d in enumerate(dates):

        if i == 0 or (d - dates[i - 1]).days == 1:

            current_streak += 1

            longest_streak = max(longest_streak, current_streak)

        else:

            current_streak = 1



    # Average confidence

    avg_conf = db.query(func.coalesce(func.avg(Logs.accuracy), 0.0)).filter(

        Logs.api_key == api_key

    ).scalar()

    avg_conf = round(float(avg_conf or 0.0), 2)



    # Per-day stats (last 30 days)

    today = date.today()

    start_date = today - timedelta(days=29)



    def per_day(tpe):

        rows = (

            db.query(func.date(Logs.created_at).label("date"), func.count(Logs.id).label("count"))

            .filter(Logs.api_key == api_key, Logs.search_type == tpe, Logs.created_at >= start_date)

            .group_by(func.date(Logs.created_at))

            .order_by("date")

            .all()

        )

        return [{"date": r.date.isoformat(), "count": r.count} for r in rows]



    def matches_per_day():

        rows = (

            db.query(func.date(Logs.created_at).label("date"), func.count(Logs.id).label("count"))

            .filter(Logs.api_key == api_key, Logs.code == 200, Logs.created_at >= start_date)

            .group_by(func.date(Logs.created_at))

            .order_by("date")

            .all()

        )

        return [{"date": r.date.isoformat(), "count": r.count} for r in rows]



    def confidence_trend():

        rows = (

            db.query(func.date(Logs.created_at).label("date"), func.avg(Logs.accuracy).label("confidence"))

            .filter(Logs.api_key == api_key, Logs.created_at >= start_date)

            .group_by(func.date(Logs.created_at))

            .order_by("date")

            .all()

        )

        return [{"date": r.date.isoformat(), "confidence": float(r.confidence or 0)} for r in rows]



    # User rank

    total_searches = total_scene_searches + total_audio_searches

    subq = (

        db.query(Logs.api_key.label("k"), func.count().label("cnt"))

        .filter(Logs.search_type.in_(["scene", "audio"]))

        .group_by(Logs.api_key)

        .subquery()

    )

    higher = db.query(func.count()).select_from(subq).filter(subq.c.cnt > total_searches).scalar() or 0

    rank_position = higher + 1



    return {

        "totalSceneSearches": total_scene_searches,

        "successfulSceneMatches": successful_scene_matches,

        "totalAudioSearches": total_audio_searches,

        "successfulAudioMatches": successful_audio_matches,

        "longestStreakDays": longest_streak,

        "averageConfidence": avg_conf,

        "sceneSearchesPerDay": per_day("scene"),

        "audioSearchesPerDay": per_day("audio"),

        "matchesPerDay": matches_per_day(),

        "confidenceTrend": confidence_trend(),

        "userRank": rank_position,

        "topUsers": {},

    }



@router.get("/users/{user_id}")

def get_user_profile(

    user_id: int,

    db: Session = Depends(get_db),

    current_user: User = Depends(get_current_user),

):

    user = db.get(User, user_id)

    if not user:

        raise HTTPException(status_code=404, detail="User not found")



    def _ensure3(val) -> List[str]:

        if val is None:

            return ["", "", ""]

        if isinstance(val, str):

            try:

                val = json.loads(val)

            except Exception:

                val = []

        if not isinstance(val, list):

            val = []

        out = [(x if isinstance(x, str) else "") for x in val[:3]]

        while len(out) < 3:

            out.append("")

        return out



    # fresh counts straight from DB

    like_count = db.scalar(

        select(func.count(UserLike.id)).where(UserLike.target_user_id == user_id)

    ) or 0



    follower_count = db.scalar(

        select(func.count(Follow.id)).where(Follow.following_id == user_id)

    ) or 0



    following_count = db.scalar(

        select(func.count(Follow.id)).where(Follow.follower_id == user_id)

    ) or 0



    # whether the current user liked/follows this profile

    liked_by_me = db.scalar(

        select(func.count(UserLike.id)).where(

            UserLike.target_user_id == user_id,

            UserLike.liker_user_id == current_user.id,

        )

    ) == 1



    follows_by_me = db.scalar(

        select(func.count(Follow.id)).where(

            Follow.follower_id == current_user.id,

            Follow.following_id == user_id,

        )

    ) == 1



    # histories & extras

    scene_history = (

        db.query(

            Logs.id,

            Anime.title_romaji.label("anime_title"),

            Logs.created_at,

            Logs.accuracy.label("accuracy"),

            Anime.cover_image.label("thumbnail"),

        )

        .join(Anime, Anime.id == Logs.anime_id, isouter=True)

        .filter(Logs.api_key == user.api_key, Logs.search_type == "scene")

        .order_by(Logs.created_at.desc())

        .limit(10)

        .all()

    )

    scene_data = [

        {

            "id": row.id,

            "anime_title": row.anime_title,

            "timestamp": row.created_at.isoformat() if row.created_at else None,

            "match_confidence": row.accuracy,

            "thumbnail": row.thumbnail,

        }

        for row in scene_history

    ]



    audio_history = (

        db.query(

            Logs.id,

            Song.song_name.label("song_title"),

            Anime.title_romaji.label("anime_title"),

            Logs.created_at,

            Logs.accuracy.label("accuracy"),

        )

        .join(Song, Song.song_id == Logs.song_id, isouter=True)

        .join(Anime, Anime.id == Logs.anime_id, isouter=True)

        .filter(Logs.api_key == user.api_key, Logs.search_type == "audio")

        .order_by(Logs.created_at.desc())

        .limit(10)

        .all()

    )

    audio_data = [

        {

            "id": row.id,

            "song_title": row.song_title,

            "anime_title": row.anime_title,

            "timestamp": row.created_at.isoformat() if row.created_at else None,

            "match_confidence": row.accuracy,

        }

        for row in audio_history

    ]



    playlists = db.query(Playlist).filter(Playlist.user_id == user.id).all()

    playlist_data = [{"id": p.id, "name": p.name, "count": len(p.songs)} for p in playlists]

    badge_data = [

        {"id": b.id, "name": b.name, "unlocked_at": b.unlocked_at}

        for b in getattr(user, "badges", [])

    ]



    analytics_data = get_public_analytics(db, user)

    favorite_anime = _ensure3(getattr(user, "favorite_anime", None))

    favorite_characters = _ensure3(getattr(user, "favorite_characters", None))



    return {

        "id": user.id,

        "display_name": user.display_name or f"User{user.id}",

        "avatar_url": user.avatar_url or "/uploads/user_avatars/default_avatar.jpg",

        "top_line": user.top_line or "",

        "bio": user.bio or "",

        "is_private": bool(user.is_private),



        # fresh counts

        "like_count": like_count,

        "follower_count": follower_count,

        "following_count": following_count,



        # optional flags for UI state

        "liked_by_me": liked_by_me,

        "follows_by_me": follows_by_me,



        "matches": getattr(user, "matches", 0),

        "created_at": user.created_at.isoformat() if user.created_at else None,

        "analytics": analytics_data,

        "badges": badge_data,

        "scene_history": scene_data,

        "audio_history": audio_data,

        "playlists": playlist_data,

        "recent_scene_matches": scene_data[:3],

        "recent_audio_matches": [

            {"song_name": a["song_title"], "artist": a["anime_title"]}

            for a in audio_data[:3]

        ],

        "favorite_anime": favorite_anime,

        "favorite_characters": favorite_characters,

    }



@router.get("/users/{user_id}/analytics")

def get_user_analytics(

    user_id: int,

    db: Session = Depends(get_db),

    current_user: User = Depends(get_current_user)

):

    user = db.query(User).get(user_id)

    if not user:

        raise HTTPException(status_code=404, detail="User not found")

    return get_public_analytics(db, user)



@router.post("/users/{user_id}/upload-favorite-image")

def upload_favorite_image(

    user_id: int,

    index: int = Form(...),

    type: str = Form(...),  # "anime" or "character"

    file: UploadFile = File(...),

    db: Session = Depends(get_db),

    current_user: User = Depends(get_current_user),

):

    if current_user.id != user_id:

        raise HTTPException(status_code=403, detail="Not allowed")



    type = (type or "").lower().strip()

    if type not in ("anime", "character"):

        raise HTTPException(status_code=400, detail="type must be 'anime' or 'character'")

    if index < 0 or index > 2:

        raise HTTPException(status_code=400, detail="index must be 0, 1, or 2")



    base_dir = os.path.dirname(os.path.abspath(__file__))

    upload_root = os.path.join(base_dir, "uploads")

    user_avatars_dir = os.path.join(upload_root, "user_avatars")

    os.makedirs(user_avatars_dir, exist_ok=True)



    ext = (os.path.splitext(file.filename or "")[1] or "").lower()

    if ext not in (".jpg", ".jpeg", ".png"):

        ct = (file.content_type or "").lower()

        ext = ".png" if "png" in ct else ".jpg"



    filename = f"user_{user_id}_{type}_{index}{ext}"

    fs_path = os.path.join(user_avatars_dir, filename)



    with open(fs_path, "wb") as f:

        shutil.copyfileobj(file.file, f)



    public_url = f"/uploads/user_avatars/{filename}"

    versioned_url = f"{public_url}?v={int(time.time())}"  # cache-buster



    def _ensure_list(value):

        if value is None:

            return ["", "", ""]

        if isinstance(value, str):

            try:

                parsed = json.loads(value)

            except Exception:

                parsed = ["", "", ""]

            while len(parsed) < 3:

                parsed.append("")

            return parsed[:3]

        if isinstance(value, list):

            lst = list(value)

            while len(lst) < 3:

                lst.append("")

            return lst[:3]

        return ["", "", ""]



    if type == "anime":

        fav = _ensure_list(getattr(current_user, "favorite_anime", None))

        fav[index] = versioned_url

        try:

            current_user.favorite_anime = fav

        except Exception:

            current_user.favorite_anime = json.dumps(fav)

    else:

        fav = _ensure_list(getattr(current_user, "favorite_characters", None))

        fav[index] = versioned_url

        try:

            current_user.favorite_characters = fav

        except Exception:

            current_user.favorite_characters = json.dumps(fav)



    db.commit()



    return {"url": versioned_url}



@router.post("/posts/{post_id}/like", response_model=LikeResponse)

def like_post(post_id: int,

              db: Session = Depends(get_db),

              current_user: User = Depends(get_current_user)):

    # Ensure post exists

    post = db.get(Post, post_id)

    if not post:

        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Post not found")



    # Check if like already exists

    existing = db.execute(

        select(PostLike).where(

            PostLike.post_id == post_id,

            PostLike.user_id == current_user.id

        )

    ).scalar_one_or_none()



    if existing:

        # Toggle off (unlike)

        db.delete(existing)

        db.commit()

        like_count = db.execute(

            select(func.count()).select_from(PostLike).where(PostLike.post_id == post_id)

        ).scalar_one()

        return LikeResponse(liked=False, like_count=like_count)



    # Create like

    db.add(PostLike(post_id=post_id, user_id=current_user.id))

    try:

        db.commit()

    except Exception:

        db.rollback()

        # Unique constraint or other error

        raise HTTPException(status_code=400, detail="Could not like post")



    like_count = db.execute(

        select(func.count()).select_from(PostLike).where(PostLike.post_id == post_id)

    ).scalar_one()

    return LikeResponse(liked=True, like_count=like_count)

@router.delete("/posts/{post_id}")

def delete_post(

    post_id: int,

    db: Session = Depends(get_db),

    current_user: User = Depends(get_current_user),

):

    post = db.query(Post).filter(Post.id == post_id).first()

    if not post:

        raise HTTPException(status_code=404, detail="Post not found")

    if post.user_id != current_user.id and not getattr(current_user, "is_admin", False):

        raise HTTPException(status_code=403, detail="Not authorized to delete this post")



    # hold data needed after row removal

    thread_id = getattr(post, "discord_thread_id", None)

    old_media = getattr(post, "image_url", None)



    # delete the post in-app first (app is source of truth)

    try:

        db.delete(post)

        db.commit()

    except Exception:

        db.rollback()

        raise



    # best-effort media cleanup

    try:

        _cleanup_post_media(old_media)

    except Exception as e:

        print(f"[uploads] delete cleanup error for post {post_id}: {e}")



    # sync delete to Discord (non-fatal if it fails)

    try:

        if thread_id:

            discord_delete_thread(thread_id)

    except Exception as e:

        print(f"[discord] non-fatal: could not delete thread for post {post_id}: {e}")



    return {"status": "deleted", "post_id": post_id}




@router.post("/users/{user_id}/like", response_model=LikeResponse)

def like_user(

    user_id: int,

    db: Session = Depends(get_db),

    current_user: User = Depends(get_current_user),

):

    if user_id == current_user.id:

        raise HTTPException(status_code=400, detail="Cannot like yourself")



    target = db.get(User, user_id)

    if not target:

        raise HTTPException(status_code=404, detail="User not found")



    try:

        db.add(UserLike(liker_user_id=current_user.id, target_user_id=user_id))

        db.commit()

    except IntegrityError:

        db.rollback()  # already liked -> ignore



    like_count = db.scalar(

        select(func.count(UserLike.id)).where(UserLike.target_user_id == user_id)

    ) or 0

    return LikeResponse(liked=True, like_count=like_count)





ANILIST_GQL = "https://graphql.anilist.co"

ANILIST_QUERY = """

query ($ids: [Int]) {

  Page(perPage: 50) {

    media(type: ANIME, id_in: $ids) {

      id

      title { romaji english }

      coverImage { large extraLarge }

      siteUrl

      season

      seasonYear

      format

      genres

      tags { name }

    }

  }

}

"""



class AnimeLogItem(BaseModel):

    anime_id: int

    count: int

    last_seen: datetime

    title_romaji: Optional[str] = None

    title_english: Optional[str] = None

    cover_image: Optional[str] = None

    site_url: Optional[str] = None



def _fallback_cover(aid: int, a: Optional[Anime], m: Optional[AniListMetadata]) -> str:

    return (m.cover_image if m and m.cover_image else None) or (a.cover_image if a and a.cover_image else None) or f"https://img.anili.st/media/{aid}"



def _ensure_meta(

    db: Session,

    ids: Iterable[Union[int, str, float, None]],

    max_age_days: int = 7,

) -> Dict[int, AniListMetadataORM]:

    """Ensure AniListMetadata exists & is fresh for the given AniList IDs.

    Returns a map {anilist_id: AniListMetadataORM}.

    """

    # --- sanitize/dedupe ids to ints only ---

    clean_ids: set[int] = set()

    for i in ids or []:

        if isinstance(i, int):

            clean_ids.add(i)

        elif isinstance(i, float) and i.is_integer():

            clean_ids.add(int(i))

        elif isinstance(i, str) and i.isdigit():

            clean_ids.add(int(i))

    if not clean_ids:

        return {}



    cutoff = datetime.utcnow() - timedelta(days=max_age_days)



    # --- load existing rows ---

    existing: List[AniListMetadataORM] = (

        db.query(AniListMetadataORM)

          .filter(AniListMetadataORM.anilist_id.in_(clean_ids))

          .all()

    )

    by_id: Dict[int, AniListMetadataORM] = {row.anilist_id: row for row in existing}



    # stale if missing OR fetched_at is NULL OR older than cutoff

    def _is_stale(aid: int) -> bool:

        row = by_id.get(aid)

        if row is None:

            return True

        fa = getattr(row, "fetched_at", None)

        return (fa is None) or (fa < cutoff)



    need: List[int] = [aid for aid in clean_ids if _is_stale(aid)]

    if not need:

        return by_id



    # --- fetch in chunks from AniList ---

    created_or_updated = False

    now = datetime.utcnow()



    for start in range(0, len(need), 50):

        chunk = list(need[start:start + 50])

        media = []

        try:

            r = requests.post(

                ANILIST_GQL,

                json={"query": ANILIST_QUERY, "variables": {"ids": chunk}},

                timeout=10,

            )

            r.raise_for_status()

            j = r.json() if r.content else {}

            media = (((j.get("data") or {}).get("Page") or {}).get("media") or []) or []

        except Exception: 

            media = []



        for m in media:

            try:

                aid = int(m.get("id"))

            except Exception:

                continue



            title = m.get("title") or {}

            coverImage = m.get("coverImage") or {}

            cover = coverImage.get("extraLarge") or coverImage.get("large") or None

            genres = ",".join((m.get("genres") or []))

            tags = ",".join([t.get("name") for t in (m.get("tags") or []) if isinstance(t, dict) and t.get("name")])



            row = by_id.get(aid)

            if row is None:

                row = AniListMetadataORM(

                    anilist_id=aid,

                    title_romaji=title.get("romaji"),

                    title_english=title.get("english"),

                    cover_image=cover,

                    season=m.get("season"),

                    season_year=m.get("seasonYear"),

                    format=m.get("format"),

                    genres=genres,

                    tags=tags,

                    fetched_at=now,

                )

                db.add(row)

                by_id[aid] = row

                created_or_updated = True

            else:

                # update only if present in response; keep existing otherwise

                row.title_romaji  = title.get("romaji")   or row.title_romaji

                row.title_english = title.get("english")  or row.title_english

                row.cover_image   = cover                 or row.cover_image

                row.season        = m.get("season")       or row.season

                row.season_year   = m.get("seasonYear")   or row.season_year

                row.format        = m.get("format")       or row.format

                row.genres        = genres                or row.genres

                row.tags          = tags                  or row.tags

                row.fetched_at    = now

                created_or_updated = True



    if created_or_updated:

        db.commit()



    return by_id



def _summary_for_user(db: Session, api_key: str, limit: int, only: Optional[str]) -> List[AnimeLogItem]:

    q = db.query(

        Logs.anime_id.label("anime_id"),

        func.count(Logs.id).label("count"),

        func.max(Logs.created_at).label("last_seen"),

    ).filter(Logs.api_key == api_key, Logs.anime_id.isnot(None))

    if only in ("scene", "audio"):

        q = q.filter(Logs.search_type == only)

    rows = q.group_by(Logs.anime_id).order_by(func.max(Logs.created_at).desc()).limit(limit).all()



    ids = [int(r.anime_id) for r in rows if r.anime_id is not None]

    anime = {a.id: a for a in db.query(Anime).filter(Anime.id.in_(ids)).all()}

    meta = _ensure_meta(db, ids)



    out = []

    for r in rows:

        aid = int(r.anime_id)

        m = meta.get(aid); a = anime.get(aid)

        out.append(AnimeLogItem(

            anime_id=aid,

            count=int(r.count),

            last_seen=r.last_seen,

            title_romaji=(m.title_romaji if m else None) or (a.title_romaji if a else None),

            title_english=(m.title_english if m else None) or (a.title_english if a else None),

            cover_image=_fallback_cover(aid, a, m),

            site_url=f"https://anilist.co/anime/{aid}",

        ))

    return out



@router.get("/me/logs/anime", response_model=List[AnimeLogItem])

def my_anime_log_summary(

    limit: int = Query(12, ge=1, le=50),

    only: Optional[str] = Query(None, description="scene | audio | all"),

    db: Session = Depends(get_db),

    current_user: User = Depends(get_current_user),

):

    return _summary_for_user(db, current_user.api_key, limit, only)



@router.get("/{user_id}/logs/anime", response_model=List[AnimeLogItem])

def user_anime_log_summary(

    user_id: int,

    limit: int = Query(12, ge=1, le=50),

    only: Optional[str] = Query(None, description="scene | audio | all"),

    db: Session = Depends(get_db),

    current_user: User = Depends(get_current_user),

):

    target = db.query(User).get(user_id)

    if not target: raise HTTPException(404, "User not found")

    if target.is_private and target.id != current_user.id:

        raise HTTPException(403, "This profile is private")

    return _summary_for_user(db, target.api_key, limit, only)



class LogsItem(BaseModel):

    log_id: int

    ts: str

    accuracy: Optional[float] = None

    song_id: Optional[int] = None

    anime_id: Optional[int] = None

    song_name: Optional[str] = None

    artist: Optional[str] = None

    anime_title: Optional[str] = None

    anilist_id: Optional[int] = None  # frontend can map later



    class Config:

        orm_mode = True



@router.get("/{user_id}/logs/audio", response_model=List[LogsItem])

def user_audio_logs(

    user_id: int,

    limit: int = Query(6, ge=1, le=50),

    before_id: int | None = Query(None, description="keyset: older than this log id"),

    response: Response = None,

    db: Session = Depends(get_db),

):

    _no_store(response)



    cols = [

        Logs.id.label("log_id"),

        Logs.created_at.label("ts"),

        Logs.accuracy.label("accuracy"),

        Logs.song_id.label("song_id"),

        Logs.anime_id.label("anime_id"),

        Song.song_name.label("song_name"),

        Song.artist.label("artist"),

        Anime.title_romaji.label("anime_title"),

    ]

    include_anilist = hasattr(AniListMetadata, "anime_id")

    if include_anilist:

        cols.append(AniListMetadata.anilist_id.label("anilist_id"))



    q = (

        db.query(*cols)

        .join(User, User.api_key == Logs.api_key)

        .outerjoin(Song,  Song.song_id == Logs.song_id)

        .outerjoin(Anime, Anime.id      == Logs.anime_id)

    )

    if include_anilist:

        q = q.outerjoin(AniListMetadata, AniListMetadata.anime_id == Logs.anime_id)



    # base filter

    q = q.filter(User.id == user_id, Logs.song_id.isnot(None))



    # keyset cursor (created_at,id)

    if before_id is not None:

        cur = db.get(Logs, before_id)

        if not cur:

            raise HTTPException(400, "Invalid cursor")

        q = q.filter(tuple_(Logs.created_at, Logs.id) < tuple_(cur.created_at, cur.id))



    rows = (

        q.order_by(Logs.created_at.desc(), Logs.id.desc())

         .limit(limit)

         .all()

    )



    out = []

    for r in rows:

        m = r._mapping if hasattr(r, "_mapping") else r

        ts_val = m["ts"]

        out.append(LogsItem(

            log_id=m["log_id"],

            ts=ts_val.isoformat() if isinstance(ts_val, datetime) else str(ts_val),

            accuracy=float(m["accuracy"]) if m["accuracy"] is not None else None,

            song_id=m["song_id"],

            anime_id=m["anime_id"],

            song_name=m.get("song_name") or "",

            artist=m.get("artist") or "",

            anime_title=m.get("anime_title") or None,

            anilist_id=m.get("anilist_id") if include_anilist else None,

        ))

    # (Optional) Return a cursor envelope if your client expects it

    return out



@router.delete("/replies/{reply_id}", response_model=Ok)

async def delete_reply(

    reply_id: int,

    db: Session = Depends(get_db),

    current_user: User = Depends(get_current_user),

):

    r = db.get(Reply, reply_id)

    if not r:

        raise HTTPException(404, "Reply not found")



    parent = db.get(Comment, r.comment_id) if r.comment_id else None

    post = db.get(Post, parent.post_id) if parent and parent.post_id else None

    post_owner_id = getattr(post, "user_id", None)

    is_admin = bool(getattr(current_user, "is_admin", False))



    if not _can_delete(current_user.id, r.user_id, post_owner_id, is_admin):

        raise HTTPException(403, detail={"reason": "not_authorized", "item_kind": "reply", "item_owner_id": r.user_id, "post_owner_id": post_owner_id, "requester_id": current_user.id})



    db.delete(r); db.commit()

    await _clear_comment_caches()

    return Ok()




@router.post("/comments/{comment_id}/replies")

async def create_reply(

    comment_id: int,

    content: str = Form(...),

    db: Session = Depends(get_db),

    current_user: User = Depends(get_current_user),

):

    post = _post_of_comment(db, comment_id)

    if not post:

        raise HTTPException(status_code=404, detail="Post not found")




    content = (content or "").strip()

    if not content:

        raise HTTPException(status_code=400, detail="Content cannot be empty")



    reply = Reply(comment_id=comment_id, user_id=current_user.id, content=content)

    db.add(reply); db.commit(); db.refresh(reply)



    u = db.get(User, reply.user_id)

    await _clear_comment_caches()

    return {

        "id": reply.id,

        "comment_id": reply.comment_id,

        "content": reply.content,

        "created_at": reply.created_at,

        "user": {"id": u.id if u else None, "display_name": u.display_name if u else "User", "avatar_url": _abs_avatar(u.avatar_url if u else None)},

    }


@router.get("/comments/{comment_id}/replies")

def get_replies(

    comment_id: int,

    db: Session = Depends(get_db),

    limit: int = Query(50, ge=1, le=100),

    before_id: int | None = Query(None, description="keyset cursor: older than this reply id"),

    response: Response = None,

):

    # Hard-disable HTTP caching so different users don't see stale results

    if response is not None:

        response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"

        response.headers["Pragma"] = "no-cache"

        response.headers["Expires"] = "0"



    # ensure parent exists

    parent = db.get(Comment, comment_id)

    if not parent:

        raise HTTPException(404, "Comment not found")



    # total for the toggle label

    total_count = db.scalar(

        select(func.count(Reply.id)).where(Reply.comment_id == comment_id)

    ) or 0



    base_q = (

        select(Reply)

        .where(Reply.comment_id == comment_id)

        .order_by(Reply.created_at.desc(), Reply.id.desc())

        .limit(limit)

    )



    if before_id is not None:

        cur = db.scalar(select(Reply).where(Reply.id == before_id))

        if not cur or cur.comment_id != comment_id:

            raise HTTPException(400, "Invalid cursor")

        base_q = (

            select(Reply)

            .where(

                and_(

                    Reply.comment_id == comment_id,

                    tuple_(Reply.created_at, Reply.id) < tuple_(cur.created_at, cur.id),

                )

            )

            .order_by(Reply.created_at.desc(), Reply.id.desc())

            .limit(limit)

        )



    rows = list(db.scalars(base_q))



    # has_more?

    has_more = False

    if rows:

        tail = rows[-1]

        has_more = bool(

            db.scalar(

                select(func.count(Reply.id)).where(

                    and_(

                        Reply.comment_id == comment_id,

                        tuple_(Reply.created_at, Reply.id) < tuple_(tail.created_at, tail.id),

                    )

                )

            )

        )



    # payload

    items = []

    for r in rows:

        u = db.get(User, r.user_id)

        items.append({

            "id": r.id,

            "comment_id": r.comment_id,

            "content": r.content,

            "created_at": r.created_at,

            "updated_at": getattr(r, "updated_at", None),

            "user": {

                "id": u.id if u else None,

                "display_name": u.display_name if u else "User",

                "avatar_url": _abs_avatar(u.avatar_url if u else None),

            },

        })



    return {

        "items": items,                                 # DESC (newest → older)

        "total_count": total_count,

        "has_more": has_more,

        "next_before_id": rows[-1].id if rows else None,

    }




@router.get("/posts/{post_id}/counts")

def get_post_counts(

    post_id: int,

    db: Session = Depends(get_db),

    current_user: User = Depends(get_current_user),

):

    post = db.get(Post, post_id)

    if not post:

        raise HTTPException(404, "Post not found")



    like_count = db.scalar(

        select(func.count(PostLike.id)).where(PostLike.post_id == post_id)

    ) or 0



    comment_count = db.scalar(

        select(func.count(Comment.id)).where(Comment.post_id == post_id)

    ) or 0



    liked_by_me = (

        db.scalar(

            select(func.count(PostLike.id)).where(

                PostLike.post_id == post_id, PostLike.user_id == current_user.id

            )

        ) == 1

    )



    # NEW: reshare counts/flag

    reshare_count = db.scalar(

        select(func.count(PostReshare.id)).where(PostReshare.post_id == post_id)

    ) or 0



    reshared_by_me = (

        db.scalar(

            select(func.count(PostReshare.id)).where(

                PostReshare.post_id == post_id, PostReshare.user_id == current_user.id

            )

        ) == 1

    )



    return {

        "post_id": post_id,

        "like_count": like_count,

        "comment_count": comment_count,

        "liked_by_me": liked_by_me,

        "reshare_count": reshare_count,       # <-- NEW

        "reshared_by_me": reshared_by_me,     # <-- NEW

    }





@router.post("/posts/counts")

def get_posts_counts(

    payload: PostCountsIn,

    db: Session = Depends(get_db),

    current_user: User = Depends(get_current_user),

):

    ids = list({i for i in payload.ids if isinstance(i, int)})

    if not ids:

        return []



    # likes

    like_rows = dict(db.execute(

        select(PostLike.post_id, func.count(PostLike.id))

        .where(PostLike.post_id.in_(ids))

        .group_by(PostLike.post_id)

    ).all())



    # comments

    comment_rows = dict(db.execute(

        select(Comment.post_id, func.count(Comment.id))

        .where(Comment.post_id.in_(ids))

        .group_by(Comment.post_id)

    ).all())



    # liked by me

    liked_rows = set(db.execute(

        select(PostLike.post_id)

        .where(PostLike.post_id.in_(ids), PostLike.user_id == current_user.id)

    ).scalars().all())



    # NEW: reshare counts

    reshare_rows = dict(db.execute(

        select(PostReshare.post_id, func.count(PostReshare.id))

        .where(PostReshare.post_id.in_(ids))

        .group_by(PostReshare.post_id)

    ).all())



    # NEW: reshared by me

    reshared_rows = set(db.execute(

        select(PostReshare.post_id)

        .where(PostReshare.post_id.in_(ids), PostReshare.user_id == current_user.id)

    ).scalars().all())



    out = []

    for pid in ids:

        out.append({

            "post_id": pid,

            "like_count": int(like_rows.get(pid, 0)),

            "comment_count": int(comment_rows.get(pid, 0)),

            "liked_by_me": pid in liked_rows,

            "reshare_count": int(reshare_rows.get(pid, 0)),      # <-- NEW

            "reshared_by_me": pid in reshared_rows,              # <-- NEW

        })

    return out





@router.patch("/comments/{comment_id}")

async def edit_comment(

    comment_id: int,

    payload: CommentUpdate,

    db: Session = Depends(get_db),

    current_user: User = Depends(get_current_user),

):

    c = db.get(Comment, comment_id)

    if not c:

        raise HTTPException(404, "Comment not found")

    if c.user_id != current_user.id and not getattr(current_user, "is_admin", False):

        raise HTTPException(403, detail={"reason": "not_owner", "owner_id": c.user_id, "requester_id": current_user.id})



    c.content = payload.content.strip()

    db.commit()

    await _clear_comment_caches()

    return {"ok": True, "id": c.id, "content": c.content}







@router.get("/feed/reshared")

def feed_reshared(

    db: Session = Depends(get_db),

    current_user: User = Depends(get_current_user),

    limit: int = 50,

):

    # people I follow

    followee_ids = select(Follow.following_id).where(Follow.follower_id == current_user.id)



    rows = (

        db.query(PostReshare)

          .join(Post, Post.id == PostReshare.post_id)

          .join(User, User.id == Post.user_id)

          .filter(PostReshare.user_id.in_(followee_ids.scalar_subquery()))

          .order_by(PostReshare.reshared_at.desc())

          .limit(limit)

          .all()

    )



    out = []

    for r in rows:

        payload = _post_payload(db, r.post, current_user.id)

        out.append({

            "reshared_at": r.reshared_at.isoformat(),

            "reshared_by": {

                "id": r.user.id,

                "display_name": r.user.display_name,

                "avatar_url": r.user.avatar_url,

            },

            "post": payload,

        })

    return out




@router.post("/comments/{comment_id}/replies-json")

def create_reply_json(

    comment_id: int,

    payload: CommentCreate,

    db: Session = Depends(get_db),

    current_user: User = Depends(get_current_user),

):

    post = _post_of_comment(db, comment_id)

    if not post:

        raise HTTPException(404, "Post not found")

    content = payload.content.strip()

    if not content:

        raise HTTPException(400, "Content cannot be empty")



    r = Reply(comment_id=comment_id, user_id=current_user.id, content=content)

    db.add(r); db.commit(); db.refresh(r)

    u = db.get(User, r.user_id)

    return {

        "id": r.id, "comment_id": r.comment_id, "content": r.content, "created_at": r.created_at,

        "user": {"id": u.id if u else None, "display_name": u.display_name if u else "User", "avatar_url": _abs_avatar(u.avatar_url if u else None)}

    }

@router.delete("/comments/{comment_id}", response_model=Ok)

async def delete_comment_adapter(

    comment_id: int,

    db: Session = Depends(get_db),

    current_user: User = Depends(get_current_user),

):

    # Load comment

    c = db.query(Comment).filter(Comment.id == comment_id).first()

    if not c:

        raise HTTPException(status_code=404, detail="Comment not found")



    # Permission: admin, comment author, or post owner

    post_owner_id = db.query(Post.user_id).filter(Post.id == c.post_id).scalar()

    is_admin = bool(getattr(current_user, "is_admin", False))

    allowed = _can_delete(current_user.id, c.user_id, post_owner_id, is_admin)

    _log_auth_decision(

        action="delete_comment",

        requester_id=current_user.id,

        item_kind="comment",

        item_owner_id=c.user_id,

        post_owner_id=post_owner_id,

        is_admin=is_admin,

        allowed=allowed,

    )

    if not allowed:

        raise HTTPException(status_code=403, detail="Not allowed to delete this item")



    # Soft-delete if there are replies; hard-delete otherwise

    has_replies = db.query(Reply).filter(Reply.comment_id == c.id).limit(1).first() is not None

    if has_replies:

        c.content = "[deleted]"

        try:

            c.deleted_at = datetime.utcnow()

        except Exception:

            pass

        db.add(c)

        soft = True

    else:

        db.delete(c)

        soft = False



    db.commit()



    try:

        await FastAPICache.clear(namespace="comments")

    except Exception:

        pass

    try:

        await FastAPICache.clear(namespace="replies")

    except Exception:

        pass



    return Ok(ok=True, id=comment_id, soft_deleted=soft)



@router.delete("/comment-items/{item_id}", response_model=Ok)

async def delete_comment_item(

    item_id: int,

    db: Session = Depends(get_db),

    current_user: User = Depends(get_current_user),

):

    kind, obj, post = _load_comment_item(db, item_id)  # ("comment"/"reply", ORM row, Post)

    if not obj:

        raise HTTPException(status_code=404, detail="Comment or reply not found")



    is_admin = bool(getattr(current_user, "is_admin", False))

    post_owner_id = getattr(post, "user_id", None)

    owner_id = getattr(obj, "user_id", None)



    allowed = _can_delete(current_user.id, owner_id, post_owner_id, is_admin)

    _log_auth_decision(

        action="delete_comment_item",

        requester_id=current_user.id,

        item_kind=kind or "unknown",

        item_owner_id=owner_id,

        post_owner_id=post_owner_id,

        is_admin=is_admin,

        allowed=allowed,

    )

    if not allowed:

        raise HTTPException(

            status_code=403,

            detail={

                "reason": "not_authorized",

                "item_kind": kind,

                "item_owner_id": owner_id,

                "post_owner_id": post_owner_id,

                "requester_id": current_user.id,

                "is_admin": is_admin,

            },

        )



    if kind == "comment":

        # If you don't have FK cascade, cleanup replies first

        db.query(Reply).filter(Reply.comment_id == obj.id).delete(synchronize_session=False)

        db.delete(obj)

    else:

        db.delete(obj)



    db.commit()



    try:

        await FastAPICache.clear(namespace="comments")

    except Exception:

        pass

    try:

        await FastAPICache.clear(namespace="replies")

    except Exception:

        pass



    return Ok()


@router.post("/posts/{post_id}/comments")

def create_comment(

    post_id: int,

    payload: dict,                    # expects {"content": "..."}; you can swap to a Pydantic model if you have one

    db: Session = Depends(get_db),

    current_user: User = Depends(get_current_user),

):

    post = db.get(Post, post_id)

    if not post:

        raise HTTPException(404, "Post not found")



    content = (payload or {}).get("content", "").strip()

    if not content:

        raise HTTPException(422, "Content is required")



    c = Comment(

        post_id=post_id,

        user_id=current_user.id,      # <-- authoritative source of truth

        content=content,

        created_at=datetime.now(timezone.utc),

    )

    db.add(c)

    db.commit()

    db.refresh(c)



    return {

        "id": c.id,

        "post_id": c.post_id,

        "content": c.content,

        "created_at": c.created_at,

        "user": {

            "id": current_user.id,

            "display_name": current_user.display_name or "User",

            "avatar_url": current_user.avatar_url,

        },

    }



# ----- DELETE COMMENT (DELETE /comments/{comment_id}) -----


    

@router.get("/posts/{post_id}/comments")

def list_comments(

    post_id: int,

    db: Session = Depends(get_db),

    limit: int = Query(50, ge=1, le=100),

    before_id: int | None = Query(None, description="Keyset cursor: show older than this comment id"),

    preview: bool = Query(False, description="Client may still trim locally"),

    response: Response = None,

):

    # no HTTP cache

    if response is not None:

        response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"

        response.headers["Pragma"] = "no-cache"

        response.headers["Expires"] = "0"



    # visibility predicate (handles both timestamp soft-delete and legacy "[deleted]" marker)

    visible = and_(

        Comment.post_id == post_id,

        or_(

            getattr(Comment, "deleted_at", None).is_(None) if hasattr(Comment, "deleted_at") else True,

            Comment.deleted_at.is_(None) if hasattr(Comment, "deleted_at") else True,  # defensive

        ),

        Comment.content != "[deleted]",

    )



    # total (visible only)

    total_count = db.scalar(select(func.count(Comment.id)).where(visible)) or 0



    # base query (newest → older)

    base_q = (

        select(Comment)

        .where(visible)

        .order_by(Comment.created_at.desc(), Comment.id.desc())

        .limit(limit)

    )



    if before_id is not None:

        cur = db.scalar(select(Comment).where(Comment.id == before_id))

        if not cur or cur.post_id != post_id:

            raise HTTPException(status_code=400, detail="Invalid cursor")



        # the cursor must also be visible; if it isn't, move the window below it anyway

        base_q = (

            select(Comment)

            .where(

                and_(

                    visible,

                    tuple_(Comment.created_at, Comment.id)

                    < tuple_(cur.created_at, cur.id),

                )

            )

            .order_by(Comment.created_at.desc(), Comment.id.desc())

            .limit(limit)

        )



    rows = list(db.scalars(base_q))

    items = [_comment_payload(db, c) for c in rows]



    # has_more?

    has_more = False

    if rows:

        tail = rows[-1]

        has_more = bool(

            db.scalar(

                select(func.count(Comment.id)).where(

                    and_(

                        visible,

                        tuple_(Comment.created_at, Comment.id)

                        < tuple_(tail.created_at, tail.id),

                    )

                )

            )

        )



    post = db.get(Post, post_id)



    return {

        "items": items,                             # DESC (newest → older)

        "total_count": total_count,

        "has_more": has_more,

        "next_before_id": rows[-1].id if rows else None,


    }

@router.get("/me/post-quota")

def get_post_quota(

    db: Session = Depends(get_db),

    current_user: User = Depends(get_current_user),

):

    tier_id = getattr(current_user, "anime_tier_id", 0) or 0

    subscribed = bool(getattr(current_user, "is_subscribed", False))

    is_premium = (tier_id >= 1) or subscribed



    last_own = (

        db.query(Post)

        .filter(Post.user_id == current_user.id)

        .order_by(Post.id.desc())

        .first()

    )



    next_allowed = None

    can_post = True



    if not is_premium and last_own is not None:

        created = (

            getattr(last_own, "created_at", None)

            or getattr(last_own, "created", None)

            or getattr(last_own, "timestamp", None)

        )

        if created is not None:

            if created.tzinfo is None:

                created = created.replace(tzinfo=timezone.utc)

            now = datetime.now(timezone.utc)

            next_allowed = created + timedelta(days=7)

            can_post = now >= next_allowed



    return {

        "is_premium": is_premium,

        "can_post": can_post,

        "next_allowed_post_at": next_allowed.isoformat() if next_allowed else None,

    }





# -------------------------------------------------

# POST /posts

# -------------------------------------------------

@router.post("/posts")

async def create_post(

    # non-defaults first (FastAPI requirement)

    background_tasks: BackgroundTasks,

    request: Request,

    db: Session = Depends(get_db),

    current_user: User = Depends(get_current_user),



    # optional form/multipart fields (work when not JSON)

    text: Optional[str] = Form(None),

    image: Optional[UploadFile] = File(None),   # kept

    file:  Optional[UploadFile] = File(None),   # legacy alias

    bg_color: Optional[str] = Form(None),



    # legacy helper field (JSON string list): '["A","B"]'

    poll_options_json: Optional[str] = Form(None),

    poll_closes_at: Optional[str] = Form(None),

    poll_multiple: Optional[bool] = Form(False),

    poll_allow_change: Optional[bool] = Form(True),

):

    """

    Accepts JSON or form/multipart for posts.

    If a poll is supplied (in any supported shape), creates Poll + PollOption rows

    and returns type:'poll' with poll/question/options in the payload.

    """



    # ---------- 0) Weekly post limit for non-pro users ----------

    # Mirror /me/post-quota logic here so backend is ALWAYS authoritative.

    tier_id = getattr(current_user, "anime_tier_id", 0) or 0

    subscribed = bool(getattr(current_user, "is_subscribed", False))

    is_premium = (tier_id >= 1) or subscribed



    if not is_premium:

        last = (

            db.query(Post)

            .filter(Post.user_id == current_user.id)

            .order_by(Post.id.desc())

            .first()

        )



        if last is not None:

            created = (

                getattr(last, "created_at", None)

                or getattr(last, "created", None)

                or getattr(last, "timestamp", None)

            )

            if created is not None:

                if created.tzinfo is None:

                    created = created.replace(tzinfo=timezone.utc)



                now = datetime.now(timezone.utc)

                next_allowed = created + timedelta(days=7)



                if now < next_allowed:

                    # Frontend can read next_allowed_post_at to show cool-down

                    raise HTTPException(

                        status_code=429,

                        detail={

                            "message": "Weekly post limit reached for free users.",

                            "next_allowed_post_at": next_allowed.isoformat(),

                        },

                    )



    # ---------- 1) Collect incoming data uniformly ----------

    ctype = (request.headers.get("content-type") or "").lower()

    body_json = None

    form_map = None



    if "application/json" in ctype:

        try:

            body_json = await request.json()

        except Exception:

            body_json = None

    else:

        try:

            form_map = await request.form()

        except Exception:

            form_map = None



    # Unified getters

    def _get_any(*keys, default=None):

        # priority: explicit function params -> JSON body -> form map

        for k in keys:

            if k == "text" and text is not None:

                return text

            if k == "bg_color" and bg_color is not None:

                return bg_color

            if k == "poll_options_json" and poll_options_json is not None:

                return poll_options_json

            if body_json and isinstance(body_json, dict) and k in body_json and body_json[k] is not None:

                return body_json[k]

            if form_map is not None and k in form_map:

                return form_map.get(k)

        return default



    # text/content/title fallbacks (what user typed becomes post.text)

    text_in = _get_any("text", "content", "title", default=None)

    if text_in is None and body_json:

        # nested poll.question is sometimes the only text provided

        text_in = (body_json.get("poll") or {}).get("question")



    # ---------- 2) Handle upload (if any) ----------

    image_url: Optional[str] = None

    image_preview_url: Optional[str] = None

    video_url: Optional[str] = None



    # If FastAPI didnt bind the UploadFile param for 'image', try to pull it from the form map,

    # and also tolerate 'file' as a legacy alias.

    if image is None:

        try:

            if form_map is None and "multipart/form-data" in ctype:

                form_map = await request.form()

        except Exception:

            form_map = None

        if form_map is not None:

            cand = form_map.get("image") or form_map.get("file")

            # Starlette returns UploadFile for file parts

            if hasattr(cand, "filename") and hasattr(cand, "content_type"):

                image = cand  # type: ignore[assignment]



    if image is not None:

        ct = (image.content_type or "").lower()

        fn = (image.filename or "").strip()

        try:

            print(f"[create_post] received file: ct={ct or ''} name={fn or ''}")

        except Exception:

            pass



        if ct not in ALLOWED:

            raise HTTPException(400, "Unsupported media type")



        os.makedirs(UPLOAD_DIR, exist_ok=True)

        ext = EXT_MAP[ct]

        base_uuid = str(uuid.uuid4())

        raw_name = f"{base_uuid}{ext}"

        raw_path = os.path.join(UPLOAD_DIR, raw_name)



        with open(raw_path, "wb") as buf:

            shutil.copyfileobj(image.file, buf)



        try:

            if ct in ("image/gif", "image/webp"):

                video_url, poster_url = _animated_to_mp4_and_poster(raw_path, base_uuid)

                image_url = poster_url

                image_preview_url = poster_url

                try:

                    os.remove(raw_path)

                except Exception:

                    pass

            else:

                _resize_still_inplace(raw_path, MAX_W, MAX_H)

                image_url = f"/uploads/{raw_name}"

                image_preview_url = image_url

        except Exception as e:

            print(f"[uploads] processing failed: {e}")

            image_url = f"/uploads/{raw_name}"

            image_preview_url = image_url

    else:

        # No file part at all

        try:

            print("[create_post] no file received (no 'image' or 'file' part)")

        except Exception:

            pass



    # ---------- 3) Normalize bg color (premium only) ----------

    color = _normalize_hex_color(_get_any("bg_color", default=None))

    if color and not is_premium:

        color = None



    # ---------- 4) Create the Post row (no 'type' kwarg!) ----------

    post = Post(

        user_id=current_user.id,

        text=(text_in or ""),

        image_url=image_url,

        background_color=color,

    )

    try:

        db.add(post)

        db.commit()

        db.refresh(post)

    except Exception:

        db.rollback()

        raise



    # ---------- 5) Detect & create a Poll (accept many shapes) ----------

    def _coerce_list(v) -> List[str]:

        if v is None:

            return []

        if isinstance(v, (list, tuple, set)):

            return [str(x).strip() for x in v if str(x).strip()]

        if isinstance(v, str):

            s = v.strip()

            # JSON list?

            try:

                parsed = json.loads(s)

                if isinstance(parsed, list):

                    return [str(x).strip() for x in parsed if str(x).strip()]

            except Exception:

                pass

            # CSV/semicolon

            sep = "," if "," in s else ";"

            return [t.strip() for t in s.split(sep) if t.strip()]

        return []



    poll_type = (_get_any("type") or "").lower()

    poll_obj  = body_json.get("poll") if isinstance(body_json, dict) else None



    # collect options from everywhere

    options_sources = []

    if poll_obj and isinstance(poll_obj, dict):

        options_sources.append(poll_obj.get("options"))

    options_sources += [

        _get_any("options"),

        _get_any("options[]"),

        _get_any("choices"),

        _get_any("answers"),

        _get_any("poll_options_json"),

    ]

    if form_map is not None:

        repeated = []

        for k in ("options", "options[]", "choices", "answers"):

            if k in form_map:

                vs = form_map.getlist(k)

                if vs:

                    repeated.extend(vs)

        if repeated:

            options_sources.append(repeated)



    all_opts: List[str] = []

    for src in options_sources:

        all_opts.extend(_coerce_list(src))



    # stable unique

    seen = set()

    opts = [x for x in all_opts if not (x in seen or seen.add(x))]



    # question

    question = None

    if poll_obj and isinstance(poll_obj, dict):

        question = (poll_obj.get("question") or "").strip() or None

    if not question:

        question = (_get_any("question") or "").strip() or None

    if not question:

        question = (text_in or "").strip() or None



    # intention check

    is_poll_intended = (poll_type == "poll") or bool(opts and question)



    if is_poll_intended and len(opts) >= 2:

        # parse closes_at

        closes_at_dt: Optional[datetime] = None

        closes_at_raw = _get_any("poll_closes_at")

        if closes_at_raw:

            s = str(closes_at_raw).strip()

            if s.endswith("Z"):

                s = s[:-1] + "+00:00"

            try:

                closes_at_dt = datetime.fromisoformat(s)

                if closes_at_dt.tzinfo is None:

                    closes_at_dt = closes_at_dt.replace(tzinfo=timezone.utc)

            except Exception:

                closes_at_dt = None



        multiple = bool((poll_obj or {}).get("multiple", poll_multiple))

        allow_change = bool((poll_obj or {}).get("allow_change", poll_allow_change))



        try:

            # Create Poll row in a schema-tolerant way

            from models import Poll as PollORM



            p = PollORM(post_id=post.id)

            # Discover Poll columns

            poll_cols = {r[0] for r in db.execute(

                sql_text("""

                    SELECT column_name

                    FROM information_schema.columns

                    WHERE table_name = 'polls'

                """)

            ).all()}



            q_field = None

            for cand in ("question", "text", "prompt", "title", "name"):

                if cand in poll_cols:

                    q_field = cand

                    break



            if q_field:

                setattr(p, q_field, question or "")

            # set optional flags if those columns exist

            if "closes_at" in poll_cols:

                setattr(p, "closes_at", closes_at_dt)

            if "multiple" in poll_cols:

                setattr(p, "multiple", bool(multiple))

            if "allow_change" in poll_cols or "allow_changes" in poll_cols:

                setattr(

                    p,

                    "allow_change" if "allow_change" in poll_cols else "allow_changes",

                    bool(allow_change),

                )



            db.add(p)

            db.flush()  # ensure p.id



            # ----- Insert options (schema-aware) -----

            opt_cols = {r[0] for r in db.execute(

                sql_text("""

                    SELECT column_name

                    FROM information_schema.columns

                    WHERE table_name = 'poll_options'

                """)

            ).all()}



            use_position = "position" in opt_cols

            use_idx      = "idx" in opt_cols

            has_vcount   = "vote_count" in opt_cols



            for i, opt_text in enumerate(opts):

                if not opt_text:

                    continue

                params = {"pid": p.id, "text": opt_text, "i": i, "vc": 0}



                if use_position:

                    if has_vcount:

                        db.execute(

                            sql_text("INSERT INTO poll_options (poll_id, text, position, vote_count) "

                                     "VALUES (:pid, :text, :i, :vc)"),

                            params,

                        )

                    else:

                        db.execute(

                            sql_text("INSERT INTO poll_options (poll_id, text, position) "

                                     "VALUES (:pid, :text, :i)"),

                            params,

                        )

                elif use_idx:

                    if has_vcount:

                        db.execute(

                            sql_text("INSERT INTO poll_options (poll_id, text, idx, vote_count) "

                                     "VALUES (:pid, :text, :i, :vc)"),

                            params,

                        )

                    else:

                        db.execute(

                            sql_text("INSERT INTO poll_options (poll_id, text, idx) "

                                     "VALUES (:pid, :text, :i)"),

                            params,

                        )

                else:

                    if has_vcount:

                        db.execute(

                            sql_text("INSERT INTO poll_options (poll_id, text, vote_count) "

                                     "VALUES (:pid, :text, :vc)"),

                            params,

                        )

                    else:

                        db.execute(

                            sql_text("INSERT INTO poll_options (poll_id, text) "

                                     "VALUES (:pid, :text)"),

                            params,

                        )



            db.commit()

            db.refresh(post)



            log.info("CREATE_POST/poll_detect: %s", json.dumps({

                "content_type": ctype,

                "is_poll_intended": True,

                "question": question,

                "options": opts[:8],

            }))



        except Exception as e:

            db.rollback()

            print(f"[poll] create failed for post {post.id}: {e}")



    # ---------- 6) Background Discord task ----------

    if not getattr(post, "discord_thread_id", None):

        background_tasks.add_task(publish_to_discord_forum_sync, post.id, image_preview_url)



    # ---------- 7) Response payload ----------

    payload = _post_payload(db, post, current_user.id)

    payload.update(

        {

            "image_preview_url": image_preview_url or _preview_url_for(image_url),

            "video_url": video_url or _guess_video_sibling(image_url),

        }

    )



    try:

        log.info("CREATE_POST/return: %s", json.dumps({

            "post_id": post.id,

            "type": payload.get("type"),

            "question": payload.get("poll", {}).get("question") if payload.get("poll") else None,

            "options": [o.get("text") for o in payload.get("poll", {}).get("options", [])]

            if payload.get("poll") else None,

        }))

    except Exception:

        pass



    return {"status": "ok", "post": payload}

# -------- Read single post (fixes your 405 on verify) --------

@router.get("/posts/{post_id}")

def get_post(post_id: int,

             db: Session = Depends(get_db),

             current_user: User = Depends(get_current_user)):

    post = db.get(Post, post_id)

    if not post:

        raise HTTPException(404, "Post not found")

    return {"status": "ok", "post": _post_payload(db, post, current_user.id)}



# -------- Read only the poll snapshot (optional convenience) --------

@router.get("/posts/{post_id}/poll")

def get_post_poll(post_id: int,

                  db: Session = Depends(get_db),

                  current_user: User = Depends(get_current_user)):

    post = db.get(Post, post_id)

    if not post or not getattr(post, "poll", None):

        raise HTTPException(404, "Poll not found")

    return {"status": "ok", "poll": _post_payload(db, post, current_user.id).get("poll")}



# -------- Close a poll now (owner/admin) --------

@router.post("/posts/{post_id}/poll/close")

def close_poll_now(post_id: int,

                   db: Session = Depends(get_db),

                   current_user: User = Depends(get_current_user)):

    from models import Poll as PollORM

    post = db.get(Post, post_id)

    if not post or not getattr(post, "poll", None):

        raise HTTPException(404, "Poll not found")



    # Only post owner or admin can close

    if post.user_id != current_user.id and not getattr(current_user, "is_admin", False):

        raise HTTPException(403, "Not authorized to close this poll")



    poll: PollORM = post.poll

    poll.closes_at = datetime.now(timezone.utc)

    db.add(poll); db.commit(); db.refresh(post)

    return {"status": "closed", "post": _post_payload(db, post, current_user.id)}

TOPBOT_USER_ID = int(os.getenv("WEEKLY_TOP_USER_ID", "1"))   # owner of the auto post

MIN_HITS = int(os.getenv("WEEKLY_TOP_MIN_HITS", "3"))        # noise guard

ET = pytz.timezone("America/New_York")




def _coalesce_accuracy():

    """Use Logs.accuracy if available, else Logs.status (your older float column)."""

    try:

        return func.coalesce(Logs.accuracy, Logs.status)

    except Exception:

        return Logs.status





def _build_post_text(top: dict) -> str:

    bits = []

    if top.get("season"): bits.append(str(top["season"]))

    if top.get("year"): bits.append(str(top["year"]))

    meta = (" · ".join(bits)) if bits else ""

    header = f"Top Find of the Week: {top['title']}" + (f" ({meta})" if meta else "") 
    desc = f"Found {top['hits']} times last week (avg conf {top['avg_conf']:.3f})."

    return f"{header}\n{desc}"




def _safe_cover(top: dict) -> Optional[str]:

    url = (top or {}).get("cover")

    if isinstance(url, str) and url.startswith("http"):

        return url

    aid = (top or {}).get("anime_id")

    return f"https://img.anili.st/media/{aid}" if aid else None




def _strip_html(s: str | None, max_len=240) -> str:

    if not s: return ""

    txt = re.sub(r"<[^>]+>", "", s)        # strip tags

    txt = re.sub(r"\s+", " ", txt).strip()

    return txt if len(txt) <= max_len else txt[: max_len - 1] + "…"



def _anilist_fetch(aid: int) -> dict:

    q = """

    query ($id: Int!) {

      Media(id: $id, type: ANIME) {

        id

        title { romaji english }

        coverImage { large extraLarge }

        bannerImage

        description(asHtml: true)

        season

        seasonYear

        format

        siteUrl

      }

    }"""

    try:

        r = requests.post("https://graphql.anilist.co",

                          json={"query": q, "variables": {"id": aid}},

                          timeout=8)

        r.raise_for_status()

        m = (r.json()["data"]["Media"])

        title = m["title"]["romaji"] or m["title"]["english"] or f"Anime #{aid}"

        cover = m["bannerImage"] or m["coverImage"]["extraLarge"] or m["coverImage"]["large"]

        return {

            "title": title,

            "cover": cover,

            "banner": m["bannerImage"],

            "desc": _strip_html(m.get("description")),

            "season": m.get("season"),

            "year": m.get("seasonYear"),

            "format": m.get("format"),

            "url": m.get("siteUrl") or f"https://anilist.co/anime/{aid}",

        }

    except Exception:

        # fallback to generic cover

        return {

            "title": f"Anime #{aid}",

            "cover": f"https://img.anili.st/media/{aid}.jpg",

            "desc": "",

            "season": None, "year": None, "format": None,

            "url": f"https://anilist.co/anime/{aid}",

        }



    
def _create_weekly_post_and_discord(db: Session, top: dict) -> dict:

    aid = int(top["anime_id"])

    meta = _anilist_fetch(aid)

    # prefer banner if available

    cover_url = meta["cover"]

    # build text with short summary + link

    bits = [b for b in [meta.get("season"), meta.get("year")] if b]

    hdr  = f"a Top Find of the Week: {meta['title']}" + (f" ({' · '.join(map(str,bits))})" if bits else "") 
    desc = f"Found {top['hits']} times last week (avg conf {top['avg_conf']:.3f})."

    summary = f"\n{meta['desc']}" if meta["desc"] else ""

    link = f"\n{meta['url']}"

    post = Post(

        user_id=TOPBOT_USER_ID,          # ← set WEEKLY_TOP_USER_ID to your “TopFind” user id

        text=f"{hdr}\n{desc}{summary}{link}",

        image_url=cover_url,             # absolute (AniList) URL

        background_color="#10B981",

    )

    db.add(post); db.commit(); db.refresh(post)

    try:

        publish_to_discord_forum_sync(post.id, cover_url)  # embed picks this image

    except Exception as e:

        print("[weekly-top] discord publish failed:", e)

    return {"post_id": post.id}


_ANILIST_HOSTS = {"img.anili.st", "anilist.co", "s4.anilist.co"}

def _fix_anilist_cdn(u: Optional[str]) -> Optional[str]:

    """

    AniList's cdn path /media/<id> works, but the .jpg suffix can 400.

    Normalize a few common cases so Discord can fetch the image.

    """

    if not u:

        return u

    try:

        from urllib.parse import urlparse, urlunparse

        pr = urlparse(u)

        host = pr.netloc.lower()

        if host == "img.anili.st" and pr.path.startswith("/media/"):

            # drop extension: /media/21707.jpg -> /media/21707

            path = re.sub(r"\.(jpg|jpeg|png|webp)$", "", pr.path, flags=re.I)

            return urlunparse((pr.scheme, pr.netloc, path, "", "", ""))

        # leave s4.anilist.co “coverImage.*.jpg” URLs alone (they’re valid)

        return u

    except Exception:

        return u
        




# ---- Public endpoints (admin/preview/manual) ----




# ---- Scheduler hook (call from your FastAPI app startup) ----


    
    
def _is_system_post_row(p) -> bool:

    try:

        return int(getattr(p, "user_id", 0)) == int(TOPBOT_USER_ID)

    except Exception:

        return False
        
        
@router.get("/feed/system")

def get_system_feed(

    db: Session = Depends(get_db),

    current_user: User = Depends(get_current_user),

    limit: int = Query(50, ge=1, le=100),

    before_id: int | None = Query(None, description="keyset: older than this post id"),

):

    base = (db.query(Post).options(selectinload(Post.poll).selectinload(Poll.options)).filter(Post.user_id == TOPBOT_USER_ID))



    if before_id is not None:

        cur = db.get(Post, before_id)

        if not cur:

            raise HTTPException(400, "Invalid cursor")

        base = base.filter(

            tuple_(Post.created_at, Post.id) < tuple_(cur.created_at, cur.id)

        )



    rows = (

        base.order_by(Post.created_at.desc(), Post.id.desc())

            .limit(limit)

            .all()

    )



    items = [_post_payload(db, p, current_user.id) for p in rows]



    # has_more?

    has_more = False


    if rows:

        tail = rows[-1]

        has_more = bool(

            db.scalar(

                select(func.count(Post.id)).where(

                    and_(

                        Post.user_id == TOPBOT_USER_ID,

                        tuple_(Post.created_at, Post.id)

                        < tuple_(tail.created_at, tail.id),

                    )

                )

            )

        )



    return {

        "items": items,

        "has_more": has_more,

        "next_before_id": rows[-1].id if rows else None,

    }

