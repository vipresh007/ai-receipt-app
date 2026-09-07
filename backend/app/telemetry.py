import logging

from app.config import get_settings

logger = logging.getLogger(__name__)


def configure_telemetry(app=None) -> None:
    """Wire Azure Application Insights if a connection string is present.

    Never raises — monitoring must not take the API down.
    """
    settings = get_settings()
    logging.basicConfig(level=settings.log_level.upper())

    if not settings.applicationinsights_connection_string:
        logger.info("App Insights not configured; skipping telemetry setup.")
        return

    try:
        from azure.monitor.opentelemetry import configure_azure_monitor

        configure_azure_monitor(connection_string=settings.applicationinsights_connection_string)
        if app is not None:
            from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor

            FastAPIInstrumentor.instrument_app(app)
        logger.info("Azure Application Insights telemetry enabled.")
    except Exception:  # noqa: BLE001 - telemetry is best-effort
        logger.warning("Failed to configure Azure telemetry", exc_info=True)
