import 'dart:convert';

import 'session_storage.dart';

String? serverHostError(String? input) {
  final host = (input ?? '').trim();
  if (host.isEmpty) return 'Enter the server IP address or hostname';
  if (RegExp(r'^[\d.]+$').hasMatch(host)) {
    final parts = host.split('.');
    if (parts.length == 4 &&
        parts.every(
          (s) =>
              RegExp(r'^\d{1,3}$').hasMatch(s) &&
              int.parse(s) <= 255 &&
              (s == '0' || !s.startsWith('0')),
        )) {
      return null;
    }
    return 'Enter four numbers between 0 and 255';
  }
  if (host.length <= 253 &&
      host
          .split('.')
          .every(
            (s) =>
                RegExp(r'^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$')
                    .hasMatch(s),
          )) {
    return null;
  }
  return 'Enter a hostname only, without https://, a port or a path';
}

// Fixed protocol endpoint; setup stores only the hostname/IP.
const serverPort = 8443;

String serverUrl(String host) =>
    Uri(scheme: 'https', host: host, port: serverPort).toString();

/// Only the revocable session key and local setup are remembered, not passwords.
class DeviceSession {
  DeviceSession({
    Future<String?> Function()? read,
    Future<void> Function(String)? write,
  }) : _read = read ?? readDeviceSession,
       _write = write ?? writeDeviceSession;
  final Future<String?> Function() _read;
  final Future<void> Function(String) _write;
  String host = '';
  String? token;
  bool biometrics = false;
  bool loaded = false;
  Future<void> _pending = Future.value();
  bool get configured => host.isNotEmpty;

  Future<void> load() async {
    final value = await _read();
    if (value == null) {
      loaded = true;
      return;
    }
    final data = jsonDecode(value) as Map<String, dynamic>;
    final savedHost = data['host'] as String;
    if (serverHostError(savedHost) != null) {
      throw const FormatException('Invalid saved server');
    }
    host = savedHost;
    token = data['token'] as String?;
    biometrics = data['biometrics'] == true;
    loaded = true;
  }

  Future<void> save({
    required String host,
    required String? token,
    required bool biometrics,
  }) async {
    if (serverHostError(host) != null) {
      throw const FormatException('Invalid server');
    }
    final value = jsonEncode({
      'host': host,
      'token': token,
      'biometrics': biometrics,
    });
    final operation = _pending.then(
      (_) => _write(value),
      onError: (_) => _write(value),
    );
    _pending = operation;
    await operation;
    this.host = host;
    this.token = token;
    this.biometrics = biometrics;
    loaded = true;
  }
}
