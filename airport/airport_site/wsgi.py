"""WSGI entry for gunicorn."""

import logging
import os

logging.basicConfig(level=logging.INFO)

from django.core.wsgi import get_wsgi_application

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "airport_site.settings")
application = get_wsgi_application()
