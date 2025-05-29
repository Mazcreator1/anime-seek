# models.py
from sqlalchemy import Column, Boolean
from typing import Optional, List
from pydantic import BaseModel
from sqlalchemy import (
    Column, Integer, String, Text, Float, Boolean, DateTime,
    ForeignKey, UniqueConstraint
)
from sqlalchemy.orm import relationship
from database import Base
from datetime import datetime
from sqlalchemy import Column, DateTime, Integer, String, Boolean
from sqlalchemy.ext.declarative import declarative_base
# Pydantic schema for creating playlists
class PlaylistCreate(BaseModel):
    name: str
    theme: Optional[str] = None
    description: Optional[str] = None

# SQLAlchemy models

class Playlist(Base):
    __tablename__ = "playlists"

    id          = Column(Integer, primary_key=True, index=True)
    name        = Column(String(255), unique=True, nullable=False)
    theme       = Column(String(100), nullable=True, index=True)
    description = Column(Text, nullable=True)
    user_id     = Column(Integer, ForeignKey("users.id"), nullable=False)
    trial_used = Column(Boolean, nullable=False, default=False)
    # one-to-many to entries
    songs       = relationship(
        "PlaylistSong",
        back_populates="playlist",
        cascade="all, delete-orphan"
    )
    owner       = relationship("User", back_populates="playlists")


class PlaylistSong(Base):
    __tablename__ = "playlist_entries"

    id           = Column(Integer, primary_key=True, index=True)
    playlist_id  = Column(
        Integer,
        ForeignKey("playlists.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    song_name    = Column(String(255), nullable=False, index=True)
    audio_url    = Column(String(500), nullable=True)
    author       = Column(String(100), nullable=True)
    duration     = Column(Float, nullable=False)

    playlist     = relationship("Playlist", back_populates="songs")

    __table_args__ = (
        UniqueConstraint("playlist_id", "song_name", name="_playlist_entries_uc"),
    )


class Anime(Base):
    __tablename__ = "anime"

    id            = Column(Integer, primary_key=True)
    title_romaji  = Column(String(255), nullable=False, unique=True, index=True)
    title_english = Column(String(255), nullable=True)
    description   = Column(Text, nullable=True)
    cover_image   = Column(String(512), nullable=True)
    season        = Column(String(32), nullable=True)
    season_year   = Column(Integer, nullable=True)
    format        = Column(String(64), nullable=True)
    genres        = Column(Text, nullable=True)  # comma-separated genre list
    tags          = Column(Text, nullable=True)  # comma-separated safe tags


class User(Base):
    __tablename__ = "users"

    id                       = Column(Integer, primary_key=True, index=True)
    email                    = Column(String(255), unique=True, index=True, nullable=False)
    hashed_pw                = Column(String(255), nullable=False)
    is_subscribed            = Column(Boolean, default=False, nullable=False)
    subscription_expires     = Column(DateTime, nullable=True)
    is_active                = Column(Boolean, default=True, nullable=False)
    stripe_customer_id       = Column(String(255), nullable=True, unique=True)
    stripe_subscription_id   = Column(String(255), nullable=True, unique=True)
    email_verified = Column(Boolean, default=False, nullable=False)
    verified_at    = Column(DateTime, nullable=True)
    trial_used = Column(Boolean, nullable=False, default=False)

    playlists                = relationship("Playlist", back_populates="owner", cascade="all, delete-orphan")

    created_at  = Column(
        DateTime,
        nullable=False,
        default=datetime.utcnow,
    )
    updated_at  = Column(
        DateTime,
        nullable=False,
        default=datetime.utcnow,
        onupdate=datetime.utcnow,
    )