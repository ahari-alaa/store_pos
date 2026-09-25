import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Minimal filled line chart, drawn by hand so the dashboard doesn't need
/// a new chart-package dependency. Good enough for a handful of points
/// (7-day sales trend) — not meant to be a general charting widget.
class SalesLineChart extends StatelessWidget {
  final List<double> values;
  final List<String> labels;

  const SalesLineChart({super.key, required this.values, required this.labels});

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return const Center(
        child: Text('No data yet', style: TextStyle(color: AppColors.textMuted)),
      );
    }
    return Column(
      children: [
        Expanded(
          child: CustomPaint(
            size: Size.infinite,
            painter: _LineChartPainter(values: values),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: labels
              .map((l) => Text(l, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)))
              .toList(),
        ),
      ],
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<double> values;

  _LineChartPainter({required this.values});

  @override
  void paint(Canvas canvas, Size size) {
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final minValue = values.reduce((a, b) => a < b ? a : b);
    final range = (maxValue - minValue).abs() < 1e-6 ? 1.0 : (maxValue - minValue);

    final stepX = values.length > 1 ? size.width / (values.length - 1) : 0.0;
    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final normalized = (values[i] - minValue) / range;
      final y = size.height - (normalized * (size.height - 12)) - 6;
      points.add(Offset(stepX * i, y));
    }

    // Filled area under the line.
    final fillPath = Path()..moveTo(points.first.dx, size.height);
    for (final p in points) {
      fillPath.lineTo(p.dx, p.dy);
    }
    fillPath.lineTo(points.last.dx, size.height);
    fillPath.close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.primary.withOpacity(0.22), AppColors.primary.withOpacity(0.0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    // Line itself.
    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      linePath.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = AppColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Dots on each point.
    final dotPaint = Paint()..color = AppColors.primary;
    for (final p in points) {
      canvas.drawCircle(p, 3.5, Paint()..color = Colors.white);
      canvas.drawCircle(p, 3.5, dotPaint..style = PaintingStyle.stroke..strokeWidth = 2);
      canvas.drawCircle(p, 2, dotPaint..style = PaintingStyle.fill);
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) => oldDelegate.values != values;
}
