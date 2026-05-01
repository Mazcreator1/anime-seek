# routes/badges.py

from typing import List
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import desc

from models import User, Badge
from auth_utils import get_current_user
from database import get_db
from analytics import get_my_analytics
from utils.badge_util import assign_badges
from utils.badge_desc import badge_descriptions

router = APIRouter()

@router.get("/users/{user_id}/badges")
def get_user_badges(
    user_id: int,
    db: Session = Depends(get_db),
    me: User = Depends(get_current_user),
):
    # Find the target user first
    target = db.get(User, user_id)
    if not target:
        raise HTTPException(status_code=404, detail="User not found")

    # If requesting your own badges, recompute/assign before reading
    if me.id == user_id:
        analytics = get_my_analytics(db=db, me=me)
        assign_badges(me, analytics, db)
        db.refresh(me)

    # IMPORTANT: Badge linkage is via api_key → query by api_key
    badges: List[Badge] = (
        db.query(Badge)
          .filter(Badge.api_key == target.api_key)
          .order_by(desc(Badge.unlocked_at), desc(Badge.id))
          .all()
    )

    return [
        {
            "name": b.name,
            "description": badge_descriptions.get(b.name, ""),
            "unlocked_at": b.unlocked_at.isoformat() if getattr(b, "unlocked_at", None) else None,
        }
        for b in badges
    ]
