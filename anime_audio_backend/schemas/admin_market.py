# schemas/admin_market.py
from pydantic import BaseModel, Field
from typing import Any, Dict, List, Union
from datetime import datetime

class MarketOutcomeCreate(BaseModel):
    label: str

class AdminMarketCreate(BaseModel):
    title: str
    description: str
    category: str
    open_time: datetime
    close_time: datetime
    resolve_time: datetime
    resolution_source: str = "manual"
    resolution_data: Dict[str, Any] = Field(default_factory=dict)

    outcomes: List[Union[str, MarketOutcomeCreate]]
