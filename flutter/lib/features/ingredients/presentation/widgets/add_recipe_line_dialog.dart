import 'package:flutter/material.dart';

import '../../domain/entities/ingredient.dart';
import '../../domain/entities/recipe.dart';

/// Units compatible with a given ingredient's storage unit — same family
/// (weight or volume) only, mirroring the backend's unitConversion.js.
List<IngredientUnit> _compatibleUnits(IngredientUnit ingredientUnit) {
  switch (ingredientUnit) {
    case IngredientUnit.g:
    case IngredientUnit.kg:
      return const [IngredientUnit.g, IngredientUnit.kg];
    case IngredientUnit.ml:
    case IngredientUnit.l:
      return const [IngredientUnit.ml, IngredientUnit.l];
    case IngredientUnit.unit:
      return const [IngredientUnit.unit];
  }
}

/// "+ Add supply" / "Edit recipe supply" modal (spec §5/§14): pick an
/// existing supply from stock, how much of it one unit of this product
/// consumes, and in which (compatible) unit. Shows the supply's current
/// stock so the manager can sanity-check the quantity while typing.
///
/// Pass [existingLine] to open in edit mode (ingredient fixed, quantity
/// and unit pre-filled and editable).
class AddRecipeLineDialog extends StatefulWidget {
  final List<Ingredient> availableIngredients;
  final RecipeLine? existingLine;
  final Future<void> Function(String ingredientId, double quantity, String unit) onSubmit;

  const AddRecipeLineDialog({
    super.key,
    required this.availableIngredients,
    required this.onSubmit,
    this.existingLine,
  });

  @override
  State<AddRecipeLineDialog> createState() => _AddRecipeLineDialogState();
}

class _AddRecipeLineDialogState extends State<AddRecipeLineDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _quantityController;
  Ingredient? _selected;
  IngredientUnit? _unit;
  bool _submitting = false;

  bool get _isEdit => widget.existingLine != null;

  @override
  void initState() {
    super.initState();
    _quantityController = TextEditingController(
      text: widget.existingLine != null ? '${widget.existingLine!.quantity}' : '',
    );
    if (widget.existingLine != null) {
      _unit = ingredientUnitFromString(widget.existingLine!.unit);
    } else if (widget.availableIngredients.isNotEmpty) {
      _selected = widget.availableIngredients.first;
      _unit = _selected!.unit;
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_isEdit && _selected == null) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final ingredientId = _isEdit ? widget.existingLine!.ingredientId : _selected!.id;
      await widget.onSubmit(ingredientId, double.parse(_quantityController.text), (_unit ?? IngredientUnit.unit).name);
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
    final storageUnit = _isEdit
        ? ingredientUnitFromString(widget.existingLine!.ingredientUnit)
        : _selected?.unit;
    final availableStock = _isEdit ? widget.existingLine!.ingredientStock : _selected?.stockQuantity;

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
                Text(_isEdit ? 'Edit recipe supply' : 'Add supply to recipe',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 20),
                if (!_isEdit && widget.availableIngredients.isEmpty)
                  const Text(
                    'No supplies yet — add one from the Stocks page first.',
                    style: TextStyle(color: Colors.grey),
                  )
                else ...[
                  if (_isEdit)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Text('Supply: ${widget.existingLine!.ingredientName}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    )
                  else
                    DropdownButtonFormField<Ingredient>(
                      value: _selected,
                      decoration: const InputDecoration(labelText: 'Supply *'),
                      items: widget.availableIngredients
                          .map((i) => DropdownMenuItem(value: i, child: Text(i.name)))
                          .toList(),
                      onChanged: (v) => setState(() {
                        _selected = v;
                        _unit = v?.unit;
                      }),
                    ),
                  if (storageUnit != null && availableStock != null) ...[
                    const SizedBox(height: 8),
                    Text('Available stock: $availableStock ${storageUnit.name}',
                        style: const TextStyle(fontSize: 12.5, color: Colors.grey)),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _quantityController,
                          decoration: const InputDecoration(labelText: 'Quantity per product *'),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          validator: (v) {
                            final n = double.tryParse(v ?? '');
                            if (n == null || n <= 0) return 'Enter a positive quantity';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<IngredientUnit>(
                          value: _unit,
                          decoration: const InputDecoration(labelText: 'Unit'),
                          items: (storageUnit == null ? const <IngredientUnit>[] : _compatibleUnits(storageUnit))
                              .map((u) => DropdownMenuItem(value: u, child: Text(u.name)))
                              .toList(),
                          onChanged: (v) => setState(() => _unit = v),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: (_submitting || (!_isEdit && widget.availableIngredients.isEmpty))
                          ? null
                          : _submit,
                      child: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(_isEdit ? 'Save' : 'Add supply'),
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
