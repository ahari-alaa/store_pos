import '../../../../core/utils/local_date_range.dart';

/// The Rapports screen's quick-period bar (spec §4) plus a custom range —
/// mirrors the backend's shared `REPORT_PERIODS` enum one-for-one
/// (reportValidators.js) so a period picked here can never resolve to a
/// different date range than the one the manager sees on screen.
enum ReportPeriod { today, yesterday, week, lastWeek, month, lastMonth, custom }

extension ReportPeriodX on ReportPeriod {
  /// Value sent to the backend as `?period=`.
  String get apiValue {
    switch (this) {
      case ReportPeriod.today:
        return 'today';
      case ReportPeriod.yesterday:
        return 'yesterday';
      case ReportPeriod.week:
        return 'week';
      case ReportPeriod.lastWeek:
        return 'last_week';
      case ReportPeriod.month:
        return 'month';
      case ReportPeriod.lastMonth:
        return 'last_month';
      case ReportPeriod.custom:
        return 'custom';
    }
  }

  String labelFr() {
    switch (this) {
      case ReportPeriod.today:
        return "Aujourd'hui";
      case ReportPeriod.yesterday:
        return 'Hier';
      case ReportPeriod.week:
        return 'Cette semaine';
      case ReportPeriod.lastWeek:
        return 'Semaine précédente';
      case ReportPeriod.month:
        return 'Ce mois';
      case ReportPeriod.lastMonth:
        return 'Mois précédent';
      case ReportPeriod.custom:
        return 'Personnalisé';
    }
  }

  String labelAr() {
    switch (this) {
      case ReportPeriod.today:
        return 'اليوم';
      case ReportPeriod.yesterday:
        return 'أمس';
      case ReportPeriod.week:
        return 'هذا الأسبوع';
      case ReportPeriod.lastWeek:
        return 'الأسبوع الماضي';
      case ReportPeriod.month:
        return 'هذا الشهر';
      case ReportPeriod.lastMonth:
        return 'الشهر الماضي';
      case ReportPeriod.custom:
        return 'فترة مخصصة';
    }
  }
}

/// The Rapports screen's full filter state: a named [period], plus the
/// explicit [from]/[to] the manager picked when [period] is
/// [ReportPeriod.custom]. Kept as one immutable value (rather than three
/// separate providers) so every report section reads a single consistent
/// snapshot of "what period is currently selected" — see
/// reports_provider.dart.
class ReportDateFilter {
  final ReportPeriod period;
  final DateTime? customFrom;
  final DateTime? customTo;

  const ReportDateFilter({required this.period, this.customFrom, this.customTo});

  static final ReportDateFilter initial = ReportDateFilter(period: ReportPeriod.month);

  ReportDateFilter copyWithPeriod(ReportPeriod period) =>
      ReportDateFilter(period: period, customFrom: customFrom, customTo: customTo);

  ReportDateFilter copyWithCustomRange(DateTime from, DateTime to) => ReportDateFilter(
        period: ReportPeriod.custom,
        customFrom: from,
        customTo: to,
      );

  /// Query parameters shared by every `/reports/*` endpoint this screen
  /// calls — always `period`, plus `from`/`to` only when it's `custom`
  /// (the backend requires both in that case, see reportValidators.js).
  Map<String, dynamic> toQuery() {
    if (period == ReportPeriod.custom && customFrom != null && customTo != null) {
      return {
        'period': 'custom',
        'from': LocalDateRange.dayStart(customFrom!),
        'to': LocalDateRange.dayEnd(customTo!),
      };
    }
    return {'period': period.apiValue};
  }

  /// True once a custom range has both endpoints — used to decide whether
  /// switching to "Période personnalisée" should immediately fetch or
  /// wait for the manager to actually pick dates.
  bool get isReady => period != ReportPeriod.custom || (customFrom != null && customTo != null);
}
