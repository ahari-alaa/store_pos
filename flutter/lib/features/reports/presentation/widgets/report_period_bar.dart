import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/design/design_system.dart';
import '../../../../core/l10n/locale_provider.dart';
import '../../../../core/widgets/ui/ui.dart';
import '../../domain/entities/report_period.dart';
import '../providers/reports_provider.dart';
import '../utils/report_export.dart';

/// Header controls (spec §5): quick periods, a custom date range, and the
/// Actualiser/Exporter actions. Every quick-period chip and the custom
/// range write to the SAME [reportFilterProvider], so exactly one filter
/// drives every section below (spec §4: "every report component must use
/// the same selected period").
class ReportPeriodBar extends ConsumerWidget {
  const ReportPeriodBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(reportFilterProvider);
    final locale = ref.watch(localeProvider);
    final isAr = locale.name == 'ar';

    String labelFor(ReportPeriod p) => isAr ? p.labelAr() : p.labelFr();

    return AppCard(
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final period in ReportPeriod.values.where((p) => p != ReportPeriod.custom))
            ChoiceChip(
              label: Text(labelFor(period)),
              selected: filter.period == period,
              onSelected: (_) =>
                  ref.read(reportFilterProvider.notifier).state = filter.copyWithPeriod(period),
            ),
          _CustomRangeChip(
            selected: filter.period == ReportPeriod.custom,
            filter: filter,
            label: labelFor(ReportPeriod.custom),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(width: 1, height: 28, color: context.colors.border),
          const SizedBox(width: AppSpacing.sm),
          AppButton.outline(
            label: tr(ref, 'reports.refresh'),
            icon: Icons.refresh_rounded,
            size: AppButtonSize.small,
            onPressed: () => ref.read(reportRefreshTickProvider.notifier).state++,
          ),
          const _ExportButton(),
        ],
      ),
    );
  }
}

class _CustomRangeChip extends ConsumerWidget {
  final bool selected;
  final ReportDateFilter filter;
  final String label;

  const _CustomRangeChip({required this.selected, required this.filter, required this.label});

  Future<void> _pickRange(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final initial = (filter.customFrom != null && filter.customTo != null)
        ? DateTimeRange(start: filter.customFrom!, end: filter.customTo!)
        : DateTimeRange(start: now.subtract(const Duration(days: 6)), end: now);

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: initial,
    );
    if (picked == null) return;
    ref.read(reportFilterProvider.notifier).state =
        filter.copyWithCustomRange(picked.start, picked.end);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = selected && filter.customFrom != null && filter.customTo != null
        ? '${DateFormat('dd/MM/yy').format(filter.customFrom!)} – ${DateFormat('dd/MM/yy').format(filter.customTo!)}'
        : label;

    return ChoiceChip(
      avatar: const Icon(Icons.calendar_month_outlined, size: 16),
      label: Text(text),
      selected: selected,
      onSelected: (_) => _pickRange(context, ref),
    );
  }
}

class _ExportButton extends ConsumerStatefulWidget {
  const _ExportButton();

  @override
  ConsumerState<_ExportButton> createState() => _ExportButtonState();
}

class _ExportButtonState extends ConsumerState<_ExportButton> {
  bool _busy = false;

  Future<void> _export(ReportExportFormat format) async {
    setState(() => _busy = true);
    try {
      await ReportExporter.export(ref: ref, format: format);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(trRead(ref, 'reports.export_failed'))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ReportExportFormat>(
      enabled: !_busy,
      onSelected: _export,
      itemBuilder: (context) => [
        PopupMenuItem(
          value: ReportExportFormat.pdf,
          child: Row(children: [
            const Icon(Icons.picture_as_pdf_outlined, size: 18),
            const SizedBox(width: AppSpacing.sm),
            Text(tr(ref, 'reports.export_pdf')),
          ]),
        ),
        PopupMenuItem(
          value: ReportExportFormat.csv,
          child: Row(children: [
            const Icon(Icons.table_chart_outlined, size: 18),
            const SizedBox(width: AppSpacing.sm),
            Text(tr(ref, 'reports.export_csv')),
          ]),
        ),
      ],
      child: AbsorbPointer(
        child: AppButton.secondary(
          label: tr(ref, 'reports.export'),
          icon: Icons.ios_share_rounded,
          size: AppButtonSize.small,
          loading: _busy,
          onPressed: () {},
        ),
      ),
    );
  }
}
