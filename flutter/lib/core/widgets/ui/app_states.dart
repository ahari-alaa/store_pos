import 'package:flutter/material.dart';

import '../../design/design_system.dart';
import 'app_button.dart';

/// Nothing to show, and that is fine.
///
/// An empty state must answer two questions: why is this empty, and what
/// can I do about it. A bare "Aucun produit" answers neither, which is
/// why [action] is a first-class parameter here rather than an
/// afterthought.
class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;

  /// One line explaining *why* it is empty — "no sales recorded today"
  /// reads very differently from "no sales match your filters".
  final String? message;

  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? actionIcon;

  /// Shrinks padding for use inside a card body rather than a full page.
  final bool compact;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(compact ? AppSpacing.lg : AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: compact ? 48 : 64,
              height: compact ? 48 : 64,
              decoration: BoxDecoration(
                color: colors.surfaceMuted,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: compact ? AppSizes.iconLg : AppSizes.iconXl,
                color: colors.textMuted,
              ),
            ),
            SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: compact ? text.cardTitle : text.sectionTitle,
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.xs),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: text.bodySecondary,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: compact ? AppSpacing.md : AppSpacing.xl),
              AppButton.primary(
                label: actionLabel!,
                icon: actionIcon,
                onPressed: onAction,
                size: compact ? AppButtonSize.small : AppButtonSize.medium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Something failed, said in language a cashier can act on.
///
/// [message] must be a human sentence. Raw exception text, stack traces,
/// SQL errors and API error objects never reach this widget — the caller
/// maps them first. [technicalDetail] exists for the cases where a
/// manager genuinely needs the underlying cause (a misconfigured server
/// address, say); it stays folded away behind a disclosure so it is
/// available without being shouted at the user.
class AppErrorState extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;
  final IconData icon;
  final String? technicalDetail;
  final bool compact;

  const AppErrorState({
    super.key,
    required this.title,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Réessayer',
    this.icon = Icons.cloud_off_rounded,
    this.technicalDetail,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(compact ? AppSpacing.lg : AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: compact ? 48 : 64,
              height: compact ? 48 : 64,
              decoration: BoxDecoration(
                color: colors.dangerSurface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: compact ? AppSizes.iconLg : AppSizes.iconXl,
                color: colors.danger,
              ),
            ),
            SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: compact ? text.cardTitle : text.sectionTitle,
            ),
            const SizedBox(height: AppSpacing.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: text.bodySecondary,
              ),
            ),
            if (onRetry != null) ...[
              SizedBox(height: compact ? AppSpacing.md : AppSpacing.xl),
              AppButton.primary(
                label: retryLabel,
                icon: Icons.refresh_rounded,
                onPressed: onRetry,
                size: compact ? AppButtonSize.small : AppButtonSize.medium,
              ),
            ],
            if (technicalDetail != null && technicalDetail!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    title: Text('Détails techniques', style: text.label),
                    children: [
                      SelectableText(
                        technicalDetail!,
                        style: text.bodySecondary.copyWith(
                          fontSize: 11.5,
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A grey block that pulses. The building block for every skeleton.
class AppSkeleton extends StatefulWidget {
  final double? width;
  final double height;
  final BorderRadius borderRadius;

  const AppSkeleton({
    super.key,
    this.width,
    this.height = 14,
    this.borderRadius = AppRadius.xsAll,
  });

  /// A circle, for avatar and image placeholders.
  const AppSkeleton.circle({super.key, required double size})
      : width = size,
        height = size,
        borderRadius = const BorderRadius.all(Radius.circular(999));

  @override
  State<AppSkeleton> createState() => _AppSkeletonState();
}

class _AppSkeletonState extends State<AppSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Color.lerp(
              colors.surfaceMuted,
              colors.surfaceHover,
              _controller.value,
            ),
            borderRadius: widget.borderRadius,
          ),
        );
      },
    );
  }
}

/// Skeleton placeholder shaped like a table, so a loading list keeps the
/// page's layout instead of collapsing to a centred spinner and then
/// jumping when data lands.
class AppTableSkeleton extends StatelessWidget {
  final int rows;
  final int columns;

  const AppTableSkeleton({super.key, this.rows = 6, this.columns = 5});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var r = 0; r < rows; r++)
          Container(
            height: AppSizes.tableRowHeight,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Row(
              children: [
                for (var c = 0; c < columns; c++) ...[
                  Expanded(
                    // Varying widths so it reads as content, not as a
                    // loading bar array.
                    flex: c == 0 ? 3 : 2,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: AppSkeleton(
                        width: c == 0 ? 160 : (c.isEven ? 72 : 96),
                        height: 12,
                      ),
                    ),
                  ),
                  if (c < columns - 1) const SizedBox(width: AppSpacing.lg),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// Skeleton shaped like a grid of cards — the POS catalog and the
/// dashboard KPI row while they load.
class AppCardGridSkeleton extends StatelessWidget {
  final int count;
  final int columns;
  final double aspectRatio;

  const AppCardGridSkeleton({
    super.key,
    this.count = 8,
    this.columns = 4,
    this.aspectRatio = 0.9,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GridView.builder(
      padding: AppSpacing.pagePadding,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: AppSpacing.lg,
        crossAxisSpacing: AppSpacing.lg,
        childAspectRatio: aspectRatio,
      ),
      itemCount: count,
      itemBuilder: (context, index) => Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppSkeleton(width: 56, height: 12),
            const SizedBox(height: AppSpacing.md),
            const Expanded(
              child: AppSkeleton(
                width: double.infinity,
                height: double.infinity,
                borderRadius: AppRadius.smAll,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const AppSkeleton(width: 100, height: 12),
          ],
        ),
      ),
    );
  }
}

/// Centred spinner with a label. For short, blocking waits only —
/// anything that loads a list or a page should use a skeleton instead, so
/// the layout does not jump.
class AppLoadingState extends StatelessWidget {
  final String? message;

  const AppLoadingState({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: colors.primary),
          ),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(message!, style: context.text.bodySecondary),
          ],
        ],
      ),
    );
  }
}
