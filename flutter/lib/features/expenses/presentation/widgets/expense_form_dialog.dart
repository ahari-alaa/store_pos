import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/local_date_range.dart';
import '../../../ingredients/presentation/providers/ingredients_provider.dart';
import '../../../pos/presentation/providers/products_manage_provider.dart';
import '../../../suppliers/presentation/providers/suppliers_provider.dart';
import '../../domain/entities/expense.dart';
import '../../domain/entities/expense_category.dart';
import '../../domain/entities/expense_type.dart';
import '../../domain/entities/expense_unit.dart';
import '../providers/expense_categories_provider.dart';

/// A file picked for a receipt, kept as bytes so this works the same way
/// on desktop and web (mirrors ProductFormDialog's photo picker).
class PickedReceipt {
  final List<int> bytes;
  final String filename;
  const PickedReceipt({required this.bytes, required this.filename});
}

/// Add/Edit form for a single expense (spec §3/§4/§10). Returns nothing
/// directly — [onSubmit] should call the expenses provider and let any
/// [ApiException] bubble back up so the dialog can show it inline instead
/// of closing on a failed save. A picked receipt is reported alongside
/// the rest of the form for the same reason ProductFormDialog reports a
/// picked photo separately: on create there's no expense id yet to
/// upload a receipt against.
class ExpenseFormDialog extends ConsumerStatefulWidget {
  final Expense? existing;
  final ExpenseType? initialType;
  final Future<void> Function(
    Map<String, dynamic> input, {
    PickedReceipt? receipt,
  }) onSubmit;

  const ExpenseFormDialog({
    super.key,
    this.existing,
    this.initialType,
    required this.onSubmit,
  });

  @override
  ConsumerState<ExpenseFormDialog> createState() => _ExpenseFormDialogState();
}

class _ExpenseFormDialogState extends ConsumerState<ExpenseFormDialog> {
  static const _uuid = Uuid();

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _description;
  late final TextEditingController _quantity;
  late final TextEditingController _unitPrice;
  late final TextEditingController _amount;
  late final TextEditingController _supplierName;
  late final TextEditingController _notes;
  late final TextEditingController _recurringDay;
  late final TextEditingController _newCategoryName;

  late ExpenseType _type;
  String? _categoryId;
  bool _hasQuantity = true;
  ExpenseUnit _unit = ExpenseUnit.kg;
  String? _supplierId;
  late DateTime _date;
  bool _affectsInventory = false;
  String? _productId;
  /// Which stock a purchase restocks: a finished product, or a raw
  /// supply/ingredient — mutually exclusive (spec §3).
  bool _isIngredientTarget = false;
  String? _ingredientId;
  bool _isRecurring = false;
  PickedReceipt? _pickedReceipt;
  bool _addingCategory = false;

  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _type = e?.expenseType ?? widget.initialType ?? ExpenseType.approvisionnement;
    _categoryId = e?.categoryId;
    _description = TextEditingController(text: e?.description ?? '');
    _hasQuantity = e != null ? e.hasQuantityBreakdown : _type == ExpenseType.approvisionnement;
    _quantity = TextEditingController(text: e?.quantity != null ? _trimZeros(e!.quantity!) : '');
    _unit = e?.unit ?? ExpenseUnit.kg;
    _unitPrice =
        TextEditingController(text: e?.unitPrice != null ? _trimZeros(e!.unitPrice!) : '');
    _amount = TextEditingController(
      text: e != null && !e.hasQuantityBreakdown ? _trimZeros(e.amount) : '',
    );
    _supplierId = e?.supplierId;
    _supplierName = TextEditingController(text: e?.supplierName ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _date = e?.occurredAt ?? DateTime.now();
    _affectsInventory = e?.affectsInventory ?? false;
    _productId = e?.productId;
    _ingredientId = e?.ingredientId;
    _isIngredientTarget = e?.ingredientId != null;
    _isRecurring = e?.isRecurring ?? false;
    _recurringDay =
        TextEditingController(text: e?.recurringDay != null ? '${e!.recurringDay}' : '');
    _newCategoryName = TextEditingController();

    // The computed total should refresh live as the user types.
    _quantity.addListener(_recompute);
    _unitPrice.addListener(_recompute);
  }

