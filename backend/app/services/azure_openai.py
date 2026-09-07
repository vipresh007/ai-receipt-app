"""Azure OpenAI receipt extraction.

Sends the receipt image (plus best-effort OCR text) to a vision-capable Azure
OpenAI deployment and asks for a strict structured `ExtractedReceipt`.
"""

import base64
import logging

from openai import AzureOpenAI

from app.config import Settings, get_settings
from app.schemas.extraction import ExtractedReceipt

logger = logging.getLogger(__name__)

_SYSTEM_PROMPT = (
    "You extract structured data from receipt photos for an expense tracker. "
    "Transcribe only what is visible in the image; the OCR text is a noisy aid, "
    "not ground truth. Never invent a merchant, amount, or date — if a field is "
    "not legible use the empty/zero/null fallback described by the schema. "
    "Amounts are decimal strings using a period as the decimal separator, with "
    "no currency symbol and no thousands separators. Dates are YYYY-MM-DD. "
    "Choose the single best-fitting category from the allowed list."
)


class ExtractionError(Exception):
    """Raised when the model cannot return usable structured data."""


class AzureOpenAIExtractor:
    def __init__(self, settings: Settings | None = None) -> None:
        self.settings = settings or get_settings()
        self._client: AzureOpenAI | None = None

    @property
    def client(self) -> AzureOpenAI:
        if self._client is None:
            if not self.settings.azure_openai_configured:
                raise ExtractionError("Azure OpenAI is not configured.")
            self._client = AzureOpenAI(
                azure_endpoint=self.settings.azure_openai_endpoint,
                api_key=self.settings.azure_openai_api_key,
                api_version=self.settings.azure_openai_api_version,
            )
        return self._client

    def extract(
        self,
        *,
        image_bytes: bytes,
        ocr_lines: list[str],
        media_type: str = "image/jpeg",
    ) -> ExtractedReceipt:
        image_b64 = base64.b64encode(image_bytes).decode()
        ocr_block = "\n".join(ocr_lines[:200]).strip() or "(none)"

        try:
            # gpt-5-family (reasoning) models reject `temperature` != 1 and use
            # `max_completion_tokens` instead of `max_tokens`. This keeps room
            # for reasoning tokens plus the JSON payload.
            completion = self.client.chat.completions.parse(
                model=self.settings.azure_openai_deployment,
                max_completion_tokens=4096,
                messages=[
                    {"role": "system", "content": _SYSTEM_PROMPT},
                    {
                        "role": "user",
                        "content": [
                            {
                                "type": "text",
                                "text": (
                                    "Extract this receipt. OCR lines "
                                    f"(may be wrong or empty):\n<ocr>\n{ocr_block}\n</ocr>"
                                ),
                            },
                            {
                                "type": "image_url",
                                "image_url": {"url": f"data:{media_type};base64,{image_b64}"},
                            },
                        ],
                    },
                ],
                response_format=ExtractedReceipt,
            )
        except Exception as exc:  # noqa: BLE001 - surface a clean error upstream
            logger.warning("Azure OpenAI extraction failed", exc_info=True)
            raise ExtractionError("The extraction service is unavailable.") from exc

        message = completion.choices[0].message
        if message.refusal:
            raise ExtractionError("Couldn't process that image.")
        if message.parsed is None:
            raise ExtractionError("The model returned no structured data.")
        return message.parsed
