import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/api_transport_io.dart';

void main() {
  test('native transport loads the bundled certificate by default', () async {
    const asset = 'assets/certificates/server.crt';
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    final certificate = await rootBundle.load(asset);
    rootBundle.evict(asset);
    final loaded = <String>[];
    binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (
      message,
    ) async {
      final name = utf8.decode(message!.buffer.asUint8List());
      loaded.add(name);
      return name == asset ? certificate : null;
    });
    addTearDown(() {
      binding.defaultBinaryMessenger.setMockMessageHandler(
        'flutter/assets',
        null,
      );
      rootBundle.evict(asset);
    });

    final client = await createApiClient();
    addTearDown(client.close);
    expect(loaded, [asset]);
  });
}
