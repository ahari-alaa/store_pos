import 'package:flutter/material.dart';

import '../../design/design_system.dart';
import 'app_states.dart';

/// A single headline metric.
///
/// Deliberately narrow in what it accepts: a label, a value, an icon, and
/// an optional trend. It has no slot for arbitrary content, because the
/// moment a KPI card can hold anything, dashboards stop being scannable.
///
/// [trendPercent] is nullable and the card renders nothing at all when it
/// is null. That is important: this application must never display an
/// invented comparison. If the backend does not return a previous-period
/// figure, the card shows the value alone rather than a fabricated
/// "+12% vs hier".
class KpiCard extends StatelessWidget {
  final String label;

  /// The formatted value — already a string, because formatting a
  /// currency correctly is the caller's job (see CurrencyFormatter), not
  /// the card's.
  final String value;

  final IconData icon;

  /// Tints the icon chip. Use sparingly and consistently: the same metric
  /// should be the same color on every screen it appears on.
  final Color? accent;

  /// Percentage change against the comparison period. Null means "not
  /// available" and renders nothing.
  final double? trendPercent;

  /// What the trend is measured against, e.g. "vs hier".
  final String? trendLabel;

  /// For a metric where a decrease is the good outcome (expenses, stock
  /// shrinkage, refunds), so the arrow colors do not lie.
  final bool invertTrendColor;

  final VoidCallback? onTap;
  final bool loading;

  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.accent,
    this.trendPercent,
    this.trendLabel,
    this.invertTrendColor = false,
    this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final accentColor = accent ?? colors.primary;

    return _KpiSurface(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                      accentColor.withOpacity(0.12), colors.surface),
                  borderRadius: AppRadius.smAll,
                ),
                child: Icon(icon, size: AppSizes.iconMd, color: accentColor),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.label,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (loading)
            const AppSkeleton(width: 120, height: 26)
          else
            FittedBox(
              // The value is the point of the card, so it shrinks to fit
              // rather than wrapping or clipping — a long total like
              // "128 450,00 DH" used to overflow these cards on a narrow
              // window.
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: text.kpiValue),
            ),
          if (!loading && trendPercent != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _Trend(
              percent: trendPercent!,
              label: trendLabel,
              invert: invertTrendColor,
            ),
          ],
        ],
      ),
    );
  }
}

class _KpiSurface extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _KpiSurface({required this.child, this.onTap});

  @override
  State<_KpiSurface> createState() => _KpiSurfaceState();
}

class _KpiSurfaceState extends State<_KpiSurface> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final interactive = widget.onTap != null;

    final card = AnimatedContainer(
      duration: AppDurations.fast,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: interactive && _hovered ? colors.surfaceHover : colors.surface,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: colors.border),
      ),
      child: widget.child,
    );

    if (!interactive) return card;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: card,
      ),
    );
  }
}

class _Trend extends StatelessWidget {
  final double percent;
  final String? label;
  final bool invert;

  const _Trend({required this.percent, this.label, this.invert = false});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final rising = percent >= 0;
    final good = invert ? !rising : rising;

    // A flat result is neither good nor bad, and coloring it green would
    // overstate the news.
    final isFlat = percent.abs() < 0.05;
    final color = isFlat
        ? colors.textMuted
        : good
            ? colors.success
            : colors.danger;

    return Row(
      children: [
        Icon(
          isFlat
              ? Icons.remove_rounded
              : rising
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 3),
        Text(
          '${percent.abs().toStringAsFixed(percent.abs() < 10 ? 1 : 0)} %',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (label != null) ...[
          const SizedBox(width: AppSpacing.xs + 1),
          Flexible(
            child: Text(
              label!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySecondary.copyWith(fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }
}
