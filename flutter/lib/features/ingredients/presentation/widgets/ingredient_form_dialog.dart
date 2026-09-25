import 'package:flutter/material.dart';

import '../../domain/entities/ingredient.dart';

/// "Ajouter un ingrédient" / edit dialog (Stocks des ingrédients screen).
class IngredientFormDialog extends StatefulWidget {
  final Ingredient? existing;
  final Future<void> Function(Map<String, dynamic> input) onSubmit;

  const IngredientFormDialog({super.key, this.existing, required this.onSubmit});

  @override
  State<IngredientFormDialog> createState() => _IngredientFormDialogState();
}

class _IngredientFormDialogState extends State<IngredientFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _stockController;
  late final TextEditingController _minStockController;
  late final TextEditingController _costController;
  IngredientUnit _unit = IngredientUnit.unit;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _stockController =
        TextEditingController(text: existing != null ? existing.stockQuantity.toString() : '0');
    _minStockController =
        TextEditingController(text: existing != null ? existing.minStock.toString() : '0');
    _costController =
        TextEditingController(text: existing != null ? existing.costPerUnit.toString() : '0');
    _unit = existing?.unit ?? IngredientUnit.unit;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _stockController.dispose();
    _minStockController.dispose();
    _costController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final input = <String, dynamic>{
        'name': _nameController.text.trim(),
        'unit': _unit.name,
        'min_stock': double.tryParse(_minStockController.text) ?? 0,
        'cost_per_unit': double.tryParse(_costController.text) ?? 0,
      };
      if (widget.existing == null) {
        input['stock_quantity'] = double.tryParse(_stockController.text) ?? 0;
      }
      await widget.onSubmit(input);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $error')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  isEditing ? 'Modifier l\'ingrédient' : 'Ajouter un ingrédient',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Ingrédient *'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (!isEditing) ...[
                      Expanded(
                        child: TextFormField(
                          controller: _stockController,
                          decoration: const InputDecoration(labelText: 'Quantité *'),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          // Backend is authoritative (ingredientValidators.createIngredient
                          // requires stock_quantity >= 0) — this just catches the
                          // mistake before a round trip (spec §16).
                          validator: (v) {
                            final n = double.tryParse(v ?? '');
                            if (n == null) return 'Required';
                            if (n < 0) return 'Cannot be negative';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: DropdownButtonFormField<IngredientUnit>(
                        value: _unit,
                        decoration: const InputDecoration(labelText: 'Unité *'),
                        items: IngredientUnit.values
                            .map((u) => DropdownMenuItem(value: u, child: Text(u.name)))
                            .toList(),
                        onChanged: (v) => setState(() => _unit = v ?? _unit),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _minStockController,
                        decoration: const InputDecoration(labelText: 'Stock minimum'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          final n = double.tryParse(v);
                          if (n == null || n < 0) return 'Cannot be negative';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _costController,
                        decoration: const InputDecoration(labelText: 'Coût / unité (DH)'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          final n = double.tryParse(v);
                          if (n == null || n < 0) return 'Cannot be negative';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                      child: const Text('Annuler'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Ajouter'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
