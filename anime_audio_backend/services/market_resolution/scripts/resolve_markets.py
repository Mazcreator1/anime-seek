from datetime import datetime, timezone
import logging

from database import SessionLocal
from models import (
    Market,
    MarketPosition,
    MarketResolution,
    Notification,
)
from services.market_resolution.engine import resolve_market

logger = logging.getLogger(__name__)


def _notify_users(db, market: Market, resolution: MarketResolution):
    """
    Create win/loss notifications for all users in a resolved market.
    Idempotent: prevents duplicate notifications.
    """
    positions = (
        db.query(MarketPosition)
        .filter(MarketPosition.market_id == market.id)
        .all()
    )

    for p in positions:
        won = p.outcome_id == resolution.winning_outcome_id

        message = (
            f"You won in '{market.title}'"
            if won
            else f"You lost in '{market.title}'"
        )

        # Prevent duplicate notifications
        exists = (
            db.query(Notification)
            .filter_by(
                user_id=p.user_id,
                type="market_result",
                message=message,
            )
            .first()
        )
        if exists:
            continue

        db.add(
            Notification(
                user_id=p.user_id,
                actor_id=p.user_id,
                type="market_result",
                message=message,
                is_read=False,
                created_at=datetime.now(timezone.utc),
            )
        )


def run():
    db = SessionLocal()
    now = datetime.now(timezone.utc)

    try:
        markets = (
            db.query(Market)
            .filter(
                Market.status == "closed",
                Market.resolve_time <= now,
            )
            .all()
        )

        if not markets:
            logger.info("No markets to resolve")
            return

        for market in markets:
            logger.info(f"Resolving market {market.id} ({market.title})")

            # Resolve outcomes + payouts
            resolution = resolve_market(db, market)
            if not resolution:
                logger.warning(f"Market {market.id} could not be resolved")
                continue

            # Notify participants
            _notify_users(db, market, resolution)

            # Finalize market state (idempotent)
            market.status = "resolved"
            if not resolution.resolved_at:
                resolution.resolved_at = now

        db.commit()

    except Exception:
        db.rollback()
        logger.exception("Market resolution failed")

    finally:
        db.close()


if __name__ == "__main__":
    run()
