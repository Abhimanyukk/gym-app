import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/api_transport_io.dart';
import 'package:gym_management_app/replab_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'api_fixture.dart';

void main() {
  test('native TLS and socket errors explain the failed connection safely', () {
    final tls = apiTransportError(
      const HandshakeException('Synthetic private transport detail'),
      'lovin.local',
    );
    expect(tls, contains('Secure connection to lovin.local failed'));
    expect(tls, contains('certificate'));
    expect(tls, isNot(contains('Synthetic private transport detail')));
    final socket = apiTransportError(
      const SocketException('Synthetic private transport detail'),
      'lovin.local',
    );
    expect(socket, contains('Cannot reach the server at lovin.local'));
    expect(socket, contains('hostname resolves'));
    expect(socket, isNot(contains('Synthetic private transport detail')));
    expect(apiTransportError(StateError('Synthetic'), 'lovin.local'), isNull);
  });

  test(
    'TLS failures surface before the password is sent to the server',
    () async {
      var requests = 0;
      final api = RepLabApi(
        client: MockClient((request) async {
          requests++;
          expect(request.url.host, 'lovin.local');
          expect(request.url.path, '/health/ready');
          expect(request.body, isEmpty);
          throw const HandshakeException('Synthetic certificate failure');
        }),
      );
      addTearDown(api.dispose);
      await expectLater(
        api.login('https://lovin.local:8443', 'Synthetic password'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', contains('certificate'))
              .having((e) => e.code, 'code', 'connection_failed')
              .having((e) => e.uncertain, 'uncertain', isFalse),
        ),
      );
      expect(requests, 1);
      expect(api.signedIn, isFalse);
    },
  );

  test(
    'TLS failures preserve sessions and uncertain-write protection',
    () async {
      final fixture = ApiFixture();
      var fail = false;
      var requests = 0;
      final api = RepLabApi(
        client: MockClient((request) async {
          requests++;
          if (fail) {
            throw const HandshakeException('Synthetic certificate failure');
          }
          final forwarded = http.Request(request.method, request.url)
            ..headers.addAll(request.headers)
            ..body = request.body;
          return http.Response.fromStream(await fixture.client.send(forwarded));
        }),
      );
      addTearDown(api.dispose);
      await api.login('https://lovin.local:8443', 'Synthetic password');
      fail = true;
      final before = requests;
      await expectLater(
        api.saveSettings('Synthetic gym', '', ''),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', contains('certificate'))
              .having(
                (e) => e.message,
                'warning',
                contains('The change may have been saved'),
              )
              .having((e) => e.code, 'code', 'connection_failed')
              .having((e) => e.uncertain, 'uncertain', isTrue),
        ),
      );
      expect(requests, before + 1);
      expect(api.signedIn, isTrue);
    },
  );

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
