from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any, Dict

from jose import JWTError, jwt
from passlib.context import CryptContext

from config import settings

pwd_ctx = CryptContext(schemes=["bcrypt"], deprecated="auto")


def hash_password(plain: str) -> str:
    return pwd_ctx.hash(plain)


def verify_password(plain: str, hashed: str) -> bool:
    return pwd_ctx.verify(plain, hashed)


def create_token(data: Dict[str, Any], expires_delta: timedelta) -> str:
    """
    Create a JWT with a UTC expiration.
    """
    to_encode = dict(data)

    exp = datetime.now(timezone.utc) + expires_delta
    to_encode["exp"] = exp

    return jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def decode_token(token: str) -> Dict[str, Any]:
    """
    Decode/verify a JWT. Raises jose.JWTError if invalid/expired.
    """
    return jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])


# Optional convenience helpers (safe to keep even if you don't use them)
def create_access_token(user_id: int, expires_minutes: int | None = None) -> str:
    mins = expires_minutes if expires_minutes is not None else getattr(settings, "ACCESS_EXPIRE_MINUTES", 30)
    return create_token({"sub": str(user_id), "type": "access"}, expires_delta=timedelta(minutes=mins))


def create_refresh_token(user_id: int, expires_days: int | None = None) -> str:
    days = expires_days if expires_days is not None else getattr(settings, "REFRESH_EXPIRE_DAYS", 180)
    return create_token({"sub": str(user_id), "type": "refresh"}, expires_delta=timedelta(days=days))
