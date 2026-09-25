import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/design_system.dart';
import '../../../../core/l10n/locale_provider.dart';
import '../../../../core/widgets/ui/ui.dart';
import '../../domain/entities/report_period.dart';
import '../providers/reports_provider.dart';
import '../utils/report_export.dart';
import 'report_widgets.dart';

/// Compact toolbar of the Rapports screen: period selector (quick periods
/// + custom range), the resolved date range, and the
/// Actualiser / Excel / PDF / Imprimer actions.
///
/// The period selector writes to the SAME [reportFilterProvider] the data
/// provider listens to, so exactly one period drives every section, the
/// PDF, the Excel export and Print.
class ReportToolbar extends ConsumerWidget {
  const ReportToolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const left = _PeriodSelector();
        const right = _Actions();
        if (constraints.maxWidth < 900) {
          return const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [left, SizedBox(height: AppSpacing.sm), right],
          );
        }
        return const Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: left),
            SizedBox(width: AppSpacing.md),
            right,
          ],
        );
      },
    );
  }
}

class _PeriodSelector extends ConsumerWidget {
  const _PeriodSelector();

  Future<void> _pickRange(BuildContext context, WidgetRef ref, ReportDateFilter filter) async {
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
    final colors = context.colors;
    final filter = ref.watch(reportFilterProvider);
    final overview = ref.watch(reportOverviewProvider).valueOrNull;
    final isAr = ref.watch(localeProvider).name == 'ar';

    String labelFor(ReportPeriod p) => isAr ? p.labelAr() : p.labelFr();

    String? rangeText;
    if (filter.period == ReportPeriod.custom && filter.customFrom != null && filter.customTo != null) {
      rangeText = '${ReportFormat.date(filter.customFrom!)}  →  ${ReportFormat.date(filter.customTo!)}';
    } else if (overview != null) {
      rangeText = overview.period.days <= 1
          ? ReportFormat.date(overview.period.start)
          : '${ReportFormat.date(overview.period.start)}  →  ${ReportFormat.date(overview.period.end)}';
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.sm,
      children: [
        PopupMenuButton<ReportPeriod>(
          tooltip: '',
          onSelected: (period) {
            if (period == ReportPeriod.custom) {
              _pickRange(context, ref, filter);
            } else {
              ref.read(reportFilterProvider.notifier).state = filter.copyWithPeriod(period);
            }
          },
          itemBuilder: (context) => [
            for (final p in ReportPeriod.values)
              CheckedPopupMenuItem<ReportPeriod>(
                value: p,
                checked: filter.period == p,
                child: Text(labelFor(p)),
              ),
          ],
          child: Container(
            height: AppSizes.buttonHeightSm,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: AppRadius.smAll,
              border: Border.all(color: colors.borderStrong),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_month_outlined, size: AppSizes.iconSm, color: colors.primary),
                const SizedBox(width: AppSpacing.sm),
                Text(labelFor(filter.period), style: context.text.button.copyWith(fontSize: 13)),
                const SizedBox(width: AppSpacing.xs),
                Icon(Icons.arrow_drop_down_rounded, size: AppSizes.iconMd, color: colors.textSecondary),
              ],
            ),
          ),
        ),
        if (filter.period == ReportPeriod.custom)
          AppButton.text(
            label: tr(ref, 'reports.change_dates'),
            icon: Icons.edit_calendar_outlined,
            size: AppButtonSize.small,
            onPressed: () => _pickRange(context, ref, filter),
          ),
        if (rangeText != null)
          Text(
            rangeText,
            style: context.text.bodySecondary.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
      ],
    );
  }
}

class _Actions extends ConsumerStatefulWidget {
  const _Actions();

  @override
  ConsumerState<_Actions> createState() => _ActionsState();
}

class _ActionsState extends ConsumerState<_Actions> {
  ReportExportFormat? _busy;

  Future<void> _run(ReportExportFormat format) async {
    if (_busy != null) return;
    setState(() => _busy = format);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final savedTo = await ReportExporter.export(ref: ref, format: format);
      if (savedTo != null && mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('${trRead(ref, 'reports.export_saved')} $savedTo')),
        );
      }
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(trRead(ref, 'reports.export_failed'))));
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasData = ref.watch(reportOverviewProvider).hasValue;
    final busy = _busy != null;

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AppButton.outline(
          label: tr(ref, 'reports.refresh'),
          icon: Icons.refresh_rounded,
          size: AppButtonSize.small,
          onPressed: () => ref.read(reportRefreshTickProvider.notifier).state++,
        ),
        PopupMenuButton<ReportExportFormat>(
          tooltip: '',
          enabled: hasData && !busy,
          onSelected: _run,
          itemBuilder: (context) => [
            PopupMenuItem(
              value: ReportExportFormat.xlsx,
              child: Text(tr(ref, 'reports.export_xlsx')),
            ),
            PopupMenuItem(
              value: ReportExportFormat.csv,
              child: Text(tr(ref, 'reports.export_csv')),
            ),
          ],
          child: AbsorbPointer(
            child: AppButton.outline(
              label: 'Excel',
              icon: Icons.table_chart_outlined,
              size: AppButtonSize.small,
              loading: _busy == ReportExportFormat.xlsx || _busy == ReportExportFormat.csv,
              onPressed: hasData && !busy ? () {} : null,
            ),
          ),
        ),
        AppButton.outline(
          label: 'PDF',
          icon: Icons.picture_as_pdf_outlined,
          size: AppButtonSize.small,
          loading: _busy == ReportExportFormat.pdf,
          onPressed: hasData && !busy ? () => _run(ReportExportFormat.pdf) : null,
        ),
        AppButton.primary(
          label: tr(ref, 'reports.print'),
          icon: Icons.print_outlined,
          size: AppButtonSize.small,
          loading: _busy == ReportExportFormat.print,
          onPressed: hasData && !busy ? () => _run(ReportExportFormat.print) : null,
        ),
      ],
    );
  }
}
