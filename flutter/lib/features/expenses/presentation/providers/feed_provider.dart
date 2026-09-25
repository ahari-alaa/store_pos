import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/feed_entry.dart';
import 'expenses_provider.dart' show expensesApiProvider;

class FeedNotifier extends StateNotifier<AsyncValue<List<FeedEntry>>> {
  final Ref _ref;

  FeedNotifier(this._ref) : super(const AsyncValue.loading()) {
    refresh();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    try {
      final api = _ref.read(expensesApiProvider);
      final items = await api.fetchFeed();
      state = AsyncValue.data(items);
    } catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }
}

final feedProvider = StateNotifierProvider<FeedNotifier, AsyncValue<List<FeedEntry>>>((ref) {
  return FeedNotifier(ref);
});
