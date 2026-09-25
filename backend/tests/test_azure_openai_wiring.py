"""Guards against openai-SDK API drift without making a network call."""

from openai import AzureOpenAI

from app.services.azure_openai import AzureOpenAIExtractor, ExtractionError


def test_parse_endpoint_exists_on_client():
    client = AzureOpenAI(
        azure_endpoint="https://example.openai.azure.com",
        api_key="not-real",
        api_version="2025-04-01-preview",
    )
    # `extract()` calls exactly this path.
    assert hasattr(client.chat.completions, "parse")


def test_extractor_errors_cleanly_when_unconfigured():
    import pytest

    extractor = AzureOpenAIExtractor()
    assert extractor.settings.azure_openai_configured is False
    with pytest.raises(ExtractionError):
        _ = extractor.client


def _capturing_extractor(effort: str):
    """An extractor whose client records the kwargs `extract()` sends."""
    from types import SimpleNamespace

    from app.config import get_settings
    from app.schemas.extraction import ExtractedReceipt

    sent: dict = {}

    def parse(**kwargs):
        sent.update(kwargs)
        parsed = ExtractedReceipt.model_validate(
            {"merchant": "M", "total": "1.00", "category": "other", "line_items": []},
            strict=False,
        )
        message = SimpleNamespace(refusal=None, parsed=parsed)
        return SimpleNamespace(choices=[SimpleNamespace(message=message)])

    settings = get_settings().model_copy(update={"azure_openai_reasoning_effort": effort})
    extractor = AzureOpenAIExtractor(settings)
    extractor._client = SimpleNamespace(
        chat=SimpleNamespace(completions=SimpleNamespace(parse=parse))
    )
    return extractor, sent


def test_reasoning_effort_is_sent_when_set():
    extractor, sent = _capturing_extractor("minimal")
    extractor.extract(image_bytes=b"x", ocr_lines=[])
    assert sent["reasoning_effort"] == "minimal"


def test_reasoning_effort_is_omitted_when_empty():
    extractor, sent = _capturing_extractor("")
    extractor.extract(image_bytes=b"x", ocr_lines=[])
    assert "reasoning_effort" not in sent
