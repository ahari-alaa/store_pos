import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/providers/auth_provider.dart';
import '../storage/token_storage.dart';
import 'api_client.dart';
import 'connection_status.dart';

/// Single shared [ApiClient] for the whole app. Every feature datasource
/// (products, sales, auth, ...) reads this instead of constructing its own
/// http client, so the auth token and base URL logic live in one place.
final Provider<ApiClient> apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    tokenProvider: () => TokenStorage.instance.readAccessToken(),
    onUnauthorized: () => ref.read(authProvider.notifier).handleSessionExpired(),
    // Feeds the top bar's connection indicator from real request
    // outcomes — see connection_status.dart for why this is derived
    // rather than polled or hard-coded.
    onReachabilityChanged: (reachable) {
      final notifier = ref.read(connectionStatusProvider.notifier);
      reachable ? notifier.reportReachable() : notifier.reportUnreachable();
    },
  );
});
