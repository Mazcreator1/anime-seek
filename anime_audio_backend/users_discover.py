# users_discover.py
from __future__ import annotations

from datetime import datetime, timedelta
from typing import List, Optional, Literal

from fastapi import APIRouter, Depends, Query, HTTPException, Header
from pydantic import BaseModel
from sqlalchemy import func, or_, and_, exists, desc
from sqlalchemy.orm import Session
from sqlalchemy import or_
from database import get_db
from models import User, Follow, UserLike, Logs

router = APIRouter(prefix="/users", tags=["users"])


# ---------- Response schema ----------
class UserLite(BaseModel):
    id: int
    display_name: str
    avatar_url: Optional[str] = None
    top_line: Optional[str] = ""
    bio: Optional[str] = ""
    like_count: int
    follower_count: int
    is_following: bool
    is_liked: bool


# ---------- Helpers ----------
def _avatar_with_v(url: Optional[str], updated_at: Optional[datetime]) -> Optional[str]:
    if not url:
        return None
    if not updated_at:
        return url
    v = int(updated_at.timestamp() * 1000)
    sep = "&" if "?" in url else "?"
    return f"{url}{sep}v={v}"


def get_current_user_optional(
    db: Session = Depends(get_db),
    authorization: Optional[str] = Header(None),
) -> Optional[User]:
    """
    Lightweight optional auth:
    - Accepts 'Authorization: Bearer <api_key>'
    - Returns the User or None
    """
    if not authorization:
        return None
    parts = authorization.split()
    if len(parts) == 2 and parts[0].lower() == "bearer":
        api_key = parts[1]
        return db.query(User).filter(User.api_key == api_key).first()
    return None


# ---------- Endpoint ----------
# users_discover.py
from typing import Optional, List
from fastapi import APIRouter, Depends, Query
from sqlalchemy import or_, func
from sqlalchemy.orm import Session

from database import get_db
from models import User, Follow, UserLike
from auth_utils import get_current_user  # <-- make sure this import exists

router = APIRouter(prefix="/users", tags=["users"])

def _abs_avatar(u: str | None) -> str | None:
    if not u:
        return None
    u = u.strip()
    return f"https://anime-seek.com{u}" if u.startswith("/uploads") else u

@router.get("/discover")
def discover_users(
    q: Optional[str] = Query(None),
    page: int = Query(1, ge=1),
    per: int  = Query(24, ge=1, le=100),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),  # <-- only inside function
):
    # base query (skip me)
    base = db.query(User).filter(User.id != current_user.id)

    # search by display_name or top_line
    if q is not None and q.strip() != "":
        q_ = f"%{q.strip()}%"
        base = base.filter(or_(User.display_name.ilike(q_), User.top_line.ilike(q_)))

    rows: List[User] = (
        base.order_by(User.created_at.desc())
            .offset((page - 1) * per)
            .limit(per)
            .all()
    )
    if not rows:
        return {"items": [], "next_page": None}

    ids = [u.id for u in rows]

    # follows_by_me
    follow_ids = {
        uid for (uid,) in db.query(Follow.following_id)
            .filter(Follow.follower_id == current_user.id,
                    Follow.following_id.in_(ids)).all()
    }

    # liked_by_me
    liked_ids = {
        uid for (uid,) in db.query(UserLike.target_user_id)
            .filter(UserLike.liker_user_id == current_user.id,
                    UserLike.target_user_id.in_(ids)).all()
    }

    # counts
    like_counts = dict(
        db.query(UserLike.target_user_id, func.count(UserLike.id))
          .filter(UserLike.target_user_id.in_(ids))
          .group_by(UserLike.target_user_id)
          .all()
    )
    follower_counts = dict(
        db.query(Follow.following_id, func.count(Follow.id))
          .filter(Follow.following_id.in_(ids))
          .group_by(Follow.following_id)
          .all()
    )

    items = []
    for u in rows:
        follows_flag = u.id in follow_ids
        liked_flag   = u.id in liked_ids
        items.append({
            "id": u.id,
            "display_name": u.display_name,
            "avatar_url": _abs_avatar(u.avatar_url) or "/uploads/user_avatars/default_avatar.jpg",
            "top_line": u.top_line or "",
            "follows_by_me": follows_flag,
            "liked_by_me":   liked_flag,
            # legacy aliases (your Flutter already reads these)
            "is_following": follows_flag,
            "is_liked":     liked_flag,
            "like_count": int(like_counts.get(u.id, 0)),
            "follower_count": int(follower_counts.get(u.id, 0)),
        })

    next_page = page + 1 if len(rows) == per else None
    return {"items": items, "next_page": next_page}

