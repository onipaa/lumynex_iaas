"""Django app config for the load test."""

from django.apps import AppConfig


class LoadtestConfig(AppConfig):
    """Load test pages and the tick API."""

    default_auto_field = "django.db.models.BigAutoField"
    name = "loadtest"
