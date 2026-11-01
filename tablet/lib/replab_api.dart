import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_transport.dart';
import 'member_profile.dart';

typedef AdminAccount = ({String id, String name, String email});
typedef MemberDirectory = ({List<MemberProfile> items, int total});

class ApiException implements Exception {
  const ApiException(this.message, {this.code = '', this.uncertain = false});
  final String message;
  final String code;
  final bool uncertain;
  @override
  String toString() => message;
}

String? apiAddressError(String? text) {
  final uri = Uri.tryParse((text ?? '').trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.port < 1 ||
      uri.port > 65535 ||
      RegExp(r'\s').hasMatch(text ?? '')) {
    return 'Enter an HTTPS server address, e.g. https://192.168.1.50:8443';
  }
  return null;
}

/// One REST/session boundary. Tokens live in memory only, never preferences/logs.
/// dover-gain-efficient: sign in after restart; add secure persistence only if needed.
class RepLabApi extends ChangeNotifier {
  RepLabApi({http.Client? client, this.timeout = const Duration(seconds: 20)})
    // Keep the injectable parameter public while the transport stays private.
    // ignore: prefer_initializing_formals
    : _client = client;
  http.Client? _client;
  final Duration timeout;
  Uri? _base;
  String? _token;
  Timer? _expiry;
  bool _disposed = false;
  AdminAccount? admin;
  String? sessionMessage;

  bool get signedIn => _token != null;
  String get baseUrl => _base?.toString() ?? '';

  Future<void> login(String url, String email, String password) async {
    final error = apiAddressError(url);
    if (error != null) throw ApiException(error);
    clearSession();
    _base = Uri.parse(url.trim()).replace(path: '');
    final value = await request(
      'POST',
      '/api/v1/auth/login',
      body: {'email': email.trim(), 'password': password},
      authenticated: false,
    );
    if (_disposed) return;
    late String token;
    late DateTime expires;
    late AdminAccount account;
    try {
      final data = value as Map<String, dynamic>;
      token = data['access_token'] as String;
      expires = DateTime.parse(data['expires_at'] as String).toUtc();
      account = parseAdmin(data['admin'] as Map<String, dynamic>);
    } catch (_) {
      throw const ApiException(
        'Invalid server login response. Please contact the server operator.',
      );
    }
    if (token.isEmpty || !expires.isAfter(DateTime.now().toUtc())) {
      throw const ApiException('Invalid server session. Please sign in again.');
    }
    _token = token;
    admin = account;
    sessionMessage = null;
    _expiry = Timer(expires.difference(DateTime.now().toUtc()), () {
      clearSession('Your session expired. Please sign in again.');
    });
    if (!_disposed) notifyListeners();
  }

  static AdminAccount parseAdmin(Map<String, dynamic> value) => (
    id: value['id'] as String,
    name: value['name'] as String,
    email: value['email'] as String,
  );

  Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool authenticated = true,
  }) async {
    if (_disposed || _base == null || (authenticated && !signedIn)) {
      throw const ApiException('Please sign in to the gym server.');
    }
    final token = _token;
    final mutation = method != 'GET';
    http.Response response;
    try {
      _client ??= await createApiClient();
      final uri = _base!.replace(path: path, queryParameters: query);
      final req = http.Request(method, uri)
        ..followRedirects = false
        ..headers['Accept'] = 'application/json';
      if (authenticated) req.headers['Authorization'] = 'Bearer $token';
      if (body != null) {
        req.headers['Content-Type'] = 'application/json';
        req.body = jsonEncode(body);
      }
      response = await (() async {
        final stream = await _client!.send(req);
        return http.Response.fromStream(stream);
      })().timeout(timeout);
    } catch (_) {
      throw ApiException(
        mutation
            ? 'No confirmed response from the server. Check your connection and certificate. The change may have been saved; check records before submitting again.'
            : 'Cannot reach the server. Check the address, connection and trusted certificate.',
        code: 'connection_failed',
        uncertain: mutation,
      );
    }
    if (authenticated && response.statusCode == 401 && token == _token) {
      clearSession(
        'Your session expired or was revoked. Please sign in again.',
      );
    }
    dynamic value;
    try {
      value = response.body.isEmpty ? null : jsonDecode(response.body);
    } catch (_) {
      throw ApiException(
        'Unexpected server response.',
        uncertain:
            mutation &&
            (response.statusCode >= 500 ||
                response.statusCode >= 200 && response.statusCode < 300),
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = value is Map ? value['error'] : null;
      final message = error is Map && error['message'] is String
          ? error['message'] as String
          : 'Server request failed (${response.statusCode}).';
      throw ApiException(
        mutation && response.statusCode >= 500
            ? '$message The change may have been saved; check records before submitting again.'
            : message,
        code: error is Map ? '${error['code'] ?? ''}' : '',
        uncertain: mutation && response.statusCode >= 500,
      );
    }
    return value;
  }

  Future<Map<String, dynamic>> dashboard() async =>
      await request('GET', '/api/v1/dashboard/summary') as Map<String, dynamic>;
  Future<void> ready() async {
    await request('GET', '/health/ready');
  }

  Future<MemberDirectory> members({
    String q = '',
    bool? active,
    int offset = 0,
  }) async {
    final data = await request(
      'GET',
      '/api/v1/members',
      query: {
        'q': q,
        'limit': '50',
        'offset': '$offset',
        if (active != null) 'active': '$active',
      },
    ) as Map<String, dynamic>;
    return (
      items: (data['items'] as List)
          .map((v) => MemberProfile.fromJson(v as Map<String, dynamic>))
          .toList(),
      total: data['total'] as int,
    );
  }

  Future<MemberProfile> member(String id) async => MemberProfile.fromJson(
    await request('GET', '/api/v1/members/$id') as Map<String, dynamic>,
  );
  Future<MemberProfile> addMember(Map<String, dynamic> fields) async =>
      MemberProfile.fromJson(
        await request('POST', '/api/v1/members', body: fields)
            as Map<String, dynamic>,
      );
  Future<List<AdminAccount>> admins() async =>
      (await request('GET', '/api/v1/admins') as List)
          .map((v) => parseAdmin(v as Map<String, dynamic>))
          .toList();
  Future<void> addAdmin(String name, String email, String password) async {
    await request(
      'POST',
      '/api/v1/admins',
      body: {'name': name.trim(), 'email': email.trim(), 'password': password},
    );
  }

  Future<Map<String, dynamic>> settings() async =>
      await request('GET', '/api/v1/settings') as Map<String, dynamic>;
  Future<Map<String, dynamic>> saveSettings(
    String name,
    String phone,
    String address,
  ) async => await request(
    'PUT',
    '/api/v1/settings',
    body: {
      'gym_name': name.trim(),
      'phone': phone.trim(),
      'address': address.trim(),
    },
  ) as Map<String, dynamic>;
  Future<void> changePassword(String current, String next) async {
    await request(
      'POST',
      '/api/v1/auth/change-password',
      body: {'current_password': current, 'new_password': next},
    );
    clearSession(
      'Password changed. All your sessions were revoked. Sign in again.',
    );
  }

  Future<void> logout() async {
    try {
      await request('POST', '/api/v1/auth/logout');
      clearSession('Signed out.');
    } on ApiException {
      clearSession(
        'Signed out on this tablet. Server revocation was not confirmed; the previous session expires automatically.',
      );
    }
  }

  void clearSession([String? message]) {
    _expiry?.cancel();
    _token = null;
    admin = null;
    sessionMessage = message;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _expiry?.cancel();
    _client?.close();
    _token = null;
    admin = null;
    super.dispose();
  }
}
