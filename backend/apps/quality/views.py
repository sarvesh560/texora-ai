from rest_framework import viewsets, permissions
from rest_framework.decorators import action
from rest_framework.response import Response
from django.db.models import Avg, Sum, Count
from .models import QualityInspection, QualityDefect, DefectType
from .serializers import QualityInspectionSerializer, QualityDefectSerializer


class QualityInspectionViewSet(viewsets.ModelViewSet):
    queryset = QualityInspection.objects.select_related("production_batch", "machine").prefetch_related("defects").all()
    serializer_class = QualityInspectionSerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["production_batch", "machine", "status"]
    search_fields = ["inspection_code", "inspector_name"]

    @action(detail=False, methods=["get"])
    def summary(self, request):
        qs = self.get_queryset()
        total = qs.count()
        passed = qs.filter(status="PASSED").count()
        failed = qs.filter(status="FAILED").count()
        conditional = qs.filter(status="CONDITIONAL_PASS").count()

        avg_score = qs.aggregate(avg=Avg("overall_score"))["avg"] or 0.0
        pass_rate = round((passed / total * 100), 1) if total > 0 else 100.0

        # Defect breakdown
        defects_qs = QualityDefect.objects.all()
        defect_type_counts = (
            defects_qs.values("defect_type")
            .annotate(total_count=Sum("count"))
            .order_by("-total_count")
        )
        defects_by_type = [
            {
                "type": d["defect_type"],
                "label": dict(DefectType.choices).get(d["defect_type"], d["defect_type"]),
                "count": d["total_count"],
            }
            for d in defect_type_counts
        ]

        severity_counts = (
            defects_qs.values("severity")
            .annotate(total_count=Sum("count"))
        )
        severity_map = {s["severity"]: s["total_count"] for s in severity_counts}

        return Response({
            "total_inspections": total,
            "passed_count": passed,
            "failed_count": failed,
            "conditional_count": conditional,
            "pass_rate_pct": pass_rate,
            "average_quality_score": round(float(avg_score), 2),
            "total_defects_logged": defects_qs.aggregate(total=Sum("count"))["total"] or 0,
            "defects_by_type": defects_by_type,
            "defects_by_severity": {
                "MINOR": severity_map.get("MINOR", 0),
                "MAJOR": severity_map.get("MAJOR", 0),
                "CRITICAL": severity_map.get("CRITICAL", 0),
            },
        })


class QualityDefectViewSet(viewsets.ModelViewSet):
    queryset = QualityDefect.objects.select_related("inspection").all()
    serializer_class = QualityDefectSerializer
    permission_classes = [permissions.AllowAny]
    filterset_fields = ["inspection", "defect_type", "severity"]
