# =========================

# Imports

# =========================



import enum

import uuid

from datetime import datetime



from sqlalchemy import (

    Column,

    Integer,

    BigInteger,

    String,

    Text,

    Boolean,

    Float,

    DateTime,

    ForeignKey,

    UniqueConstraint,

    Index,

    Enum,

    Numeric,

    Table,

)

from sqlalchemy.dialects.postgresql import JSONB, INET

from sqlalchemy.orm import relationship, backref, synonym

from sqlalchemy.sql import func



from database import Base





# =========================

# Association Tables

# =========================



anime_genre = Table(

    "anime_genre",

    Base.metadata,

    Column("anime_id", ForeignKey("anime.id"), primary_key=True),

    Column("genre_id", ForeignKey("genre.id"), primary_key=True),

)





# =========================

# Social / Users

# =========================



class Follow(Base):

    __tablename__ = "follows"



    id = Column(Integer, primary_key=True)

    follower_id = Column(Integer, ForeignKey("users.id"), nullable=False)

    following_id = Column(Integer, ForeignKey("users.id"), nullable=False)

    created_at = Column(DateTime, default=datetime.utcnow)



    follower = relationship("User", foreign_keys=[follower_id], back_populates="following")

    following = relationship("User", foreign_keys=[following_id], back_populates="followers")



    __table_args__ = (UniqueConstraint("follower_id", "following_id", name="uq_follow"),)





class User(Base):

    __tablename__ = "users"



    id = Column(Integer, primary_key=True, index=True)

    api_key = Column(

        String(128),

        unique=True,

        nullable=False,

        default=lambda: uuid.uuid4().hex,

        index=True,

    )

    scene_challenge_attempts = relationship(
    "SceneChallengeAttempt",
    back_populates="user",
    cascade="all, delete-orphan",
    passive_deletes=True,
    )

    anime_tier_id = Column(Integer, default=0, server_default="0", nullable=False)

    is_admin = Column(Boolean, default=False, nullable=False)


    is_verified = Column(Boolean, nullable=False, server_default="false")
    
    provider_uid = Column(String(191), unique=True, nullable=False, index=True)

    email = Column(String(255), unique=True, index=True, nullable=False)

    password = Column(String(255), nullable=False)



    display_name = Column(String(30), unique=True, index=True, nullable=False)

    first_name = Column(String(100))

    last_name = Column(String(100))



    is_active = Column(Boolean, default=True, nullable=False)

    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    updated_at = Column(DateTime, default=datetime.utcnow, nullable=False)



    top_line = Column(String(256), default="")

    favorite_anime = Column(JSONB)

    favorite_characters = Column(JSONB)

    profile_song_json = Column(JSONB)


    stripe_customer_id = Column(String(255), nullable=True)

    stripe_subscription_id = Column(String(255), nullable=True)



    is_subscribed = Column(Boolean, default=False, nullable=False)

    subscription_expires = Column(DateTime, nullable=True)

    cancel_at_period_end = Column(Boolean, default=False, nullable=False)


    avatar_url = Column(String(256))

    bio = Column(Text)

    is_private = Column(Boolean, default=False, nullable=False)

    verification_token = Column(String(255))

    email_verified = Column(Boolean, nullable=False, server_default="false")

    verified_at = Column(DateTime)

    trial_used = Column(Boolean, default=False, nullable=False)

    badges = relationship(

        "Badge",

        back_populates="user",

        cascade="all, delete",

        primaryjoin="User.api_key == Badge.api_key",

    )



    playlists = relationship("Playlist", back_populates="owner", cascade="all, delete-orphan")

    reset_tokens = relationship("PasswordResetToken", back_populates="user", cascade="all, delete-orphan")



    logs = relationship(

        "Logs",

        back_populates="user",

        primaryjoin="User.api_key == foreign(Logs.api_key)",

        foreign_keys="Logs.api_key",

    )



    followers = relationship(

        "Follow",

        foreign_keys="[Follow.following_id]",

        back_populates="following",

        cascade="all, delete-orphan",

    )

    following = relationship(

        "Follow",

        foreign_keys="[Follow.follower_id]",

        back_populates="follower",

        cascade="all, delete-orphan",

    )



    post_likes = relationship(

        "PostLike",

        back_populates="user",

        cascade="all, delete-orphan",

        passive_deletes=True,

    )



    likes_sent = relationship(

        "UserLike",

        foreign_keys="[UserLike.liker_user_id]",

        back_populates="liker",

        cascade="all, delete-orphan",

        passive_deletes=True,

    )

    likes_received = relationship(

        "UserLike",

        foreign_keys="[UserLike.target_user_id]",

        back_populates="target",

        cascade="all, delete-orphan",

        passive_deletes=True,

    )





