import pytest
from django.urls import reverse
from rest_framework.test import APIClient
from rest_framework import status
from apps.factories.models import Factory, Department, DepartmentType
from apps.machines.models import MachineType, Machine, MachineStatus


@pytest.fixture
def api_client():
    return APIClient()


@pytest.mark.django_db
def test_factory_and_machine_api_endpoints(api_client):
    """Test GET and POST for Factory and Machine REST API endpoints."""
    factory = Factory.objects.create(name="Texora Coimbatore Mill", code="FAC-CBE-01")
    dept = Department.objects.create(
        factory=factory, department_type=DepartmentType.KNITTING, name="Knitting Section", code="KNT-01"
    )
    m_type = MachineType.objects.create(
        category=DepartmentType.KNITTING, name="Circular Single Jersey Machine", manufacturer="Mayer & Cie"
    )
    machine = Machine.objects.create(
        code="KNT-CS-01", name="Mayer Circular #1", machine_type=m_type, department=dept
    )

    # 1. Test Factory List API
    response = api_client.get("/api/v1/factories/")
    assert response.status_code == status.HTTP_200_OK
    assert len(response.json()) >= 1
    assert response.json()[0]["code"] == "FAC-CBE-01"

    # 2. Test Department List API
    response = api_client.get("/api/v1/departments/")
    assert response.status_code == status.HTTP_200_OK
    assert response.json()[0]["code"] == "KNT-01"

    # 3. Test Machine Detail & Telemetry action
    response = api_client.get(f"/api/v1/machines/{machine.id}/")
    assert response.status_code == status.HTTP_200_OK
    data = response.json()
    assert data["code"] == "KNT-CS-01"
    assert data["status"] == "OPERATIONAL"

    # 4. Test Telemetry Endpoint
    response = api_client.get(f"/api/v1/machines/{machine.id}/telemetry/")
    assert response.status_code == status.HTTP_200_OK
    assert isinstance(response.json(), list)


@pytest.mark.django_db
def test_approval_action_api(api_client):
    """Test approval workflow actions: POST /api/v1/approvals/{id}/approve/"""
    factory = Factory.objects.create(name="Texora Mill", code="FAC-03")
    dept = Department.objects.create(
        factory=factory, department_type=DepartmentType.FINISHING, name="Finishing Stenter", code="FIN-01"
    )
    from apps.incidents.models import FactoryIncident
    from apps.approvals.models import ApprovalRequest, ApprovalStatus

    incident = FactoryIncident.objects.create(
        incident_code="INC-FIN-001",
        factory=factory,
        department=dept,
        summary="Stenter exhaust humidity overload",
    )

    approval = ApprovalRequest.objects.create(
        approval_code="APR-2026-0099",
        incident=incident,
        title="Approve Exhaust Damper Throttle",
        description="Adjust exhaust airflow from 80% to 55%",
        status=ApprovalStatus.PENDING,
    )

    # Call approve action
    url = f"/api/v1/approvals/{approval.id}/approve/"
    response = api_client.post(
        url,
        {"approved_by": "Senior Mill Engineer", "response_notes": "Approved for 1 hour"},
        format="json",
    )
    assert response.status_code == status.HTTP_200_OK
    data = response.json()
    assert data["status"] == "APPROVED"
    assert data["approved_by"] == "Senior Mill Engineer"
