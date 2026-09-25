import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/design/design_system.dart';

/// Number/date formatting shared by the Rapports screen, the PDF and the
/// Excel/CSV export, so a figure is written the same way everywhere:
/// space as thousands separator, dot as decimal separator, e.g.
/// `1 420.00 DH` (the shop's existing convention — see CurrencyFormatter).
///
/// Plain ASCII spaces on purpose: the PDF's built-in font has no glyph for
/// the narrow no-break space `intl` would emit for the `fr` locale.
class ReportFormat {
  ReportFormat._();

  static String _group(String digits) {
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  /// `1 420.00`
  static String amount(double value) {
    final negative = value < 0;
    final fixed = value.abs().toStringAsFixed(2);
    final parts = fixed.split('.');
    return '${negative ? '-' : ''}${_group(parts[0])}.${parts[1]}';
  }

  /// `1 420.00 DH`
  static String money(double value) => '${amount(value)} DH';

  /// `1 420`
  static String integer(int value) {
    final text = _group(value.abs().toString());
    return value < 0 ? '-$text' : text;
  }

  /// `80 %`
  static String percent(double value) {
    final text = value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
    return '$text %';
  }

  static String date(DateTime d) => DateFormat('dd/MM/yyyy').format(d);
  static String dateShort(DateTime d) => DateFormat('dd/MM').format(d);
  static String time(DateTime d) => DateFormat('HH:mm').format(d);
  static String dateTime(DateTime d) => DateFormat('dd/MM/yyyy HH:mm').format(d);
}

/// A titled surface with a compact header. When [height] is given the body
/// gets exactly the remaining space (tables scroll INSIDE it instead of
/// stretching the whole page); without it the panel wraps its content.
class ReportPanel extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? action;
  final double? height;
  final EdgeInsetsGeometry bodyPadding;
  final Widget child;

  const ReportPanel({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.action,
    this.height,
    this.bodyPadding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.label.copyWith(letterSpacing: 0.6, color: colors.textPrimary),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySecondary.copyWith(fontSize: 11.5),
                  ),
                ],
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: AppSpacing.sm), action!],
        ],
      ),
    );

    final body = Padding(padding: bodyPadding, child: child);

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: height == null ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Divider(height: 1, thickness: 1, color: colors.border),
          if (height == null) body else Expanded(child: body),
        ],
      ),
    );
  }
}

class ReportColumn {
  final String label;
  final int flex;
  final double? width;
  final bool alignEnd;

  const ReportColumn(this.label, {this.flex = 1, this.width, this.alignEnd = false});
}

class ReportRow {
  final List<Widget> cells;
  final VoidCallback? onTap;

  const ReportRow(this.cells, {this.onTap});
}

/// A plain-text table cell: one line, ellipsis, tabular figures.
Widget reportText(
  BuildContext context,
  String value, {
  bool bold = false,
  Color? color,
  bool alignEnd = false,
}) {
  return Text(
    value,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    textAlign: alignEnd ? TextAlign.end : TextAlign.start,
    style: context.text.tableCell.copyWith(
      fontSize: 12.5,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
}

/// Dense desktop table: 30 px rows, sticky header, optional totals row,
/// scrolls vertically inside whatever height its parent gives it. Must be
/// placed in a bounded-height parent (a [ReportPanel] with `height`).
class ReportTable extends StatelessWidget {
  static const double rowHeight = 30;

  final List<ReportColumn> columns;
  final List<ReportRow> rows;

  /// Bold totals row pinned under the scrolling rows.
  final ReportRow? footer;

  /// Shown instead of the rows when [rows] is empty.
  final Widget? empty;

  const ReportTable({
    super.key,
    required this.columns,
    required this.rows,
    this.footer,
    this.empty,
  });

  Widget _line(BuildContext context, List<Widget> cells, {Color? background, VoidCallback? onTap}) {
    final content = Container(
      height: rowHeight,
      color: background,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        children: [
          for (var i = 0; i < columns.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.sm),
            _cell(columns[i], i < cells.length ? cells[i] : const SizedBox.shrink()),
          ],
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(onTap: onTap, child: content);
  }

  Widget _cell(ReportColumn column, Widget child) {
    final aligned = Align(
      alignment: column.alignEnd ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: child,
    );
    if (column.width != null) return SizedBox(width: column.width, child: aligned);
    return Expanded(flex: column.flex, child: aligned);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;

    final header = _line(
      context,
      [
        for (final c in columns)
          Text(
            c.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.tableHeader.copyWith(fontSize: 11),
          ),
      ],
      background: colors.surfaceMuted,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Expanded(
          child: rows.isEmpty
              ? (empty ?? const SizedBox.shrink())
              : ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => Divider(height: 1, thickness: 1, color: colors.border),
                  itemBuilder: (context, index) =>
                      _line(context, rows[index].cells, onTap: rows[index].onTap),
                ),
        ),
        if (footer != null) ...[
          Divider(height: 1, thickness: 1, color: colors.borderStrong),
          _line(context, footer!.cells, background: colors.surfaceMuted),
        ],
      ],
    );
  }
}

/// Small centered message used for an empty / failed section body. Adapts
/// to the space it is given: a tall body gets icon-over-text, a short one
/// (e.g. the "Ventes récentes" panel with no rows) a single compact line,
/// so it can never overflow its panel.
class ReportEmpty extends StatelessWidget {
  final String message;
  final IconData icon;

  const ReportEmpty({super.key, required this.message, this.icon = Icons.inbox_outlined});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 110;
        if (compact) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20, color: colors.textMuted),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      message,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodySecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 28, color: colors.textMuted),
                const SizedBox(height: AppSpacing.sm),
                Text(message, textAlign: TextAlign.center, style: context.text.bodySecondary),
              ],
            ),
          ),
        );
      },
    );
  }
}
