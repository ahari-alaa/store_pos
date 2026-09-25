import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/design_system.dart';
import '../../../../core/l10n/locale_provider.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/restricted_page.dart';
import '../../../../core/widgets/ui/ui.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/entities/dashboard_extras.dart';
import '../providers/dashboard_provider.dart';
import '../widgets/articles_sold_card.dart';
import '../widgets/cashier_ranking_card.dart';
import '../widgets/dashboard_error_view.dart';
import '../widgets/period_selector.dart';
import '../widgets/recent_sales_card.dart';
import '../widgets/revenue_bar_chart_card.dart';
import '../widgets/sales_line_chart.dart';
import '../widgets/sales_status_chart.dart';

/// Accueil / Dashboard.
///
/// All sections (KPI cards, best cashier, sales status, revenue chart,
/// recent sales) come from the `/reports/dashboard-*` endpoints and
/// refresh whenever [dashboardPeriodProvider] changes.
///
/// The legacy "today vs yesterday" summary (top products, low-stock
/// alerts, 7-day mini chart) that used to sit below a divider here has
/// been removed from this page.
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Every /reports/* endpoint this page calls requires the
    // 'reports.view' permission (admin/manager only — see
    // store_pos_backend/src/middleware/authorize.js's ROLE_PERMISSIONS).
    // A cashier landing here would previously get a 403 from every single
    // fetch and see nothing but "Impossible de charger le tableau de
    // bord" — mirror the server-side check on the client instead, the
    // same way ExpensesPage/ProductsPage/CashiersPage already do (see
    // RestrictedPage's doc comment), so the UI says so plainly rather
    // than showing a broken screen full of failed requests. The
    // navigation side of this fix is in app_router.dart (`_redirect`
    // sends a cashier session to `/pos` instead of `/dashboard` after
    // login) and app_sidebar.dart (Accueil hidden from a cashier's
    // sidebar); this guard is the defensive fallback for a direct/deep
    // link straight to `/dashboard`.
    final user = ref.watch(authProvider).user;
    if (user != null && !user.canViewReports) {
      return RestrictedPage(message: tr(ref, 'dashboard.restricted'));
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(dashboardOverviewProvider);
        ref.invalidate(cashierRankingProvider);
        ref.invalidate(articlesSoldProvider);
        ref.invalidate(salesStatusProvider);
        ref.invalidate(revenueSeriesProvider);
        ref.invalidate(recentSalesProvider);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    tr(ref, 'nav.dashboard'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.sectionTitle,
                  ),
                ),
                const PeriodSelector(),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            const _OverviewKpiRow(),
            const SizedBox(height: AppSpacing.xl),
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 900;
                const chart = RevenueBarChartCard();
                const side = CashierRankingCard();
                if (!isWide) {
                  return const Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [chart, SizedBox(height: AppSpacing.xl), side],
                  );
                }
                return const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: chart),
                    SizedBox(width: AppSpacing.xl),
                    Expanded(child: side),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.xl),
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 900;
                const articles = ArticlesSoldCard();
                const status = SalesStatusChart();
                if (!isWide) {
                  return const Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [articles, SizedBox(height: AppSpacing.xl), status],
                  );
                }
                return const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: articles),
                    SizedBox(width: AppSpacing.xl),
                    Expanded(child: status),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.xl),
            const RecentSalesCard(),
          ],
        ),
      ),
    );
  }
}

class _OverviewKpiRow extends ConsumerWidget {
  const _OverviewKpiRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final overviewAsync = ref.watch(dashboardOverviewProvider);

    return overviewAsync.when(
      // Skeletons in the shape of the real cards, not a lone spinner in a
      // 100px box: the page no longer jumps as each section resolves, and
      // the cashier can see what is arriving.
      loading: () => const AppCardGridSkeleton(count: 4, columns: 4, aspectRatio: 2.4),
      // The KPI row is the first thing on the page, so it's the most
      // valuable place to say WHAT failed rather than "no connection" —
      // which was misleading whenever the server was reachable but
      // answering 403/500.
      error: (error, _) => DashboardErrorInline(
        error: error,
        onRetry: () => ref.invalidate(dashboardOverviewProvider),
      ),
      data: (overview) {
        // No trend badges here. The reference mockup shows "+12 % vs
        // hier" under every figure, but GET /reports/dashboard-overview
        // returns four scalars and no comparison period (see
        // DashboardOverview) — so a trend could only be invented. The
        // KpiCard supports `trendPercent` and will show it the day the
        // endpoint returns a previous-period total; until then the cards
        // stay honest.
        final tiles = <Widget>[
          KpiCard(
            icon: Icons.payments_outlined,
            accent: colors.primary,
            label: tr(ref, 'dashboard.revenue_today'),
            value: CurrencyFormatter.format(overview.totalRevenue),
          ),
          KpiCard(
            icon: Icons.receipt_long_outlined,
            accent: colors.info,
            label: tr(ref, 'dashboard.sales'),
            value: '${overview.saleCount}',
          ),
          KpiCard(
            icon: Icons.inventory_2_outlined,
            accent: colors.success,
            label: tr(ref, 'dashboard.products_sold'),
            value: '${overview.itemsSold}',
          ),
          KpiCard(
            icon: Icons.shopping_basket_outlined,
            accent: colors.warning,
            label: tr(ref, 'dashboard.average_basket'),
            value: CurrencyFormatter.format(overview.averageSale),
          ),
        ];

        return LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth > 1100
                ? 4
                : (constraints.maxWidth > 560 ? 2 : 1);
            // The aspect ratio has to grow as the tiles narrow, or a
            // one-column layout produces a 900px-tall KPI card.
            final aspectRatio = switch (columns) {
              4 => 2.4,
              2 => 3.0,
              _ => 4.0,
            };
            return GridView.count(
              crossAxisCount: columns,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: AppSpacing.lg,
              mainAxisSpacing: AppSpacing.lg,
              childAspectRatio: aspectRatio,
              children: tiles,
            );
          },
        );
      },
    );
  }
}
