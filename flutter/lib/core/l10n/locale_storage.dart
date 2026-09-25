import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app_locale.dart';

/// Persists the chosen app language on-device, the same way
/// [ReceiptSettingsStorage] persists receipt settings — reusing the
/// project's existing local key/value approach instead of adding a new
/// storage dependency (see that class's doc comment).
class LocaleStorage {
  LocaleStorage._();
  static final LocaleStorage instance = LocaleStorage._();

  final _storage = const FlutterSecureStorage();
  static const _key = 'store_pos_app_locale';

  Future<AppLocale> read() async {
    try {
      final raw = await _storage.read(key: _key);
      return AppLocaleX.fromCode(raw);
    } catch (_) {
      return AppLocale.fr;
    }
  }

  Future<void> write(AppLocale locale) async {
    await _storage.write(key: _key, value: locale.locale.languageCode);
  }
}
