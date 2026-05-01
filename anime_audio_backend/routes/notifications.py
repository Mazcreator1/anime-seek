# routes/notifications.py

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from database import get_db
from models import Notification
from auth_utils import get_current_user

router = APIRouter(prefix="/notifications", tags=["Notifications"])

@router.get("")
def list_notifications(
    db: Session = Depends(get_db),
    user=Depends(get_current_user),
):
    notes = (
        db.query(Notification)
        .filter(Notification.user_id == user.id)
        .order_by(Notification.created_at.desc())
        .all()
    )

    return [
        {
            "id": n.id,
            "message": n.message,
            "type": n.type,
            "is_read": n.is_read,
            "created_at": n.created_at,
        }
        for n in notes
    ]
