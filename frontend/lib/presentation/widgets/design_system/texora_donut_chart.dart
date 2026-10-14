import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/texora_design_system.dart';

class TexoraDonutSegment {
  final String label;
  final double value;
  final Color color;
  final String? countLabel;

  const TexoraDonutSegment({
    required this.label,
    required this.value,
    required this.color,
    this.countLabel,
  });
}

class TexoraDonutChart extends StatefulWidget {
  final List<TexoraDonutSegment> segments;
  final double size;
  final double strokeWidth;
  final String centerValue;
  final String centerLabel;
  final bool showLegend;
  final bool isInteractive;

  const TexoraDonutChart({
    super.key,
    required this.segments,
    this.size = 130,
    this.strokeWidth = 16,
    this.centerValue = '',
    this.centerLabel = '',
    this.showLegend = true,
    this.isInteractive = true,
  });

  @override
  State<TexoraDonutChart> createState() => _TexoraDonutChartState();
}

class _TexoraDonutChartState extends State<TexoraDonutChart> {
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    final validSegments = widget.segments.where((s) => s.value > 0).toList();
    final totalValue = validSegments.fold<double>(0.0, (sum, s) => sum + s.value);

    final chartWidget = TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (context, animProgress, child) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size(widget.size, widget.size),
                painter: _DonutChartPainter(
                  segments: validSegments,
                  totalValue: totalValue,
                  strokeWidth: widget.strokeWidth,
                  hoveredIndex: _hoveredIndex,
                  progress: animProgress,
                ),
              ),
              // Center Label & Value
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.centerValue.isNotEmpty)
                    Text(
                      _hoveredIndex != null && _hoveredIndex! < validSegments.length
                          ? (validSegments[_hoveredIndex!].countLabel ??
                              validSegments[_hoveredIndex!].value.toInt().toString())
                          : widget.centerValue,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: TexoraColors.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                  if (widget.centerLabel.isNotEmpty)
                    Text(
                      _hoveredIndex != null && _hoveredIndex! < validSegments.length
                          ? validSegments[_hoveredIndex!].label
                          : widget.centerLabel,
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: TexoraColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );

    if (!widget.showLegend) {
      return chartWidget;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 420;

        final legendItems = widget.segments.map((s) {
          final idx = validSegments.indexOf(s);
          final isHovered = _hoveredIndex == idx && idx != -1;
          final pct = totalValue > 0 ? (s.value / totalValue) * 100 : 0.0;

          return InkWell(
            onTap: widget.isInteractive && idx != -1
                ? () {
                    setState(() {
                      _hoveredIndex = _hoveredIndex == idx ? null : idx;
                    });
                  }
                : null,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: s.color,
                      shape: BoxShape.circle,
                      border: isHovered
                          ? Border.all(color: TexoraColors.textPrimary, width: 1.5)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    s.label,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: isHovered ? FontWeight.w700 : FontWeight.w500,
                      color: isHovered ? TexoraColors.textPrimary : TexoraColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${s.countLabel ?? s.value.toInt()} (${pct.toStringAsFixed(0)}%)',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: isHovered ? TexoraColors.textPrimary : TexoraColors.textMuted,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList();

        if (isNarrow) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              chartWidget,
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: legendItems,
              ),
            ],
          );
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            chartWidget,
            const SizedBox(width: 16),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: legendItems,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  final List<TexoraDonutSegment> segments;
  final double totalValue;
  final double strokeWidth;
  final int? hoveredIndex;
  final double progress;

  _DonutChartPainter({
    required this.segments,
    required this.totalValue,
    required this.strokeWidth,
    required this.hoveredIndex,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (totalValue <= 0 || segments.isEmpty) {
      final basePaint = Paint()
        ..color = TexoraColors.borderDefault
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;
      canvas.drawCircle(Offset(size.width / 2, size.height / 2), (size.width - strokeWidth) / 2, basePaint);
      return;
    }

    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    double startAngle = -math.pi / 2;
    const gapAngle = 0.04; // subtle gap between segments

    for (int i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final sweepAngle = (segment.value / totalValue) * (2 * math.pi) * progress;
      final effectiveSweep = math.max(0.0, sweepAngle - gapAngle);

      final isHovered = hoveredIndex == i;
      final currentStroke = isHovered ? strokeWidth + 4 : strokeWidth;

      final paint = Paint()
        ..color = isHovered ? segment.color : segment.color.withAlpha(220)
        ..style = PaintingStyle.stroke
        ..strokeWidth = currentStroke
        ..strokeCap = StrokeCap.round;

      if (effectiveSweep > 0.01) {
        canvas.drawArc(rect, startAngle + (gapAngle / 2), effectiveSweep, false, paint);
      }

      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) {
    return oldDelegate.hoveredIndex != hoveredIndex ||
        oldDelegate.progress != progress ||
        oldDelegate.segments != segments;
  }
}
