import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_transport.dart';
import 'device_session.dart';
import 'member_profile.dart';
import 'member_enrollment.dart';

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
      uri.port != serverPort ||
      RegExp(r'\s').hasMatch(text ?? '')) {
    return 'Invalid server connection. Enter only the hostname or IP in setup.';
  }
  return null;
}

/// One REST boundary. DeviceSession persists the key in encrypted native storage,
/// never the password. Web preview keeps bearer keys in memory only.
class RepLabApi extends ChangeNotifier {
  RepLabApi({http.Client? client, this.timeout = const Duration(seconds: 20)})
    // Keep the injectable parameter public while the transport stays private.
    // ignore: prefer_initializing_formals
    : _client = client,
      _injectedClient = client;
  http.Client? _client;
  final http.Client? _injectedClient;
  DateTime? _expiresAt;
  final Duration timeout;
  Uri? _base;
  String? _token;
  Timer? _expiry;
  bool _published = false;
  bool _disposed = false;
  AdminAccount? admin;
  String? sessionMessage;

  bool get signedIn => _token != null && _published;
  String? get sessionKey => _token;
  String get baseUrl => _base?.toString() ?? '';

  Future<void> login(String url, String password, {bool notify = true}) async {
    final error = apiAddressError(url);
    if (error != null) throw ApiException(error);
    clearSession();
    _base = Uri.parse(url.trim()).replace(path: '');
    final health = await request('GET', '/health/ready', authenticated: false);
    if (health is! Map || !['2', '3'].contains(health['schema'])) {
      throw const ApiException(
        'Update the gym server to RepLab 0.3 and run its migration before setting up this app.',
        code: 'server_update_required',
      );
    }
    final value = await request(
      'POST',
      '/api/v1/auth/login',
      body: {'password': password},
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
    _expiresAt = expires;
    admin = account;
    sessionMessage = null;
    _scheduleExpiry();
    if (notify) publishSession();
  }

  Future<void> resume(String url, String key) async {
    if (apiAddressError(url) != null || key.isEmpty) {
      throw const ApiException('Invalid saved session.');
    }
    _base = Uri.parse(url).replace(path: '');
    _token = key;
    try {
      final data =
          await request('POST', '/api/v1/auth/resume') as Map<String, dynamic>;
      admin = parseAdmin(data['admin'] as Map<String, dynamic>);
      final expires = DateTime.parse(data['expires_at'] as String).toUtc();
      _expiresAt = expires;
      if (!expires.isAfter(DateTime.now().toUtc())) {
        throw const ApiException(
          'Saved session expired.',
          code: 'unauthorized',
        );
      }
      _scheduleExpiry();
      sessionMessage = null;
      publishSession();
    } catch (_) {
      _token = null;
      _published = false;
      admin = null;
      rethrow;
    }
  }

  void publishSession() {
    if (!_disposed && _token != null) {
      _published = true;
      notifyListeners();
    }
  }

  RepLabApi newConnection() =>
      RepLabApi(client: _injectedClient, timeout: timeout);
  void adoptSession(RepLabApi other) {
    if (other._token == null ||
        other.admin == null ||
        other._expiresAt == null) {
      throw const ApiException('New server session is not valid.');
    }
    _base = other._base;
    _token = other._token;
    admin = other.admin;
    _expiresAt = other._expiresAt;
    _scheduleExpiry();
    sessionMessage = null;
    publishSession();
  }

  void _scheduleExpiry() {
    _expiry?.cancel();
    final remaining = _expiresAt!.difference(DateTime.now().toUtc());
    if (remaining <= Duration.zero) {
      clearSession('Your session expired. Please sign in again.');
      return;
    }
    // Browser timers overflow above ~24.8 days. Recheck long sessions daily.
    const checkpoint = Duration(days: 1);
    _expiry = Timer(
      remaining > checkpoint ? checkpoint : remaining,
      _scheduleExpiry,
    );
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
    if (_disposed || _base == null || (authenticated && _token == null)) {
      throw const ApiException('Please sign in to the gym server.');
    }
    final token = _token;
    final base = _base!;
    final mutation = method != 'GET' && !path.startsWith('/api/v1/auth/');
    http.Response response;
    try {
      _client ??= await createApiClient();
      final uri = base.replace(path: path, queryParameters: query);
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
    } catch (error) {
      final message = error is TimeoutException
          ? 'The server at ${base.host} did not respond in time. Check your '
                'connection and that RepLab is running.'
          : apiTransportError(error, base.host) ??
                'Cannot reach the server. Check the address, connection and trusted certificate.';
      throw ApiException(
        mutation
            ? 'No confirmed response from the server. $message The change may have been saved; check records before submitting again.'
            : message,
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
  Future<EnrollmentOptions> enrollmentOptions() async {
    try {
      return EnrollmentOptions.fromJson(
        await request('GET', '/api/v1/enrollment-options')
            as Map<String, dynamic>,
      );
    } on ApiException catch (error) {
      if (error.code == 'not_found') {
        throw const ApiException(
          'Update the gym server to RepLab 0.4 and run its migration to register photos, plans and payments.',
          code: 'server_update_required',
        );
      }
      rethrow;
    }
  }

  Future<MemberProfile> enrollMember(Map<String, dynamic> fields) async =>
      MemberProfile.fromJson(
        await request('POST', '/api/v1/members/enroll', body: fields)
            as Map<String, dynamic>,
      );
  Future<MemberProfile> findEnrollment(String requestId) async =>
      MemberProfile.fromJson(
        await request('GET', '/api/v1/enrollments/$requestId')
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
    _published = false;
    admin = null;
    sessionMessage = message;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _expiry?.cancel();
    if (_injectedClient == null) _client?.close();
    _token = null;
    admin = null;
    super.dispose();
  }
}