Index("uq_user_display_name_lower", func.lower(User.display_name), unique=False)


# =========================

# Economy / Markets

# =========================



class CurrencyType(str, enum.Enum):

    virtual = "virtual"

    premium = "premium"

    cash = "cash"





class MarketStatus(str, enum.Enum):

    open = "open"

    closed = "closed"

    resolved = "resolved"

    cancelled = "cancelled"





class TransactionReason(str, enum.Enum):

    market_entry = "market_entry"

    market_payout = "market_payout"

    bonus = "bonus"

    adjustment = "adjustment"





class Wallet(Base):

    __tablename__ = "wallets"



    id = Column(Integer, primary_key=True)

    user_id = Column(Integer, index=True, nullable=False)

    balance = Column(Numeric(12, 2), nullable=False, default=0)

    currency_type = Column(Enum(CurrencyType), nullable=False)

    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())



    transactions = relationship("WalletTransaction", back_populates="wallet")



    __table_args__ = (UniqueConstraint("user_id", "currency_type", name="uq_user_currency"),)





class WalletTransaction(Base):

    __tablename__ = "wallet_transactions"



    id = Column(Integer, primary_key=True)

    wallet_id = Column(Integer, ForeignKey("wallets.id"), nullable=False)

    amount = Column(Numeric(12, 2), nullable=False)

    reason = Column(Enum(TransactionReason), nullable=False)

    reference_type = Column(String(50))

    reference_id = Column(Integer)

    created_at = Column(DateTime(timezone=True), server_default=func.now())



    wallet = relationship("Wallet", back_populates="transactions")





class Market(Base):

    __tablename__ = "markets"



    id = Column(Integer, primary_key=True)

    slug = Column(String(100), unique=True, nullable=False)

    title = Column(String(255), nullable=False)

    description = Column(String(500))

    category = Column(String(50), nullable=False)



    open_time = Column(DateTime(timezone=True), nullable=False)

    close_time = Column(DateTime(timezone=True), nullable=False)

    resolve_time = Column(DateTime(timezone=True), nullable=False)



    resolution_source = Column(String(50), nullable=False)

    resolution_data = Column(JSONB, nullable=False)

    cover_image_url = Column(Text)
    gif_url = Column(Text)
    banner_color = Column(String(32))

    status = Column(Enum(MarketStatus), nullable=False, default=MarketStatus.open)

    created_at = Column(DateTime(timezone=True), server_default=func.now())



    outcomes = relationship("MarketOutcome", back_populates="market")
    
    total_stake = Column(Numeric(12, 2), default=0)

    positions = relationship("MarketPosition", back_populates="market")





class MarketOutcome(Base):

    __tablename__ = "market_outcomes"



    id = Column(Integer, primary_key=True)

    market_id = Column(Integer, ForeignKey("markets.id"), nullable=False)

    label = Column(String(50), nullable=False)

    is_winner = Column(Boolean)



    market = relationship("Market", back_populates="outcomes")





class MarketPosition(Base):

    __tablename__ = "market_positions"



    id = Column(Integer, primary_key=True)

    user_id = Column(Integer, index=True, nullable=False)

    market_id = Column(Integer, ForeignKey("markets.id"), nullable=False)

    outcome_id = Column(Integer, ForeignKey("market_outcomes.id"), nullable=False)



    stake_amount = Column(Numeric(12, 2), nullable=False)

    odds_snapshot = Column(Numeric(6, 4))

    created_at = Column(DateTime(timezone=True), server_default=func.now())



    market = relationship("Market", back_populates="positions")

    outcome = relationship("MarketOutcome")



    __table_args__ = (UniqueConstraint("user_id", "market_id", name="uq_user_market"),)





