import 'package:flutter/material.dart';

import '../../design/design_system.dart';
import 'app_button.dart';
import 'app_states.dart';

/// Horizontal alignment of a column's content.
///
/// The rule this application follows, and the old tables did not: text
/// left, numbers right, status and actions centred. Right-aligned numbers
/// are what let a manager scan a column of prices and see the magnitudes
/// line up, instead of reading every row.
enum AppColumnAlign { left, right, center }

class AppTableColumn<T> {
  final String label;

  /// Builds the cell. Return a plain `Text` for most columns — the table
  /// applies the shared cell style so callers do not restate it.
  final Widget Function(BuildContext context, T row) cell;

  final AppColumnAlign align;

  /// Relative width. A column with flex 3 takes three times the space of
  /// one with flex 1.
  final int flex;

  /// Fixed pixel width instead of flex — for the actions column, and for
  /// image thumbnails.
  final double? width;

  /// Supplies the value this column sorts on. Null means the column is
  /// not sortable and its header shows no sort affordance.
  final Comparable<Object>? Function(T row)? sortKey;

  const AppTableColumn({
    required this.label,
    required this.cell,
    this.align = AppColumnAlign.left,
    this.flex = 2,
    this.width,
    this.sortKey,
  });
}

/// The application's table.
///
/// Handles, in one place, everything the previous hand-rolled tables each
/// handled differently or not at all: header styling, row height, zebra-
/// free hairline separation, hover feedback, row selection, click-to-sort,
/// horizontal scrolling on narrow windows (rather than clipping columns),
/// and the empty/loading/error states.
///
/// The horizontal scroll matters: the old product and sales tables simply
/// squeezed their columns until the text clipped when the window narrowed.
/// Here, [minWidth] sets the point below which the table scrolls sideways
/// inside its own viewport, so no column is ever destroyed to fit and the
/// page body never scrolls horizontally.
class AppDataTable<T> extends StatefulWidget {
  final List<AppTableColumn<T>> columns;
  final List<T> rows;

  /// Called when a row is clicked. Rows become hoverable and show a
  /// pointer cursor only when this is set.
  final void Function(T row)? onRowTap;

  /// Highlights a row as selected — for a table paired with a detail
  /// panel.
  final bool Function(T row)? isSelected;

  final bool loading;
  final String? errorMessage;
  final VoidCallback? onRetry;

  /// Shown when [rows] is empty and there is no error.
  final Widget? emptyState;

  final double minWidth;
  final double rowHeight;

  const AppDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.onRowTap,
    this.isSelected,
    this.loading = false,
    this.errorMessage,
    this.onRetry,
    this.emptyState,
    this.minWidth = 900,
    this.rowHeight = AppSizes.tableRowHeight,
  });

  @override
  State<AppDataTable<T>> createState() => _AppDataTableState<T>();
}

class _AppDataTableState<T> extends State<AppDataTable<T>> {
  int? _sortColumn;
  bool _ascending = true;
  final ScrollController _horizontal = ScrollController();

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  void _toggleSort(int index) {
    setState(() {
      if (_sortColumn == index) {
        _ascending = !_ascending;
      } else {
        _sortColumn = index;
        _ascending = true;
      }
    });
  }

