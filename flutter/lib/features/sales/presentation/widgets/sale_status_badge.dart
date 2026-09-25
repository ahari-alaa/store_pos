import 'package:flutter/material.dart';

import '../../../../core/design/design_system.dart';
import '../../../../core/widgets/ui/ui.dart';
import '../../domain/entities/sale.dart';

/// PAID / NOT PAID / PARTIALLY PAID / REFUNDED badge.
///
/// Now a thin wrapper over the shared [StatusBadge] instead of a bespoke
/// pill: the previous version drew its own 999px radius, 9/4 padding and
/// 11px type, which is the sort of near-miss that makes two badges on
/// adjacent screens look subtly different for no reason.
///
/// Two things are deliberately overridden rather than left to
/// [StatusBadge]'s defaults:
///
///  * **The colour of PENDING.** The generic `statusColor` maps PENDING to
///    warning, which is right for a generic workflow state. Here PENDING
///    means the customer has not paid, which the store needs to read as a
///    debt — so it stays danger, as it was before the redesign.
///  * **The label.** Sale labels come from [SalePaymentStatus.label],
///    which the spec fixes as "NOT PAID" (never "PENDING"). Passing it
///    explicitly keeps that contract in one place.
class SaleStatusBadge extends StatelessWidget {
  final SalePaymentStatus status;

  const SaleStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final Color color;
    switch (status) {
      case SalePaymentStatus.paid:
        color = colors.success;
        break;
      case SalePaymentStatus.partiallyPaid:
        color = colors.warning;
        break;
      case SalePaymentStatus.refunded:
        color = colors.textSecondary;
        break;
      case SalePaymentStatus.pending:
        color = colors.danger;
        break;
    }

    return StatusBadge(
      // The raw backend value, so anything reading the badge's status
      // string sees the same token the API uses.
      status: status.name,
      label: status.label,
      color: color,
    );
  }
}
