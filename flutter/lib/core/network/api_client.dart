import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../config/api_config.dart';
import 'api_exception.dart';

/// Reads the current access token (from secure storage) on every request,
/// so a freshly-logged-in or freshly-logged-out state is always reflected
/// without needing to rebuild this client.
typedef TokenProvider = Future<String?> Function();

/// Thin HTTP client for the `store_pos_backend` API.
///
/// Every backend response is either:
///   `{ success: true, data: {...} }`
///   `{ success: false, error: { code, message, details? } }`
/// (see backend/src/utils/apiResponse.js + middleware/errorHandler.js).
/// This client unwraps `data` on success and throws [ApiException] on
/// failure, so callers never touch the envelope directly.
class ApiClient {
  final http.Client _http;
  final TokenProvider _tokenProvider;

  /// Called whenever the server rejects the current token (401 with an
  /// auth-related code). Typically wired to clear the stored session and
  /// send the user back to the login screen.
  final Future<void> Function()? onUnauthorized;

  /// Reports whether each request actually reached the server, so the UI
  /// can show a truthful connection indicator instead of a decorative
  /// one. `true` means the server answered (even with an error status);
  /// `false` means the request failed at the transport layer.
  ///
  /// Optional and null by default, so nothing that constructs an
  /// [ApiClient] without it (tests, one-off scripts) changes behaviour.
  final void Function(bool reachable)? onReachabilityChanged;

  ApiClient({
    required TokenProvider tokenProvider,
    http.Client? httpClient,
    this.onUnauthorized,
    this.onReachabilityChanged,
  })  : _tokenProvider = tokenProvider,
        _http = httpClient ?? http.Client();

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final base = Uri.parse(ApiConfig.baseUrl);
    final cleanBasePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    final cleanPath = path.startsWith('/') ? path : '/$path';

    return base.replace(
      path: '$cleanBasePath$cleanPath',
      queryParameters: (query == null || query.isEmpty)
          ? null
          : query.map((key, value) => MapEntry(key, value.toString())),
    );
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) {
    return _send('GET', _uri(path, query));
  }

  Future<Map<String, dynamic>> post(String path, {Object? body}) {
    return _send('POST', _uri(path), body: body);
  }

  /// [suppressUnauthorized] lets a caller opt a specific request out of the
  /// global "401 → log the current user out" handling below. Every request
  /// carries the *currently signed-in* user's own token regardless of what
  /// it's about, so a 401 normally does mean that user's session is dead —
  /// except for admin-only requests that act on a DIFFERENT account (e.g.
  /// deactivating another cashier). A 401 there is never evidence that the
  /// admin's own session is invalid, so it must not log the admin out (see
  /// AuthApi.updateUser / CashiersNotifier.updateCashier).
  Future<Map<String, dynamic>> put(String path, {Object? body, bool suppressUnauthorized = false}) {
    return _send('PUT', _uri(path), body: body, suppressUnauthorized: suppressUnauthorized);
  }

  Future<Map<String, dynamic>> delete(String path) {
    return _send('DELETE', _uri(path));
  }

  /// Multipart POST for file uploads (currently just product images — see
  /// products_api.dart#uploadImage / backend's `/products/:id/image`).
  /// Kept separate from [_send] since multipart requests are built and
  /// streamed differently than a plain JSON body, but shares the same
  /// auth header and response-envelope handling.
  Future<Map<String, dynamic>> postMultipart(
    String path, {
    required String fieldName,
    required List<int> bytes,
    required String filename,
    String? mimeType,
  }) async {
    final token = await _tokenProvider();
    final uri = _uri(path);
    final request = http.MultipartRequest('POST', uri)
      ..headers['Accept'] = 'application/json'
      ..files.add(
        http.MultipartFile.fromBytes(
          fieldName,
          bytes,
          filename: filename,
          contentType: mimeType != null ? MediaType.parse(mimeType) : null,
        ),
      );
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    http.Response response;
    try {
      final streamed = await _http.send(request);
      response = await http.Response.fromStream(streamed);
    } on SocketException {
      throw ApiException(
        code: 'NETWORK_ERROR',
        message: 'Could not reach the server at ${ApiConfig.baseUrl}. '
            'Check your connection and that the backend is running.',
      );
    } on HttpException {
      throw const ApiException(
          code: 'NETWORK_ERROR', message: 'A network error occurred.');
    }

    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> _send(String method, Uri uri,
      {Object? body, bool suppressUnauthorized = false}) async {
    final token = await _tokenProvider();
    // Debug-build only. This was a bare `print`, which (a) violates the
    // project's own `avoid_print` lint and so failed `flutter analyze`,
    // and (b) shipped request/token telemetry into release logs.
    // `debugPrint` under `kDebugMode` is compiled out of release builds.
    if (kDebugMode) {
      debugPrint('[API] $method $uri | tokenPresent=${token != null}');
    }
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
    final encodedBody = body == null ? null : jsonEncode(body);

    http.Response response;
    try {
      switch (method) {
        case 'GET':
          response = await _http.get(uri, headers: headers);
          break;
        case 'POST':
          response = await _http.post(uri, headers: headers, body: encodedBody);
          break;
        case 'PUT':
          response = await _http.put(uri, headers: headers, body: encodedBody);
          break;
        case 'DELETE':
          response = await _http.delete(uri, headers: headers);
          break;
        default:
          throw ApiException(
              code: 'UNSUPPORTED_METHOD',
              message: 'Unsupported HTTP method $method');
      }
    } on SocketException {
      onReachabilityChanged?.call(false);
      throw ApiException(
        code: 'NETWORK_ERROR',
        message: 'Could not reach the server at ${ApiConfig.baseUrl}. '
            'Check your connection and that the backend is running.',
      );
    } on HttpException {
      onReachabilityChanged?.call(false);
      throw const ApiException(
          code: 'NETWORK_ERROR', message: 'A network error occurred.');
    } on FormatException {
      throw const ApiException(
          code: 'NETWORK_ERROR', message: 'Malformed server address.');
    }

    // The server answered. Whatever the status code, the connection
    // itself is working — a 422 is not an outage.
    onReachabilityChanged?.call(true);
    return _handleResponse(response, suppressUnauthorized: suppressUnauthorized);
  }

  Future<Map<String, dynamic>> _handleResponse(http.Response response,
      {bool suppressUnauthorized = false}) async {
    Map<String, dynamic> decoded;
    try {
      decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException(
        statusCode: response.statusCode,
        code: 'INVALID_RESPONSE',
        message:
            'The server returned an unexpected response (${response.statusCode}).',
      );
    }

    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        decoded['success'] == true) {
      final data = decoded['data'];
      return data is Map<String, dynamic> ? data : <String, dynamic>{};
    }

    final error = decoded['error'] as Map<String, dynamic>?;
    final code = (error?['code'] as String?) ?? 'UNKNOWN_ERROR';
    final message = (error?['message'] as String?) ??
        'Something went wrong (${response.statusCode}).';
    final details = error?['details'] as Map<String, dynamic>?;

    final apiException = ApiException(
        statusCode: response.statusCode, code: code, message: message, details: details);

    if (response.statusCode == 401 && onUnauthorized != null && !suppressUnauthorized) {
      await onUnauthorized!();
    }

    throw apiException;
  }
}
