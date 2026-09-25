import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/design/design_system.dart';
import '../../domain/entities/report_overview.dart';
import 'report_widgets.dart';

/// Combined chart: bars = chiffre d'affaires (left axis), line = number of
/// sales (right axis). Buckets come from the server already sized for the
/// period (hourly for a day, daily up to ~5 weeks, monthly beyond), so the
/// chart never re-buckets. Hover shows the bucket's date, CA and sales.
///
/// Both axes use 4 intervals so their grid lines coincide.
class RevenueOrdersChart extends StatefulWidget {
  final ReportRevenueSeries series;
  final String revenueLabel;
  final String salesLabel;

  const RevenueOrdersChart({
    super.key,
    required this.series,
    required this.revenueLabel,
    required this.salesLabel,
  });

  @override
  State<RevenueOrdersChart> createState() => _RevenueOrdersChartState();
}

class _RevenueOrdersChartState extends State<RevenueOrdersChart> {
  int? _hover;

  static const double _left = _ChartPainter.left;
  static const double _right = _ChartPainter.right;

  String _title(ReportBucket b) {
    switch (widget.series.granularity) {
      case 'hour':
        final end = b.start.add(const Duration(hours: 1));
        return '${ReportFormat.date(b.start)}  ${DateFormat('HH:00').format(b.start)} - ${DateFormat('HH:00').format(end)}';
      case 'month':
        return DateFormat('MM/yyyy').format(b.start);
      default:
        return ReportFormat.date(b.start);
    }
  }

