import pytest
from django.urls import reverse
from rest_framework.test import APIClient
from rest_framework import status


@pytest.fixture
def api_client():
    return APIClient()


@pytest.mark.django_db
def test_health_check_endpoint(api_client):
    """Test that GET /api/v1/health/ returns 200 and valid JSON schema."""
    url = reverse("health-check")
    response = api_client.get(url)

    assert response.status_code == status.HTTP_200_OK
    data = response.json()
    assert data["status"] == "healthy"
    assert data["service"] == "Texora AI Factory Operations Platform"
    assert data["version"] == "1.0.0"
    assert "timestamp" in data


@pytest.mark.django_db
def test_readiness_check_endpoint(api_client):
    """Test that GET /api/v1/health/readiness/ verifies database connectivity."""
    url = reverse("readiness-check")
    response = api_client.get(url)

    assert response.status_code == status.HTTP_200_OK
    data = response.json()
    assert data["status"] == "ready"
    assert data["dependencies"]["database"] == "connected"
    assert "timestamp" in data
