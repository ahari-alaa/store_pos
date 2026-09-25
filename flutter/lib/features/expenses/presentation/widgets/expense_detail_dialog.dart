import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../domain/entities/expense.dart';
import '../../domain/entities/expense_type.dart';
import '../providers/expenses_provider.dart';
import 'expense_form_dialog.dart';

/// Detail panel for a single expense (spec §9): full breakdown, receipt
/// preview, and Modifier / Supprimer / Voir reçu actions.
class ExpenseDetailDialog extends ConsumerStatefulWidget {
  final Expense expense;
  final bool canEdit;
  final bool canDelete;

  const ExpenseDetailDialog({
    super.key,
    required this.expense,
    required this.canEdit,
    required this.canDelete,
  });

  @override
  ConsumerState<ExpenseDetailDialog> createState() => _ExpenseDetailDialogState();
}

class _ExpenseDetailDialogState extends ConsumerState<ExpenseDetailDialog> {
  bool _busy = false;
  String? _error;

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

  String _fmtDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} à ${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _openReceipt() async {
    final expense = widget.expense;
    final url = expense.fullReceiptUrl;
    if (url == null) return;
    if (!expense.receiptIsPdf) {
      // Images are already shown inline — nothing extra to "open".
      return;
    }
    setState(() => _busy = true);
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        await Printing.layoutPdf(onLayout: (_) async => response.bodyBytes);
      } else {
        setState(() => _error = 'Impossible de charger le reçu.');
      }
    } catch (_) {
      setState(() => _error = 'Impossible de charger le reçu.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    final notifier = ref.read(expensesProvider.notifier);
    await showDialog(
      context: context,
      builder: (_) => ExpenseFormDialog(
        existing: widget.expense,
        onSubmit: (input, {receipt}) async {
          final updated = await notifier.updateExpense(widget.expense.id, input);
          if (receipt != null) {
            await notifier.uploadReceipt(updated.id,
                bytes: receipt.bytes, filename: receipt.filename);
          }
        },
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer la dépense'),
        content:
            const Text('Êtes-vous sûr de vouloir supprimer cette dépense ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(expensesProvider.notifier).deleteExpense(widget.expense.id);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.expense;
    final color = _typeColor(e.expenseType);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.category,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Container(
                  margin: const EdgeInsets.only(top: 4, bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    e.expenseType.label,
                    style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ),
                Text(
                  _fmtDate(e.occurredAt),
                  style: const TextStyle(color: AppColors.textMuted),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Montant', style: TextStyle(color: AppColors.textSecondary)),
                      Text(
                        CurrencyFormatter.format(e.amount),
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _infoRow('Description', e.description?.isNotEmpty == true ? e.description! : '—'),
                if (e.hasQuantityBreakdown) ...[
                  _infoRow('Quantité', '${_trim(e.quantity!)} ${e.unit!.label}'),
                  _infoRow('Prix unitaire', CurrencyFormatter.format(e.unitPrice!)),
                ],
                if ((e.supplierName ?? '').isNotEmpty) _infoRow('Fournisseur', e.supplierName!),
                if (e.productName != null) _infoRow('Produit lié (stock)', e.productName!),
                if (e.ingredientName != null) _infoRow('Supply liée (stock)', e.ingredientName!),
                if ((e.notes ?? '').isNotEmpty) _infoRow('Notes', e.notes!),
                if (e.isRecurring)
                  _infoRow(
                    'Récurrence',
                    e.recurringDay != null
                        ? 'Mensuelle, vers le ${e.recurringDay}'
                        : 'Mensuelle',
                  ),
                if (e.fullReceiptUrl != null) ...[
                  const SizedBox(height: 8),
                  const Text('Reçu', style: TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  if (!e.receiptIsPdf)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        e.fullReceiptUrl!,
                        height: 160,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Text('Image indisponible'),
                      ),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _openReceipt,
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Voir reçu (PDF)'),
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
                    if (widget.canDelete)
                      TextButton(
                        onPressed: _busy ? null : _delete,
                        style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                        child: const Text('Supprimer'),
                      ),
                    if (widget.canEdit) ...[
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _busy ? null : _edit,
                        child: const Text('Modifier'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _trim(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 2),
          Text(value),
        ],
      ),
    );
  }
}
