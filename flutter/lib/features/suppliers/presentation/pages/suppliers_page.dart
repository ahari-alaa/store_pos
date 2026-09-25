import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/restricted_page.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/entities/supplier.dart';
import '../providers/suppliers_provider.dart';
import '../widgets/supplier_form_dialog.dart';

class SuppliersPage extends ConsumerStatefulWidget {
  const SuppliersPage({super.key});

  @override
  ConsumerState<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends ConsumerState<SuppliersPage> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    if (user == null || !user.canManageSuppliers) {
      return const RestrictedPage(
        message: 'Only admins and managers can manage suppliers.',
      );
    }

    final suppliersAsync = ref.watch(suppliersProvider);

    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded, size: 20),
                    hintText: 'Search suppliers by name, phone, or email...',
                  ),
                  onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => _openForm(context),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Add supplier'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: suppliersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _ErrorState(
                message: error is ApiException ? error.message : 'Could not load suppliers.',
                onRetry: () => ref.read(suppliersProvider.notifier).refresh(),
              ),
              data: (suppliers) {
                final filtered = _search.isEmpty
                    ? suppliers
                    : suppliers.where((s) {
                        return s.name.toLowerCase().contains(_search) ||
                            (s.phone?.toLowerCase().contains(_search) ?? false) ||
                            (s.email?.toLowerCase().contains(_search) ?? false);
                      }).toList();

                if (filtered.isEmpty) {
                  return const Center(
                    child: Text('No suppliers found', style: TextStyle(color: AppColors.textSecondary)),
                  );
                }

                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final supplier = filtered[index];
                      return _SupplierTile(
                        supplier: supplier,
                        onEdit: () => _openForm(context, existing: supplier),
                        onDeactivate: () => _confirmDeactivate(context, supplier),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openForm(BuildContext context, {Supplier? existing}) {
    showDialog(
      context: context,
      builder: (_) => SupplierFormDialog(
        existing: existing,
        onSubmit: (input) async {
          final notifier = ref.read(suppliersProvider.notifier);
          if (existing == null) {
            await notifier.createSupplier(input);
          } else {
            await notifier.updateSupplier(existing.id, input);
          }
        },
      ),
    );
  }

  Future<void> _confirmDeactivate(BuildContext context, Supplier supplier) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Deactivate supplier?'),
        content: Text('"${supplier.name}" will be marked inactive.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(suppliersProvider.notifier).deactivateSupplier(supplier.id);
    }
  }
}

class _SupplierTile extends StatelessWidget {
  final Supplier supplier;
  final VoidCallback onEdit;
  final VoidCallback onDeactivate;

  const _SupplierTile({required this.supplier, required this.onEdit, required this.onDeactivate});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: CircleAvatar(
        backgroundColor: AppColors.primarySurface,
        child: Icon(Icons.local_shipping_outlined, color: AppColors.primary, size: 20),
      ),
      title: Text(supplier.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        [
          if (supplier.contactName != null) supplier.contactName!,
          if (supplier.phone != null) supplier.phone!,
          if (supplier.email != null) supplier.email!,
        ].join(' • '),
        style: const TextStyle(color: AppColors.textSecondary),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: supplier.isActive ? AppColors.primarySurface : AppColors.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              supplier.isActive ? 'Active' : 'Inactive',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: supplier.isActive ? AppColors.primary : AppColors.textMuted,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: onEdit,
          ),
          if (supplier.isActive)
            IconButton(
              tooltip: 'Deactivate',
              icon: const Icon(Icons.block_outlined, size: 20, color: AppColors.danger),
              onPressed: onDeactivate,
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
          const Icon(Icons.cloud_off_rounded, size: 40, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
