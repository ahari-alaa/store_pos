import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/restricted_page.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../ingredients/presentation/providers/ingredients_provider.dart';
import '../../../ingredients/presentation/widgets/quick_restock_dialog.dart';
import '../../domain/entities/expense.dart';
import '../../domain/entities/expense_monthly_report.dart';
import '../../domain/entities/expense_type.dart';
import '../../domain/entities/feed_entry.dart';
import '../providers/expenses_provider.dart';
import '../providers/feed_provider.dart';
import '../widgets/expense_detail_dialog.dart';
import '../widgets/expense_filters_sheet.dart';
import '../widgets/expense_form_dialog.dart';

class ExpensesPage extends ConsumerStatefulWidget {
  const ExpensesPage({super.key});

  @override
  ConsumerState<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends ConsumerState<ExpensesPage> {
  final _searchController = TextEditingController();

  // Stocks + Dépenses are one page now (single sidebar entry): default to
  // the merged chronological feed, with the existing filterable expense
  // table still available behind a toggle for anyone who wants to dig
  // into just the expenses side.
  bool _showFeed = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Manual French month names, deliberately not using
  // `DateFormat.yMMMM('fr_FR')`: that requires `initializeDateFormatting`
  // to have been called first (the app currently never calls it — every
  // other DateFormat in the codebase uses the default/English locale),
  // and would throw a LocaleDataException otherwise. A small static
  // table avoids adding that app-wide initialization just for this one
  // label.
  static const _frenchMonths = [
    'Janvier',
    'Février',
    'Mars',
    'Avril',
    'Mai',
    'Juin',
    'Juillet',
    'Août',
    'Septembre',
    'Octobre',
    'Novembre',
    'Décembre',
  ];

  String _monthLabel(DateTime month) =>
      '${_frenchMonths[month.month - 1]} ${month.year}';

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    if (user == null || !user.canManageExpenses) {
      return const RestrictedPage(
        message:
            "Seuls les administrateurs et gérants peuvent gérer les dépenses.",
      );
    }

    final state = ref.watch(expensesProvider);
    final notifier = ref.read(expensesProvider.notifier);

    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // --- Header ---------------------------------------------------
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Stocks & Dépenses',
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold)),
                    SizedBox(height: 4),
                    Text(
                      'Tout ce qui entre et sort du magasin, au même endroit',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _openRestock(context),
                icon: const Icon(Icons.inventory_2_outlined, size: 18),
                label: const Text('Nouveau stock'),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: () => _openForm(context, initialType: state.tab),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Nouvelle dépense'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _ViewModeToggle(
                showFeed: _showFeed,
                onChanged: (value) => setState(() => _showFeed = value),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => context.push('/stocks'),
                icon: const Icon(Icons.tune_rounded, size: 16),
                label: const Text('Gérer les ingrédients'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (_showFeed)
            const Expanded(child: _CombinedFeed())
          else ...[
            // --- Month selector + recurring suggestions ------------------
            Align(
              alignment: Alignment.centerRight,
              child: _MonthSelector(
                label: _monthLabel(state.month),
                onPrevious: notifier.goToPreviousMonth,
                onNext: notifier.goToNextMonth,
              ),
            ),
            const SizedBox(height: 12),
            state.recurringSuggestions.maybeWhen(
              data: (suggestions) => suggestions.isEmpty
                  ? const SizedBox.shrink()
                  : _RecurringSuggestionsBanner(
                      suggestions: suggestions,
                      onCreate: (s) => _openForm(context, template: s),
                    ),
              orElse: () => const SizedBox.shrink(),
            ),

            // --- Tabs -------------------------------------------------------
            _ExpenseTypeTabs(
              selected: state.tab,
              onSelected: notifier.setTab,
            ),
            const SizedBox(height: 16),

            // --- Summary cards ------------------------------------------
            state.report.when(
              loading: () => const _SummaryCardsPlaceholder(),
              error: (_, __) => const SizedBox.shrink(),
              data: (report) => _SummaryCards(report: report),
            ),
            const SizedBox(height: 16),

            // --- Search + filters -------------------------------------
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded, size: 20),
                      hintText: 'Rechercher une dépense...',
                    ),
                    onSubmitted: (v) =>
                        notifier.setFilters(state.filters.copyWith(search: v)),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () =>
                      _openFilters(context, state.filters, notifier),
                  icon: Icon(
                    Icons.filter_list_rounded,
                    size: 20,
                    color: state.filters.isActive ? AppColors.primary : null,
                  ),
                  label: Text(
                      state.filters.isActive ? 'Filtres actifs' : 'Filtres'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // --- Table ----------------------------------------------------
            Expanded(
              child: state.expenses.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => _ErrorState(
                  message: error is ApiException
                      ? error.message
                      : 'Impossible de charger les dépenses.',
                  onRetry: notifier.loadAll,
                ),
                data: (expenses) {
                  if (expenses.isEmpty) {
                    return _EmptyState(
                        onAdd: () =>
                            _openForm(context, initialType: state.tab));
                  }
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        const _HeaderRow(),
                        const Divider(height: 1),
                        Expanded(
                          child: ListView.separated(
                            itemCount: expenses.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final expense = expenses[index];
                              return InkWell(
                                onTap: () => _openDetail(context, expense),
                                child: _ExpenseRow(expense: expense),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openRestock(BuildContext context) {
    final ingredients = ref.read(ingredientsProvider).valueOrNull ?? const [];
    showDialog(
      context: context,
      builder: (_) => QuickRestockDialog(
        ingredients: ingredients,
        onSubmit: (ingredientId, quantity, note) async {
          await ref
              .read(ingredientsProvider.notifier)
              .addStock(ingredientId, quantity, note: note);
          ref.read(feedProvider.notifier).refresh();
        },
      ),
    );
  }

  void _openForm(BuildContext context,
      {ExpenseType? initialType, Expense? template}) {
    showDialog(
      context: context,
      builder: (_) => ExpenseFormDialog(
        initialType: template?.expenseType ?? initialType,
        existing: template != null ? _asDraftFrom(template) : null,
        onSubmit: (input, {receipt}) async {
          final notifier = ref.read(expensesProvider.notifier);
          final created = await notifier.createExpense(input);
          if (receipt != null) {
            await notifier.uploadReceipt(created.id,
                bytes: receipt.bytes, filename: receipt.filename);
          }
        },
      ),
    );
  }

  /// A recurring suggestion is a *template* for a brand-new expense (spec
  /// §5), never an edit of the old one — so this reuses [ExpenseFormDialog]
  /// in "create" mode (no `existing.id` is ever sent back to the server)
  /// while still pre-filling last month's amount/supplier/etc, with
  /// today's date instead of the old occurrence's date.
  Expense _asDraftFrom(Expense template) {
    return Expense(
      id: '',
      clientOperationId: '',
      expenseType: template.expenseType,
      categoryId: template.categoryId,
      category: template.category,
      description: template.description,
      amount: template.amount,
      quantity: template.quantity,
      unit: template.unit,
      unitPrice: template.unitPrice,
      supplierId: template.supplierId,
      supplierName: template.supplierName,
      notes: null,
      productId: template.productId,
      productName: template.productName,
      ingredientId: template.ingredientId,
      ingredientName: template.ingredientName,
      affectsInventory: template.affectsInventory,
      isRecurring: template.isRecurring,
      recurringDay: template.recurringDay,
      receiptUrl: null,
      occurredAt: DateTime.now(),
      createdAt: DateTime.now(),
    );
  }

  void _openDetail(BuildContext context, Expense expense) {
    final user = ref.read(authProvider).user;
    showDialog(
      context: context,
      builder: (_) => ExpenseDetailDialog(
        expense: expense,
        canEdit: user?.canManageExpenses ?? false,
        canDelete: user?.canManageExpenses ?? false,
      ),
    );
  }

  void _openFilters(
    BuildContext context,
    ExpenseFilters current,
    ExpensesNotifier notifier,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => ExpenseFiltersSheet(
        initial: current,
        onApply: (filters) {
          notifier.setFilters(filters);
        },
      ),
    );
  }
}

class _ViewModeToggle extends StatelessWidget {
  final bool showFeed;
  final ValueChanged<bool> onChanged;

  const _ViewModeToggle({required this.showFeed, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleTab(
              label: 'Flux', selected: showFeed, onTap: () => onChanged(true)),
          _ToggleTab(
              label: 'Détail dépenses',
              selected: !showFeed,
              onTap: () => onChanged(false)),
        ],
      ),
    );
  }
}

class _ToggleTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleTab(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: selected
              ? [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 1))
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Single chronological list mixing expenses and ingredient stock
/// movements — the default view of the merged Stocks + Dépenses page.
class _CombinedFeed extends ConsumerWidget {
  const _CombinedFeed();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(feedProvider);

    return feedAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorState(
        message: error is ApiException
            ? error.message
            : 'Impossible de charger le flux.',
        onRetry: () => ref.read(feedProvider.notifier).refresh(),
      ),
      data: (entries) {
        if (entries.isEmpty) {
          return const Center(
            child: Text('Aucune activité pour le moment',
                style: TextStyle(color: AppColors.textSecondary)),
          );
        }
        return Card(
          clipBehavior: Clip.antiAlias,
          child: RefreshIndicator(
            onRefresh: () => ref.read(feedProvider.notifier).refresh(),
            child: ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) => _FeedRow(entry: entries[index]),
            ),
          ),
        );
      },
    );
  }
}

