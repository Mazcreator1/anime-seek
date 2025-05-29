# config.py
from pydantic import BaseSettings, EmailStr, Field, validator
from typing import List, Optional
from pathlib import Path

class Settings(BaseSettings):
    # —— App & DB ——
    APP_HOST: str = "0.0.0.0"
    APP_PORT: int = 8000

    DB_HOST: str
    DB_USER: str
    DB_PASSWORD: str
    DB_NAME: str

    # —— Stripe & JWT ——
    STRIPE_API_KEY: str
    STRIPE_WEBHOOK_SECRET: str
    STRIPE_PRICE_ID: str
    SECRET_KEY: str

    ALGORITHM: str = "HS256"
    ACCESS_EXPIRE_MINUTES: int = 60
    REFRESH_EXPIRE_DAYS: int   = 7

    # Redis / rate-limiting
    REDIS_HOST: str = "localhost"
    REDIS_PORT: int = 6379
    RATE_LIMIT_COUNT: int = 5
    RATE_LIMIT_WINDOW: int = 300

    # Uploads & external services
    MAX_UPLOAD_SIZE: int = 5 * 1024 * 1024
    SOLR_URL: str = "http://localhost:8983/solr/cl_0/lireq"
    ANILIST_API: str

    # Stripe
    STRIPE_API_KEY: str
    STRIPE_WEBHOOK_SECRET: str
    STRIPE_PRICE_ID: str

    # —— Email (SMTP) ——
    EMAIL_FROM: EmailStr
    SMTP_HOST: str
    SMTP_PORT: int
    SMTP_USER: str
    SMTP_PASSWORD: str



    # —— CORS & Static ——
    ALLOWED_ORIGINS: List[str] = Field(default_factory=lambda: ["https://anime-seek.com"])
    STATIC_DIR: str = "static"

    # —— OAuth/Social Login ——
    OAUTH_GOOGLE_CLIENT_ID: Optional[str]
    OAUTH_GOOGLE_CLIENT_SECRET: Optional[str]
    # add other providers…

    class Config:
        env_file = str(Path(__file__).parent.parent / ".env")
        env_file_encoding = "utf-8"

    @validator("ALLOWED_ORIGINS", pre=True)
    def _split_origins(cls, v):
        # if someone passes a comma-separated string, split it
        if isinstance(v, str):
            return [origin.strip() for origin in v.split(",") if origin.strip()]
        # otherwise assume it’s already a list
        return v

settings = Settings()
