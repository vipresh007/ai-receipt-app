"""The LLM extraction contract.

`ExtractedReceipt` is what we ask Azure OpenAI to return (strict structured
output). Money values are decimal *strings* so nothing rounds through a float.
"""

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

CategorySlug = Literal[
    "groceries",
    "restaurants",
    "transport",
    "shopping",
    "entertainment",
    "health",
    "utilities",
    "travel",
    "other",
]


class ExtractedLineItem(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str
    price: str  # decimal string, e.g. "4.29"
    quantity: int = 1


class ExtractedReceipt(BaseModel):
    model_config = ConfigDict(extra="forbid")

    merchant: str = ""
    purchased_at: str | None = None  # YYYY-MM-DD
    total: str = "0"  # decimal string
    tax: str = "0"  # decimal string
    category: CategorySlug = "other"
    currency: str = "USD"
    line_items: list[ExtractedLineItem] = Field(default_factory=list)
    confidence: float | None = None
