import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/design_system.dart';
import '../../../../core/l10n/locale_provider.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/ui/ui.dart';
import '../../../reports/domain/entities/my_report.dart';
import '../../../reports/presentation/widgets/report_widgets.dart';
import 'sale_status_badge.dart';

/// One order of the signed-in cashier, as a card:
///
///   Commande #ab12cd34                                   [PAID]
///   18/09/2026 • 14:35
///   Café Americain          x2               20.00 DH
///   Croissant               x1                8.00 DH
///   Total                                    28.00 DH
///   ● À servir                        [ IMPRIMER / SERVIR ]
///
/// The card owns no business logic: [onServe] / [onReprint] are provided by
/// the page (see OrderActions). While an action runs, the button shows a
/// spinner and ignores taps, so the same order can't be submitted twice from
/// this client.
class MyOrderCard extends ConsumerStatefulWidget {
  final MyOrder order;

  /// Shown for an order that is still "à servir".
  final Future<void> Function()? onServe;

  /// Shown for an order that was already served.
  final Future<void> Function()? onReprint;

  const MyOrderCard({
    super.key,
    required this.order,
    this.onServe,
    this.onReprint,
  });

  @override
  ConsumerState<MyOrderCard> createState() => _MyOrderCardState();
}

class _MyOrderCardState extends ConsumerState<MyOrderCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final order = widget.order;

    final served = order.isServed;
    final servedAt = order.servedAt;

    final statusLabel = served
        ? '${tr(ref, 'mine.status_served')}${servedAt != null ? ' · ${ReportFormat.time(servedAt)}' : ''}'
        : tr(ref, 'mine.status_to_serve');

    final VoidCallback? action;
    if (served) {
      final onReprint = widget.onReprint;
      action = onReprint == null ? null : () => _run(onReprint);
    } else {
      final onServe = widget.onServe;
      action = onServe == null ? null : () => _run(onServe);
    }

    return AppCard(
      accentBorderColor: served ? null : colors.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${tr(ref, 'mine.order')} #${order.receiptNumber}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.cardTitle,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              SaleStatusBadge(status: order.paymentStatus),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${ReportFormat.date(order.occurredAt)} • ${ReportFormat.time(order.occurredAt)}',
            style: text.bodySecondary,
          ),
          const SizedBox(height: AppSpacing.md),
          for (final line in order.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      line.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.body,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text('x${line.quantity}', style: text.bodySecondary),
                  const SizedBox(width: AppSpacing.lg),
                  SizedBox(
                    width: 86,
                    child: Text(
                      CurrencyFormatter.format(line.subtotal),
                      textAlign: TextAlign.end,
                      style: text.body,
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Divider(height: 1, thickness: 1, color: colors.border),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  tr(ref, 'mine.total'),
                  style: text.body.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                CurrencyFormatter.format(order.total),
                style: text.body.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusBadge(
                      status: served ? 'SERVED' : 'TO_SERVE',
                      label: statusLabel,
                      color: served ? colors.success : colors.warning,
                    ),
                    if (order.receiptPrintCount > 1)
                      Text(
                        '${tr(ref, 'mine.printed_times')} ${order.receiptPrintCount}×',
                        style: text.bodySecondary,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (served)
                AppButton.outline(
                  label: tr(ref, 'mine.action_reprint'),
                  icon: Icons.print_outlined,
                  size: AppButtonSize.small,
                  loading: _busy,
                  onPressed: action,
                )
              else
                AppButton.primary(
                  label: tr(ref, 'mine.action_serve'),
                  icon: Icons.print_rounded,
                  size: AppButtonSize.small,
                  loading: _busy,
                  onPressed: action,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Lays order cards out in as many columns as fit (min ~360px each), so the
/// queue is readable on both a 1366px laptop and a large POS monitor.
class MyOrderGrid extends StatelessWidget {
  final List<Widget> children;

  const MyOrderGrid({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = AppSpacing.md;
        final columns = (constraints.maxWidth / 380).floor().clamp(1, 4);
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}
