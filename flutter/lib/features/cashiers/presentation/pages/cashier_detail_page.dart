import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/restricted_page.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../reports/domain/entities/cashier_sales_report.dart';
import '../../../sales/domain/entities/sale.dart';
import '../../../sales/presentation/providers/sales_provider.dart';
import '../../../sales/presentation/widgets/sale_detail_dialog.dart';
import '../../../sales/presentation/widgets/sale_status_badge.dart';
import '../providers/cashiers_provider.dart';
import '../widgets/change_pin_dialog.dart';

/// Which period the "Sales Report" section is currently showing —
/// Cashiers screen → tap a staff member → Day/Month toggle (spec §2/§4).
enum _ReportMode { day, month }

/// Detail screen for a single staff member (Cashiers screen → tap a row):
/// their profile info plus a full Day/Month sales report — orders, total
/// sales, paid/not paid/partially paid counts, the day's (or month's daily
/// breakdown of) receipts — all backed by the server-side
/// GET /reports/cashier-sales aggregation rather than downloading the
/// store's whole sales history (spec §10). Admin-only, matching
/// [CashiersPage] itself.
class CashierDetailPage extends ConsumerStatefulWidget {
  final String cashierId;

  /// Passed via `context.push('/cashiers/$id', extra: user)` from the
  /// Cashiers list so this screen doesn't need its own network round trip
  /// for the common case. Can be null on a direct/refreshed navigation
  /// (e.g. a web deep link) — [_resolveUser] falls back to looking the id
  /// up in the already-loaded [cashiersProvider] list in that case.
  final AppUser? initialUser;

  const CashierDetailPage({super.key, required this.cashierId, this.initialUser});

  @override
  ConsumerState<CashierDetailPage> createState() => _CashierDetailPageState();
}

