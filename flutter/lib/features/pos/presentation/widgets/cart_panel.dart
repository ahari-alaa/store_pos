import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../../../core/design/design_system.dart';
import '../../../../core/l10n/locale_provider.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/widgets/ui/ui.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../sales/presentation/providers/sales_provider.dart';
import '../../../settings/presentation/providers/receipt_settings_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/payment_provider.dart';
import '../providers/receipt_data.dart';
import '../providers/sale_provider.dart';
import '../utils/receipt_pdf.dart';
import 'cart_item_tile.dart';
import 'payment_section.dart';
import 'sale_success_dialog.dart';
import 'totals_summary.dart';

class CartPanel extends ConsumerWidget {
  /// True when the POS is running in a narrow window. The panel keeps
  /// every control — it only narrows. Dropping the cart on a small screen
  /// would make the till unusable, which is why this is a width change
  /// and not a visibility one.
  final bool compact;

  const CartPanel({super.key, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final items = ref.watch(cartProvider);
    final totals = ref.watch(cartTotalsProvider);
    final payment = ref.watch(paymentProvider);
    final isSubmitting = ref.watch(isSubmittingSaleProvider);

    final canComplete = items.isNotEmpty &&
        payment.amountEntered >= totals.total - 0.001 &&
        !isSubmitting;

    return Container(
      width: compact
          ? AppSizes.cartPanelWidthCompact
          : AppSizes.cartPanelWidth,
      decoration: BoxDecoration(
        color: colors.surface,
        // The panel sits on the RIGHT of the POS layout (see PosPage), so
        // its divider belongs on the leading edge. It was drawing the
        // border on the right — an unbroken hairline against the window
        // edge, with no separation from the product grid it was supposed
        // to be divided from.
        border: Border(left: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(itemCount: items.length),
          Divider(height: 1, thickness: 1, color: colors.border),
          Expanded(
            child: items.isEmpty
                ? const _EmptyCart()
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md,
                    ),
                    itemCount: items.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, thickness: 1, color: colors.border),
                    itemBuilder: (context, index) =>
                        CartItemTile(item: items[index]),
                  ),
          ),
          Divider(height: 1, thickness: 1, color: colors.border),
          // Capped + scrollable rather than a bare fixed-size child: on a
          // short window this section (totals + payment + action buttons)
          // can be taller than the space left after the header/list, and
          // an un-capped Column here would throw a RenderFlex overflow
          // instead of just scrolling.
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.62,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const TotalsSummary(),
                  const SizedBox(height: AppSpacing.lg),
                  const PaymentSection(),
                  const SizedBox(height: AppSpacing.lg),
                  // The single most important control on the screen, so
                  // it gets the large height and the full panel width.
                  SizedBox(
                    height: AppSizes.buttonHeightLg,
                    child: AppButton.primary(
                      label: isSubmitting
                          ? tr(ref, 'pos.paying')
                          : tr(ref, 'pos.pay'),
                      icon: Icons.check_circle_outline_rounded,
                      size: AppButtonSize.large,
                      expand: true,
                      loading: isSubmitting,
                      onPressed: canComplete
                          ? () => _completeSale(
                                context,
                                ref,
                                totals.total,
                                payment.mode,
                              )
                          : null,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // Was three stacked icon+label buttons at 9.5px — below
                  // any reasonable legibility floor, and unreadable on a
                  // till screen at arm's length. Now: one labelled outline
                  // button for the action that has real consequences
                  // (it creates a persisted sale), and two icon buttons
                  // with tooltips for the two that are just output.
                  Row(
                    children: [
                      Expanded(
                        child: AppButton.outline(
                          label: tr(ref, 'pos.receipt_unpaid'),
                          icon: Icons.receipt_long_outlined,
                          onPressed: isSubmitting
                              ? null
                              : () => _giveReceiptWithoutPaying(context, ref),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      AppIconButton(
                        icon: Icons.print_outlined,
                        tooltip: tr(ref, 'pos.print'),
                        onPressed:
                            isSubmitting ? null : () => _printReceipt(context, ref),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      AppIconButton(
                        icon: Icons.ios_share_rounded,
                        tooltip: tr(ref, 'pos.share'),
                        onPressed:
                            isSubmitting ? null : () => _shareReceipt(context, ref),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _completeSale(
    BuildContext context,
    WidgetRef ref,
    double total,
    PaymentMode mode,
  ) async {
    final payment = ref.read(paymentProvider);
    final change = mode == PaymentMode.card ? 0.0 : payment.amountEntered - total;

    // Snapshot everything the receipt needs now, before the cart/payment
    // state is reset below — the dialog and its "Print receipt" preview
    // must still show the sale that was just completed either way.
    final itemsSnapshot = ref.read(cartProvider);
    final totalsSnapshot = ref.read(cartTotalsProvider);
    final paymentEntries = payment.toEntries().where((e) => e.amount > 0).toList();
    final cashierName = ref.read(authProvider).user?.name ?? 'Cashier';

    ref.read(isSubmittingSaleProvider.notifier).state = true;
    try {
      // Posts the sale (+ items + payments) to the backend, which also
      // atomically deducts stock (see services/saleService.js). Only once
      // that succeeds do we show the confirmation and clear the cart —
      // a failed request never silently empties an unsold cart.
      final result = await ref.read(saleControllerProvider).completeSale();
      final sale = result['sale'] as Map<String, dynamic>? ?? const {};

      final receipt = ReceiptData.fromSaleResponse(
        sale: sale,
        items: itemsSnapshot,
        totals: totalsSnapshot,
        cashierName: cashierName,
        payments: paymentEntries,
        change: change,
      );

      if (!context.mounted) return;
      await showDialog(
        context: context,
        builder: (_) => SaleSuccessDialog(
          total: total,
          change: change < 0 ? 0 : change,
          receipt: receipt,
        ),
      );

      ref.read(cartProvider.notifier).clear();
      ref.read(discountPercentProvider.notifier).state = 0;
      ref.read(paymentProvider.notifier).reset();
      // So the Sales screen (if already loaded) shows this sale next time
      // it's viewed, without a stale cached list.
      ref.invalidate(salesProvider);
    } on ApiException catch (e) {
      if (!context.mounted) return;
      showAppToast(context, message: e.message, kind: AppToastKind.error);
    } on SaleSubmissionException catch (e) {
      if (!context.mounted) return;
      showAppToast(context, message: e.message, kind: AppToastKind.error);
    } catch (_) {
      if (!context.mounted) return;
      showAppToast(
        context,
        message: trRead(ref, 'pos.sale_failed'),
        kind: AppToastKind.error,
      );
    } finally {
      ref.read(isSubmittingSaleProvider.notifier).state = false;
    }
  }

  /// Builds a NOT-PAID [ReceiptData] snapshot from the current cart, or
  /// returns null (after showing a SnackBar) if there's nothing to build a
  /// receipt from. Never calls the sale/payment API — used only by
  /// [_printReceipt]/[_shareReceipt] to preview the cart before any sale
  /// exists yet. This is intentionally NOT what "Give receipt without
  /// paying" uses (see [_giveReceiptWithoutPaying] below) — that button
  /// creates a real, persisted sale (Sales spec §2/§3), while these two
  /// stay a pure pre-sale preview.
  ReceiptData? _buildUnpaidReceipt(BuildContext context, WidgetRef ref) {
    final items = ref.read(cartProvider);
    if (items.isEmpty) {
      showAppToast(
        context,
        message: trRead(ref, 'pos.cart_empty_toast'),
        kind: AppToastKind.warning,
      );
      return null;
    }
    final totals = ref.read(cartTotalsProvider);
    final cashierName = ref.read(authProvider).user?.name ?? 'Cashier';
    return ReceiptData.fromCart(items: items, totals: totals, cashierName: cashierName);
  }

  /// "Give receipt without paying" (Sales spec §2/§3/§12): creates a REAL
  /// sale on the backend with no payment rows, so it shows up in the
  /// Sales screen immediately as NOT PAID (`payment_status = PENDING`),
  /// with a stable receipt number and creation time that will never
  /// change even once it's paid later (spec §8/§9). This does NOT record
  /// a cash payment, does NOT mark the sale as paid, and does NOT create
  /// any fake payment data — see saleService.createSale.
  Future<void> _giveReceiptWithoutPaying(BuildContext context, WidgetRef ref) async {
    final itemsSnapshot = ref.read(cartProvider);
    if (itemsSnapshot.isEmpty) {
      showAppToast(
        context,
        message: trRead(ref, 'pos.cart_empty_toast'),
        kind: AppToastKind.warning,
      );
      return;
    }

    final totalsSnapshot = ref.read(cartTotalsProvider);
    final cashierName = ref.read(authProvider).user?.name ?? 'Cashier';

    ref.read(isSubmittingSaleProvider.notifier).state = true;
    try {
      final result = await ref.read(saleControllerProvider).createUnpaidSale();
      final sale = result['sale'] as Map<String, dynamic>? ?? const {};

      final receipt = ReceiptData.fromSaleResponse(
        sale: sale,
        items: itemsSnapshot,
        totals: totalsSnapshot,
        cashierName: cashierName,
      );

      // The sale is real and stock has already been deducted for it, so —
      // just like a completed paid sale — the cart is cleared only after
      // the backend call succeeds.
      ref.read(cartProvider.notifier).clear();
      ref.read(discountPercentProvider.notifier).state = 0;
      ref.read(paymentProvider.notifier).reset();
      ref.invalidate(salesProvider);

      if (!context.mounted) return;
      showAppToast(
        context,
        message: '${trRead(ref, 'pos.unpaid_created')} — #${receipt.receiptNumber}',
        kind: AppToastKind.info,
      );
      // Routed through go_router (not Navigator.push) — see the comment on
      // the '/receipt-preview' route in app_router.dart for why.
      await context.push('/receipt-preview', extra: receipt);
    } on ApiException catch (e) {
      if (!context.mounted) return;
      showAppToast(context, message: e.message, kind: AppToastKind.error);
    } on SaleSubmissionException catch (e) {
      if (!context.mounted) return;
      showAppToast(context, message: e.message, kind: AppToastKind.error);
    } catch (_) {
      if (!context.mounted) return;
      showAppToast(
        context,
        message: trRead(ref, 'pos.receipt_failed'),
        kind: AppToastKind.error,
      );
    } finally {
      ref.read(isSubmittingSaleProvider.notifier).state = false;
    }
  }

  /// Sends the current cart straight to the OS print dialog, using the
  /// receipt settings configured in Settings → Receipt & Printer. Since
  /// this runs before any payment is taken, the printed receipt is marked
  /// NOT PAID (use "Pay" first, then the post-sale receipt dialog, to
  /// print a paid receipt).
  Future<void> _printReceipt(BuildContext context, WidgetRef ref) async {
    final receipt = _buildUnpaidReceipt(context, ref);
    if (receipt == null) return;
    try {
      final settings = ref.read(receiptSettingsProvider);
      final bytes = await (await buildReceiptPdf(receipt, settings)).save();
      final printed = await Printing.layoutPdf(
        onLayout: (format) async => bytes,
        name: 'receipt-${receipt.receiptNumber}',
      );
      if (!context.mounted) return;
      if (printed) {
        showAppToast(
          context,
          message: trRead(ref, 'pos.print_sent'),
          kind: AppToastKind.success,
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      showAppToast(
        context,
        message: trRead(ref, 'pos.printer_unavailable'),
        kind: AppToastKind.error,
      );
    }
  }

  /// Generates the current cart's receipt as a PDF and opens the OS share
  /// sheet, using the store/receipt settings from Settings → Receipt &
  /// Printer.
  Future<void> _shareReceipt(BuildContext context, WidgetRef ref) async {
    final receipt = _buildUnpaidReceipt(context, ref);
    if (receipt == null) return;
    try {
      final settings = ref.read(receiptSettingsProvider);
      final bytes = await (await buildReceiptPdf(receipt, settings)).save();
      await Printing.sharePdf(bytes: bytes, filename: 'receipt-${receipt.receiptNumber}.pdf');
    } catch (_) {
      if (!context.mounted) return;
      showAppToast(
        context,
        message: trRead(ref, 'pos.share_failed'),
        kind: AppToastKind.error,
      );
    }
  }
}

class _Header extends ConsumerWidget {
  final int itemCount;
  const _Header({required this.itemCount});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final text = context.text;

    final subtitle = itemCount == 0
        ? trRead(ref, 'pos.item_count_zero')
        : '$itemCount ${itemCount == 1 ? trRead(ref, 'pos.item_count_one') : trRead(ref, 'pos.item_count_many')}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  trRead(ref, 'pos.current_sale'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.cardTitle,
                ),
                const SizedBox(height: 2),
                // Was a static "New sale" label that never changed. The
                // live item count is the thing a cashier actually wants
                // here — it is the fastest cross-check against the
                // customer's basket.
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySecondary.copyWith(color: colors.textMuted),
                ),
              ],
            ),
          ),
          if (itemCount > 0)
            AppIconButton(
              icon: Icons.delete_outline_rounded,
              tooltip: trRead(ref, 'pos.clear_sale'),
              destructive: true,
              // Clearing the sale used to be a single unconfirmed tap
              // next to the item list — one slip and a full basket was
              // gone with no undo. It now states the consequence first.
              onPressed: () async {
                final confirmed = await showAppConfirmDialog(
                  context,
                  title: trRead(ref, 'pos.clear_sale'),
                  message: trRead(ref, 'pos.clear_sale_confirm'),
                  confirmLabel: trRead(ref, 'pos.clear_sale'),
                  cancelLabel: trRead(ref, 'common.cancel'),
                  destructive: true,
                );
                if (!confirmed) return;
                ref.read(cartProvider.notifier).clear();
                ref.read(discountPercentProvider.notifier).state = 0;
                ref.read(paymentProvider.notifier).reset();
              },
            ),
        ],
      ),
    );
  }
}

class _EmptyCart extends ConsumerWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Wrapped in a scroll view so a short/squeezed window shrinks or
    // scrolls this instead of throwing a RenderFlex overflow.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: AppEmptyState(
        icon: Icons.shopping_cart_outlined,
        title: trRead(ref, 'pos.empty_cart'),
        message: trRead(ref, 'pos.empty_cart_hint'),
      ),
    );
  }
}
