# lib/payments/routes.py
import stripe
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import Optional
from database import get_db
from models import User
from auth_utils import get_current_user
from config import settings

router = APIRouter()

PRICE_IDS = {
    "Watcher": settings.STRIPE_PRICE_WATCHER,
    "Otaku":   settings.STRIPE_PRICE_OTAKU,
    "Senpai":  settings.STRIPE_PRICE_SENPAI,
    "Kami":    settings.STRIPE_PRICE_KAMISAMA,
}

@router.post("/create-payment-sheet")
def create_payment_sheet(
    tier: str = Query(..., description="One of watcher|otaku|senpai|kami"),
    db: Session = Depends(get_db),
    user: User    = Depends(get_current_user),
):
    price_id = PRICE_IDS.get(tier)
    if price_id is None:
        raise HTTPException(400, "Invalid tier")

    if not user.stripe_customer_id:
        cust = stripe.Customer.create(email=user.email)
        user.stripe_customer_id = cust.id
        db.add(user); db.commit()

    eph = stripe.EphemeralKey.create(
        customer=user.stripe_customer_id,
        stripe_version="2022-11-15",
    )
    price = stripe.Price.retrieve(price_id)
    intent = stripe.PaymentIntent.create(
        amount=price.unit_amount,
        currency=price.currency,
        customer=user.stripe_customer_id,
        automatic_payment_methods={"enabled": True},
    )

    return {
        "customer":       user.stripe_customer_id,
        "ephemeralKey":   eph.secret,
        "paymentIntent":  intent.client_secret,
        "publishableKey": settings.STRIPE_PUBLISHABLE_KEY,
    }
