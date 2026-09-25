/// A failed API call, normalized from the backend's
/// `{ success: false, error: { code, message } }` envelope (see
/// store_pos_backend/src/utils/apiResponse.js and errorHandler.js) so every
/// screen can show `.message` directly and branch on `.code` when needed
/// (e.g. 'INSUFFICIENT_STOCK', 'INVALID_CREDENTIALS', 'TOKEN_EXPIRED').
class ApiException implements Exception {
  final int? statusCode;
  final String code;
  final String message;
  final Map<String, dynamic>? details;

  const ApiException({
    this.statusCode,
    required this.code,
    required this.message,
    this.details,
  });

  bool get isAuthError =>
      code == 'TOKEN_EXPIRED' || code == 'TOKEN_INVALID' || code == 'NO_TOKEN' || code == 'USER_NOT_FOUND';

  @override
  String toString() => 'ApiException($code): $message';
}
