import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/texora_design_system.dart';

class TelemetryDataPoint {
  final DateTime timestamp;
  final double value;
  final String? label;

  const TelemetryDataPoint({
    required this.timestamp,
    required this.value,
    this.label,
  });
}

class TexoraTrendChart extends StatefulWidget {
  final List<TelemetryDataPoint> points;
  final String metricName;
  final String unit;
  final Color lineColor;
  final double? warningThreshold;
  final double? criticalThreshold;
  final double height;

  const TexoraTrendChart({
    super.key,
    required this.points,
    required this.metricName,
    required this.unit,
    this.lineColor = TexoraColors.primaryBlue,
    this.warningThreshold,
    this.criticalThreshold,
    this.height = 180,
  });

  @override
  State<TexoraTrendChart> createState() => _TexoraTrendChartState();
}

class _TexoraTrendChartState extends State<TexoraTrendChart> {
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.points.isEmpty) {
      return Container(
        height: widget.height,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: TexoraColors.workspaceBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: TexoraColors.borderDefault),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.show_chart_rounded, color: TexoraColors.textMuted, size: 28),
              const SizedBox(height: 8),
              Text(
                'No historical ${widget.metricName} readings logged for this asset.',
                style: const TextStyle(
                  color: TexoraColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Telemetry history appears as real sensor events occur.',
                style: TextStyle(color: TexoraColors.textMuted, fontSize: 10.5),
              ),
            ],
          ),
        ),
      );
    }

    // Sort chronologically ascending for the chart
    final sorted = List<TelemetryDataPoint>.from(widget.points)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final values = sorted.map((p) => p.value).toList();
    double minVal = values.reduce(math.min);
    double maxVal = values.reduce(math.max);

    if (widget.warningThreshold != null) {
      maxVal = math.max(maxVal, widget.warningThreshold!);
    }
    if (widget.criticalThreshold != null) {
      maxVal = math.max(maxVal, widget.criticalThreshold!);
    }

    // Padding for min/max
    final range = maxVal - minVal;
    final padding = range > 0 ? range * 0.15 : 1.0;
    final displayMin = math.max(0.0, minVal - padding);
    final displayMax = maxVal + padding;

    final hoveredPoint = _hoveredIndex != null && _hoveredIndex! < sorted.length
        ? sorted[_hoveredIndex!]
        : sorted.last;

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: TexoraColors.borderDefault),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with metric name, current value, and hovered timestamp
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: widget.lineColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.metricName.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: TexoraColors.textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${hoveredPoint.value.toStringAsFixed(2)} ${widget.unit}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: widget.lineColor,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
              Text(
                '${hoveredPoint.timestamp.hour.toString().padLeft(2, '0')}:${hoveredPoint.timestamp.minute.toString().padLeft(2, '0')}:${hoveredPoint.timestamp.second.toString().padLeft(2, '0')} (${sorted.length})',
                style: const TextStyle(
                  fontSize: 10,
                  color: TexoraColors.textMuted,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Chart Canvas
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return MouseRegion(
                  onHover: (event) {
                    final localX = event.localPosition.dx;
                    final step = constraints.maxWidth / math.max(1, sorted.length - 1);
                    final idx = (localX / step).round().clamp(0, sorted.length - 1);
                    if (_hoveredIndex != idx) {
                      setState(() => _hoveredIndex = idx);
                    }
                  },
                  onExit: (_) {
                    if (_hoveredIndex != null) {
                      setState(() => _hoveredIndex = null);
                    }
                  },
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, constraints.maxHeight),
                    painter: _TrendChartPainter(
                      points: sorted,
                      minVal: displayMin,
                      maxVal: displayMax,
                      lineColor: widget.lineColor,
                      warningThreshold: widget.warningThreshold,
                      criticalThreshold: widget.criticalThreshold,
                      hoveredIndex: _hoveredIndex,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendChartPainter extends CustomPainter {
  final List<TelemetryDataPoint> points;
  final double minVal;
  final double maxVal;
  final Color lineColor;
  final double? warningThreshold;
  final double? criticalThreshold;
  final int? hoveredIndex;

  _TrendChartPainter({
    required this.points,
    required this.minVal,
    required this.maxVal,
    required this.lineColor,
    this.warningThreshold,
    this.criticalThreshold,
    this.hoveredIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final range = maxVal - minVal > 0 ? maxVal - minVal : 1.0;
    final w = size.width;
    final h = size.height;

    // Helper: calculate Y coordinate
    double getY(double val) {
      final normalized = (val - minVal) / range;
      return h - (normalized * h);
    }

    // Helper: calculate X coordinate
    double getX(int idx) {
      if (points.length <= 1) return w / 2;
      return (idx / (points.length - 1)) * w;
    }

    // Draw grid lines
    final gridPaint = Paint()
      ..color = TexoraColors.borderDefault.withAlpha(120)
      ..strokeWidth = 0.8;
    for (int i = 1; i <= 3; i++) {
      final y = (h / 4) * i;
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }

    // Draw warning threshold line (dashed amber)
    if (warningThreshold != null && warningThreshold! >= minVal && warningThreshold! <= maxVal) {
      final y = getY(warningThreshold!);
      final warnPaint = Paint()
        ..color = const Color(0xFFF59E0B).withAlpha(180)
        ..strokeWidth = 1.0;
      _drawDashedLine(canvas, Offset(0, y), Offset(w, y), warnPaint);
    }

    // Draw critical threshold line (dashed red)
    if (criticalThreshold != null && criticalThreshold! >= minVal && criticalThreshold! <= maxVal) {
      final y = getY(criticalThreshold!);
      final critPaint = Paint()
        ..color = TexoraColors.criticalText.withAlpha(200)
        ..strokeWidth = 1.2;
      _drawDashedLine(canvas, Offset(0, y), Offset(w, y), critPaint);
    }

    // Compute Bezier Curve Path
    final path = Path();
    final fillPath = Path();

    final startX = getX(0);
    final startY = getY(points[0].value);
    path.moveTo(startX, startY);
    fillPath.moveTo(startX, h);
    fillPath.lineTo(startX, startY);

    for (int i = 0; i < points.length - 1; i++) {
      final x0 = getX(i);
      final y0 = getY(points[i].value);
      final x1 = getX(i + 1);
      final y1 = getY(points[i + 1].value);

      final cx0 = x0 + (x1 - x0) / 2;
      final cy0 = y0;
      final cx1 = x0 + (x1 - x0) / 2;
      final cy1 = y1;

      path.cubicTo(cx0, cy0, cx1, cy1, x1, y1);
      fillPath.cubicTo(cx0, cy0, cx1, cy1, x1, y1);
    }

    fillPath.lineTo(getX(points.length - 1), h);
    fillPath.close();

    // Draw soft gradient fill
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          lineColor.withAlpha(50),
          lineColor.withAlpha(5),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    // Draw main trend line
    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    // Draw hovered indicator dot and vertical cursor line
    if (hoveredIndex != null && hoveredIndex! < points.length) {
      final hx = getX(hoveredIndex!);
      final hy = getY(points[hoveredIndex!].value);

      final cursorPaint = Paint()
        ..color = TexoraColors.textMuted.withAlpha(120)
        ..strokeWidth = 1.0;
      canvas.drawLine(Offset(hx, 0), Offset(hx, h), cursorPaint);

      final dotBgPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      final dotStrokePaint = Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;

      canvas.drawCircle(Offset(hx, hy), 4.5, dotBgPaint);
      canvas.drawCircle(Offset(hx, hy), 4.5, dotStrokePaint);
    }
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashWidth = 5.0;
    const dashSpace = 4.0;
    double currentX = start.dx;
    while (currentX < end.dx) {
      final nextX = math.min(currentX + dashWidth, end.dx);
      canvas.drawLine(Offset(currentX, start.dy), Offset(nextX, start.dy), paint);
      currentX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _TrendChartPainter oldDelegate) {
    return oldDelegate.hoveredIndex != hoveredIndex ||
        oldDelegate.points != points ||
        oldDelegate.lineColor != lineColor;
  }
}
