import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the app can currently reach the backend.
enum ConnectionStatus {
  /// No request has completed yet this session.
  unknown,

  /// The last request reached the server.
  online,

  /// The last request failed at the transport layer (server unreachable,
  /// network down). Note this is specifically *not* set for a request the
  /// server answered with a 4xx — a validation error means the connection
  /// is fine.
  offline,
}

/// Tracks reachability of the backend, derived from the outcome of the
/// API calls the app actually makes.
///
/// A deliberate design note, because it is the difference between an
/// honest indicator and a decorative one: this does **not** poll a health
/// endpoint and does **not** report a hard-coded "En ligne". It reports
/// what the last real request did. If the app has not talked to the
/// server yet, the status is [ConnectionStatus.unknown] and the UI shows
/// nothing rather than claiming a connection it has not verified.
///
/// This project has no offline write queue yet — the Flutter client is
/// online-only and every mutation goes straight to the API (the backend's
/// `/sync` endpoints exist but nothing on the client uses them, and the
/// pubspec still lists SQLite as a later phase). So the status chip in
/// the top bar reports reachability and nothing more. It must not grow a
/// "2 éléments en attente" badge until there is a real local queue to
/// count, because an invented pending-count is worse than no indicator at
/// all: it tells a cashier their sale is safely queued when it is not.
class ConnectionStatusNotifier extends StateNotifier<ConnectionStatus> {
  ConnectionStatusNotifier() : super(ConnectionStatus.unknown);

  DateTime? _lastContact;

  /// Timestamp of the last request that reached the server, for the
  /// "dernier contact" line in the status tooltip.
  DateTime? get lastContact => _lastContact;

  /// Called by [ApiClient] after every request that got any answer from
  /// the server, including error answers.
  void reportReachable() {
    _lastContact = DateTime.now();
    if (state != ConnectionStatus.online) state = ConnectionStatus.online;
  }

  /// Called by [ApiClient] when a request failed before reaching the
  /// server.
  void reportUnreachable() {
    if (state != ConnectionStatus.offline) state = ConnectionStatus.offline;
  }
}

final connectionStatusProvider =
    StateNotifierProvider<ConnectionStatusNotifier, ConnectionStatus>((ref) {
  return ConnectionStatusNotifier();
});