class MarketResolution(Base):

    __tablename__ = "market_resolutions"



    id = Column(Integer, primary_key=True)

    market_id = Column(Integer, ForeignKey("markets.id"), nullable=False)

    resolved_at = Column(DateTime(timezone=True), server_default=func.now())

    winning_outcome_id = Column(Integer, ForeignKey("market_outcomes.id"), nullable=False)

    resolver = Column(String(50), nullable=False)

    resolution_payload = Column(JSONB, nullable=False)


# =========================

# Content / Logs / Media

# =========================



class PasswordResetToken(Base):

    __tablename__ = "password_reset_tokens"



    id = Column(Integer, primary_key=True)

    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)

    token = Column(String(255), nullable=False, unique=True)

    used = Column(Boolean, default=False, nullable=False)

    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)



    user = relationship("User", back_populates="reset_tokens")





class Logs(Base):

    __tablename__ = "logs"



    id = Column(BigInteger, primary_key=True)

    api_key = Column(String(128), ForeignKey("users.api_key", ondelete="SET NULL"), nullable=True, index=True)

    ip = Column(INET, index=True, nullable=False)

    uid = synonym("ip")

    status = Column(Integer, nullable=False)

    accuracy = Column(Float)

    search_type = Column(String(10), nullable=False, default="scene")

    search_time = Column(Integer, nullable=False)

    code = Column(Integer, nullable=False, default=200)

    song_id = Column(Integer, ForeignKey("songs.song_id", ondelete="SET NULL"), index=True)

    anime_id = Column(Integer, ForeignKey("anime.id", ondelete="SET NULL"), index=True)

    created_at = Column(DateTime, default=datetime.utcnow)



    song = relationship("Song", back_populates="logs")

    anime = relationship("Anime", cascade="all, delete")

    user = relationship(

        "User",

        back_populates="logs",

        primaryjoin="foreign(Logs.api_key) == User.api_key",

        foreign_keys=[api_key],

    )





class Playlist(Base):

    __tablename__ = "playlists"



    id = Column(Integer, primary_key=True)

    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)

    name = Column(String(15), nullable=False)

    created_at = Column(DateTime, default=datetime.utcnow)

    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)



    owner = relationship("User", back_populates="playlists")

    songs = relationship("PlaylistSong", back_populates="playlist", cascade="all, delete-orphan")





class PlaylistSong(Base):

    __tablename__ = "playlist_entries"



    id = Column(Integer, primary_key=True, index=True)

    playlist_id = Column(Integer, ForeignKey("playlists.id", ondelete="CASCADE"), nullable=False, index=True)

    song_name = Column(String(255), nullable=False, index=True)

    audio_url = Column(String(500))

    author = Column(String(100))

    duration = Column(Float, nullable=False)



    playlist = relationship("Playlist", back_populates="songs")



    __table_args__ = (UniqueConstraint("playlist_id", "song_name", name="_playlist_entries_uc"),)





class Anime(Base):

    __tablename__ = "anime"



    id = Column(Integer, primary_key=True)

    title_romaji = Column(String(255), nullable=False, unique=True, index=True)

    title_english = Column(String(255))

    description = Column(Text)

    cover_image = Column(String(512))

    season = Column(String(32))

    season_year = Column(Integer)

    format = Column(String(64))



    logs = relationship("Logs", back_populates="anime", cascade="all, delete-orphan")

    genres = relationship("Genre", secondary=anime_genre, back_populates="animes")





class Genre(Base):

    __tablename__ = "genre"



    id = Column(Integer, primary_key=True)

    name = Column(String(15), unique=True, nullable=False)



    animes = relationship("Anime", secondary=anime_genre, back_populates="genres")





class Song(Base):

    __tablename__ = "songs"



    song_id = Column(Integer, primary_key=True, index=True)

    song_name = Column(String(255), nullable=False, index=True)

    fingerprinted = Column(Boolean, default=False, nullable=False)

    artist = Column(String(128))

    streaming_service = Column(String(128))

    op_ed_type = Column(String(32))

    anime_title = Column(String(255))

    audio_url = Column(String(512))

    youtube_url = Column(String(512))

    spotify_url = Column(String(512))

    video_url = Column(String(512))

    file_sha1 = Column(String(40))



    logs = relationship("Logs", back_populates="song")


