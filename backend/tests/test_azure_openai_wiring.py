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
