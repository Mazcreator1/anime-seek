# recreate_tables.py
import os
from sqlalchemy import create_engine, inspect
from sqlalchemy.engine.url import make_url

# --- Base/engine ---
# If your database.py already defines `engine`, we'll reuse it.
from database import Base
try:
    from database import engine as existing_engine
except ImportError:
    existing_engine = None

# --- IMPORT ALL MODELS SO THEY REGISTER WITH Base.metadata ---
# ⬇️ CHANGE 'models' to your actual module path if different
from models import (
    Follow,
    User,
    PasswordResetToken,
    Logs,
    Playlist,
    PlaylistSong,
    Anime,
    Genre,
    Song,
    AniListMetadata,
    AnimeTiers,
    Notification,
    Badge,
    Post,
    Comment,
    Reply,
    PostLike,
    UserLike,
    anime_genre,  # association table
)

# --- Engine setup (fallback if database.engine not provided) ---
DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "mysql+mysqlconnector://user:password@db:3306/dejavu?charset=utf8mb4",
)
engine = existing_engine or create_engine(DATABASE_URL, pool_pre_ping=True, echo=True)

# --- Ensure DB exists (MySQL only), then create tables ---
url = make_url(str(engine.url))
db_name = url.database

with engine.begin() as conn:
    if url.get_backend_name().startswith("mysql"):
        conn.exec_driver_sql(f"CREATE DATABASE IF NOT EXISTS `{db_name}` CHARACTER SET utf8mb4")
        conn.exec_driver_sql(f"USE `{db_name}`")
    Base.metadata.create_all(conn)

# --- Verify ---
insp = inspect(engine)
print("Tables:", sorted(insp.get_table_names()))
