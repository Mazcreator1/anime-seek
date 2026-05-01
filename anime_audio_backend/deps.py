# app/deps.py
from fastapi import Depends, HTTPException, status
from models import User
from auth_utils import get_current_user
from typing import Optional

async def get_current_active_user(user: User = Depends(get_current_user)):
    if not user.is_active:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Inactive user")
    return user


def require_active_subscription(user: User):

    # free tier = watcher; quotas still enforced

    if user.stripe_price_id != STRIPE_PRICE_WATCHER:

        # they’re on a paid tier—must be active

        if user.subscription_status != "active":

            raise HTTPException(

                status_code=402,

                detail={

                    "error": "Subscription required",

                    "upgrade_url": "https://anime-seek.com/fastaapi/subscribe"

                }

            )

    # else: watcher tier => leave your existing quota‐check logic in place

    return