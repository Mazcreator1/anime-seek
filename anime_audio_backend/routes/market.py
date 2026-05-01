from fastapi import APIRouter, Depends, HTTPException, Query

from sqlalchemy.orm import Session

from datetime import datetime, timezone



from database import get_db

from models import (

    Market,

    MarketOutcome,

    MarketPosition,

    Wallet,

    MarketResolution,

)

from auth_utils import get_current_user



router = APIRouter(prefix="/markets", tags=["Markets"])





# ─────────────────────────────

# LIST MARKETS

# ─────────────────────────────

@router.get("")

def list_markets(

    category: str | None = Query(None),

    status: str | None = Query("open"),

    db: Session = Depends(get_db),

):

    q = db.query(Market)



    if status:

        q = q.filter(Market.status == status)



    if category:

        q = q.filter(Market.category == category)



    markets = q.order_by(Market.close_time.asc()).all()



    return [

        {

            "id": m.id,

            "slug": m.slug,

            "title": m.title,

            "description": m.description,

            "category": m.category,

            "status": m.status,

            "open_time": m.open_time,

            "close_time": m.close_time,

            "resolve_time": m.resolve_time,

            "winning_outcome_id": (

                m.resolution.winning_outcome_id

                if m.status == "resolved" and m.resolution

                else None

            ),

            "outcomes": [

                {"id": o.id, "label": o.label}

                for o in m.outcomes

            ],

        }

        for m in markets

    ]



# ─────────────────────────────

# MY POSITIONS

# ─────────────────────────────

@router.get("/me/positions")

def my_positions(

    db: Session = Depends(get_db),

    user=Depends(get_current_user),

):

    positions = (

        db.query(MarketPosition)

        .join(Market)

        .outerjoin(MarketResolution, MarketResolution.market_id == Market.id)

        .join(MarketOutcome)

        .filter(MarketPosition.user_id == user.id)

        .order_by(Market.resolve_time.desc())

        .all()

    )



    return [

        {

            "market_id": p.market.id,

            "market_title": p.market.title,

            "outcome_label": p.outcome.label,

            "stake": float(p.stake_amount),

            "is_resolved": p.market.status == "resolved",

            "is_win": (

                p.market.status == "resolved"

                and p.market.resolution

                and p.market.resolution.winning_outcome_id == p.outcome_id

            ),

        }

        for p in positions

    ]



# ─────────────────────────────

# GET SINGLE MARKET

# ─────────────────────────────

@router.get("/{market_id}")

def get_market(market_id: int, db: Session = Depends(get_db)):

    market = db.get(Market, market_id)

    if not market:

        raise HTTPException(404, "Market not found")



    return {

        "id": market.id,

        "slug": market.slug,

        "title": market.title,

        "description": market.description,

        "category": market.category,

        "status": market.status,

        "open_time": market.open_time,

        "close_time": market.close_time,

        "resolve_time": market.resolve_time,

        "winning_outcome_id": (

            market.resolution.winning_outcome_id

            if market.status == "resolved" and market.resolution

            else None

        ),

        "resolved_at": (

            market.resolution.resolved_at

            if market.status == "resolved" and market.resolution

            else None

        ),

        "outcomes": [

            {"id": o.id, "label": o.label}

            for o in market.outcomes

        ],

    }





# ─────────────────────────────

# ENTER MARKET

# ─────────────────────────────

@router.post("/{market_id}/enter")

def enter_market(

    market_id: int,

    payload: dict,

    db: Session = Depends(get_db),

    user=Depends(get_current_user),

):

    now = datetime.now(timezone.utc)



    outcome_id = payload.get("outcome_id")

    stake = payload.get("stake_amount")



    if not isinstance(outcome_id, int) or not isinstance(stake, (int, float)) or stake <= 0:

        raise HTTPException(400, "Invalid stake or outcome")



    market = db.get(Market, market_id)

    if not market:

        raise HTTPException(404, "Market not found")



    if market.status != "open" or not (market.open_time <= now < market.close_time):

        raise HTTPException(400, "Market is not open")



    existing = (

        db.query(MarketPosition)

        .filter_by(user_id=user.id, market_id=market_id)

        .first()

    )

    if existing:

        raise HTTPException(400, "Already entered this market")



    outcome = (

        db.query(MarketOutcome)

        .filter_by(id=outcome_id, market_id=market_id)

        .first()

    )

    if not outcome:

        raise HTTPException(400, "Invalid outcome")



    wallet = (

        db.query(Wallet)

        .filter_by(user_id=user.id, currency_type="virtual")

        .with_for_update()

        .first()

    )

    if not wallet or wallet.balance < stake:

        raise HTTPException(400, "Insufficient balance")



    try:

        wallet.balance -= stake



        position = MarketPosition(

            user_id=user.id,

            market_id=market_id,

            outcome_id=outcome_id,

            stake_amount=stake,

        )



        db.add(position)

        db.commit()

    except Exception:

        db.rollback()

        raise

    finally:

        db.close()



    return {"ok": True}





