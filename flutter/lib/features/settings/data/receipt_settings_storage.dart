import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/entities/receipt_settings.dart';

/// Persists [ReceiptSettings] on-device, the same way TokenStorage persists
/// the session (see core/storage/token_storage.dart) — this project has no
/// other local key/value settings store, so it reuses that exact approach
/// instead of introducing a second storage mechanism or a new dependency.
class ReceiptSettingsStorage {
  ReceiptSettingsStorage._();
  static final ReceiptSettingsStorage instance = ReceiptSettingsStorage._();

  final _storage = const FlutterSecureStorage();
  static const _settingsKey = 'store_pos_receipt_settings';

  Future<ReceiptSettings> read() async {
    try {
      final raw = await _storage.read(key: _settingsKey);
      if (raw == null || raw.isEmpty) return ReceiptSettings.defaults;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return ReceiptSettings.fromJson(json);
    } catch (_) {
      // Corrupted/unreadable settings should never block the cashier from
      // using the POS — fall back to sane defaults instead of crashing.
      return ReceiptSettings.defaults;
    }
  }

  Future<void> write(ReceiptSettings settings) async {
    await _storage.write(key: _settingsKey, value: jsonEncode(settings.toJson()));
  }
}