class _CashierDetailPageState extends ConsumerState<CashierDetailPage> {
  _ReportMode _mode = _ReportMode.day;
  late DateTime _day;
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    _day = _today();
    _month = DateTime(_day.year, _day.month, 1);
  }

  DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool get _isToday => _isSameDay(_day, _today());

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  void _shiftDay(int delta) {
    setState(() => _day = _day.add(Duration(days: delta)));
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta, 1));
  }

  Future<void> _pickDay(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2020),
      lastDate: _today(),
    );
    if (picked != null) {
      setState(() => _day = DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _pickMonth(BuildContext context) async {
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (_) => _MonthPickerDialog(initialMonth: _month),
    );
    if (picked != null) {
      setState(() => _month = picked);
    }
  }

  /// Opens a single day's receipts (spec §4/§8: clicking a row in the
  /// Month report's daily breakdown). Reuses [cashierDaySalesProvider] and
  /// the same [_ReceiptsList]/[SaleDetailDialog] as Day mode — no second
  /// receipt-list or receipt-detail implementation.
  Future<void> _openDay(AppUser user, DateTime date) async {
    await showDialog<void>(
      context: context,
      // `dialogContext` (not the page's `context`) for the same reason as
      // ConfirmToggleActiveDialog: this dialog is pushed onto the ROOT
      // navigator, while the page's context resolves to go_router's
      // ShellRoute navigator. Closing with the page context would pop
      // this *page* off the shell stack instead of closing the dialog.
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 620),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        DateFormat('EEEE, d MMM yyyy').format(date),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(dialogContext).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: Consumer(
                      builder: (context, ref, _) {
                        final salesAsync =
                            ref.watch(cashierDaySalesProvider((cashierId: user.id, day: date)));
                        return _ReceiptsList(salesAsync: salesAsync);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  AppUser? _resolveUser(List<AppUser> loaded) {
    if (widget.initialUser != null) return widget.initialUser;
    for (final u in loaded) {
      if (u.id == widget.cashierId) return u;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(authProvider).user;
    if (currentUser == null || !currentUser.isAdmin) {
      return const RestrictedPage(
        message: 'Only admins can view staff details.',
      );
    }

    final cashiersAsync = ref.watch(cashiersProvider);
    final user = _resolveUser(cashiersAsync.valueOrNull ?? const <AppUser>[]);

    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.all(24),
      child: user == null
          ? _LoadingOrMissing(
              loading: cashiersAsync.isLoading && !cashiersAsync.hasValue,
              onBack: () => _goBack(context),
            )
          : _buildContent(context, user, currentUser),
    );
  }

  /// Pops back to the Cashiers list when this screen has a back-stack
  /// entry to pop (the normal case — reached via `context.push` from
  /// [CashiersPage]), or navigates there directly when it doesn't (a
  /// direct/refreshed URL on web, where this route is the only entry).
  void _goBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/cashiers');
    }
  }

  void _openChangePin(BuildContext context, AppUser currentAdmin, AppUser target) {
    showDialog(
      context: context,
      builder: (_) => ChangePinDialog(
        user: target,
        onSubmit: (pin) => ref.read(cashiersProvider.notifier).changePin(
              target.id,
              pin,
              currentUserId: currentAdmin.id,
            ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, AppUser user, AppUser currentUser) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextButton.icon(
            onPressed: () => _goBack(context),
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text('Back to staff'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              padding: EdgeInsets.zero,
              alignment: Alignment.centerLeft,
            ),
          ),
          const SizedBox(height: 12),
          _ProfileCard(user: user, onChangePin: () => _openChangePin(context, currentUser, user)),
          const SizedBox(height: 20),
          Text(
            'Sales Report',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _ModeToggle(
            mode: _mode,
            onChanged: (mode) => setState(() => _mode = mode),
          ),
          const SizedBox(height: 16),
          if (_mode == _ReportMode.day) _buildDayReport(user) else _buildMonthReport(user),
        ],
      ),
    );
  }

  Widget _buildDayReport(AppUser user) {
    final params = (cashierId: user.id, day: _day);
    final summaryAsync = ref.watch(cashierDaySummaryProvider(params));
    final salesAsync = ref.watch(cashierDaySalesProvider(params));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DaySelector(
          day: _day,
          isToday: _isToday,
          onPrevious: () => _shiftDay(-1),
          onNext: _isToday ? null : () => _shiftDay(1),
          onPickDate: () => _pickDay(context),
        ),
        const SizedBox(height: 16),
        _SummaryCards(summaryAsync: summaryAsync),
        const SizedBox(height: 20),
        Text(
          'Receipts',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        _ReceiptsList(salesAsync: salesAsync),
      ],
    );
  }

  Widget _buildMonthReport(AppUser user) {
    final reportAsync =
        ref.watch(cashierMonthReportProvider((cashierId: user.id, month: _month)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MonthSelector(
          month: _month,
          isCurrentMonth: _isCurrentMonth,
          onPrevious: () => _shiftMonth(-1),
          onNext: _isCurrentMonth ? null : () => _shiftMonth(1),
          onPickMonth: () => _pickMonth(context),
        ),
        const SizedBox(height: 16),
        _SummaryCards(
          summaryAsync: reportAsync.when(
            data: (report) => AsyncValue.data(report.summary),
            loading: () => const AsyncValue.loading(),
            error: (e, s) => AsyncValue.error(e, s),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Daily activity',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        reportAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => _ErrorState(
            message: error is ApiException ? error.message : 'Could not load the monthly report.',
            onRetry: () => ref.invalidate(cashierMonthReportProvider((cashierId: user.id, month: _month))),
          ),
          data: (report) => _DailyBreakdownList(
            days: report.days,
            onTapDay: (date) => _openDay(user, date),
          ),
        ),
      ],
    );
  }
}

class _LoadingOrMissing extends StatelessWidget {
  final bool loading;
  final VoidCallback onBack;

  const _LoadingOrMissing({required this.loading, required this.onBack});

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.person_off_outlined, size: 40, color: AppColors.textMuted),
          const SizedBox(height: 12),
          const Text('Could not find this staff account.', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text('Back to staff'),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final AppUser user;
  final VoidCallback onChangePin;

  const _ProfileCard({required this.user, required this.onChangePin});

  String _roleLabel(String role) {
    switch (role) {
      case 'admin':
        return 'Admin';
      case 'manager':
        return 'Manager';
      default:
        return 'Cashier';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: AppColors.primarySurface,
              child: Text(
                user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                  fontSize: 24,
                ),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                  const SizedBox(height: 4),
                  Text(user.email, style: const TextStyle(color: AppColors.textSecondary)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _roleLabel(user.role),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  user.isActive ? 'Active' : 'Inactive',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: user.isActive ? AppColors.textSecondary : AppColors.danger,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: onChangePin,
              icon: const Icon(Icons.dialpad_rounded, size: 18),
              label: const Text('Change PIN'),
            ),
          ],
        ),
      ),
    );
  }
}

