import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

String? apiTransportError(Object error, String host) {
  if (error is HandshakeException) {
    return 'Secure connection to $host failed. Check that the app trusts the '
        "Pi's active certificate, that it includes $host, and that the "
        'certificate and device date are valid.';
  }
  if (error is SocketException) {
    return 'Cannot reach the server at $host. Check that the hostname resolves, '
        'the tablet can reach the Pi on the network, and RepLab is running.';
  }
  return null;
}

Future<http.Client> createApiClient() async {
  const asset = String.fromEnvironment(
    'API_CERT_ASSET',
    defaultValue: 'assets/certificates/server.crt',
  );
  final context = SecurityContext(withTrustedRoots: true);
  if (asset.isNotEmpty) {
    final bytes = await rootBundle.load(asset);
    context.setTrustedCertificatesBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
  }
  // Never use badCertificateCallback: retain hostname, expiry and chain checks.
  return IOClient(
    HttpClient(context: context)
      ..connectionTimeout = const Duration(seconds: 15),
  );
}