  List<T> get _sortedRows {
    final column = _sortColumn;
    if (column == null) return widget.rows;
    final keyOf = widget.columns[column].sortKey;
    if (keyOf == null) return widget.rows;

    final sorted = List<T>.of(widget.rows);
    sorted.sort((a, b) {
      final ka = keyOf(a);
      final kb = keyOf(b);
      // Nulls sort last in both directions — a missing value is not
      // "smallest", it is "unknown", and it should not lead the table.
      if (ka == null && kb == null) return 0;
      if (ka == null) return 1;
      if (kb == null) return -1;
      final result = ka.compareTo(kb);
      return _ascending ? result : -result;
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (widget.loading) {
      return AppTableSkeleton(columns: widget.columns.length.clamp(2, 6));
    }

    if (widget.errorMessage != null) {
      return AppErrorState(
        title: 'Chargement impossible',
        message: widget.errorMessage!,
        onRetry: widget.onRetry,
        compact: true,
      );
    }

    if (widget.rows.isEmpty) {
      return widget.emptyState ??
          const AppEmptyState(
            icon: Icons.inbox_outlined,
            title: 'Aucun résultat',
            message: 'Aucune donnée à afficher pour le moment.',
            compact: true,
          );
    }

    final rows = _sortedRows;

    return LayoutBuilder(
      builder: (context, constraints) {
        final needsScroll = constraints.maxWidth < widget.minWidth;
        final tableWidth = needsScroll ? widget.minWidth : constraints.maxWidth;

        final table = SizedBox(
          width: tableWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(colors),
              Flexible(
                child: ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, index) => _TableRow<T>(
                    row: rows[index],
                    columns: widget.columns,
                    height: widget.rowHeight,
                    onTap: widget.onRowTap,
                    selected: widget.isSelected?.call(rows[index]) ?? false,
                    isLast: index == rows.length - 1,
                  ),
                ),
              ),
            ],
          ),
        );

        if (!needsScroll) return table;

        return Scrollbar(
          controller: _horizontal,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _horizontal,
            scrollDirection: Axis.horizontal,
            child: table,
          ),
        );
      },
    );
  }

  Widget _header(AppColorScheme colors) {
    return Container(
      height: AppSizes.tableHeaderHeight,
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          for (var i = 0; i < widget.columns.length; i++)
            _headerCell(i, widget.columns[i], colors),
        ],
      ),
    );
  }

  Widget _headerCell(int index, AppTableColumn<T> column, AppColorScheme colors) {
    final sortable = column.sortKey != null;
    final active = _sortColumn == index;

    Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: switch (column.align) {
        AppColumnAlign.left => MainAxisAlignment.start,
        AppColumnAlign.right => MainAxisAlignment.end,
        AppColumnAlign.center => MainAxisAlignment.center,
      },
      children: [
        Flexible(
          child: Text(
            column.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.tableHeader.copyWith(
              color: active ? colors.primary : colors.textSecondary,
            ),
          ),
        ),
        if (sortable) ...[
          const SizedBox(width: AppSpacing.xs),
          Icon(
            active
                ? (_ascending
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded)
                : Icons.unfold_more_rounded,
            size: 13,
            color: active ? colors.primary : colors.textMuted,
          ),
        ],
      ],
    );

    if (sortable) {
      content = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => _toggleSort(index),
          behavior: HitTestBehavior.opaque,
          child: content,
        ),
      );
    }

    final aligned = Align(
      alignment: switch (column.align) {
        AppColumnAlign.left => Alignment.centerLeft,
        AppColumnAlign.right => Alignment.centerRight,
        AppColumnAlign.center => Alignment.center,
      },
      child: content,
    );

    return column.width != null
        ? SizedBox(width: column.width, child: aligned)
        : Expanded(flex: column.flex, child: aligned);
  }
}

class _TableRow<T> extends StatefulWidget {
  final T row;
  final List<AppTableColumn<T>> columns;
  final double height;
  final void Function(T row)? onTap;
  final bool selected;
  final bool isLast;

  const _TableRow({
    required this.row,
    required this.columns,
    required this.height,
    required this.onTap,
    required this.selected,
    required this.isLast,
  });

  @override
  State<_TableRow<T>> createState() => _TableRowState<T>();
}

class _TableRowState<T> extends State<_TableRow<T>> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final interactive = widget.onTap != null;

    final background = widget.selected
        ? colors.primarySurface
        : (_hovered && interactive ? colors.surfaceHover : colors.surface);

    Widget row = Container(
      height: widget.height,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      decoration: BoxDecoration(
        color: background,
        border: widget.isLast
            ? null
            : Border(bottom: BorderSide(color: colors.border)),
      ),
      child: DefaultTextStyle.merge(
        style: context.text.tableCell,
        // Every cell gets one line and ellipsis by default, which is what
        // stops a long product name from overflowing the row — the old
        // tables let unbounded Text widgets throw layout errors here.
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        child: Row(
          children: [
            for (final column in widget.columns)
              _cell(context, column),
          ],
        ),
      ),
    );

    if (!interactive) return row;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => widget.onTap!(widget.row),
        behavior: HitTestBehavior.opaque,
        child: row,
      ),
    );
  }

  Widget _cell(BuildContext context, AppTableColumn<T> column) {
    final aligned = Align(
      alignment: switch (column.align) {
        AppColumnAlign.left => Alignment.centerLeft,
        AppColumnAlign.right => Alignment.centerRight,
        AppColumnAlign.center => Alignment.center,
      },
      child: column.cell(context, widget.row),
    );

    return column.width != null
        ? SizedBox(width: column.width, child: aligned)
        : Expanded(flex: column.flex, child: aligned);
  }
}

/// Pagination footer. Shows the range as well as the page number, because
/// "1–25 sur 312" answers a question that "Page 1" does not.
class AppPagination extends StatelessWidget {
  final int page;
  final int pageCount;
  final int totalItems;
  final int pageSize;
  final ValueChanged<int> onPageChanged;

  const AppPagination({
    super.key,
    required this.page,
    required this.pageCount,
    required this.totalItems,
    required this.pageSize,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final first = totalItems == 0 ? 0 : (page - 1) * pageSize + 1;
    final last = (page * pageSize).clamp(0, totalItems);

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Text('$first–$last sur $totalItems', style: context.text.bodySecondary),
          const Spacer(),
          AppIconButton(
            icon: Icons.chevron_left_rounded,
            tooltip: 'Page précédente',
            onPressed: page > 1 ? () => onPageChanged(page - 1) : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Text('$page / $pageCount', style: context.text.numeric),
          ),
          AppIconButton(
            icon: Icons.chevron_right_rounded,
            tooltip: 'Page suivante',
            onPressed: page < pageCount ? () => onPageChanged(page + 1) : null,
          ),
        ],
      ),
    );
  }
}
