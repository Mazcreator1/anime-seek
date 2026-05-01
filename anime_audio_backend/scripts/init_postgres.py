# scripts/init_pg.py
import os
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker
from sqlalchemy.exc import SQLAlchemyError

# 1) Point to POSTGRES, not MySQL
PG_URL = (
    os.getenv("SQLALCHEMY_DATABASE_URL_POSTGRES")
    or "postgresql+psycopg://postgres:postgres@postgres:5432/postgres"
)

engine = create_engine(PG_URL, pool_pre_ping=True, future=True)

# 2) Import models AFTER engine is defined so metadata is populated
import models  # noqa: E402
from models import Base  # noqa: E402

PG_BOOTSTRAP_DDL = [
    # safe if already installed; skip if you don't need them
    'CREATE EXTENSION IF NOT EXISTS "uuid-ossp";',
    "CREATE EXTENSION IF NOT EXISTS pgcrypto;",
    "CREATE EXTENSION IF NOT EXISTS citext;",
    # helper for your login IP→API key upsert (Postgres type)
    "CREATE TABLE IF NOT EXISTS ip_api_map (ip INET PRIMARY KEY, api_key TEXT);",
]

def main():
    if engine.dialect.name != "postgresql":
        raise SystemExit(f"Refusing to run: DSN is not Postgres -> {engine.dialect.name}")

    with engine.begin() as conn:
        for stmt in PG_BOOTSTRAP_DDL:
            try:
                conn.execute(text(stmt))
            except SQLAlchemyError as e:
                print(f"Skipping DDL due to error: {e}")

        # Create all tables + foreign keys from SQLAlchemy models
        Base.metadata.create_all(bind=conn, checkfirst=True)

    print("✅ Postgres schema initialized (tables, FKs, extensions, ip_api_map).")

if __name__ == "__main__":
    main()
