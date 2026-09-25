import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/receipt_settings_storage.dart';
import '../../domain/entities/receipt_settings.dart';

/// Holds the current receipt/printer configuration for the whole app.
///
/// Loaded once from on-device storage at startup (mirrors AuthNotifier's
/// `_restoreSession` pattern in auth_provider.dart) and kept in memory from
/// then on, so every screen that builds a receipt (POS screen buttons,
/// the post-sale dialog, the receipt preview page) reads the same
/// up-to-date settings without re-reading storage each time.
class ReceiptSettingsNotifier extends StateNotifier<ReceiptSettings> {
  bool _loaded = false;

  ReceiptSettingsNotifier() : super(ReceiptSettings.defaults) {
    _load();
  }

  /// Whether the persisted settings have finished loading. Screens can
  /// ignore this in practice (defaults are safe to render immediately),
  /// but it's exposed for completeness/testability.
  bool get isLoaded => _loaded;

  Future<void> _load() async {
    final loaded = await ReceiptSettingsStorage.instance.read();
    state = loaded;
    _loaded = true;
  }

  Future<void> update(ReceiptSettings Function(ReceiptSettings current) updater) async {
    final next = updater(state);
    state = next;
    await ReceiptSettingsStorage.instance.write(next);
  }

  Future<void> resetToDefaults() async {
    state = ReceiptSettings.defaults;
    await ReceiptSettingsStorage.instance.write(ReceiptSettings.defaults);
  }
}

final receiptSettingsProvider =
    StateNotifierProvider<ReceiptSettingsNotifier, ReceiptSettings>((ref) {
  return ReceiptSettingsNotifier();
});
