# app/tasks.py
from datetime import datetime, timedelta
from sqlalchemy.orm import Session
from models import PasswordResetToken
from database import SessionLocal
from typing import Optional

def prune_reset_tokens(db: Session):
    cutoff = datetime.utcnow() - timedelta(days=1)
    db.query(PasswordResetToken).filter(
        (PasswordResetToken.used == True) |
        (PasswordResetToken.created_at < cutoff)
      ).delete(synchronize_session=False)
    db.commit()
