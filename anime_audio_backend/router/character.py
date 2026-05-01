from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from database import get_db
from auth_utils import get_current_user
from models import User, AnimeTiers
from db_models.generated_character import GeneratedCharacter
from schemas.character import (
    CharacterFavoriteRequest,
    CharacterGenerateRequest,
    CharacterResponse,
    CharacterSaveRequest,
)
from services.character_generation_service import CharacterGenerationService

router = APIRouter(prefix="/character", tags=["character"])
generation_service = CharacterGenerationService()

ALLOWED_CHARACTER_TIERS = {"otaku", "senpai", "kami"}


def _is_admin_user(user: User) -> bool:
    return (
        getattr(user, "is_admin", False) is True
        or getattr(user, "is_superuser", False) is True
        or str(getattr(user, "role", "")).strip().lower() == "admin"
        or str(getattr(user, "display_name", "")).strip().lower() == "administrator"
    )


def _get_user_tier_name(user: User, db: Session) -> str:
    if getattr(user, "anime_tier_id", None) is None:
        return ""

    tier = db.get(AnimeTiers, user.anime_tier_id)
    if not tier:
        return ""

    return str(getattr(tier, "name", "")).strip().lower()


def _require_character_generation_tier(user: User, db: Session) -> None:
    if _is_admin_user(user):
        return

    tier_name = _get_user_tier_name(user, db)

    if tier_name not in ALLOWED_CHARACTER_TIERS:
        raise HTTPException(
            status_code=403,
            detail="Character generation with backstory is available for Otaku tier and above.",
        )


@router.post("/generate", response_model=CharacterResponse)
async def generate_character(
    payload: CharacterGenerateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if not current_user or current_user.id is None:
        raise HTTPException(status_code=401, detail="Invalid authenticated user")

    _require_character_generation_tier(current_user, db)

    generated = await generation_service.generate(payload)

    record = GeneratedCharacter(**generated, user_id=current_user.id)
    db.add(record)
    db.commit()
    db.refresh(record)

    return record


@router.get("/history", response_model=list[CharacterResponse])
async def get_character_history(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    items = (
        db.query(GeneratedCharacter)
        .filter(GeneratedCharacter.user_id == current_user.id)
        .order_by(GeneratedCharacter.created_at.desc())
        .limit(50)
        .all()
    )
    return items


@router.post("/save", response_model=CharacterResponse)
async def save_character(
    payload: CharacterSaveRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if not current_user or current_user.id is None:
        raise HTTPException(status_code=401, detail="Invalid authenticated user")

    record = GeneratedCharacter(**payload.model_dump(), user_id=current_user.id)
    db.add(record)
    db.commit()
    db.refresh(record)
    return record


@router.patch("/{character_id}/favorite", response_model=CharacterResponse)
async def update_favorite(
    character_id: int,
    payload: CharacterFavoriteRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    record = (
        db.query(GeneratedCharacter)
        .filter(
            GeneratedCharacter.id == character_id,
            GeneratedCharacter.user_id == current_user.id,
        )
        .first()
    )

    if not record:
        raise HTTPException(status_code=404, detail="Character not found")

    record.is_favorite = payload.is_favorite
    db.commit()
    db.refresh(record)
    return record


@router.post("/variation")
async def generate_variation(data: dict):
    return []