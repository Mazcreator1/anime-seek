# metadata_service.py

import json
from datetime import datetime
from sqlalchemy.orm import Session
from models import AniListMetadata
from typing import Optional

def store_anime_metadata(raw: dict, db: Session):
    media = raw["data"]["Media"]
    meta = (
        db.query(AniListMetadata)
          .filter_by(anilist_id=media["id"])
          .one_or_none()
    )
    if not meta:
        meta = AniListMetadata(anilist_id=media["id"])
    # map fields
    meta.title_romaji  = media["title"]["romaji"]
    meta.title_english = media["title"].get("english")
    meta.description   = media.get("description")
    meta.cover_image   = media["coverImage"]["large"]
    meta.season        = media.get("season")
    meta.season_year   = media.get("seasonYear")
    meta.format        = media.get("format")
    meta.genres        = json.dumps(media.get("genres", []))
    meta.tags          = json.dumps([t["name"] for t in media.get("tags", [])])
    meta.fetched_at    = datetime.utcnow()

    db.add(meta)
    db.commit()
