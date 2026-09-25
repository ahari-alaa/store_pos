import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/design/design_system.dart';
import '../../../../core/l10n/locale_provider.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/ui/ui.dart';
import '../../../dashboard/domain/entities/dashboard_extras.dart';
import '../../../dashboard/presentation/widgets/dashboard_error_view.dart';
import '../providers/reports_provider.dart';

/// "Évolution du chiffre d'affaires" (spec §7) — a line chart over the
/// selected period, bucketed hourly/daily/monthly by the backend
/// depending on how wide that period is (reportService.js#
/// dashboardRevenueSeries's auto-granularity), never a fixed rolling
/// window unrelated to the filter above it. Hover shows a tooltip with
/// the bucket's date, revenue, and order count (when the backend
/// provided one — see [RevenueBucket.saleCount]).
class RevenueEvolutionChart extends ConsumerWidget {
  const RevenueEvolutionChart({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bucketsAsync = ref.watch(reportRevenueSeriesProvider);

    return AppSectionCard(
      title: tr(ref, 'reports.revenue_evolution'),
      child: SizedBox(
        height: 280,
        child: bucketsAsync.when(
          loading: () => const SizedBox(
            width: double.infinity,
            child: AppSkeleton(height: 240),
          ),
          error: (error, _) => DashboardErrorInline(
            error: error,
            onRetry: () => ref.invalidate(reportRevenueSeriesProvider),
          ),
          data: (buckets) {
            if (buckets.isEmpty || buckets.every((b) => b.revenue == 0)) {
              return AppEmptyState(
                icon: Icons.show_chart_rounded,
                title: tr(ref, 'reports.empty_title'),
                message: tr(ref, 'reports.empty_message'),
              );
            }
            return _RevenueLineChart(buckets: buckets);
          },
        ),
      ),
    );
  }
}

class _RevenueLineChart extends StatefulWidget {
  final List<RevenueBucket> buckets;

  const _RevenueLineChart({required this.buckets});

  @override
  State<_RevenueLineChart> createState() => _RevenueLineChartState();
}

class _RevenueLineChartState extends State<_RevenueLineChart> {
  int? _hoverIndex;

  void _updateHover(Offset localPosition, Size size) {
    if (widget.buckets.isEmpty) return;
    final step = size.width / (widget.buckets.length - 1).clamp(1, 1 << 30);
    final index = (localPosition.dx / step).round().clamp(0, widget.buckets.length - 1);
    setState(() => _hoverIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final buckets = widget.buckets;
    final maxRevenue = buckets.map((b) => b.revenue).fold<double>(0, (a, b) => a > b ? a : b);

    // Heuristic purely for axis-label formatting (the backend already
    // chose the actual bucketing) — a span under a day between the first
    // two buckets means hourly, more than ~40 days between first/last
    // means monthly, else daily.
    final isHourly = buckets.length > 1 &&
        buckets[1].bucketStart.difference(buckets[0].bucketStart).inHours < 20;
    final isMonthly = !isHourly &&
        buckets.isNotEmpty &&
        buckets.last.bucketStart.difference(buckets.first.bucketStart).inDays > 40;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              return MouseRegion(
                onHover: (event) => _updateHover(event.localPosition, size),
                onExit: (_) => setState(() => _hoverIndex = null),
                child: GestureDetector(
                  onPanUpdate: (details) => _updateHover(details.localPosition, size),
                  onPanEnd: (_) => setState(() => _hoverIndex = null),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CustomPaint(
                        size: size,
                        painter: _LineChartPainter(
                          buckets: buckets,
                          maxRevenue: maxRevenue <= 0 ? 1 : maxRevenue,
                          hoverIndex: _hoverIndex,
                          lineColor: colors.primary,
                          fillColor: colors.primary.withOpacity(0.12),
                          gridColor: colors.border,
                          hoverLineColor: colors.textMuted,
                        ),
                      ),
                      if (_hoverIndex != null)
                        _Tooltip(
                          bucket: buckets[_hoverIndex!],
                          index: _hoverIndex!,
                          total: buckets.length,
                          size: size,
                          isHourly: isHourly,
                          isMonthly: isMonthly,
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _AxisLabels(buckets: buckets, isMonthly: isMonthly, isHourly: isHourly),
      ],
    );
  }
}

class _AxisLabels extends StatelessWidget {
  final List<RevenueBucket> buckets;
  final bool isMonthly;
  final bool isHourly;

  const _AxisLabels({required this.buckets, required this.isMonthly, required this.isHourly});

  String _label(DateTime dt) {
    if (isHourly) return DateFormat.Hm().format(dt);
    if (isMonthly) return DateFormat('MMM yy').format(dt);
    return DateFormat('dd/MM').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    if (buckets.isEmpty) return const SizedBox.shrink();
    // Thin out labels so they never overlap on a wide bucket count (e.g.
    // 31 daily buckets) — show at most ~6 evenly spaced labels.
    final maxLabels = 6;
    final step = (buckets.length / maxLabels).ceil().clamp(1, buckets.length);
    final entries = <Widget>[];
    for (var i = 0; i < buckets.length; i += step) {
      entries.add(Text(_label(buckets[i].bucketStart), style: context.text.bodySecondary));
    }
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: entries);
  }
}

class _Tooltip extends StatelessWidget {
  final RevenueBucket bucket;
  final int index;
  final int total;
  final Size size;
  final bool isHourly;
  final bool isMonthly;

