from datetime import datetime
from pydantic import BaseModel
from decimal import Decimal

class WalletTransactionOut(BaseModel):
    id: int
    amount: Decimal
    reason: str
    reference_type: str | None
    reference_id: int | None
    created_at: datetime

    class Config:
        from_attributes = True
