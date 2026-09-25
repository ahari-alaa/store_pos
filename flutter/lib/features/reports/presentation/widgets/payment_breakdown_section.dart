import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/design_system.dart';
import '../../../../core/l10n/locale_provider.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/ui/ui.dart';
import '../../../dashboard/presentation/widgets/dashboard_error_view.dart';
import '../../domain/entities/reports_models.dart';
import '../providers/reports_provider.dart';

const List<Color> _kPaletteFallback = [
  Color(0xFF3B82F6),
  Color(0xFF22C55E),
  Color(0xFFF59E0B),
  Color(0xFFA855F7),
  Color(0xFFEF4444),
  Color(0xFF14B8A6),
];

/// "Répartition des paiements" (spec §9) — every real payment method
/// present in the store's data (never a hard-coded CASH/CARD list), each
/// with amount, share of total, and transaction count.
class PaymentBreakdownSection extends ConsumerWidget {
  const PaymentBreakdownSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(reportSalesSummaryProvider);

    return AppSectionCard(
      title: tr(ref, 'reports.payment_breakdown'),
      child: summaryAsync.when(
        loading: () => const SizedBox(
          height: 180,
          width: double.infinity,
          child: AppSkeleton(height: 160),
        ),
        error: (error, _) => DashboardErrorInline(
          error: error,
          onRetry: () => ref.invalidate(reportSalesSummaryProvider),
        ),
        data: (report) {
          if (report.byPaymentMethod.isEmpty) {
            return AppEmptyState(
              icon: Icons.pie_chart_outline_rounded,
              title: tr(ref, 'reports.empty_title'),
              message: tr(ref, 'reports.empty_message'),
              compact: true,
            );
          }
          return _PaymentBreakdownBody(entries: report.byPaymentMethod);
        },
      ),
    );
  }
}

class _PaymentBreakdownBody extends StatelessWidget {
  final List<PaymentBreakdownEntry> entries;

  const _PaymentBreakdownBody({required this.entries});

  String _methodLabel(WidgetRef ref, String method) {
    switch (method) {
      case 'CASH':
        return tr(ref, 'payment_method.cash');
      case 'CARD':
        return tr(ref, 'payment_method.card');
      case 'TRANSFER':
        return tr(ref, 'payment_method.transfer');
      case 'MIXED':
        return tr(ref, 'payment_method.mixed');
      default:
        return method;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final colors = [for (var i = 0; i < entries.length; i++) _kPaletteFallback[i % _kPaletteFallback.length]];

        return LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 420;
            final donut = SizedBox(
              width: 140,
              height: 140,
              child: CustomPaint(
                painter: _DonutPainter(
                  values: entries.map((e) => e.percent).toList(),
                  colors: colors,
                  trackColor: context.colors.surfaceMuted,
                ),
              ),
            );
            final legend = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < entries.length; i++) ...[
                  _LegendRow(
                    color: colors[i],
                    label: _methodLabel(ref, entries[i].paymentMethod),
                    amount: CurrencyFormatter.format(entries[i].amount),
                    percent: entries[i].percent,
                    transactionCount: entries[i].transactionCount,
                  ),
                  if (i < entries.length - 1) const SizedBox(height: AppSpacing.sm),
                ],
              ],
            );

            if (narrow) {
              return Column(
                children: [
                  Center(child: donut),
                  const SizedBox(height: AppSpacing.lg),
                  legend,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                donut,
                const SizedBox(width: AppSpacing.xl),
                Expanded(child: legend),
              ],
            );
          },
        );
      },
    );
  }
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;
  final String amount;
  final double percent;
  final int transactionCount;

  const _LegendRow({
    required this.color,
    required this.label,
    required this.amount,
    required this.percent,
    required this.transactionCount,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) => Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(label, style: context.text.body, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text('${percent.toStringAsFixed(1)}%', style: context.text.bodySecondary),
          const SizedBox(width: AppSpacing.md),
          Text(amount, style: context.text.tableCell.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  final Color trackColor;

  _DonutPainter({required this.values, required this.colors, required this.trackColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    const strokeWidth = 20.0;
    final rect = Rect.fromCircle(center: center, radius: radius - strokeWidth / 2);

    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawArc(rect, 0, 2 * math.pi, false, track);

    var startAngle = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = (values[i].clamp(0, 100) / 100) * 2 * math.pi;
      if (sweep <= 0) continue;
      final paint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect, startAngle, sweep, false, paint);
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.colors != colors;
}
