import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/providers.dart';
import '../../../../core/utils/local_date_range.dart';
import '../../data/datasources/expenses_api.dart';
import '../../domain/entities/expense.dart';
import '../../domain/entities/expense_monthly_report.dart';
import '../../domain/entities/expense_type.dart';

final expensesApiProvider = Provider<ExpensesApi>((ref) {
  return ExpensesApi(ref.watch(apiClientProvider));
});

/// Search/filter combination for the expense table (spec §8). Kept
/// separate from the selected month/tab since those two drive which
/// "page" the user is on, while these are refinements within it.
class ExpenseFilters {
  final String search;
  final String? categoryId;
  final String? supplierId;
  final String? unit;
  final double? minAmount;
  final double? maxAmount;

  const ExpenseFilters({
    this.search = '',
    this.categoryId,
    this.supplierId,
    this.unit,
    this.minAmount,
    this.maxAmount,
  });

  bool get isActive =>
      search.trim().isNotEmpty ||
      categoryId != null ||
      supplierId != null ||
      unit != null ||
      minAmount != null ||
      maxAmount != null;

  ExpenseFilters copyWith({
    String? search,
    String? categoryId,
    bool clearCategoryId = false,
    String? supplierId,
    bool clearSupplierId = false,
    String? unit,
    bool clearUnit = false,
    double? minAmount,
    bool clearMinAmount = false,
    double? maxAmount,
    bool clearMaxAmount = false,
  }) {
    return ExpenseFilters(
      search: search ?? this.search,
      categoryId: clearCategoryId ? null : (categoryId ?? this.categoryId),
      supplierId: clearSupplierId ? null : (supplierId ?? this.supplierId),
      unit: clearUnit ? null : (unit ?? this.unit),
      minAmount: clearMinAmount ? null : (minAmount ?? this.minAmount),
      maxAmount: clearMaxAmount ? null : (maxAmount ?? this.maxAmount),
    );
  }
}

/// Everything the Expenses page (spec §6) needs to render: the selected
/// month, the active type tab, filters, and the three independently-
/// loading slices of data (list / monthly report / recurring
/// suggestions) that make it up.
class ExpensesState {
  final DateTime month;
  final ExpenseType? tab; // null = "Toutes"
  final ExpenseFilters filters;
  final AsyncValue<List<Expense>> expenses;
  final AsyncValue<ExpenseMonthlyReport> report;
  final AsyncValue<List<Expense>> recurringSuggestions;

  const ExpensesState({
    required this.month,
    required this.tab,
    required this.filters,
    required this.expenses,
    required this.report,
    required this.recurringSuggestions,
  });

  factory ExpensesState.initial() => ExpensesState(
        month: DateTime(DateTime.now().year, DateTime.now().month, 1),
        tab: null,
        filters: const ExpenseFilters(),
        expenses: const AsyncValue.loading(),
        report: const AsyncValue.loading(),
        recurringSuggestions: const AsyncValue.data([]),
      );

  ExpensesState copyWith({
    DateTime? month,
    ExpenseType? tab,
    bool clearTab = false,
    ExpenseFilters? filters,
    AsyncValue<List<Expense>>? expenses,
    AsyncValue<ExpenseMonthlyReport>? report,
    AsyncValue<List<Expense>>? recurringSuggestions,
  }) {
    return ExpensesState(
      month: month ?? this.month,
      tab: clearTab ? null : (tab ?? this.tab),
      filters: filters ?? this.filters,
      expenses: expenses ?? this.expenses,
      report: report ?? this.report,
      recurringSuggestions: recurringSuggestions ?? this.recurringSuggestions,
    );
  }
}

class ExpensesNotifier extends StateNotifier<ExpensesState> {
  final ExpensesApi _api;

  ExpensesNotifier(this._api) : super(ExpensesState.initial()) {
    loadAll();
  }

  Future<void> loadAll() async {
    await Future.wait([_loadExpenses(), _loadReport(), _loadRecurringSuggestions()]);
  }

  Future<void> _loadExpenses() async {
    state = state.copyWith(expenses: const AsyncValue.loading());
    try {
      final page = await _api.list(
        monthStart: state.month,
        from: LocalDateRange.monthStart(state.month),
        to: LocalDateRange.monthEnd(state.month),
        expenseType: state.tab?.apiValue,
        categoryId: state.filters.categoryId,
        supplierId: state.filters.supplierId,
        unit: state.filters.unit,
        search: state.filters.search,
        minAmount: state.filters.minAmount,
        maxAmount: state.filters.maxAmount,
        pageSize: 500,
      );
      state = state.copyWith(expenses: AsyncValue.data(page.items));
    } catch (error, stack) {
      state = state.copyWith(expenses: AsyncValue.error(error, stack));
    }
  }

  Future<void> _loadReport() async {
    state = state.copyWith(report: const AsyncValue.loading());
    try {
      final report = await _api.monthlyReport(state.month.year, state.month.month);
      state = state.copyWith(report: AsyncValue.data(report));
    } catch (error, stack) {
      state = state.copyWith(report: AsyncValue.error(error, stack));
    }
  }

  Future<void> _loadRecurringSuggestions() async {
    try {
      final suggestions =
          await _api.recurringSuggestions(state.month.year, state.month.month);
      state = state.copyWith(recurringSuggestions: AsyncValue.data(suggestions));
    } catch (_) {
      // Non-critical: the "suggested this month" banner just won't show.
      state = state.copyWith(recurringSuggestions: const AsyncValue.data([]));
    }
  }

  void goToPreviousMonth() {
    final m = state.month;
    state = state.copyWith(month: DateTime(m.year, m.month - 1, 1));
    loadAll();
  }

  void goToNextMonth() {
    final m = state.month;
    state = state.copyWith(month: DateTime(m.year, m.month + 1, 1));
    loadAll();
  }

  void setMonth(DateTime month) {
    state = state.copyWith(month: DateTime(month.year, month.month, 1));
    loadAll();
  }

  void setTab(ExpenseType? tab) {
    state = state.copyWith(tab: tab, clearTab: tab == null);
    _loadExpenses();
  }

  void setFilters(ExpenseFilters filters) {
    state = state.copyWith(filters: filters);
    _loadExpenses();
  }

  Future<Expense> createExpense(Map<String, dynamic> input) async {
    final expense = await _api.create(input);
    await loadAll();
    return expense;
  }

  Future<Expense> updateExpense(String id, Map<String, dynamic> input) async {
    final expense = await _api.update(id, input);
    await loadAll();
    return expense;
  }

  Future<void> deleteExpense(String id) async {
    await _api.delete(id);
    await loadAll();
  }

  Future<Expense> uploadReceipt(
    String expenseId, {
    required List<int> bytes,
    required String filename,
  }) async {
    final expense = await _api.uploadReceipt(expenseId, bytes: bytes, filename: filename);
    await loadAll();
    return expense;
  }

  Future<Expense> removeReceipt(String expenseId) async {
    final expense = await _api.removeReceipt(expenseId);
    await loadAll();
    return expense;
  }
}

final expensesProvider = StateNotifierProvider<ExpensesNotifier, ExpensesState>((ref) {
  return ExpensesNotifier(ref.watch(expensesApiProvider));
});
