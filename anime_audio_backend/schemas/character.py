from datetime import datetime
from typing import Optional

from pydantic import BaseModel


class CharacterGenerateRequest(BaseModel):
    prompt: str
    style: str
    art_style: str = "modern_anime"
    gender: str
    hair: str
    eyes: str
    outfit: str
    mood: str


class CharacterSaveRequest(BaseModel):
    prompt: str
    style: str
    art_style: str = "modern_anime"
    gender: str
    hair: str
    eyes: str
    outfit: str
    mood: str
    image_url: str
    is_favorite: bool = False
    name: Optional[str] = None
    backstory: Optional[str] = None
    story_scene: Optional[str] = None


class CharacterFavoriteRequest(BaseModel):
    is_favorite: bool


class CharacterResponse(BaseModel):
    id: int
    user_id: Optional[int] = None
    prompt: str
    style: str
    art_style: str = "modern_anime"
    gender: str
    hair: str
    eyes: str
    outfit: str
    mood: str
    image_url: str
    is_favorite: bool = False
    name: Optional[str] = None
    backstory: Optional[str] = None
    story_scene: Optional[str] = None
    created_at: datetime

    class Config:
        from_attributes = True