from pydantic import BaseModel
from typing import Optional, List

class SceneChallengeOut(BaseModel):
    id: int
    anilist_id: Optional[int] = None
    episode: Optional[int] = None
    timestamp: Optional[str] = None
    image_url: str
    difficulty: str
    hints: List[str]

    class Config:
        from_attributes = True


class SceneChallengeSubmitIn(BaseModel):
    guessed_title: str
    hints_used: int = 0
    time_taken_ms: Optional[int] = None
    mode: str = "endless"


class SceneChallengeSubmitOut(BaseModel):
    correct: bool
    answer: str
    episode: Optional[int] = None
    timestamp: Optional[str] = None
    anilist_id: Optional[int] = None