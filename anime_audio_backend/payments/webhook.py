# payments/webhook.py

import logging
import stripe
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Request, Header, HTTPException, Depends
from sqlalchemy.orm import Session

from database import get_db
from models import User
from config import settings

router = APIRouter(prefix="/payments", tags=["payments"])

# Stripe API key for server-side calls
stripe.api_key = settings.STRIPE_SECRET_KEY

# Price-ID -> tier mapping (Watcher removed; free tier is always 0)
PRICE_TO_TIER = {
    settings.STRIPE_PRICE_OTAKU: 1,
    settings.STRIPE_PRICE_SENPAI: 2,
    settings.STRIPE_PRICE_KAMISAMA: 3,
}

# Optional fallback if you set Stripe Price.lookup_key values (recommended)
LOOKUP_TO_TIER = {
    "otaku": 1,
    "senpai": 2,
    "kami": 3,
    "kamisama": 3,
}


def _resolve_tier_from_subscription(sub: dict) -> Optional[int]:
    """
    Resolve our anime_tier_id from a Stripe subscription object.
    Prefers Price ID mapping; falls back to Price.lookup_key.
    """
    price = (
        sub.get("items", {})
        .get("data", [{}])[0]
        .get("price", {})
    )

    price_id = price.get("id")
    lookup_key = price.get("lookup_key")

    tier_id = PRICE_TO_TIER.get(price_id)
    if tier_id is None and lookup_key:
        tier_id = LOOKUP_TO_TIER.get(str(lookup_key).lower())

    # Helpful diagnostics
    logging.info(
        f"[tier] price_id={price_id!r} lookup_key={lookup_key!r} -> tier_id={tier_id!r} "
        f"known_price_ids={list(PRICE_TO_TIER.keys())}"
    )

    return tier_id


def _set_expiry_from_subscription(user: User, sub: dict, context: str) -> None:
    expires_ts = sub.get("current_period_end")
    if expires_ts is not None:
        user.subscription_expires = datetime.utcfromtimestamp(expires_ts)
    else:
        logging.warning(f"{context}: no current_period_end on sub {sub.get('id')}")


