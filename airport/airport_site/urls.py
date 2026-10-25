"""Routes for the airport load test."""

from django.urls import path

from loadtest import views

urlpatterns = [
    path("", views.home, name="home"),
    path("health", views.health, name="health"),
    path("start", views.start, name="start"),
    path("status", views.status, name="status"),
    path("cluster", views.cluster, name="cluster"),
    path("api/tick", views.tick, name="tick"),
]