  void _updateHover(Offset position, double width) {
    final n = widget.series.buckets.length;
    final plotW = width - _left - _right;
    if (n == 0 ||
        plotW <= 0 ||
        position.dx < _left ||
        position.dx > _left + plotW) {
      if (_hover != null) setState(() => _hover = null);
      return;
    }
    final index =
        ((position.dx - _left) / (plotW / n)).floor().clamp(0, n - 1).toInt();
    if (index != _hover) setState(() => _hover = index);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final buckets = widget.series.buckets;

    final maxRevenue =
        buckets.fold<double>(0, (m, b) => math.max(m, b.revenue));
    final maxCount = buckets.fold<int>(0, (m, b) => math.max(m, b.saleCount));
    final revenueStep = _niceStep(maxRevenue / 4);
    final countStep = math.max(1, (maxCount / 4).ceil());

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _LegendDot(
                  color: colors.primary,
                  label: widget.revenueLabel,
                  square: true),
              const SizedBox(width: AppSpacing.lg),
              _LegendDot(color: colors.textPrimary, label: widget.salesLabel),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                final n = buckets.length;
                final plotW = size.width - _left - _right;
                final hover = _hover;

                Widget? tooltip;
                if (hover != null && hover < n && plotW > 0) {
                  final b = buckets[hover];
                  final cx = _left + (plotW / n) * (hover + 0.5);
                  const tipWidth = 190.0;
                  final tipLeft = (cx - tipWidth / 2)
                      .clamp(0.0, math.max(0.0, size.width - tipWidth))
                      .toDouble();
                  tooltip = Positioned(
                    left: tipLeft,
                    top: 0,
                    width: tipWidth,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: AppRadius.xsAll,
                          border: Border.all(color: colors.borderStrong),
                          boxShadow:
                              AppShadows.hover(Theme.of(context).brightness),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_title(b),
                                style: context.text.label
                                    .copyWith(color: colors.textPrimary)),
                            const SizedBox(height: 4),
                            Text(
                                '${widget.revenueLabel} : ${ReportFormat.money(b.revenue)}',
                                style: context.text.bodySecondary
                                    .copyWith(fontSize: 12)),
                            Text(
                                '${widget.salesLabel} : ${ReportFormat.integer(b.saleCount)}',
                                style: context.text.bodySecondary
                                    .copyWith(fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                return MouseRegion(
                  onHover: (event) =>
                      _updateHover(event.localPosition, size.width),
                  onExit: (_) => setState(() => _hover = null),
                  child: Stack(
                    children: [
                      CustomPaint(
                        size: size,
                        painter: _ChartPainter(
                          buckets: buckets,
                          granularity: widget.series.granularity,
                          revenueMax: revenueStep * 4,
                          countMax: (countStep * 4).toDouble(),
                          hover: hover,
                          barColor: colors.primary,
                          lineColor: colors.textPrimary,
                          gridColor: colors.border,
                          labelColor: colors.textSecondary,
                          surfaceColor: colors.surface,
                          hoverColor: colors.primary.withOpacity(0.08),
                        ),
                      ),
                      if (tooltip != null) tooltip,
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 1 / 2 / 5 x 10^k step that is >= [raw] (and never 0).
  static double _niceStep(double raw) {
    if (raw <= 0) return 1;
    final exponent = (math.log(raw) / math.ln10).floor();
    final base = math.pow(10, exponent).toDouble();
    final fraction = raw / base;
    final nice =
        fraction <= 1 ? 1 : (fraction <= 2 ? 2 : (fraction <= 5 ? 5 : 10));
    return nice * base;
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  final bool square;

  const _LegendDot(
      {required this.color, required this.label, this.square = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: square ? BoxShape.rectangle : BoxShape.circle,
            borderRadius: square ? BorderRadius.circular(2) : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: context.text.bodySecondary.copyWith(fontSize: 12)),
      ],
    );
  }
}

class _ChartPainter extends CustomPainter {
  static const double left = 54;
  static const double right = 34;
  static const double top = 10;
  static const double bottom = 24;

  final List<ReportBucket> buckets;
  final String granularity;
  final double revenueMax;
  final double countMax;
  final int? hover;
  final Color barColor;
  final Color lineColor;
  final Color gridColor;
  final Color labelColor;
  final Color surfaceColor;
  final Color hoverColor;

  const _ChartPainter({
    required this.buckets,
    required this.granularity,
    required this.revenueMax,
    required this.countMax,
    required this.hover,
    required this.barColor,
    required this.lineColor,
    required this.gridColor,
    required this.labelColor,
    required this.surfaceColor,
    required this.hoverColor,
  });

  static String _compact(double v) {
    if (v >= 1000) {
      final k = v / 1000;
      return '${k == k.roundToDouble() ? k.toStringAsFixed(0) : k.toStringAsFixed(1)}k';
    }
    return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  }

  void _label(
    Canvas canvas,
    String text,
    Offset anchor, {
    TextAlign align = TextAlign.left,
    bool centerY = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
          text: text, style: TextStyle(fontSize: 10.5, color: labelColor)),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    var dx = anchor.dx;
    if (align == TextAlign.right) dx -= painter.width;
    if (align == TextAlign.center) dx -= painter.width / 2;
    final dy = centerY ? anchor.dy - painter.height / 2 : anchor.dy;
    painter.paint(canvas, Offset(dx, dy));
  }

  String _xLabel(ReportBucket b) {
    switch (granularity) {
      case 'hour':
        return DateFormat('HH:00').format(b.start);
      case 'month':
        return DateFormat('MM/yy').format(b.start);
      default:
        return DateFormat('dd/MM').format(b.start);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final plotW = size.width - left - right;
    final plotH = size.height - top - bottom;
    final n = buckets.length;
    if (plotW <= 0 || plotH <= 0 || n == 0) return;

    final slot = plotW / n;
    final baseline = top + plotH;

    // Grid + both axes (4 intervals each).
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = baseline - plotH * i / 4;
      canvas.drawLine(Offset(left, y), Offset(left + plotW, y), grid);
      _label(canvas, _compact(revenueMax * i / 4), Offset(left - 6, y),
          align: TextAlign.right, centerY: true);
      _label(canvas, (countMax * i / 4).round().toString(),
          Offset(left + plotW + 6, y),
          centerY: true);
    }

    if (hover != null && hover! < n) {
      canvas.drawRect(
        Rect.fromLTWH(left + slot * hover!, top, slot, plotH),
        Paint()..color = hoverColor,
      );
    }

    // Bars: chiffre d'affaires.
    final barWidth = math.min(slot * 0.62, 38.0);
    final barPaint = Paint()..color = barColor;
    for (var i = 0; i < n; i++) {
      final b = buckets[i];
      if (b.revenue <= 0) continue;
      final h = math.max(1.0, plotH * (b.revenue / revenueMax));
      final cx = left + slot * (i + 0.5);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(cx - barWidth / 2, baseline - h, barWidth, h),
          topLeft: const Radius.circular(3),
          topRight: const Radius.circular(3),
        ),
        barPaint,
      );
    }

    // Line: number of sales.
    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    final points = <Offset>[];
    for (var i = 0; i < n; i++) {
      final cx = left + slot * (i + 0.5);
      final cy = baseline - plotH * (buckets[i].saleCount / countMax);
      points.add(Offset(cx, cy));
      if (i == 0) {
        path.moveTo(cx, cy);
      } else {
        path.lineTo(cx, cy);
      }
    }
    if (n > 1) canvas.drawPath(path, linePaint);
    final dotFill = Paint()..color = surfaceColor;
    final dotStroke = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    // With many buckets the dots would merge into a blob: draw them only
    // when there is room, always for the hovered bucket.
    final showDots = slot >= 14;
    for (var i = 0; i < n; i++) {
      if (!showDots && i != hover) continue;
      canvas.drawCircle(points[i], 3.5, dotFill);
      canvas.drawCircle(points[i], 3.5, dotStroke);
    }

    // X labels, thinned out so they never overlap.
    const labelSlot = 46.0;
    final every = math.max(1, (labelSlot / slot).ceil());
    for (var i = 0; i < n; i += every) {
      _label(canvas, _xLabel(buckets[i]),
          Offset(left + slot * (i + 0.5), baseline + 6),
          align: TextAlign.center);
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) {
    return old.buckets != buckets ||
        old.hover != hover ||
        old.revenueMax != revenueMax ||
        old.countMax != countMax ||
        old.barColor != barColor ||
        old.lineColor != lineColor;
  }
}
