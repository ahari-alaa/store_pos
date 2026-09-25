import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/expenses_api.dart';
import '../../domain/entities/expense_category.dart';
import 'expenses_provider.dart';

class ExpenseCategoriesNotifier extends StateNotifier<AsyncValue<List<ExpenseCategory>>> {
  final ExpensesApi _api;

  ExpenseCategoriesNotifier(this._api) : super(const AsyncValue.loading()) {
    refresh();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    try {
      final categories = await _api.fetchCategories();
      state = AsyncValue.data(categories);
    } catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  Future<void> createCategory({required String name, required String expenseType}) async {
    await _api.createCategory(name: name, expenseType: expenseType);
    await refresh();
  }

  Future<void> deactivateCategory(String id) async {
    await _api.deactivateCategory(id);
    await refresh();
  }
}

final expenseCategoriesProvider =
    StateNotifierProvider<ExpenseCategoriesNotifier, AsyncValue<List<ExpenseCategory>>>((ref) {
  return ExpenseCategoriesNotifier(ref.watch(expensesApiProvider));
});
