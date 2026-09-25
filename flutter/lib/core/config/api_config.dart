import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Points the app at the `store_pos_backend` Node/Express API.
///
/// Override at build/run time without touching code, e.g.:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.20:3000/api
///
/// This is the value you'll want to change for a physical device or a
/// deployed server — the platform-based defaults below only work for
/// backend running on the SAME machine as the emulator/simulator.
class ApiConfig {
  ApiConfig._();

  static const String _override = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    if (_override.isNotEmpty) return _override;

    // Android emulator can't reach the host machine via `localhost` — it
    // has to use the special loopback alias `10.0.2.2`. Every other
    // target (iOS simulator, desktop, web) can reach the host directly.
    if (!kIsWeb && Platform.isAndroid) {
      return 'http://10.0.2.2:3000/api';
    }
    return 'http://localhost:3000/api';
  }

  /// The bare server origin (no `/api` suffix), for loading static assets
  /// the API returns relative paths for — currently just product images
  /// (see products_api.dart / backend's `/uploads` static mount).
  static String get originUrl {
    final uri = Uri.parse(baseUrl);
    // BUG (was `query: ''`): Uri.replace treats an empty-string query as
    // an *explicit* (present but empty) query component, not "no query"
    // — so toString() renders a bare trailing `?`, e.g.
    // "http://localhost:3000?". Product.fullImageUrl then appends the
    // image path straight after that, producing
    // "http://localhost:3000?/uploads/products/xyz.png" — everything
    // after the `?` is parsed as a query string, not a path, so the
    // server sees a request for `/` and returns 404. Passing `query:
    // null` (the actual "omit it" value) avoids the `?` entirely.
    return uri.replace(path: '', query: null).toString();
  }
}
