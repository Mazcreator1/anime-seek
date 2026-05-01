# routes/admin_market.py

from __future__ import annotations

from datetime import datetime, timezone
from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from auth_utils import require_admin
from database import get_db
from models import Market, MarketOutcome, User
from schemas.admin_market import AdminMarketCreate
from utils.slug import slugify

router = APIRouter(prefix="/admin/markets", tags=["Admin_Markets"])


def _norm_label(o) -> str:
    """
    Accept either:
      - {"label": "YES"}
      - MarketOutcomeCreate(label="YES")
      - "YES"
    Returns normalized uppercase label.
    """
    if isinstance(o, dict):
        v = o.get("label") or ""
    else:
        v = getattr(o, "label", None) or str(o or "")
    return v.strip().upper()


@router.post("", status_code=status.HTTP_201_CREATED)
def create_market(
    payload: AdminMarketCreate,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin),  # HARD ADMIN GUARD
    
):
    # 1) Time validation
    if not (payload.open_time < payload.close_time < payload.resolve_time):
        raise HTTPException(
            status_code=400,
            detail="Invalid market timing: must be open < close < resolve",
        )

    # 2) Slug generation & uniqueness
    slug = slugify(payload.title)
    exists = db.query(Market).filter(Market.slug == slug).first()
    if exists:
        raise HTTPException(status_code=400, detail="Market with this slug already exists")

    # 3) Resolution source validation
    allowed_sources = {"manual", "anilist", "mal"}
    if payload.resolution_source not in allowed_sources:
        raise HTTPException(status_code=400, detail="Invalid resolution source")

    if payload.resolution_source == "anilist":
        if not payload.resolution_data or "anilist_id" not in payload.resolution_data:
            raise HTTPException(status_code=400, detail="AniList resolution requires anilist_id")

    # 4) Outcomes validation
    if not payload.outcomes or len(payload.outcomes) < 2:
        raise HTTPException(status_code=400, detail="At least two outcomes are required")

    labels: List[str] = []
    for o in payload.outcomes:
        lab = _norm_label(o)
        if not lab:
            raise HTTPException(status_code=400, detail="Outcome label cannot be empty")
        labels.append(lab)

    # Model 1 hard rule: YES/NO only
    if set(labels) != {"YES", "NO"}:
        raise HTTPException(
            status_code=400,
            detail="Model 1 markets must have outcomes YES and NO",
        )

    # 5) Create market
    market = Market(
        slug=slug,
        title=payload.title,
        description=payload.description,
        category=payload.category,
        open_time=payload.open_time,
        close_time=payload.close_time,
        resolve_time=payload.resolve_time,
        resolution_source=payload.resolution_source,
        resolution_data=payload.resolution_data,
        status="open",
        created_at=datetime.now(timezone.utc),
    )

    db.add(market)
    db.flush()  # ensures market.id exists

    # 6) Create outcomes
    # Use stable order and de-dupe.
    for label in ["YES", "NO"]:
        db.add(MarketOutcome(market_id=market.id, label=label, is_winner=None))

    db.commit()
    db.refresh(market)

    return {
        "id": market.id,
        "slug": market.slug,
        "status": market.status,
        "title": market.title,
        "description": market.description,
        "category": market.category,
        "open_time": market.open_time,
        "close_time": market.close_time,
        "resolve_time": market.resolve_time,
        "resolution_source": market.resolution_source,
        "resolution_data": market.resolution_data,
        "outcomes": ["YES", "NO"],
    }
