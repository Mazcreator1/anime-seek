from pydantic import BaseModel, Field


class MarketEntryCreate(BaseModel):
    outcome_id: int
    stake_amount: float = Field(..., gt=0)

from fastapi import HTTPException, status
from models import MarketPosition, Wallet, WalletTransaction
from schemas.market_entry import MarketEntryCreate
from auth import get_current_user



@router.post("/{market_id}/enter", status_code=status.HTTP_201_CREATED)
def enter_market(
    market_id: int,
    payload: MarketEntryCreate,
    db: Session = Depends(get_db),
    user=Depends(get_current_user),
):
    now = datetime.now(timezone.utc)

    market = (
        db.query(Market)
        .filter(
            Market.id == market_id,
            Market.status == "open",
            Market.close_time > now,
        )
        .first()
    )

    if not market:
        raise HTTPException(400, "Market is not open")

    existing = (
        db.query(MarketPosition)
        .filter(
            MarketPosition.user_id == user.id,
            MarketPosition.market_id == market_id,
        )
        .first()
    )

    if existing:
        raise HTTPException(409, "Already entered this market")

    wallet = (
        db.query(Wallet)
        .filter(
            Wallet.user_id == user.id,
            Wallet.currency_type == "virtual",
        )
        .with_for_update()
        .first()
    )

    if not wallet or wallet.balance < payload.stake_amount:
        raise HTTPException(400, "Insufficient balance")

    wallet.balance -= payload.stake_amount

    position = MarketPosition(
        user_id=user.id,
        market_id=market.id,
        outcome_id=payload.outcome_id,
        stake_amount=payload.stake_amount,
    )

    db.add(position)

    db.add(
        WalletTransaction(
            wallet_id=wallet.id,
            amount=-payload.stake_amount,
            reason="market_entry",
            reference_type="market",
            reference_id=market.id,
        )
    )

    db.commit()

    return {"status": "entered"}



@router.get("/me/positions")
def my_positions(
    db: Session = Depends(get_db),
    user=Depends(get_current_user),
):
    positions = (
        db.query(MarketPosition)
        .filter(MarketPosition.user_id == user.id)
        .all()
    )

    return [
        {
            "market_id": p.market_id,
            "outcome_id": p.outcome_id,
            "stake_amount": p.stake_amount,
            "created_at": p.created_at,
        }
        for p in positions
    ]
