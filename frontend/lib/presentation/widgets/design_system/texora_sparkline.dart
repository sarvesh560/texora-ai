import 'package:flutter/material.dart';
import '../../../core/theme/texora_design_system.dart';

class TexoraSparkline extends StatelessWidget {
  final List<double> data;
  final Color? color;
  final double width;
  final double height;
  final double strokeWidth;
  final bool showFill;

  const TexoraSparkline({
    super.key,
    required this.data,
    this.color,
    this.width = 72,
    this.height = 24,
    this.strokeWidth = 2.0,
    this.showFill = true,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return SizedBox(
        width: width,
        height: height,
        child: Center(
          child: Container(
            height: 1.5,
            width: width * 0.7,
            color: TexoraColors.borderDefault,
          ),
        ),
      );
    }

    final lineColor = color ??
        (data.last > (data.first * 1.25)
            ? TexoraColors.criticalText
            : TexoraColors.successText);

    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _SparklinePainter(
          data: data,
          lineColor: lineColor,
          strokeWidth: strokeWidth,
          showFill: showFill,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> data;
  final Color lineColor;
  final double strokeWidth;
  final bool showFill;

  _SparklinePainter({
    required this.data,
    required this.lineColor,
    required this.strokeWidth,
    required this.showFill,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) {
      final p = Paint()
        ..color = lineColor
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        p,
      );
      return;
    }

    double minY = data.reduce((a, b) => a < b ? a : b);
    double maxY = data.reduce((a, b) => a > b ? a : b);

    if (minY == maxY) {
      minY -= 1.0;
      maxY += 1.0;
    }

    final rangeY = maxY - minY;
    final stepX = size.width / (data.length - 1);

    final path = Path();
    final fillPath = Path();

    for (int i = 0; i < data.length; i++) {
      final x = i * stepX;
      final normalizedY = (data[i] - minY) / rangeY;
      final y = size.height - (normalizedY * (size.height - strokeWidth * 2)) - strokeWidth;

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        final prevX = (i - 1) * stepX;
        final prevNormY = (data[i - 1] - minY) / rangeY;
        final prevY = size.height - (prevNormY * (size.height - strokeWidth * 2)) - strokeWidth;

        final midX = (prevX + x) / 2;
        path.cubicTo(midX, prevY, midX, y, x, y);
        fillPath.cubicTo(midX, prevY, midX, y, x, y);
      }
    }

    if (showFill) {
      fillPath.lineTo(size.width, size.height);
      fillPath.close();

      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            lineColor.withAlpha(50),
            lineColor.withAlpha(5),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
        ..style = PaintingStyle.fill;

      canvas.drawPath(fillPath, fillPaint);
    }

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.data != data || oldDelegate.lineColor != lineColor;
  }
}
