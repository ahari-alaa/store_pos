/// One row of the merged "Stocks + Dépenses" feed — either an expense or
/// an ingredient stock movement, normalized to a common shape so the UI
/// can render both in a single chronological list. Mirrors
/// GET /api/expenses/feed (see store_pos_backend/src/repositories/
/// expenseRepository.js#combinedFeed).
enum FeedEntryType { expense, stockMovement }

class FeedEntry {
  final String id;
  final FeedEntryType type;
  final DateTime occurredAt;
  final double? amount; // set for expenses
  final double? quantityDelta; // set for stock movements
  final String? unit; // set for stock movements
  final String movementType; // expense_type OR ingredient movement_type
  final String title; // category name OR ingredient name
  final String? description;
  final String? relatedName; // supplier name, when known

  const FeedEntry({
    required this.id,
    required this.type,
    required this.occurredAt,
    required this.movementType,
    required this.title,
    this.amount,
    this.quantityDelta,
    this.unit,
    this.description,
    this.relatedName,
  });

  factory FeedEntry.fromJson(Map<String, dynamic> json) {
    return FeedEntry(
      id: '${json['id']}',
      type: json['entry_type'] == 'STOCK_MOVEMENT'
          ? FeedEntryType.stockMovement
          : FeedEntryType.expense,
      occurredAt: DateTime.tryParse('${json['occurred_at']}') ?? DateTime.now(),
      amount: json['amount'] != null ? double.tryParse('${json['amount']}') : null,
      quantityDelta:
          json['quantity_delta'] != null ? double.tryParse('${json['quantity_delta']}') : null,
      unit: json['unit'] as String?,
      movementType: '${json['movement_type'] ?? ''}',
      title: '${json['title'] ?? ''}',
      description: json['description'] as String?,
      relatedName: json['related_name'] as String?,
    );
  }
}
