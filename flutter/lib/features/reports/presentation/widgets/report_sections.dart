import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design/design_system.dart';
import '../../../../core/l10n/locale_provider.dart';
import '../../../../core/widgets/ui/ui.dart';
import '../../../dashboard/domain/entities/dashboard_extras.dart';
import '../../../sales/presentation/widgets/sale_detail_dialog.dart';
import '../../domain/entities/report_overview.dart';
import 'report_widgets.dart';

/// Heights of the fixed-size panels. Tables scroll INSIDE their panel, so
/// the page layout never depends on how many rows a period produced.
class ReportPanelHeights {
  ReportPanelHeights._();

  static const double chartRow = 330;
  static const double tablesRow = 290;
  static const double lowerRow = 250;
}

String _paymentMethodLabel(WidgetRef ref, String method) {
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
      return method.isEmpty ? '—' : method;
  }
}

/// Lets a table keep a sensible minimum width: below it the table scrolls
/// horizontally inside its panel instead of squeezing text or overflowing.
class _MinWidth extends StatelessWidget {
  final double minWidth;
  final Widget child;

  const _MinWidth({required this.minWidth, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= minWidth) return child;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: minWidth, child: child),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------
// COMMANDES PAR HEURE
// ---------------------------------------------------------------------

class OrdersByHourPanel extends ConsumerWidget {
  final ReportOverview data;
  final double height;

  const OrdersByHourPanel({super.key, required this.data, required this.height});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final hourly = data.ordersByHour;
    final rows = hourly.activeRange;
    final busiest = rows.isEmpty ? 0 : rows.map((r) => r.orders).reduce(math.max);

    return ReportPanel(
      title: tr(ref, 'reports.orders_by_hour'),
      subtitle: data.period.days > 1 ? tr(ref, 'reports.orders_by_hour_cumulative') : null,
      height: height,
      child: ReportTable(
        columns: [
          ReportColumn(tr(ref, 'reports.col_hour'), flex: 4),
          ReportColumn(tr(ref, 'reports.col_orders'), flex: 3, alignEnd: true),
          ReportColumn(tr(ref, 'reports.col_revenue_dh'), flex: 3, alignEnd: true),
        ],
        rows: [
          for (final r in rows)
            ReportRow([
              reportText(context, r.label,
                  bold: r.orders == busiest, color: r.orders == busiest ? colors.primary : null),
              reportText(context, ReportFormat.integer(r.orders),
                  alignEnd: true, bold: r.orders == busiest, color: r.orders == busiest ? colors.primary : null),
              reportText(context, ReportFormat.amount(r.revenue), alignEnd: true),
            ]),
        ],
        footer: rows.isEmpty
            ? null
            : ReportRow([
                reportText(context, tr(ref, 'reports.total_row'), bold: true),
                reportText(context, ReportFormat.integer(hourly.totalOrders), bold: true, alignEnd: true),
                reportText(context, ReportFormat.amount(hourly.totalRevenue), bold: true, alignEnd: true),
              ]),
        empty: ReportEmpty(message: tr(ref, 'reports.no_sales'), icon: Icons.schedule_outlined),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// MOYENS DE PAIEMENT
// ---------------------------------------------------------------------

class PaymentsPanel extends ConsumerWidget {
  final ReportOverview data;
  final double height;

  const PaymentsPanel({super.key, required this.data, required this.height});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final p = data.payments;

    Widget summaryLine(String label, String value, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 2),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySecondary.copyWith(fontSize: 12)),
              ),
              Text(value,
                  style: context.text.tableCell.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
            ],
          ),
        );

    return ReportPanel(
      title: tr(ref, 'reports.payments_title'),
      subtitle: tr(ref, 'reports.amounts_in_dh'),
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _MinWidth(
              minWidth: 330,
              child: ReportTable(
                columns: [
                  ReportColumn(tr(ref, 'reports.col_payment_method'), flex: 4),
                  ReportColumn(tr(ref, 'reports.col_collected'), flex: 4, alignEnd: true),
                  ReportColumn(tr(ref, 'reports.col_count'), flex: 2, alignEnd: true),
                  ReportColumn(tr(ref, 'reports.col_in_drawer'), flex: 4, alignEnd: true),
                ],
                rows: [
                  for (final m in p.methods)
                    ReportRow([
                      reportText(context, _paymentMethodLabel(ref, m.method)),
                      reportText(context, ReportFormat.amount(m.amount), alignEnd: true),
                      reportText(context, ReportFormat.integer(m.count), alignEnd: true),
                      reportText(context, ReportFormat.amount(m.inDrawer), alignEnd: true),
                    ]),
                ],
                footer: ReportRow([
                  reportText(context, tr(ref, 'reports.total_row'), bold: true),
                  reportText(context, ReportFormat.amount(p.totalCollected), bold: true, alignEnd: true),
                  reportText(context, ReportFormat.integer(p.transactions), bold: true, alignEnd: true),
                  reportText(context, ReportFormat.amount(p.inDrawer), bold: true, alignEnd: true),
                ]),
                empty: ReportEmpty(message: tr(ref, 'reports.no_payments'), icon: Icons.payments_outlined),
              ),
            ),
          ),
          Divider(height: 1, thickness: 1, color: colors.border),
          const SizedBox(height: 4),
          summaryLine(
            tr(ref, 'reports.outstanding'),
            ReportFormat.money(p.outstanding),
            color: p.outstanding > 0 ? colors.warning : null,
          ),
          summaryLine(tr(ref, 'reports.change_given'), ReportFormat.money(p.changeGiven)),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// PRODUITS LES PLUS VENDUS
// ---------------------------------------------------------------------

class TopProductsPanel extends ConsumerWidget {
  final ReportOverview data;
  final double height;

