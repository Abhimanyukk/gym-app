import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

Future<http.Client> createApiClient() async {
  const asset = String.fromEnvironment('API_CERT_ASSET');
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
