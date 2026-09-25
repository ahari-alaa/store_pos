import 'package:flutter/material.dart';

import '../../domain/entities/ingredient.dart';

/// Ingredient picker + quantity in one dialog — used from the merged
/// Stocks + Dépenses feed page's "Nouveau stock" button, where (unlike
/// the Stocks catalog page) there's no ingredient already selected.
class QuickRestockDialog extends StatefulWidget {
  final List<Ingredient> ingredients;
  final Future<void> Function(String ingredientId, double quantity, String? note) onSubmit;

  const QuickRestockDialog({super.key, required this.ingredients, required this.onSubmit});

  @override
  State<QuickRestockDialog> createState() => _QuickRestockDialogState();
}

class _QuickRestockDialogState extends State<QuickRestockDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _noteController = TextEditingController();
  Ingredient? _selected;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.ingredients.isNotEmpty) _selected = widget.ingredients.first;
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selected == null || !_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(
        _selected!.id,
        double.parse(_quantityController.text),
        _noteController.text.trim(),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $error')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Nouveau stock', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 20),
                if (widget.ingredients.isEmpty)
                  const Text(
                    'No ingredients yet — create one from an ingredient\'s recipe first.',
                    style: TextStyle(color: Colors.grey),
                  )
                else ...[
                  DropdownButtonFormField<Ingredient>(
                    value: _selected,
                    decoration: const InputDecoration(labelText: 'Ingrédient *'),
                    items: widget.ingredients
                        .map((i) => DropdownMenuItem(
                              value: i,
                              child: Text('${i.name} (${i.stockQuantity} ${i.unit.name})'),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _selected = v),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _quantityController,
                    decoration: InputDecoration(
                      labelText: 'Quantité reçue *',
                      suffixText: _selected?.unit.name,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      final n = double.tryParse(v ?? '');
                      if (n == null || n <= 0) return 'Enter a positive quantity';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _noteController,
                    decoration: const InputDecoration(labelText: 'Note (optionnel)'),
                  ),
                ],
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
                      onPressed: (_submitting || widget.ingredients.isEmpty) ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Ajouter au stock'),
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