/// [ Day ] [ Month ] segmented toggle (spec §2/§4), styled with the app's
/// existing palette rather than a new one (spec §12).
class _ModeToggle extends StatelessWidget {
  final _ReportMode mode;
  final ValueChanged<_ReportMode> onChanged;

  const _ModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeButton(
            label: 'Day',
            selected: mode == _ReportMode.day,
            onTap: () => onChanged(_ReportMode.day),
          ),
          _ModeButton(
            label: 'Month',
            selected: mode == _ReportMode.month,
            onTap: () => onChanged(_ReportMode.month),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeButton({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: selected
              ? [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4, offset: const Offset(0, 1))]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
            color: selected ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _DaySelector extends StatelessWidget {
  final DateTime day;
  final bool isToday;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onPickDate;

  const _DaySelector({
    required this.day,
    required this.isToday,
    required this.onPrevious,
    required this.onNext,
    required this.onPickDate,
  });

  @override
  Widget build(BuildContext context) {
    String two(int n) => n.toString().padLeft(2, '0');
    final label = isToday ? 'Today' : '${two(day.day)}/${two(day.month)}/${day.year}';

    return Row(
      children: [
        IconButton(
          tooltip: 'Previous day',
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: onPrevious,
        ),
        InkWell(
          onTap: onPickDate,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.calendar_today_rounded, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: 'Next day',
          icon: const Icon(Icons.chevron_right_rounded),
          onPressed: onNext,
        ),
      ],
    );
  }
}

/// [ September 2026 ▾ ] month selector with prev/next arrows (spec §4),
/// mirroring [_DaySelector]'s layout so Day/Month feel like the same
/// control.
class _MonthSelector extends StatelessWidget {
  final DateTime month;
  final bool isCurrentMonth;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onPickMonth;

  const _MonthSelector({
    required this.month,
    required this.isCurrentMonth,
    required this.onPrevious,
    required this.onNext,
    required this.onPickMonth,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Previous month',
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: onPrevious,
        ),
        InkWell(
          onTap: onPickMonth,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.calendar_month_rounded, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Text(
                  DateFormat('MMMM yyyy').format(month),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down_rounded, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: 'Next month',
          icon: const Icon(Icons.chevron_right_rounded),
          onPressed: onNext,
        ),
      ],
    );
  }
}

/// Simple year/month picker (Flutter has no built-in month-only picker).
class _MonthPickerDialog extends StatefulWidget {
  final DateTime initialMonth;

  const _MonthPickerDialog({required this.initialMonth});

  @override
  State<_MonthPickerDialog> createState() => _MonthPickerDialogState();
}

class _MonthPickerDialogState extends State<_MonthPickerDialog> {
  late int _year = widget.initialMonth.year;
  late int _month = widget.initialMonth.month;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final years = [for (var y = 2020; y <= now.year; y++) y];

    return AlertDialog(
      title: const Text('Select month'),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              value: _month,
              decoration: const InputDecoration(labelText: 'Month'),
              items: [
                for (var m = 1; m <= 12; m++)
                  DropdownMenuItem(value: m, child: Text(DateFormat('MMMM').format(DateTime(2000, m)))),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _month = value);
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<int>(
              value: _year,
              decoration: const InputDecoration(labelText: 'Year'),
              items: [for (final y in years) DropdownMenuItem(value: y, child: Text('$y'))],
              onChanged: (value) {
                if (value != null) setState(() => _year = value);
              },
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            final picked = DateTime(_year, _month, 1);
            final firstAllowed = DateTime(now.year, now.month, 1);
            Navigator.of(context).pop(picked.isAfter(firstAllowed) ? firstAllowed : picked);
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

/// Orders / Total sales / Paid stat cards, shared by Day and Month mode
/// (spec §2/§4/§12). Not-paid and partially-paid counts are shown as a
/// compact line beneath the cards rather than two more cards, keeping the
/// existing 3-card layout (spec §12's mockup) while still surfacing every
/// figure spec §2/§4 asks for.
class _SummaryCards extends StatelessWidget {
  final AsyncValue<CashierReportSummary> summaryAsync;

  const _SummaryCards({required this.summaryAsync});

  @override
  Widget build(BuildContext context) {
    if (summaryAsync.isLoading && !summaryAsync.hasValue) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (summaryAsync.hasError && !summaryAsync.hasValue) {
      final error = summaryAsync.error;
      return _ErrorState(
        message: error is ApiException ? error.message : 'Could not load the sales report.',
        onRetry: () {},
      );
    }

    final summary = summaryAsync.valueOrNull ?? CashierReportSummary.empty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Orders',
                value: '${summary.orders}',
                icon: Icons.receipt_long_rounded,
                color: AppColors.info,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _StatCard(
                label: 'Total sales',
                value: CurrencyFormatter.format(summary.totalSales),
                icon: Icons.payments_rounded,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _StatCard(
                label: 'Paid',
                value: '${summary.paidOrders}',
                icon: Icons.check_circle_outline_rounded,
                color: AppColors.success,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            Text(
              'Not paid: ${summary.notPaidOrders}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            if (summary.partiallyPaidOrders > 0)
              Text(
                'Partially paid: ${summary.partiallyPaidOrders}',
                style: const TextStyle(color: AppColors.warning, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
          ],
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(height: 12),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }
}

/// Daily breakdown table for Month mode (spec §4): one row per day the
/// backend returned (days with zero orders are simply absent — nothing to
/// show), tappable to drill into that day's receipts.
class _DailyBreakdownList extends StatelessWidget {
  final List<CashierDailyBreakdown> days;
  final ValueChanged<DateTime> onTapDay;

  const _DailyBreakdownList({required this.days, required this.onTapDay});

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text('No activity this month', style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }

    // Most recent day first, matching the Day view's newest-first receipts.
    final sorted = [...days]..sort((a, b) => b.date.compareTo(a.date));

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final day in sorted) ...[
            _DailyBreakdownRow(day: day, onTap: () => onTapDay(day.date)),
            if (day != sorted.last) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _DailyBreakdownRow extends StatelessWidget {
  final CashierDailyBreakdown day;
  final VoidCallback onTap;

  const _DailyBreakdownRow({required this.day, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                DateFormat('dd/MM/yyyy').format(day.date),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text('${day.summary.orders} orders', style: const TextStyle(color: AppColors.textSecondary)),
            ),
            Expanded(
              flex: 2,
              child: Text(
                CurrencyFormatter.format(day.summary.totalSales),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

/// Receipts list shared by Day mode and the Month-mode day drill-down
/// (spec §3/§8). Every row opens the existing [SaleDetailDialog] — no
/// second receipt-detail implementation.
class _ReceiptsList extends StatelessWidget {
  final AsyncValue<List<Sale>> salesAsync;

  const _ReceiptsList({required this.salesAsync});

  @override
  Widget build(BuildContext context) {
    if (salesAsync.isLoading && !salesAsync.hasValue) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (salesAsync.hasError && !salesAsync.hasValue) {
      final error = salesAsync.error;
      return _ErrorState(
        message: error is ApiException ? error.message : 'Could not load receipts.',
        onRetry: () {},
      );
    }

    final sales = salesAsync.valueOrNull ?? const <Sale>[];
    if (sales.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text('No receipts for this day', style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final sale in sales) ...[
            _ReceiptRow(sale: sale, onTap: () => showDialog(context: context, builder: (_) => SaleDetailDialog(sale: sale))),
            if (sale != sales.last) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  final Sale sale;
  final VoidCallback onTap;

  const _ReceiptRow({required this.sale, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final local = sale.occurredAt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final time = '${two(local.hour)}:${two(local.minute)}';

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text('#${sale.receiptNumber}', style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            Expanded(
              flex: 1,
              child: Text(time, style: const TextStyle(color: AppColors.textSecondary)),
            ),
            Expanded(
              flex: 2,
              child: Text(
                CurrencyFormatter.format(sale.total),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(alignment: Alignment.centerLeft, child: SaleStatusBadge(status: sale.status)),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 40, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