@router.post("/webhook")
async def stripe_webhook(
    request: Request,
    stripe_signature: Optional[str] = Header(None, alias="Stripe-Signature"),
    db: Session = Depends(get_db),
):
    # IMPORTANT: use raw body bytes for signature verification
    payload = await request.body()

    if not stripe_signature:
        logging.error("Missing Stripe-Signature header")
        raise HTTPException(400, "Missing Stripe-Signature header")

    try:
        event = stripe.Webhook.construct_event(
            payload=payload,
            sig_header=stripe_signature,
            secret=settings.STRIPE_WEBHOOK_SECRET,
        )
    except ValueError as e:
        logging.error(f"Invalid payload: {e}")
        raise HTTPException(400, "Invalid payload")
    except stripe.error.SignatureVerificationError as e:
        logging.error(f"Invalid signature: {e}")
        raise HTTPException(400, "Invalid signature")

    event_type = event.get("type")
    data = event.get("data", {}).get("object", {})
    logging.info(f"Stripe webhook received: {event_type}")

    # 1) New subscription via Checkout
    if event_type == "checkout.session.completed":
        cust_id = data.get("customer")
        sub_id = data.get("subscription")

        if not (cust_id and sub_id):
            logging.warning("checkout.session.completed missing customer or subscription id")
            return {"status": "success"}

        # Retrieve subscription so we can read price + current_period_end reliably
        sub = stripe.Subscription.retrieve(sub_id, expand=["items.data.price"])
        tier_id = _resolve_tier_from_subscription(sub)

        # find or link the user
        user = db.query(User).filter_by(stripe_customer_id=cust_id).first()

        # Fallback: client_reference_id -> user id
        if not user and data.get("client_reference_id"):
            try:
                uid = int(data["client_reference_id"])
                user = db.query(User).get(uid)
            except (ValueError, TypeError):
                user = None

            if user:
                user.stripe_customer_id = cust_id
                db.commit()
                logging.info(f"Linked stripe_customer_id to user #{user.id}")

        if user:
            user.is_subscribed = True
            user.cancel_at_period_end = False
            user.stripe_subscription_id = sub.get("id")

            if tier_id is not None:
                user.anime_tier_id = tier_id

            _set_expiry_from_subscription(user, sub, "checkout.session.completed")

            db.commit()
            logging.info(
                f"Checkout completed → user #{user.id} subscribed, "
                f"stripe_sub={sub.get('id')}, tier={user.anime_tier_id}, "
                f"expires={user.subscription_expires}"
            )
        else:
            logging.warning(
                f"No user for stripe_customer_id={cust_id!r} and no usable client_reference_id"
            )

    # 2) Recurring payment succeeded — extend access
    elif event_type == "invoice.payment_succeeded":
        invoice = data
        cust_id = invoice.get("customer")
        sub_id = invoice.get("subscription")

        user = db.query(User).filter_by(stripe_customer_id=cust_id).first()
        if not user:
            logging.warning(f"invoice.payment_succeeded: No user for customer {cust_id!r}")
        else:
            user.is_subscribed = True
            user.cancel_at_period_end = False

            if sub_id:
                # Pull subscription to get current_period_end + current price reliably
                sub = stripe.Subscription.retrieve(sub_id, expand=["items.data.price"])
                user.stripe_subscription_id = sub_id

                tier_id = _resolve_tier_from_subscription(sub)
                if tier_id is not None:
                    user.anime_tier_id = tier_id

                _set_expiry_from_subscription(user, sub, "invoice.payment_succeeded")
            else:
                logging.warning(
                    "invoice.payment_succeeded missing subscription id; cannot refresh expiry from subscription"
                )

            db.commit()
            logging.info(
                f"Invoice succeeded → user #{user.id} expires at {user.subscription_expires} "
                f"tier={user.anime_tier_id}"
            )

    # 3) Subscription canceled/ended
    elif event_type == "customer.subscription.deleted":
        sub_id = data.get("id")
        user = db.query(User).filter_by(stripe_subscription_id=sub_id).first()
        if user:
            user.is_subscribed = False
            user.cancel_at_period_end = False
            user.subscription_expires = None
            user.anime_tier_id = 0  # free tier
            db.commit()
            logging.info(f"Subscription ended → user #{user.id} downgraded to free tier")
        else:
            logging.warning(f"No user for cancelled sub {sub_id!r}")

    # 4) Payment failure — immediate unsubscribe
    elif event_type == "invoice.payment_failed":
        sub_id = data.get("subscription")
        user = db.query(User).filter_by(stripe_subscription_id=sub_id).first()
        if user:
            user.is_subscribed = False
            user.cancel_at_period_end = False
            user.subscription_expires = None
            user.anime_tier_id = 0  # free tier
            db.commit()
            logging.info(f"Payment failed → user #{user.id} downgraded to free tier")
        else:
            logging.warning(f"No user for failed invoice sub {sub_id!r}")

    # 5) Plan change or cancel-at-period-end toggled
    elif event_type == "customer.subscription.updated":
        sub_payload = data  # payload contains the subscription (may not include expanded price)
        sub_id = sub_payload.get("id")
        cancel_flag = sub_payload.get("cancel_at_period_end", False)

        # Ensure we have price.lookup_key if you rely on it (expand)
        sub = stripe.Subscription.retrieve(sub_id, expand=["items.data.price"]) if sub_id else sub_payload
        tier_id = _resolve_tier_from_subscription(sub)

        user = db.query(User).filter_by(stripe_subscription_id=sub_id).first()
        if user:
            if tier_id is not None:
                user.anime_tier_id = tier_id

            user.cancel_at_period_end = cancel_flag

            # update expiry if Stripe provides it
            _set_expiry_from_subscription(user, sub, "customer.subscription.updated")

            # if not canceling, keep subscribed
            if not cancel_flag:
                user.is_subscribed = True

            db.commit()
            logging.info(
                f"Subscription updated → user #{user.id} tier={user.anime_tier_id}, "
                f"cancel_at_period_end={user.cancel_at_period_end}, "
                f"expires={user.subscription_expires}"
            )
        else:
            logging.warning(f"No user for updated sub {sub_id!r}")

    else:
        logging.info(f"No handler for event type: {event_type}")

    return {"status": "success"}
