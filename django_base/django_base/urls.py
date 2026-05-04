"""
URL configuration for django_base project.

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/6.0/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  path('', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.urls import include, path
    2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
"""
from django.contrib import admin
from django.core.cache import cache
from django.conf import settings
from django.db import DatabaseError, connection
from django.http import JsonResponse
from django.urls import path
import socket


def db_health(_request):
    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1")
            cursor.fetchone()
    except DatabaseError:
        return JsonResponse({"database": "error"}, status=503)
    return JsonResponse({"database": "ok"})


def cache_health(_request):
    cache_key = "health:cache:counter"

    try:
        cache.add(cache_key, 0, timeout=60)
        counter = cache.incr(cache_key)
        stored_value = cache.get(cache_key)
    except Exception as exc:
        return JsonResponse(
            {
                "cache": "error",
                "backend": settings.CACHES["default"]["BACKEND"],
                "detail": str(exc),
            },
            status=503,
        )

    return JsonResponse(
        {
            "cache": "ok",
            "backend": settings.CACHES["default"]["BACKEND"],
            "location": settings.CACHES["default"].get("LOCATION", "local-memory"),
            "hostname": socket.gethostname(),
            "counter": counter,
            "stored_value": stored_value,
        }
    )


urlpatterns = [
    path('admin/', admin.site.urls),
    path('health/db/', db_health),
    path('health/cache/', cache_health),
]