# =========================

# Social Feed / Polls

# =========================



class AniListMetadata(Base):

    __tablename__ = "anilist_metadata"



    id = Column(Integer, primary_key=True, index=True)

    anilist_id = Column(Integer, nullable=False, unique=True, index=True)

    title_romaji = Column(String(255))

    title_english = Column(String(255))

    description = Column(Text)

    cover_image = Column(String(512))

    season = Column(String(32))

    season_year = Column(Integer)

    match_count = Column(Integer, default=0, nullable=False)

    format = Column(String(64))

    genres = Column(Text)

    tags = Column(Text)

    fetched_at = Column(DateTime, default=datetime.utcnow, nullable=False)



    anime_id = Column(Integer, ForeignKey("anime.id"), unique=True, index=True)

    anime = relationship("Anime", cascade="all, delete")



    __table_args__ = (UniqueConstraint("anilist_id", name="uq_anilist_id"),)





class AnimeTiers(Base):

    __tablename__ = "anime_tiers"



    id = Column(Integer, primary_key=True)

    priority = Column(Integer, nullable=False)

    concurrency = Column(Integer, nullable=False)

    quota = Column(Integer, nullable=False)

    notes = Column(String(128))

    patreon_id = Column(Integer, default=0)





class Notification(Base):

    __tablename__ = "notifications"



    id = Column(Integer, primary_key=True)

    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"))

    actor_id = Column(Integer, ForeignKey("users.id"), nullable=False)

    type = Column(String(30), nullable=False)

    message = Column(Text)

    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    is_read = Column(Boolean, default=False, nullable=False)

    user = relationship("User", foreign_keys=[user_id])

    actor = relationship("User", foreign_keys=[actor_id])



class Badge(Base):

    __tablename__ = "badges"



    id = Column(Integer, primary_key=True)

    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)

    api_key = Column(String(128), ForeignKey("users.api_key"))

    name = Column(String(255), nullable=False)

    unlocked_at = Column(DateTime, nullable=False)

    icon_url = Column(String(512))



    user = relationship("User", back_populates="badges", primaryjoin="User.api_key == Badge.api_key")





class Post(Base):

    __tablename__ = "posts"



    id = Column(Integer, primary_key=True, index=True)

    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), index=True)

    text = Column(Text)

    image_url = Column(Text)

    background_color = Column(String(9))

    discord_thread_id = Column(String(32), index=True)



    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)



    user = relationship("User")

    comments = relationship("Comment", back_populates="post", cascade="all, delete-orphan")

    likes = relationship("PostLike", back_populates="post", cascade="all, delete-orphan", passive_deletes=True)



    __table_args__ = (Index("ix_posts_user_created", "user_id", "created_at"),)





class Comment(Base):

    __tablename__ = "comments"



    id = Column(Integer, primary_key=True)

    post_id = Column(Integer, ForeignKey("posts.id", ondelete="CASCADE"), nullable=False)

    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)

    content = Column(Text, nullable=False)

    created_at = Column(DateTime, default=func.now())



    post = relationship("Post", back_populates="comments")

    user = relationship("User")

    replies = relationship("Reply", back_populates="comment", cascade="all, delete-orphan")





class Reply(Base):

    __tablename__ = "replies"



    id = Column(Integer, primary_key=True)

    comment_id = Column(Integer, ForeignKey("comments.id", ondelete="CASCADE"), nullable=False)

    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)

    content = Column(Text, nullable=False)

    created_at = Column(DateTime, default=func.now())



    comment = relationship("Comment", back_populates="replies")

    user = relationship("User")





class PostLike(Base):

    __tablename__ = "post_likes"



    id = Column(Integer, primary_key=True)

    post_id = Column(Integer, ForeignKey("posts.id", ondelete="CASCADE"), index=True, nullable=False)

    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False)

    created_at = Column(DateTime, server_default=func.current_timestamp(), nullable=False)



    post = relationship("Post", back_populates="likes")

    user = relationship("User", back_populates="post_likes")



    __table_args__ = (UniqueConstraint("post_id", "user_id", name="uq_post_like_once"),)





