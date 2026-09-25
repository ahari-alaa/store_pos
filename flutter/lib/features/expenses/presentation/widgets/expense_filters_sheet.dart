import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../suppliers/presentation/providers/suppliers_provider.dart';
import '../../domain/entities/expense_unit.dart';
import '../providers/expense_categories_provider.dart';
import '../providers/expenses_provider.dart';

/// Bottom sheet for the "Filtres" button (spec §8): category, supplier,
/// unit, and amount range, all combinable. Date filtering is handled by
/// the month navigator on the main page instead of duplicated here —
/// every list/report/summary already scopes to the selected month.
class ExpenseFiltersSheet extends ConsumerStatefulWidget {
  final ExpenseFilters initial;
  final ValueChanged<ExpenseFilters> onApply;

  const ExpenseFiltersSheet({super.key, required this.initial, required this.onApply});

  @override
  ConsumerState<ExpenseFiltersSheet> createState() => _ExpenseFiltersSheetState();
}

class _ExpenseFiltersSheetState extends ConsumerState<ExpenseFiltersSheet> {
  String? _categoryId;
  String? _supplierId;
  ExpenseUnit? _unit;
  late final TextEditingController _minAmount;
  late final TextEditingController _maxAmount;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.initial.categoryId;
    _supplierId = widget.initial.supplierId;
    _unit = ExpenseUnit.fromApiValue(widget.initial.unit);
    _minAmount = TextEditingController(
      text: widget.initial.minAmount != null ? '${widget.initial.minAmount}' : '',
    );
    _maxAmount = TextEditingController(
      text: widget.initial.maxAmount != null ? '${widget.initial.maxAmount}' : '',
    );
  }

  @override
  void dispose() {
    _minAmount.dispose();
    _maxAmount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(expenseCategoriesProvider);
    final suppliersAsync = ref.watch(suppliersProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Filtres', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _categoryId = null;
                    _supplierId = null;
                    _unit = null;
                    _minAmount.clear();
                    _maxAmount.clear();
                  });
                },
                child: const Text('Réinitialiser'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          categoriesAsync.when(
            data: (categories) => DropdownButtonFormField<String>(
              value: _categoryId,
              decoration: const InputDecoration(labelText: 'Catégorie'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Toutes les catégories')),
                ...categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
              ],
              onChanged: (v) => setState(() => _categoryId = v),
            ),
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 12),
          suppliersAsync.when(
            data: (suppliers) => DropdownButtonFormField<String>(
              value: _supplierId,
              decoration: const InputDecoration(labelText: 'Fournisseur'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Tous les fournisseurs')),
                ...suppliers.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))),
              ],
              onChanged: (v) => setState(() => _supplierId = v),
            ),
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<ExpenseUnit?>(
            value: _unit,
            decoration: const InputDecoration(labelText: 'Unité'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Toutes les unités')),
              ...ExpenseUnit.values.map((u) => DropdownMenuItem(value: u, child: Text(u.label))),
            ],
            onChanged: (v) => setState(() => _unit = v),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _minAmount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Montant min (DH)'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _maxAmount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Montant max (DH)'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                widget.onApply(
                  ExpenseFilters(
                    search: widget.initial.search,
                    categoryId: _categoryId,
                    supplierId: _supplierId,
                    unit: _unit?.apiValue,
                    minAmount: double.tryParse(_minAmount.text.trim()),
                    maxAmount: double.tryParse(_maxAmount.text.trim()),
                  ),
                );
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: AppColors.primary,
              ),
              child: const Text('Appliquer les filtres'),
            ),
          ),
        ],
      ),
    );
  }
}
