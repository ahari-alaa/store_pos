import '../../../../core/network/api_client.dart';
import '../../domain/entities/expense.dart';
import '../../domain/entities/expense_category.dart';
import '../../domain/entities/expense_monthly_report.dart';
import '../../domain/entities/feed_entry.dart';

/// A page of expenses (spec §8: backend filtering/pagination, never load
/// the entire table at once).
class ExpensePage {
  final List<Expense> items;
  final int total;
  final int page;
  final int pageSize;

  const ExpensePage({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  bool get hasMore => items.isNotEmpty && page * pageSize < total;
}

/// Talks to `/api/expenses` (see
/// store_pos_backend/src/routes/expenseRoutes.js).
class ExpensesApi {
  final ApiClient _client;

  const ExpensesApi(this._client);

  Future<ExpensePage> list({
    required DateTime monthStart,
    required String from,
    required String to,
    String? expenseType,
    String? categoryId,
    String? supplierId,
    String? unit,
    String? search,
    double? minAmount,
    double? maxAmount,
    int page = 1,
    int pageSize = 100,
  }) async {
    final data = await _client.get('/expenses', query: {
      'from': from,
      'to': to,
      'page': page,
      'page_size': pageSize,
      if (expenseType != null) 'expense_type': expenseType,
      if (categoryId != null) 'category_id': categoryId,
      if (supplierId != null) 'supplier_id': supplierId,
      if (unit != null) 'unit': unit,
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (minAmount != null) 'min_amount': minAmount,
      if (maxAmount != null) 'max_amount': maxAmount,
    });

    final items = (data['items'] as List<dynamic>? ?? const [])
        .map((raw) => Expense.fromJson(raw as Map<String, dynamic>))
        .toList();
    return ExpensePage(
      items: items,
      total: (data['total'] as num?)?.toInt() ?? items.length,
      page: (data['page'] as num?)?.toInt() ?? page,
      pageSize: (data['pageSize'] as num?)?.toInt() ?? pageSize,
    );
  }

  Future<Expense> getById(String id) async {
    final data = await _client.get('/expenses/$id');
    return Expense.fromJson(data['expense'] as Map<String, dynamic>);
  }

  Future<Expense> create(Map<String, dynamic> input) async {
    final data = await _client.post('/expenses', body: input);
    return Expense.fromJson(data['expense'] as Map<String, dynamic>);
  }

  Future<Expense> update(String id, Map<String, dynamic> input) async {
    final data = await _client.put('/expenses/$id', body: input);
    return Expense.fromJson(data['expense'] as Map<String, dynamic>);
  }

  Future<void> delete(String id) async {
    await _client.delete('/expenses/$id');
  }

  Future<ExpenseMonthlyReport> monthlyReport(int year, int month) async {
    final data = await _client.get('/expenses/report/monthly', query: {
      'year': year,
      'month': month,
    });
    return ExpenseMonthlyReport.fromJson(data);
  }

  Future<List<Expense>> recurringSuggestions(int year, int month) async {
    final data = await _client.get('/expenses/recurring-suggestions', query: {
      'year': year,
      'month': month,
    });
    return (data['suggestions'] as List<dynamic>? ?? const [])
        .map((raw) => Expense.fromJson(raw as Map<String, dynamic>))
        .toList();
  }

  Future<List<ExpenseCategory>> fetchCategories({String? expenseType}) async {
    final data = await _client.get('/expenses/categories', query: {
      if (expenseType != null) 'expense_type': expenseType,
    });
    return (data['categories'] as List<dynamic>? ?? const [])
        .map((raw) => ExpenseCategory.fromJson(raw as Map<String, dynamic>))
        .toList();
  }

  Future<ExpenseCategory> createCategory({
    required String name,
    required String expenseType,
  }) async {
    final data = await _client.post('/expenses/categories', body: {
      'name': name,
      'expense_type': expenseType,
    });
    return ExpenseCategory.fromJson(data['category'] as Map<String, dynamic>);
  }

  Future<void> deactivateCategory(String id) async {
    await _client.delete('/expenses/categories/$id');
  }

  Future<Expense> uploadReceipt(
    String expenseId, {
    required List<int> bytes,
    required String filename,
  }) async {
    final data = await _client.postMultipart(
      '/expenses/$expenseId/receipt',
      fieldName: 'receipt',
      bytes: bytes,
      filename: filename,
      mimeType: _mimeTypeForFilename(filename),
    );
    return Expense.fromJson(data['expense'] as Map<String, dynamic>);
  }

  Future<Expense> removeReceipt(String expenseId) async {
    final data = await _client.delete('/expenses/$expenseId/receipt');
    return Expense.fromJson(data['expense'] as Map<String, dynamic>);
  }

  /// Combined Stocks + Dépenses feed (single chronological list mixing
  /// expenses and ingredient stock movements) — GET /expenses/feed.
  Future<List<FeedEntry>> fetchFeed({int page = 1, int pageSize = 40}) async {
    final data = await _client.get('/expenses/feed', query: {
      'page': page,
      'page_size': pageSize,
    });
    return (data['items'] as List<dynamic>? ?? const [])
        .map((raw) => FeedEntry.fromJson(raw as Map<String, dynamic>))
        .toList();
  }

  /// Matches backend's middleware/upload.js#ALLOWED_RECEIPT_MIME_TYPES —
  /// the server rejects anything else, so this must stay in sync with it.
  String _mimeTypeForFilename(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    return 'image/jpeg'; // covers .jpg / .jpeg, and is the safest default
  }
}