class _FeedRow extends StatelessWidget {
  final FeedEntry entry;

  const _FeedRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isExpense = entry.type == FeedEntryType.expense;
    final d = entry.occurredAt;
    final dateLabel =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

    final IconData icon;
    final Color color;
    String trailing;

    if (isExpense) {
      icon = Icons.payments_outlined;
      color = AppColors.accentOrange;
      trailing = entry.amount != null
          ? '- ${CurrencyFormatter.format(entry.amount!)}'
          : '';
    } else {
      final isIncoming = (entry.quantityDelta ?? 0) >= 0;
      icon = isIncoming
          ? Icons.arrow_downward_rounded
          : Icons.arrow_upward_rounded;
      color = isIncoming ? AppColors.success : AppColors.danger;
      final qty = entry.quantityDelta ?? 0;
      trailing =
          '${qty > 0 ? '+' : ''}${qty.toStringAsFixed(qty == qty.roundToDouble() ? 0 : 1)} ${entry.unit ?? ''}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          SizedBox(
              width: 48,
              child: Text(dateLabel,
                  style: const TextStyle(color: AppColors.textSecondary))),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.title,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  isExpense
                      ? (entry.relatedName?.isNotEmpty == true
                          ? entry.relatedName!
                          : _movementLabel(entry.movementType, isExpense: true))
                      : _movementLabel(entry.movementType, isExpense: false),
                  style:
                      const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          Text(
            trailing,
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: isExpense ? AppColors.danger : color),
          ),
        ],
      ),
    );
  }

  String _movementLabel(String raw, {required bool isExpense}) {
    if (isExpense) {
      switch (raw) {
        case 'APPROVISIONNEMENT':
          return 'Approvisionnement';
        case 'CHARGE_FIXE':
          return 'Charge fixe';
        default:
          return 'Autre dépense';
      }
    }
    switch (raw) {
      case 'PURCHASE':
        return 'Achat / réception';
      case 'SALE_CONSUMPTION':
        return 'Consommation automatique';
      case 'ADJUSTMENT':
        return 'Ajustement';
      case 'DAMAGE':
        return 'Perte / casse';
      default:
        return raw;
    }
  }
}

