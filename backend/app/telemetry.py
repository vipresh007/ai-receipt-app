import logging

from app.config import get_settings

logger = logging.getLogger(__name__)

# The Azure SDK + OTel exporter log every internal HTTP call at INFO, which
# drowns the app's own access logs. Pin them to WARNING.
_NOISY_LOGGERS = (
    "azure.core.pipeline.policies.http_logging_policy",
    "azure.monitor.opentelemetry.exporter",
    "azure.identity",
    "opentelemetry.attributes",
    "httpx",
    "httpcore",
)


def configure_telemetry(app=None) -> None:
    """Wire Azure Application Insights if a connection string is present.

    Never raises — monitoring must not take the API down.
    """
    settings = get_settings()
    logging.basicConfig(level=settings.log_level.upper())
    for name in _NOISY_LOGGERS:
        logging.getLogger(name).setLevel(logging.WARNING)

    if not settings.applicationinsights_connection_string:
        logger.info("App Insights not configured; skipping telemetry setup.")
        return

    try:
        from azure.monitor.opentelemetry import configure_azure_monitor

        configure_azure_monitor(connection_string=settings.applicationinsights_connection_string)
        if app is not None:
            from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor

            FastAPIInstrumentor.instrument_app(app)
        # configure_azure_monitor can re-enable verbose azure logging — pin again.
        for name in _NOISY_LOGGERS:
            logging.getLogger(name).setLevel(logging.WARNING)
        logger.info("Azure Application Insights telemetry enabled.")
    except Exception:  # noqa: BLE001 - telemetry is best-effort
        logger.warning("Failed to configure Azure telemetry", exc_info=True)
