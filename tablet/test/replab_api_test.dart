import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gym_management_app/replab_api.dart';

import 'api_fixture.dart';

void main() {
  test('HTTPS address and safe URL requirements', () {
    for (final url in [
      '',
      'http://localhost:8001',
      'https://u:p@host',
      'https://host/path',
      'https://host?q=x',
      'https://host#x',
    ]) {
      expect(apiAddressError(url), isNotNull);
    }
    expect(apiAddressError('https://192.168.1.50:8443'), isNull);
  });

  test(
    'real contract serialization, auth, query encoding and session revocation',
    () async {
      final fixture = ApiFixture();
      final api = RepLabApi(client: fixture.client);
      addTearDown(api.dispose);
      await api.login(
        'https://localhost:8001',
        ' admin@example.com ',
        'synthetic test password',
      );
      expect(api.signedIn, isTrue);
      expect(api.admin?.name, 'Server Admin');
      final login = fixture.requests.single;
      expect(login.followRedirects, isFalse);
      expect(login.headers.containsKey('Authorization'), isFalse);
      expect(await api.dashboard(), containsPair('total_members', 1));
      await api.members(q: '+1 202 & 555', active: false, offset: 50);
      expect(fixture.requests.last.url.queryParameters, {
        'q': '+1 202 & 555',
        'active': 'false',
        'limit': '50',
        'offset': '50',
      });
      final directory = await api.members();
      final profile = await api.member(directory.items.single.id!);
      expect(profile.number, 'M-0042');
      expect(profile.plan, isNull);
      expect(profile.isActive, isTrue);
      await api.saveSettings('Updated gym', '', '');
      expect((await api.settings())['gym_name'], 'Updated gym');
      await api.changePassword('synthetic current', 'synthetic new password');
      expect(api.signedIn, isFalse);
      expect(api.sessionMessage, contains('Password changed'));
    },
  );

  test(
    'failed credentials never authenticate; protected 401 clears session',
    () async {
      final fixture = ApiFixture()..allowLogin = false;
      final api = RepLabApi(client: fixture.client);
      addTearDown(api.dispose);
      await expectLater(
        api.login('https://localhost:8001', 'admin@example.com', 'synthetic'),
        throwsA(isA<ApiException>()),
      );
      expect(api.signedIn, isFalse);
      fixture.allowLogin = true;
      await api.login(
        'https://localhost:8001',
        'admin@example.com',
        'synthetic',
      );
      fixture.expired = true;
      await expectLater(api.dashboard(), throwsA(isA<ApiException>()));
      expect(api.signedIn, isFalse);
      expect(api.admin, isNull);
    },
  );

  test('offline reads preserve session; uncertain writes never retry automatically', () async {
    final fixture = ApiFixture();
    final api = RepLabApi(client: fixture.client);
    addTearDown(api.dispose);
    await api.login('https://localhost:8001', 'admin@example.com', 'synthetic');
    fixture.failReads = true;
    await expectLater(api.members(), throwsA(isA<ApiException>()));
    expect(api.signedIn, isTrue);
    fixture.failWrites = true;
    final before = fixture.requests.length;
    await expectLater(
      api.addMember({'name': 'Synthetic member'}),
      throwsA(
        isA<ApiException>().having((e) => e.uncertain, 'uncertain', isTrue),
      ),
    );
    expect(fixture.requests.length, before + 1);
    await api.logout();
    expect(api.signedIn, isFalse);
    expect(api.sessionMessage, contains('revocation was not confirmed'));
  });

  test(
    'timeout reports ambiguous writes without leaking transport details',
    () async {
      final fixture = ApiFixture();
      final client = MockClient(
        (request) => request.url.path.endsWith('/login')
            ? fixture.client.get(request.url)
            : Completer<http.Response>().future,
      );
      final api = RepLabApi(
        client: client,
        timeout: const Duration(milliseconds: 10),
      );
      addTearDown(api.dispose);
      await api.login(
        'https://localhost:8001',
        'admin@example.com',
        'synthetic',
      );
      await expectLater(
        api.saveSettings('Synthetic', '', ''),
        throwsA(
          isA<ApiException>().having((e) => e.uncertain, 'uncertain', isTrue),
        ),
      );
    },
  );
}
