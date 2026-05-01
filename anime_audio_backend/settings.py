import os
from typing import Optional

STRIPE_SECRET_KEY           = os.getenv("STRIPE_API_KEY")
STRIPE_WEBHOOK_SECRET    = os.getenv("STRIPE_WEBHOOK_SECRET")
STRIPE_PUBLISHABLE_KEY   = os.getenv("STRIPE_PUBLISHABLE_KEY")
STRIPE_PRICE_WATCHER     = os.getenv("STRIPE_PRICE_WATCHER")   # free tier product
STRIPE_PRICE_OTAKU       = os.getenv("STRIPE_PRICE_OTAKU")
STRIPE_PRICE_SENPAI      = os.getenv("STRIPE_PRICE_SENPAI")
STRIPE_PRICE_KAMISAMA    = os.getenv("STRIPE_PRICE_KAMISAMA")