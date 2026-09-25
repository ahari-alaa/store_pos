import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/locale_provider.dart';
import '../../../../core/widgets/ui/ui.dart';
import '../../../reports/domain/entities/my_report.dart';
import '../providers/order_serve_controller.dart';

/// UI side of IMPRIMER / SERVIR and RÉIMPRIMER: runs the controller and tells
/// the cashier exactly what happened (toast / retry dialog).
///
/// Always call these with the PAGE's [context] (not the order card's): the
/// card leaves the "À servir" list the moment the order is served, and a
/// toast must not depend on a widget that has just been removed.
class OrderActions {
  OrderActions._();

  /// IMPRIMER / SERVIR: print, and only after a confirmed print mark the
  /// order served.
  static Future<void> serve(BuildContext context, WidgetRef ref, MyOrder order) async {
    ServeResult result;
    try {
      result = await ref.read(orderServeControllerProvider).printAndServe(order.id);
    } catch (_) {
      result = const ServeResult(ServeOutcome.failed);
    }
    if (!context.mounted) return;

    // Printed but not recorded (connection lost / server error): the receipt
    // is already on paper, so only the "mark as served" step is retried — with
    // the same idempotency key, so it can never be recorded twice.
    while (result.outcome == ServeOutcome.printedNotRecorded) {
      final retry = await showAppConfirmDialog(
        context,
        title: trRead(ref, 'mine.retry_title'),
        message: trRead(ref, 'mine.retry_message'),
        consequence: trRead(ref, 'mine.retry_consequence'),
        confirmLabel: trRead(ref, 'mine.retry_confirm'),
        cancelLabel: trRead(ref, 'mine.retry_later'),
        icon: Icons.print_rounded,
      );
      if (!context.mounted) return;
      if (!retry) {
        // Stays "à servir": nothing was recorded. Say so instead of leaving
        // the cashier to guess.
        showAppToast(
          context,
          message: trRead(ref, 'mine.retry_message'),
          kind: AppToastKind.warning,
        );
        return;
      }
      try {
        result = await ref.read(orderServeControllerProvider).markServed(
              order.id,
              operationId: result.operationId ?? '',
            );
      } catch (_) {
        result = const ServeResult(ServeOutcome.failed);
      }
      if (!context.mounted) return;
    }

    _toast(context, ref, result);
  }

  /// RÉIMPRIMER: prints a served order's receipt again (served state and its
  /// timestamp are never changed).
  static Future<void> reprint(BuildContext context, WidgetRef ref, MyOrder order) async {
    ServeResult result;
    try {
      result = await ref.read(orderServeControllerProvider).reprint(order.id);
    } catch (_) {
      result = const ServeResult(ServeOutcome.failed);
    }
    if (!context.mounted) return;
    _toast(context, ref, result);
  }

  static void _toast(BuildContext context, WidgetRef ref, ServeResult result) {
    switch (result.outcome) {
      case ServeOutcome.served:
        showAppToast(context, message: trRead(ref, 'mine.msg_served'), kind: AppToastKind.success);
      case ServeOutcome.reprinted:
        showAppToast(context, message: trRead(ref, 'mine.msg_reprinted'), kind: AppToastKind.success);
      case ServeOutcome.reprintedNotRecorded:
        showAppToast(
          context,
          message: trRead(ref, 'mine.msg_reprint_not_recorded'),
          kind: AppToastKind.warning,
        );
      case ServeOutcome.alreadyServed:
        showAppToast(
          context,
          message: trRead(ref, 'mine.msg_already_served'),
          kind: AppToastKind.warning,
        );
      case ServeOutcome.cancelled:
        showAppToast(context, message: trRead(ref, 'mine.msg_cancelled'), kind: AppToastKind.info);
      case ServeOutcome.offline:
        showAppToast(context, message: trRead(ref, 'mine.msg_offline'), kind: AppToastKind.warning);
      case ServeOutcome.printFailed:
        showAppToast(
          context,
          message: trRead(ref, 'mine.msg_print_failed'),
          kind: AppToastKind.error,
        );
      case ServeOutcome.printedNotRecorded:
      case ServeOutcome.failed:
        showAppToast(context, message: trRead(ref, 'mine.msg_failed'), kind: AppToastKind.error);
    }
  }
}
