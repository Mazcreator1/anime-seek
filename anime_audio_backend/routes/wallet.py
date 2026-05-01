from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from database import get_db
from auth_utils import get_current_user
from models import Wallet, WalletTransaction, User
from schemas.wallet import WalletTransactionOut

router = APIRouter(prefix="/me/wallet", tags=["wallet"])

@router.get("")
def get_wallet(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """
    Wallet summary used by the frontend MarketPage.
    """
    wallet = (
        db.query(Wallet)
        .filter(Wallet.user_id == user.id)
        .first()
    )

    if not wallet:
        # If you prefer auto-create wallet, do it here.
        return {"balance": 0, "currency_type": "virtual"}

    return {
        "id": wallet.id,
        "balance": float(wallet.balance),
        "currency_type": getattr(wallet, "currency_type", "virtual"),
    }


@router.get("/transactions", response_model=list[WalletTransactionOut])
def get_wallet_transactions(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    wallet = (
        db.query(Wallet)
        .filter(Wallet.user_id == user.id)
        .first()
    )

    if not wallet:
        return []

    return (
        db.query(WalletTransaction)
        .filter(WalletTransaction.wallet_id == wallet.id)
        .order_by(WalletTransaction.created_at.desc())
        .all()
    )