  const TopProductsPanel({super.key, required this.data, required this.height});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = data.topProducts;
    return ReportPanel(
      title: tr(ref, 'reports.top_products'),
      subtitle: tr(ref, 'reports.amounts_in_dh'),
      height: height,
      child: _MinWidth(
        minWidth: 300,
        child: ReportTable(
          columns: [
            const ReportColumn('#', width: 22),
            ReportColumn(tr(ref, 'reports.col_product'), flex: 6),
            ReportColumn(tr(ref, 'reports.col_quantity'), flex: 3, alignEnd: true),
            ReportColumn(tr(ref, 'reports.column_revenue'), flex: 4, alignEnd: true),
          ],
          rows: [
            for (var i = 0; i < products.length; i++)
              ReportRow([
                reportText(context, '${i + 1}', color: context.colors.textMuted),
                reportText(context, products[i].name),
                reportText(context, ReportFormat.integer(products[i].quantity), alignEnd: true, bold: true),
                reportText(context, ReportFormat.amount(products[i].revenue), alignEnd: true),
              ]),
          ],
          empty: ReportEmpty(message: tr(ref, 'reports.no_sales'), icon: Icons.inventory_2_outlined),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// PERFORMANCE DES CAISSIERS
// ---------------------------------------------------------------------

class CashiersPanel extends ConsumerWidget {
  final ReportOverview data;
  final double height;

  const CashiersPanel({super.key, required this.data, required this.height});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cashiers = data.cashiers;
    final totalSales = cashiers.fold<int>(0, (s, c) => s + c.saleCount);
    final totalItems = cashiers.fold<int>(0, (s, c) => s + c.itemsSold);
    final totalRevenue = data.kpis.revenue;

    return ReportPanel(
      title: tr(ref, 'reports.cashier_performance'),
      subtitle: tr(ref, 'reports.amounts_in_dh'),
      height: height,
      child: _MinWidth(
        minWidth: 340,
        child: ReportTable(
          columns: [
            ReportColumn(tr(ref, 'reports.column_cashier'), flex: 4),
            ReportColumn(tr(ref, 'reports.col_sales'), flex: 2, alignEnd: true),
            ReportColumn(tr(ref, 'reports.column_items'), flex: 3, alignEnd: true),
            ReportColumn(tr(ref, 'reports.column_revenue'), flex: 4, alignEnd: true),
            ReportColumn(tr(ref, 'reports.column_average_basket'), flex: 4, alignEnd: true),
          ],
          rows: [
            for (final c in cashiers)
              ReportRow(
                [
                  reportText(context, c.name),
                  reportText(context, ReportFormat.integer(c.saleCount), alignEnd: true),
                  reportText(context, ReportFormat.integer(c.itemsSold), alignEnd: true),
                  reportText(context, ReportFormat.amount(c.revenue), alignEnd: true, bold: true),
                  reportText(context, ReportFormat.amount(c.averageTicket), alignEnd: true),
                ],
                // Same drill-down the previous Rapports screen opened.
                onTap: () => context.push(
                  '/reports/cashiers/${c.id}',
                  extra: CashierRankingEntry(
                    cashierId: c.id,
                    cashierName: c.name,
                    role: '',
                    saleCount: c.saleCount,
                    itemsSold: c.itemsSold,
                    totalSales: c.revenue,
                    averageSale: c.averageTicket,
                  ),
                ),
              ),
          ],
          footer: cashiers.isEmpty
              ? null
              : ReportRow([
                  reportText(context, tr(ref, 'reports.total_row'), bold: true),
                  reportText(context, ReportFormat.integer(totalSales), bold: true, alignEnd: true),
                  reportText(context, ReportFormat.integer(totalItems), bold: true, alignEnd: true),
                  reportText(context, ReportFormat.amount(totalRevenue), bold: true, alignEnd: true),
                  reportText(
                    context,
                    ReportFormat.amount(totalSales > 0 ? totalRevenue / totalSales : 0),
                    bold: true,
                    alignEnd: true,
                  ),
                ]),
          empty: ReportEmpty(message: tr(ref, 'reports.no_sales'), icon: Icons.groups_outlined),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// DÉPENSES
// ---------------------------------------------------------------------

class ExpensesPanel extends ConsumerWidget {
  final ReportOverview data;
  final double height;

  const ExpensesPanel({super.key, required this.data, required this.height});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = data.expenses;
    return ReportPanel(
      title: tr(ref, 'reports.expenses'),
      subtitle: tr(ref, 'reports.amounts_in_dh'),
      height: height,
      child: _MinWidth(
        minWidth: 300,
        child: ReportTable(
          columns: [
            ReportColumn(tr(ref, 'reports.col_category'), flex: 5),
            ReportColumn('%', flex: 2, alignEnd: true),
            ReportColumn(tr(ref, 'reports.col_amount'), flex: 4, alignEnd: true),
          ],
          rows: [
            for (final c in e.byCategory)
              ReportRow([
                reportText(context, c.category),
                reportText(context, ReportFormat.percent(c.percent), alignEnd: true, color: context.colors.textSecondary),
                reportText(context, ReportFormat.amount(c.amount), alignEnd: true),
              ]),
          ],
          footer: e.byCategory.isEmpty
              ? null
              : ReportRow([
                  reportText(context, tr(ref, 'reports.total_row'), bold: true),
                  reportText(context, ReportFormat.percent(100), bold: true, alignEnd: true),
                  reportText(context, ReportFormat.amount(e.total), bold: true, alignEnd: true),
                ]),
          empty: ReportEmpty(message: tr(ref, 'reports.no_expenses'), icon: Icons.account_balance_wallet_outlined),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// STOCK & ALERTES
// ---------------------------------------------------------------------

class StockAlertsPanel extends ConsumerWidget {
  final ReportOverview data;
  final double height;

  const StockAlertsPanel({super.key, required this.data, required this.height});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final a = data.alerts;

    Widget alertRow({
      required String label,
      required int count,
      required Color color,
      String? detail,
      String? route,
    }) {
      final active = count > 0;
      final tone = active ? color : colors.success;
      final content = Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 7),
        child: Row(
          children: [
            Icon(active ? Icons.circle : Icons.check_circle_outline_rounded, size: active ? 9 : 16, color: tone),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.tableCell.copyWith(fontSize: 12.5)),
                  if (active && detail != null)
                    Text(detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodySecondary.copyWith(fontSize: 11)),
                ],
              ),
            ),
            Text(
              ReportFormat.integer(count),
              style: context.text.tableCell.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: active ? tone : colors.textMuted,
              ),
            ),
            if (route != null && active) ...[
              const SizedBox(width: AppSpacing.xs),
              Icon(Icons.chevron_right_rounded, size: 18, color: colors.textMuted),
            ],
          ],
        ),
      );
      if (route == null || !active) return content;
      return InkWell(onTap: () => context.go(route), child: content);
    }

    final divider = Divider(height: 1, thickness: 1, color: colors.border);
    final concerned = a.stockItems;

    return ReportPanel(
      title: tr(ref, 'reports.stock_alerts_title'),
      height: height,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          if (a.stockAvailable) ...[
            alertRow(label: tr(ref, 'reports.alert_out_of_stock'), count: a.outOfStock, color: colors.danger, route: '/products'),
            divider,
            alertRow(label: tr(ref, 'reports.alert_low_stock'), count: a.lowStock, color: colors.warning, route: '/products'),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.cloud_off_rounded, size: 16, color: colors.textMuted),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(tr(ref, 'reports.stock_unavailable'), style: context.text.bodySecondary.copyWith(fontSize: 12)),
                  ),
                ],
              ),
            ),
          divider,
          alertRow(
            label: tr(ref, 'reports.alert_unpaid'),
            count: a.unpaidCount,
            color: colors.danger,
            detail: ReportFormat.money(a.unpaidAmount),
            route: '/sales',
          ),
          divider,
          alertRow(
            label: tr(ref, 'reports.alert_partial'),
            count: a.partialCount,
            color: colors.warning,
            detail: '${tr(ref, 'reports.remaining')} ${ReportFormat.money(a.partialRemaining)}',
            route: '/sales',
          ),
          if (a.cancelled + a.refunded > 0) ...[
            divider,
            alertRow(
              label: tr(ref, 'reports.alert_cancelled'),
              count: a.cancelled + a.refunded,
              color: colors.info,
              route: '/sales',
            ),
          ],
          if (concerned.isNotEmpty) ...[
            Container(
              color: colors.surfaceMuted,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
              child: Text(
                tr(ref, 'reports.alert_items').toUpperCase(),
                style: context.text.tableHeader.copyWith(fontSize: 10.5),
              ),
            ),
            for (final item in concerned)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(item.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySecondary.copyWith(fontSize: 12)),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      '${item.quantity == item.quantity.roundToDouble() ? item.quantity.toStringAsFixed(0) : item.quantity.toStringAsFixed(1)}'
                      '${item.unit != null ? ' ${item.unit}' : ''}',
                      style: context.text.tableCell.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: item.outOfStock ? colors.danger : colors.warning,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// VENTES RÉCENTES
// ---------------------------------------------------------------------

class RecentSalesPanel extends ConsumerWidget {
  final ReportOverview data;

  const RecentSalesPanel({super.key, required this.data});

  static double heightFor(int rowCount) => 41 + 31 + math.max(4, rowCount) * 31.0 + 4;

  Widget _statusBadge(BuildContext context, WidgetRef ref, ReportSaleRow sale) {
    final colors = context.colors;
    if (sale.saleStatus == 'CANCELLED') {
      return StatusBadge(
        status: 'cancelled',
        label: tr(ref, 'reports.sale_cancelled'),
        color: colors.textSecondary,
        size: StatusBadgeSize.small,
      );
    }
    if (sale.saleStatus == 'REFUNDED') {
      return StatusBadge(
        status: 'refunded',
        label: tr(ref, 'reports.sale_refunded'),
        color: colors.textSecondary,
        size: StatusBadgeSize.small,
      );
    }
    switch (sale.paymentStatus) {
      case 'PAID':
        return StatusBadge(status: 'paid', label: tr(ref, 'reports.sale_paid'), color: colors.success, size: StatusBadgeSize.small);
      case 'PARTIALLY_PAID':
        return StatusBadge(status: 'partial', label: tr(ref, 'reports.sale_partial'), color: colors.warning, size: StatusBadgeSize.small);
      case 'REFUNDED':
        return StatusBadge(status: 'refunded', label: tr(ref, 'reports.sale_refunded'), color: colors.textSecondary, size: StatusBadgeSize.small);
      default:
        return StatusBadge(status: 'unpaid', label: tr(ref, 'reports.sale_unpaid'), color: colors.danger, size: StatusBadgeSize.small);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sales = data.recentSales;

    return ReportPanel(
      title: tr(ref, 'reports.recent_sales'),
      height: heightFor(sales.length),
      action: AppButton.text(
        label: tr(ref, 'reports.see_all_sales'),
        icon: Icons.arrow_forward_rounded,
        size: AppButtonSize.small,
        onPressed: () => context.go('/sales'),
      ),
      child: _MinWidth(
        minWidth: 760,
        child: ReportTable(
          columns: [
            ReportColumn(tr(ref, 'reports.col_ticket'), width: 84),
            ReportColumn(tr(ref, 'reports.column_date'), width: 84),
            ReportColumn(tr(ref, 'reports.col_time'), width: 52),
            ReportColumn(tr(ref, 'reports.column_cashier'), flex: 1),
            ReportColumn(tr(ref, 'reports.column_items'), width: 64, alignEnd: true),
            ReportColumn(tr(ref, 'reports.col_amount'), width: 110, alignEnd: true),
            ReportColumn(tr(ref, 'reports.column_payment_method'), width: 120),
            ReportColumn(tr(ref, 'reports.column_status'), width: 104),
          ],
          rows: [
            for (final s in sales)
              ReportRow(
                [
                  reportText(context, '#${s.ticket.toUpperCase()}', bold: true),
                  reportText(context, ReportFormat.date(s.occurredAt)),
                  reportText(context, ReportFormat.time(s.occurredAt)),
                  reportText(context, s.cashierName),
                  reportText(context, ReportFormat.integer(s.itemsCount), alignEnd: true),
                  reportText(
                    context,
                    ReportFormat.money(s.total),
                    alignEnd: true,
                    bold: true,
                    color: s.isCompleted ? null : context.colors.textMuted,
                  ),
                  reportText(context, s.paymentMethod == null ? '—' : _paymentMethodLabel(ref, s.paymentMethod!)),
                  _statusBadge(context, ref, s),
                ],
                // The existing sale/receipt detail — not a second system.
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => SaleDetailDialog(sale: s.toSale()),
                ),
              ),
          ],
          empty: ReportEmpty(message: tr(ref, 'reports.no_sales'), icon: Icons.receipt_long_outlined),
        ),
      ),
    );
  }
}
