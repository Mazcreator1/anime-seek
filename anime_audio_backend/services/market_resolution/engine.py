from datetime import datetime, timezone
from sqlalchemy.orm import Session
from models import (
    Market,
    MarketOutcome,
    MarketPosition,
    MarketResolution,
    Wallet,
    WalletTransaction,
)


def resolve_market(db: Session, market: Market):
    # Guard: already resolved
    if market.status == "resolved":
        return

    winning_outcome = (
        db.query(MarketOutcome)
        .filter(
            MarketOutcome.market_id == market.id,
            MarketOutcome.is_winner.is_(True),
        )
        .first()
    )

    if not winning_outcome:
        raise RuntimeError("No winning outcome defined")

    positions = (
        db.query(MarketPosition)
        .filter(MarketPosition.market_id == market.id)
        .all()
    )

    total_pool = sum(p.stake_amount for p in positions)

    winners = [p for p in positions if p.outcome_id == winning_outcome.id]
    total_winning_stake = sum(p.stake_amount for p in winners)

    for position in winners:
        payout = (
            position.stake_amount / total_winning_stake
        ) * total_pool

        wallet = (
            db.query(Wallet)
            .filter(
                Wallet.user_id == position.user_id,
                Wallet.currency_type == "virtual",
            )
            .with_for_update()
            .first()
        )

        wallet.balance += payout

        db.add(
            WalletTransaction(
                wallet_id=wallet.id,
                amount=payout,
                reason="market_payout",
                reference_type="market",
                reference_id=market.id,
            )
        )

    market.status = "resolved"

    db.add(
        MarketResolution(
            market_id=market.id,
            winning_outcome_id=winning_outcome.id,
            resolver="engine",
            resolution_payload={
                "total_pool": float(total_pool),
                "winning_outcome": winning_outcome.label,
            },
        )
    )

    db.commit()
