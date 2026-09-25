import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app_palette.dart';

/// Persists the chosen [AppPalette] on-device, the same way
/// `ReceiptSettingsStorage` persists receipt settings (see that class's
/// doc comment) — this project's existing local key/value approach,
/// reused instead of adding a new storage dependency.
class ThemeStorage {
  ThemeStorage._();
  static final ThemeStorage instance = ThemeStorage._();

  final _storage = const FlutterSecureStorage();
  static const _key = 'store_pos_app_theme';

  Future<AppPalette?> read() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return null;
      return AppPalette.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(AppPalette palette) async {
    await _storage.write(key: _key, value: jsonEncode(palette.toJson()));
  }
}
