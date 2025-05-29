# payments/webhook.py
import stripe
from datetime import datetime
from fastapi import APIRouter, Request, Header, HTTPException, Depends
from sqlalchemy.orm import Session

from database import get_db
from models import User
from config import settings

router = APIRouter(prefix="/payments", tags=["payments"])

stripe.api_key = settings.STRIPE_API_KEY

@router.post("/webhook")
async def stripe_webhook(
        request: Request,
        stripe_signature: str = Header(..., alias="Stripe-Signature"),
        db: Session = Depends(get_db),
):
    payload = await request.body()
    try:
        event = stripe.Webhook.construct_event(
            payload, stripe_signature, settings.STRIPE_WEBHOOK_SECRET
        )
    except stripe.error.SignatureVerificationError:
        raise HTTPException(400, "Invalid Stripe signature")

    data = event["data"]["object"]
    typ  = event["type"]

    # 1) On checkout completion
    if typ == "checkout.session.completed":
        sub = stripe.Subscription.retrieve(data["subscription"])
        user = db.query(User).filter_by(stripe_customer_id=data["customer"]).first()
        if user:
            user.is_subscribed = True
            user.subscription_expires = datetime.utcfromtimestamp(sub.current_period_end)
            user.stripe_subscription_id = sub.id
            db.commit()

    # 2) On renewals
    elif typ == "invoice.payment_succeeded":
        sub = stripe.Subscription.retrieve(data["subscription"])
        user = db.query(User).filter_by(stripe_subscription_id=sub.id).first()
        if user:
            user.subscription_expires = datetime.utcfromtimestamp(sub.current_period_end)
            db.commit()

    # 3) On cancel or failure
    elif typ in ("customer.subscription.deleted", "invoice.payment_failed"):
        sub_id = data.get("id") or data.get("subscription")
        user = db.query(User).filter_by(stripe_subscription_id=sub_id).first()
        if user:
            user.is_subscribed = False
            user.subscription_expires = None
            db.commit()

    return {"status": "success"}