class _MonthSelector extends StatelessWidget {
  final String label;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  const _MonthSelector(
      {required this.label, required this.onPrevious, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left_rounded)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          IconButton(
              onPressed: onNext, icon: const Icon(Icons.chevron_right_rounded)),
        ],
      ),
    );
  }
}

class _ExpenseTypeTabs extends StatelessWidget {
  final ExpenseType? selected;
  final ValueChanged<ExpenseType?> onSelected;

  const _ExpenseTypeTabs({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, ExpenseType? value) {
      final isSelected = selected == value;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: isSelected,
          onSelected: (_) => onSelected(value),
          selectedColor: AppColors.primaryLight,
          labelStyle: TextStyle(
            color: isSelected ? AppColors.primaryDark : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
          backgroundColor: AppColors.surface,
          side: BorderSide(
              color: isSelected ? AppColors.primary : AppColors.border),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip('Toutes', null),
          for (final type in ExpenseType.values) chip(type.pluralLabel, type),
        ],
      ),
    );
  }
}

class _SummaryCardsPlaceholder extends StatelessWidget {
  const _SummaryCardsPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 96,
      child: Center(child: LinearProgressIndicator()),
    );
  }
}

class _SummaryCards extends StatelessWidget {
  final ExpenseMonthlyReport report;

