import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/locale_provider.dart';
import '../../domain/entities/dashboard_extras.dart';
import '../providers/dashboard_provider.dart';

/// Aujourd'hui / Cette semaine / Ce mois selector driving every
/// period-aware dashboard section (KPI cards, "Meilleur caissier",
/// "Statut des ventes", "Ventes récentes").
class PeriodSelector extends ConsumerWidget {
  const PeriodSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(dashboardPeriodProvider);

    String labelFor(DashboardPeriod p) {
      switch (p) {
        case DashboardPeriod.today:
          return tr(ref, 'period.today');
        case DashboardPeriod.week:
          return tr(ref, 'period.week');
        case DashboardPeriod.month:
          return tr(ref, 'period.month');
      }
    }

    return SegmentedButton<DashboardPeriod>(
      segments: DashboardPeriod.values
          .map((p) => ButtonSegment(value: p, label: Text(labelFor(p))))
          .toList(),
      selected: {selected},
      showSelectedIcon: false,
      onSelectionChanged: (selection) {
        ref.read(dashboardPeriodProvider.notifier).state = selection.first;
      },
    );
  }
}
