from sqlalchemy import Column, Integer, String, Boolean, ForeignKey, DateTime, Text, Float
from sqlalchemy.sql import func
from database import Base

class SceneChallenge(Base):
    __tablename__ = "scene_challenges"

    id = Column(Integer, primary_key=True, index=True)
    anilist_id = Column(Integer, nullable=True, index=True)
    anime_title = Column(String(255), nullable=False, index=True)
    anime_title_romaji = Column(String(255), nullable=True)
    anime_title_english = Column(String(255), nullable=True)

    episode = Column(Integer, nullable=True)
    timestamp = Column(String(32), nullable=True)

    image_url = Column(Text, nullable=False)
    difficulty = Column(String(20), nullable=False, default="easy")

    hint_1 = Column(String(255), nullable=True)
    hint_2 = Column(String(255), nullable=True)
    hint_3 = Column(String(255), nullable=True)

    is_daily = Column(Boolean, nullable=False, default=False)
    is_active = Column(Boolean, nullable=False, default=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now())


class SceneChallengeAttempt(Base):
    __tablename__ = "scene_challenge_attempts"

    id = Column(Integer, primary_key=True, index=True)
    challenge_id = Column(Integer, ForeignKey("scene_challenges.id"), nullable=False, index=True)
    user_id = Column(Integer, ForeignKey("user.id"), nullable=False, index=True)

    guessed_title = Column(String(255), nullable=False)
    is_correct = Column(Boolean, nullable=False, default=False)
    hints_used = Column(Integer, nullable=False, default=0)
    time_taken_ms = Column(Integer, nullable=True)

    mode = Column(String(20), nullable=False, default="endless")  # endless or daily
    created_at = Column(DateTime(timezone=True), server_default=func.now())