  const _SummaryCards({required this.report});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            title: 'Approvisionnements',
            amount: report.supplies,
            count: report.suppliesCount,
            color: AppColors.accentTeal,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryCard(
            title: 'Charges fixes',
            amount: report.fixed,
            count: report.fixedCount,
            color: AppColors.accentOrange,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryCard(
            title: 'Autres',
            amount: report.other,
            count: report.otherCount,
            color: AppColors.accentPurple,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryCard(
            title: 'Total dépenses',
            amount: report.total,
            count: report.totalCount,
            color: AppColors.primary,
            emphasized: true,
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final double amount;
  final int count;
  final Color color;
  final bool emphasized;

  const _SummaryCard({
    required this.title,
    required this.amount,
    required this.count,
    required this.color,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: emphasized ? color.withOpacity(0.08) : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: emphasized ? color.withOpacity(0.3) : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 8),
          Text(
            CurrencyFormatter.format(amount),
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(height: 2),
          Text('$count entrée${count > 1 ? 's' : ''}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ],
      ),
    );
  }
}

class _RecurringSuggestionsBanner extends StatelessWidget {
  final List<Expense> suggestions;
  final ValueChanged<Expense> onCreate;

  const _RecurringSuggestionsBanner(
      {required this.suggestions, required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.info.withOpacity(0.08),
        border: Border.all(color: AppColors.info.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.event_repeat_rounded, size: 18, color: AppColors.info),
              SizedBox(width: 8),
              Text('Dépenses récurrentes à créer ce mois-ci',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: suggestions
                .map(
                  (s) => OutlinedButton.icon(
                    onPressed: () => onCreate(s),
                    icon: const Icon(Icons.add, size: 16),
                    label: Text(
                        '${s.category} · ${CurrencyFormatter.format(s.amount)}'),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: AppColors.textMuted,
      letterSpacing: 0.4,
    );
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          SizedBox(width: 84, child: Text('DATE', style: style)),
          Expanded(flex: 3, child: Text('CATÉGORIE', style: style)),
          Expanded(flex: 2, child: Text('TYPE', style: style)),
          Expanded(flex: 2, child: Text('QUANTITÉ', style: style)),
          Expanded(flex: 2, child: Text('MONTANT', style: style)),
          Expanded(flex: 2, child: Text('FOURNISSEUR', style: style)),
        ],
      ),
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  final Expense expense;

  const _ExpenseRow({required this.expense});

  Color _typeColor(ExpenseType type) {
    switch (type) {
      case ExpenseType.approvisionnement:
        return AppColors.accentTeal;
      case ExpenseType.chargeFixe:
        return AppColors.accentOrange;
      case ExpenseType.autre:
        return AppColors.accentPurple;
    }
  }

  String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  Widget build(BuildContext context) {
    final color = _typeColor(expense.expenseType);
    final d = expense.occurredAt;
    final dateLabel =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          SizedBox(width: 84, child: Text(dateLabel)),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(expense.category,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if ((expense.description ?? '').isNotEmpty)
                  Text(
                    expense.description!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textMuted),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                expense.expenseType.label,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: color),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              expense.hasQuantityBreakdown
                  ? '${_trim(expense.quantity!)} ${expense.unit!.label}'
                  : '—',
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              CurrencyFormatter.format(expense.amount),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              (expense.supplierName ?? '').isNotEmpty
                  ? expense.supplierName!
                  : '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.receipt_long_outlined,
              size: 40, color: AppColors.textMuted),
          const SizedBox(height: 12),
          const Text('Aucune dépense pour ce mois',
              style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Nouvelle dépense'),
          ),
        ],
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
          const Icon(Icons.cloud_off_rounded,
              size: 40, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }
}