  const _Tooltip({
    required this.bucket,
    required this.index,
    required this.total,
    required this.size,
    required this.isHourly,
    required this.isMonthly,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final x = total <= 1 ? 0.0 : (index / (total - 1)) * size.width;
    final alignRight = x > size.width - 140;

    final dateLabel = isHourly
        ? DateFormat('dd/MM HH:mm').format(bucket.bucketStart)
        : isMonthly
            ? DateFormat('MMMM yyyy').format(bucket.bucketStart)
            : DateFormat('EEEE dd/MM/yyyy').format(bucket.bucketStart);

    return Positioned(
      left: alignRight ? null : x + 8,
      right: alignRight ? size.width - x + 8 : null,
      top: 0,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: AppRadius.smAll,
            border: Border.all(color: colors.border),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          constraints: const BoxConstraints(maxWidth: 180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(dateLabel, style: context.text.bodySecondary),
              const SizedBox(height: 2),
              Text(
                CurrencyFormatter.format(bucket.revenue),
                style: context.text.cardTitle.copyWith(color: colors.primary),
              ),
              if (bucket.saleCount != null)
                Consumer(
                  builder: (context, ref, _) => Text(
                    '${bucket.saleCount} ${tr(ref, 'reports.orders_suffix')}',
                    style: context.text.bodySecondary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<RevenueBucket> buckets;
  final double maxRevenue;
  final int? hoverIndex;
  final Color lineColor;
  final Color fillColor;
  final Color gridColor;
  final Color hoverLineColor;

  _LineChartPainter({
    required this.buckets,
    required this.maxRevenue,
    required this.hoverIndex,
    required this.lineColor,
    required this.fillColor,
    required this.gridColor,
    required this.hoverLineColor,
  });

  Offset _pointFor(int i, Size size) {
    final x = buckets.length <= 1 ? 0.0 : (i / (buckets.length - 1)) * size.width;
    final y = size.height - (buckets[i].revenue / maxRevenue) * (size.height - 8) - 4;
    return Offset(x, y);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Horizontal grid lines (0%, 50%, 100%).
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final fraction in [0.0, 0.5, 1.0]) {
      final y = size.height - fraction * (size.height - 4) - 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (buckets.isEmpty) return;

    final linePath = Path();
    final fillPath = Path();
    for (var i = 0; i < buckets.length; i++) {
      final p = _pointFor(i, size);
      if (i == 0) {
        linePath.moveTo(p.dx, p.dy);
        fillPath.moveTo(p.dx, size.height);
        fillPath.lineTo(p.dx, p.dy);
      } else {
        linePath.lineTo(p.dx, p.dy);
        fillPath.lineTo(p.dx, p.dy);
      }
    }
    final last = _pointFor(buckets.length - 1, size);
    fillPath.lineTo(last.dx, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, Paint()..color = fillColor);
    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Dots on every point, filled solid on the hovered one.
    for (var i = 0; i < buckets.length; i++) {
      final p = _pointFor(i, size);
      final isHover = i == hoverIndex;
      canvas.drawCircle(p, isHover ? 4.5 : 2.5, Paint()..color = lineColor);
      if (isHover) {
        canvas.drawCircle(p, 4.5, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5);
      }
    }

    if (hoverIndex != null) {
      final p = _pointFor(hoverIndex!, size);
      final dashPaint = Paint()
        ..color = hoverLineColor
        ..strokeWidth = 1;
      const dashHeight = 4.0;
      double y = 0;
      while (y < size.height) {
        canvas.drawLine(Offset(p.dx, y), Offset(p.dx, y + dashHeight), dashPaint);
        y += dashHeight * 2;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return oldDelegate.buckets != buckets ||
        oldDelegate.hoverIndex != hoverIndex ||
        oldDelegate.maxRevenue != maxRevenue;
  }
}
