import 'package:flutter/material.dart';

import '../../design/design_system.dart';

/// A pill showing a status, tinted by meaning.
///
/// This is the one place the application decides what a status *looks*
/// like. Feed it the raw backend value — `PAID`, `PENDING`, `CANCELLED`,
/// `LOW_STOCK` — and it resolves the color through
/// [AppColorScheme.statusColor], so the POS, the sales table, the orders
/// board and the stock list can never disagree about what green means.
///
/// Critically, this widget does **not** invent statuses. If the backend
/// sends a value it does not recognise, it renders it neutrally rather
/// than guessing, and the raw value stays visible so the problem is
/// obvious instead of hidden behind a wrong color.
class StatusBadge extends StatelessWidget {
  /// The backend status value, e.g. `PAID`. Used to pick the color.
  final String status;

  /// What the user reads. Pass the translated label here; [status] stays
  /// the untranslated backend value so the color mapping keeps working in
  /// every language.
  final String label;

  /// Small dot before the label. On by default — a shape cue as well as a
  /// color one, so the badge still carries meaning for a colorblind user.
  final bool showDot;

  final StatusBadgeSize size;

  /// Overrides the resolved color. Only for a status whose meaning the
  /// caller genuinely knows better (e.g. a computed stock level).
  final Color? color;

  const StatusBadge({
    super.key,
    required this.status,
    required this.label,
    this.showDot = true,
    this.size = StatusBadgeSize.medium,
    this.color,
  });

  /// Convenience for the three stock states, which are computed from
  /// quantities rather than sent as a status string by the backend.
  factory StatusBadge.stock({
    required num quantity,
    required num minimum,
    required String inStockLabel,
    required String lowStockLabel,
    required String outOfStockLabel,
    StatusBadgeSize size = StatusBadgeSize.medium,
  }) {
    // Note the <= 0 branch: stock at or below zero is always "out of
    // stock". The UI never presents a negative quantity as a normal
    // level — if the data is negative that is a stock integrity problem,
    // and it reads as a rupture, not as "minus three in stock".
    if (quantity <= 0) {
      return StatusBadge(
        status: 'OUT_OF_STOCK',
        label: outOfStockLabel,
        size: size,
      );
    }
    if (quantity <= minimum) {
      return StatusBadge(status: 'LOW_STOCK', label: lowStockLabel, size: size);
    }
    return StatusBadge(status: 'IN_STOCK', label: inStockLabel, size: size);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final resolved = color ?? colors.statusColor(status);
    final background = color != null
        ? Color.alphaBlend(color!.withOpacity(0.12), colors.surface)
        : colors.statusSurface(status);

    final compact = size == StatusBadgeSize.small;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.sm : AppSpacing.md,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: compact ? 5 : 6,
              height: compact ? 5 : 6,
              decoration: BoxDecoration(color: resolved, shape: BoxShape.circle),
            ),
            SizedBox(width: compact ? 5 : AppSpacing.sm - 2),
          ],
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w600,
              color: resolved,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

enum StatusBadgeSize { small, medium }
