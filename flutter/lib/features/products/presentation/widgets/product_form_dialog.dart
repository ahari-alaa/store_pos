import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/product_image.dart';
import '../../../pos/domain/entities/product.dart';

/// Add/Edit form for a single product. Returns nothing directly — the
/// caller passes [onSubmit], which should call the products-manage
/// provider and let any [ApiException] bubble back up here so the dialog
/// can show it inline instead of closing on a failed save.
///
/// A photo pick is reported alongside the rest of the form (`imageBytes` +
/// `imageFilename`) rather than uploaded from here directly, because on
/// create there's no product id yet to upload against — the caller
/// creates/updates the product first, then uploads the image against
/// whichever id resulted (see products_page.dart).
class ProductFormDialog extends StatefulWidget {
  final Product? existing;
  final Future<void> Function(
    Map<String, dynamic> input, {
    Uint8List? imageBytes,
    String? imageFilename,
    bool removeImage,
  }) onSubmit;

  const ProductFormDialog({super.key, this.existing, required this.onSubmit});

  @override
  State<ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _category;
  late final TextEditingController _barcode;
  late final TextEditingController _sku;
  late final TextEditingController _price;
  late final TextEditingController _cost;
  late final TextEditingController _taxRatePercent;
  late final TextEditingController _stock;
  bool _isActive = true;
  bool _saving = false;
  String? _error;

  Uint8List? _pickedImageBytes;
  String? _pickedImageFilename;
  bool _removeExistingImage = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _name = TextEditingController(text: p?.name ?? '');
    _category = TextEditingController(text: p?.category ?? '');
    _barcode = TextEditingController(text: p?.barcode ?? '');
    _sku = TextEditingController(text: p?.sku ?? '');
    _price = TextEditingController(text: p != null ? _trimZeros(p.price) : '');
    _cost = TextEditingController(text: p != null ? _trimZeros(p.cost) : '0');
    _taxRatePercent =
        TextEditingController(text: p != null ? _trimZeros(p.taxRate * 100) : '0');
    _stock = TextEditingController(text: p != null ? p.stockQuantity.toString() : '0');
    _isActive = p?.isActive ?? true;
  }

  String _trimZeros(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toString();
  }

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _barcode.dispose();
    _sku.dispose();
    _price.dispose();
    _cost.dispose();
    _taxRatePercent.dispose();
    _stock.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true, // ensures bytes are populated on every platform, not just web
    );
    final file = result?.files.single;
    if (file?.bytes == null) return;
    setState(() {
      _pickedImageBytes = file!.bytes;
      _pickedImageFilename = file.name;
      _removeExistingImage = false;
    });
  }

  void _clearImage() {
    setState(() {
      _pickedImageBytes = null;
      _pickedImageFilename = null;
      _removeExistingImage = widget.existing?.imageUrl != null;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final input = <String, dynamic>{
      'name': _name.text.trim(),
      'category': _category.text.trim().isEmpty ? null : _category.text.trim(),
      'barcode': _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
      'sku': _sku.text.trim().isEmpty ? null : _sku.text.trim(),
      'price': double.parse(_price.text.trim()),
      'cost': double.tryParse(_cost.text.trim()) ?? 0,
      'tax_rate': (double.tryParse(_taxRatePercent.text.trim()) ?? 0) / 100,
      if (!_isEdit) 'stock_quantity': int.tryParse(_stock.text.trim()) ?? 0,
      if (_isEdit) 'is_active': _isActive,
    };

    try {
      await widget.onSubmit(
        input,
        imageBytes: _pickedImageBytes,
        imageFilename: _pickedImageFilename,
        removeImage: _removeExistingImage,
      );
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
    final hasExistingImage = widget.existing?.fullImageUrl != null && !_removeExistingImage;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
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
                    _isEdit ? 'Edit product' : 'Add product',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: _pickImage,
                          child: Container(
                            width: 96,
                            height: 96,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: _pickedImageBytes != null
                                ? Image.memory(_pickedImageBytes!, fit: BoxFit.cover)
                                : hasExistingImage
                                    ? ProductImage(
                                        imageUrl: widget.existing!.fullImageUrl,
                                        placeholderIcon: Icons.image_not_supported_outlined,
                                      )
                                    : const Icon(
                                        Icons.add_a_photo_outlined,
                                        color: AppColors.textMuted,
                                        size: 28,
                                      ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: _pickImage,
                              child: Text(hasExistingImage || _pickedImageBytes != null
                                  ? 'Change photo'
                                  : 'Add photo'),
                            ),
                            if (hasExistingImage || _pickedImageBytes != null)
                              TextButton(
                                onPressed: _clearImage,
                                child: const Text('Remove'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _category,
                    decoration: const InputDecoration(labelText: 'Category (optional)'),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _barcode,
                          decoration: const InputDecoration(labelText: 'Barcode'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _sku,
                          decoration: const InputDecoration(labelText: 'SKU'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _price,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Price'),
                          validator: (v) {
                            final parsed = double.tryParse((v ?? '').trim());
                            if (parsed == null || parsed < 0) return 'Enter a valid price';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _cost,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Cost'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _taxRatePercent,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Tax rate (%)'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _stock,
                          enabled: !_isEdit,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Initial stock',
                            helperText: _isEdit ? 'Use Restock to change stock' : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_isEdit) ...[
                    const SizedBox(height: 8),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Active'),
                      subtitle: const Text('Inactive products are hidden from the POS grid'),
                      value: _isActive,
                      onChanged: (v) => setState(() => _isActive = v),
                    ),
                  ],
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
                        child: const Text('Cancel'),
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
                            : Text(_isEdit ? 'Save changes' : 'Add product'),
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
}