  String _trimZeros(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toString();
  }

  void _recompute() => setState(() {});

  double? get _computedTotal {
    final q = double.tryParse(_quantity.text.trim());
    final p = double.tryParse(_unitPrice.text.trim());
    if (q == null || p == null) return null;
    return double.parse((q * p).toStringAsFixed(2));
  }

  @override
  void dispose() {
    _description.dispose();
    _quantity.dispose();
    _unitPrice.dispose();
    _amount.dispose();
    _supplierName.dispose();
    _notes.dispose();
    _recurringDay.dispose();
    _newCategoryName.dispose();
    super.dispose();
  }

  Future<void> _pickReceipt() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      withData: true,
    );
    final file = result?.files.single;
    if (file?.bytes == null) return;
    setState(() {
      _pickedReceipt = PickedReceipt(bytes: file!.bytes!, filename: file.name);
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      _date = DateTime(picked.year, picked.month, picked.day, _date.hour, _date.minute);
    });
  }

  Future<void> _addCategoryQuickly() async {
    final name = _newCategoryName.text.trim();
    if (name.isEmpty) return;
    setState(() => _addingCategory = true);
    try {
      await ref
          .read(expenseCategoriesProvider.notifier)
          .createCategory(name: name, expenseType: _type.apiValue);
      _newCategoryName.clear();
      final categories = ref.read(expenseCategoriesProvider).value ?? const [];
      final created = categories.where((c) => c.name == name && c.expenseType == _type);
      if (created.isNotEmpty) {
        setState(() => _categoryId = created.first.id);
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _addingCategory = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_hasQuantity && double.tryParse(_unitPrice.text.trim()) == null) {
      setState(() => _error = 'Enter a valid unit price');
      return;
    }
    if (_affectsInventory && (_isIngredientTarget ? _ingredientId : _productId) == null) {
      setState(() => _error = _isIngredientTarget
          ? 'Select a supply to link this purchase to stock'
          : 'Select a product to link this purchase to inventory');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final input = <String, dynamic>{
      if (!_isEdit) 'client_operation_id': _uuid.v4(),
      if (_categoryId != null) 'category_id': _categoryId,
      if (_categoryId == null) 'expense_type': _type.apiValue,
      'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
      if (_hasQuantity) ...{
        'quantity': double.parse(_quantity.text.trim()),
        'unit': _unit.apiValue,
        'unit_price': double.parse(_unitPrice.text.trim()),
      } else
        'amount': double.parse(_amount.text.trim()),
      'supplier_id': _supplierId,
      'supplier_name': _supplierName.text.trim().isEmpty ? null : _supplierName.text.trim(),
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      'affects_inventory': _affectsInventory,
      'product_id': _affectsInventory && !_isIngredientTarget ? _productId : null,
      'ingredient_id': _affectsInventory && _isIngredientTarget ? _ingredientId : null,
      'is_recurring': _isRecurring,
      'recurring_day': _isRecurring && _recurringDay.text.trim().isNotEmpty
          ? int.tryParse(_recurringDay.text.trim())
          : null,
      'occurred_at': LocalDateRange.iso(_date),
    };

    try {
      await widget.onSubmit(input, receipt: _pickedReceipt);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(expenseCategoriesProvider);
    final suppliersAsync = ref.watch(suppliersProvider);
    final productsAsync = ref.watch(productsManageProvider);
    final ingredientsAsync = ref.watch(ingredientsProvider);

    final allCategories = categoriesAsync.value ?? const <ExpenseCategory>[];
    final categoriesForType = allCategories.where((c) => c.expenseType == _type).toList();
    // Keep the selected category consistent with the current type tab —
    // but only once categories have actually loaded, so the loading
    // flicker on first build never wipes out an existing expense's
    // category before the dropdown has anything to match it against.
    if (categoriesAsync.hasValue &&
        _categoryId != null &&
        !categoriesForType.any((c) => c.id == _categoryId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _categoryId = null);
      });
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _isEdit ? 'Modifier la dépense' : 'Ajouter une dépense',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 20),

                  // --- Type ---------------------------------------------------
                  Text('Type', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  SegmentedButton<ExpenseType>(
                    segments: ExpenseType.values
                        .map((t) => ButtonSegment(value: t, label: Text(t.label)))
                        .toList(),
                    selected: {_type},
                    onSelectionChanged: (selection) {
                      setState(() {
                        _type = selection.first;
                        _categoryId = null;
                        // Supplies mode makes most sense for Approvisionnement
                        // by default, but stays user-adjustable either way.
                        _hasQuantity = _type == ExpenseType.approvisionnement;
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  // --- Category ------------------------------------------------
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _categoryId,
                          decoration: const InputDecoration(labelText: 'Catégorie *'),
                          items: categoriesForType
                              .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                              .toList(),
                          onChanged: (v) => setState(() => _categoryId = v),
                          validator: (v) => v == null ? 'Catégorie requise' : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Nouvelle catégorie',
                        onPressed: () => _showAddCategorySheet(context),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // --- Description ---------------------------------------------
                  TextFormField(
                    controller: _description,
                    decoration: const InputDecoration(labelText: 'Description'),
                  ),
                  const SizedBox(height: 8),

                  // --- Supplies vs fixed amount ----------------------------------
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Fourniture (quantité × prix unitaire)'),
                    subtitle: const Text('Désactivez pour une charge à montant fixe'),
                    value: _hasQuantity,
                    onChanged: (v) => setState(() => _hasQuantity = v),
                  ),
                  if (_hasQuantity) ...[
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _quantity,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Quantité *'),
                            validator: (v) {
                              final parsed = double.tryParse((v ?? '').trim());
                              if (parsed == null || parsed <= 0) return 'Quantité invalide';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<ExpenseUnit>(
                            value: _unit,
                            decoration: const InputDecoration(labelText: 'Unité'),
                            items: ExpenseUnit.values
                                .map((u) => DropdownMenuItem(value: u, child: Text(u.label)))
                                .toList(),
                            onChanged: (v) => setState(() => _unit = v ?? _unit),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _unitPrice,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Prix unitaire (DH) *'),
                      validator: (v) {
                        final parsed = double.tryParse((v ?? '').trim());
                        if (parsed == null || parsed < 0) return 'Prix invalide';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.primarySurface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.primaryLight),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Montant total'),
                          Text(
                            _computedTotal != null
                                ? '${_computedTotal!.toStringAsFixed(2)} DH'
                                : '—',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    TextFormField(
                      controller: _amount,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Montant (DH) *'),
                      validator: (v) {
                        final parsed = double.tryParse((v ?? '').trim());
                        if (parsed == null || parsed <= 0) return 'Montant invalide';
                        return null;
                      },
                    ),
                  ],
                  const SizedBox(height: 14),

                  // --- Supplier --------------------------------------------------
                  suppliersAsync.when(
                    data: (suppliers) => DropdownButtonFormField<String>(
                      value: _supplierId,
                      decoration: const InputDecoration(labelText: 'Fournisseur'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('— Aucun / autre —')),
                        ...suppliers.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))),
                      ],
                      onChanged: (v) {
                        setState(() {
                          _supplierId = v;
                          if (v != null) {
                            final match = suppliers.where((s) => s.id == v);
                            if (match.isNotEmpty) _supplierName.text = match.first.name;
                          }
                        });
                      },
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _supplierName,
                    decoration: const InputDecoration(
                      labelText: 'Nom du fournisseur (si non listé)',
                    ),
                  ),
                  const SizedBox(height: 14),

                  // --- Date --------------------------------------------------
                  InkWell(
                    onTap: _pickDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Date *'),
                      child: Text(
                        '${_date.day.toString().padLeft(2, '0')}/'
                        '${_date.month.toString().padLeft(2, '0')}/${_date.year}',
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // --- Notes --------------------------------------------------
                  TextFormField(
                    controller: _notes,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Notes'),
                  ),
                  const SizedBox(height: 8),

                  // --- Inventory linkage (only meaningful for supplies) -------
                  if (_hasQuantity) ...[
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Affecte le stock'),
                      subtitle: const Text(
                        'Ajoute la quantité au stock du produit ou de la matière première liée',
                      ),
                      value: _affectsInventory,
                      onChanged: (v) => setState(() => _affectsInventory = v),
                    ),
                    if (_affectsInventory) ...[
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('Produit fini')),
                          ButtonSegment(value: true, label: Text('Matière première (supply)')),
                        ],
                        selected: {_isIngredientTarget},
                        onSelectionChanged: (s) => setState(() => _isIngredientTarget = s.first),
                      ),
                      const SizedBox(height: 10),
                      if (!_isIngredientTarget)
                        productsAsync.when(
                          data: (products) => DropdownButtonFormField<String>(
                            value: _productId,
                            decoration: const InputDecoration(labelText: 'Produit lié *'),
                            items: products
                                .where((p) => p.isActive)
                                .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
                                .toList(),
                            onChanged: (v) => setState(() => _productId = v),
                            validator: (v) {
                              if (_affectsInventory && !_isIngredientTarget && v == null) {
                                return 'Produit requis';
                              }
                              return null;
                            },
                          ),
                          loading: () => const LinearProgressIndicator(),
                          error: (_, __) => const Text(
                            'Impossible de charger les produits',
                            style: TextStyle(color: AppColors.danger),
                          ),
                        )
                      else
                        ingredientsAsync.when(
                          data: (ingredients) => DropdownButtonFormField<String>(
                            value: _ingredientId,
                            decoration: const InputDecoration(labelText: 'Supply liée *'),
                            items: ingredients
                                .where((i) => i.isActive)
                                .map((i) => DropdownMenuItem(
                                    value: i.id, child: Text('${i.name} (${i.unit.name})')))
                                .toList(),
                            onChanged: (v) => setState(() => _ingredientId = v),
                            validator: (v) {
                              if (_affectsInventory && _isIngredientTarget && v == null) {
                                return 'Supply requise';
                              }
                              return null;
                            },
                          ),
                          loading: () => const LinearProgressIndicator(),
                          error: (_, __) => const Text(
                            'Impossible de charger les matières premières',
                            style: TextStyle(color: AppColors.danger),
                          ),
                        ),
                    ],
                    const SizedBox(height: 8),
                  ],

                  // --- Recurring -----------------------------------------------
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Dépense récurrente (mensuelle)'),
                    subtitle: const Text(
                      'Ex. Électricité, Internet — sera suggérée chaque mois',
                    ),
                    value: _isRecurring,
                    onChanged: (v) => setState(() => _isRecurring = v),
                  ),
                  if (_isRecurring)
                    TextFormField(
                      controller: _recurringDay,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Jour habituel du mois (optionnel)',
                      ),
                    ),
                  const SizedBox(height: 8),

                  // --- Receipt ----------------------------------------------
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _pickReceipt,
                        icon: const Icon(Icons.attach_file),
                        label: Text(
                          _pickedReceipt != null
                              ? _pickedReceipt!.filename
                              : (widget.existing?.receiptUrl != null
                                  ? 'Remplacer le reçu'
                                  : 'Joindre un reçu'),
                        ),
                      ),
                      if (_pickedReceipt != null)
                        IconButton(
                          onPressed: () => setState(() => _pickedReceipt = null),
                          icon: const Icon(Icons.close),
                        ),
                    ],
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: AppColors.danger)),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _saving ? null : () => Navigator.of(context).pop(),
                        child: const Text('Annuler'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _saving ? null : _submit,
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(_isEdit ? 'Enregistrer' : 'Enregistrer'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showAddCategorySheet(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nouvelle catégorie'),
        content: TextField(
          controller: _newCategoryName,
          autofocus: true,
          decoration: InputDecoration(labelText: 'Nom (${_type.label})'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: _addingCategory
                ? null
                : () async {
                    await _addCategoryQuickly();
                    if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                  },
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
  }
}
