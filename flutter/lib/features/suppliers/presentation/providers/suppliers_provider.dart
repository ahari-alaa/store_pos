import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/providers.dart';
import '../../data/datasources/suppliers_api.dart';
import '../../domain/entities/supplier.dart';

final suppliersApiProvider = Provider<SuppliersApi>((ref) {
  return SuppliersApi(ref.watch(apiClientProvider));
});

class SuppliersNotifier extends StateNotifier<AsyncValue<List<Supplier>>> {
  final SuppliersApi _api;

  SuppliersNotifier(this._api) : super(const AsyncValue.loading()) {
    refresh();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    try {
      final suppliers = await _api.fetchAll();
      state = AsyncValue.data(suppliers);
    } catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  Future<void> createSupplier(Map<String, dynamic> input) async {
    await _api.create(input);
    await refresh();
  }

  Future<void> updateSupplier(String id, Map<String, dynamic> input) async {
    await _api.update(id, input);
    await refresh();
  }

  Future<void> deactivateSupplier(String id) async {
    await _api.delete(id);
    await refresh();
  }
}

final suppliersProvider =
    StateNotifierProvider<SuppliersNotifier, AsyncValue<List<Supplier>>>((ref) {
  return SuppliersNotifier(ref.watch(suppliersApiProvider));
});