class UserLike(Base):

    __tablename__ = "user_likes"



    id = Column(Integer, primary_key=True)

    liker_user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False)

    target_user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False)

    created_at = Column(DateTime, server_default=func.current_timestamp(), nullable=False)



    liker = relationship("User", foreign_keys=[liker_user_id], back_populates="likes_sent")

    target = relationship("User", foreign_keys=[target_user_id], back_populates="likes_received")



    __table_args__ = (UniqueConstraint("liker_user_id", "target_user_id", name="uq_user_like_pair"),)





class PostReshare(Base):

    __tablename__ = "post_reshares"



    id = Column(Integer, primary_key=True)

    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False)

    post_id = Column(Integer, ForeignKey("posts.id", ondelete="CASCADE"), index=True, nullable=False)

    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)



    user = relationship("User")

    post = relationship("Post")



    __table_args__ = (UniqueConstraint("user_id", "post_id", name="uq_post_reshares_user_post"),)





class Poll(Base):

    __tablename__ = "polls"



    id = Column(Integer, primary_key=True)

    post_id = Column(Integer, ForeignKey("posts.id", ondelete="CASCADE"), unique=True, index=True, nullable=False)

    closes_at = Column(DateTime(timezone=True))

    multiple = Column(Boolean, default=False, nullable=False)

    allow_change = Column(Boolean, default=True, nullable=False)

    created_at = Column(DateTime(timezone=True), server_default=func.now())



    post = relationship("Post", backref=backref("poll", uselist=False, cascade="all, delete-orphan"))





class PollOption(Base):

    __tablename__ = "poll_options"



    id = Column(Integer, primary_key=True)

    poll_id = Column(Integer, ForeignKey("polls.id", ondelete="CASCADE"), index=True, nullable=False)

    idx = Column(Integer, nullable=False)

    text = Column(String(200), nullable=False)

    vote_count = Column(Integer, default=0, nullable=False)



    poll = relationship("Poll", backref=backref("options", order_by="PollOption.idx", cascade="all, delete-orphan"))





class PollVote(Base):

    __tablename__ = "poll_votes"



    id = Column(Integer, primary_key=True)

    poll_id = Column(Integer, ForeignKey("polls.id", ondelete="CASCADE"), index=True, nullable=False)

    option_id = Column(Integer, ForeignKey("poll_options.id", ondelete="CASCADE"), nullable=False)

    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False)

    created_at = Column(DateTime(timezone=True), server_default=func.now())



    __table_args__ = (UniqueConstraint("poll_id", "user_id", name="uq_poll_user_single"),)
    option = relationship("PollOption")



class SceneChallenge(Base):
    __tablename__ = "scene_challenges"

    id = Column(Integer, primary_key=True, index=True)

    anilist_id = Column(Integer, nullable=True, index=True)
    anime_title = Column(String(255), nullable=False, index=True)
    anime_title_romaji = Column(String(255), nullable=True)
    anime_title_english = Column(String(255), nullable=True)

    episode = Column(Integer, nullable=True)
    timestamp = Column(String(32), nullable=True)

    image_url = Column(String(512), nullable=False)
    difficulty = Column(String(20), nullable=False, default="easy")

    hint_1 = Column(String(255), nullable=True)
    hint_2 = Column(String(255), nullable=True)
    hint_3 = Column(String(255), nullable=True)

    is_daily = Column(Boolean, default=False, nullable=False)
    is_active = Column(Boolean, default=True, nullable=False)

    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    attempts = relationship(
        "SceneChallengeAttempt",
        back_populates="challenge",
        cascade="all, delete-orphan",
    )


class SceneChallengeAttempt(Base):
    __tablename__ = "scene_challenge_attempts"

    id = Column(Integer, primary_key=True, index=True)

    challenge_id = Column(
        Integer,
        ForeignKey("scene_challenges.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    user_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    guessed_title = Column(String(255), nullable=False)
    is_correct = Column(Boolean, default=False, nullable=False)
    hints_used = Column(Integer, default=0, nullable=False)
    time_taken_ms = Column(Integer, nullable=True)

    mode = Column(String(20), nullable=False, default="endless")
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    challenge = relationship("SceneChallenge", back_populates="attempts")
    user = relationship("User", back_populates="scene_challenge_attempts")

    __table_args__ = (
        Index("ix_scene_attempt_user_created", "user_id", "created_at"),
    )