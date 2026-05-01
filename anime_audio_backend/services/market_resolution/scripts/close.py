from datetime import datetime, timezone
from models import Market


def close_markets(db):
    now = datetime.now(timezone.utc)

    markets = (
        db.query(Market)
        .filter(
            Market.status == "open",
            Market.close_time <= now,
        )
        .all()
    )

    for market in markets:
        market.status = "closed"

    db.commit()



from services.market_resolution.close import close_markets

def run():
    db = SessionLocal()

    close_markets(db)

    now = datetime.now(timezone.utc)
    markets = (
        db.query(Market)
        .filter(
            Market.status == "closed",
            Market.resolve_time <= now,
        )
        .all()
    )

    for market in markets:
        resolve_market(db, market)

    db.close()


def resolve_from_anilist(market: Market):
    data = market.resolution_data

    anime_id = data["anime_id"]
    field = data["field"]
    operator = data["operator"]
    value = data["value"]

    actual = fetch_anilist_field(anime_id, field)

    if operator == "<=":
        return actual <= value
    if operator == ">=":
        return actual >= value
