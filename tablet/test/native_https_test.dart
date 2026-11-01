import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/replab_api.dart';

void main() {
  const url = String.fromEnvironment('LIVE_TEST_API_URL');
  TestWidgetsFlutterBinding.ensureInitialized();
  final overrides = HttpOverrides.current;
  setUp(() {
    if (url.isNotEmpty) HttpOverrides.global = null;
  });
  tearDown(() => HttpOverrides.global = overrides);
  test(
    'native HTTPS transport talks to an isolated Rust/PostgreSQL API',
    () async {
      expect(
        url,
        'https://localhost:9443',
        reason: 'Never point integration tests at the deployment API.',
      );
      final api = RepLabApi();
      addTearDown(api.dispose);
      await expectLater(
        api.login(
          url,
          'not-registered@example.com',
          'synthetic transport test password',
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'invalid_credentials',
          ),
        ),
      );
      final ready = await api.request(
        'GET',
        '/health/ready',
        authenticated: false,
      );
      expect(ready, containsPair('database', 'ok'));
      expect(ready, containsPair('schema', '1'));
      expect(api.signedIn, isFalse);
    },
    skip: url.isEmpty
        ? 'Set LIVE_TEST_API_URL to an isolated test server.'
        : false,
  );

  test(
    'native client authenticates and persists through the real Rust/PostgreSQL API',
    () async {
      expect(
        url,
        'https://localhost:9443',
        reason: 'Use only the isolated replab_test fixture.',
      );
      final api = RepLabApi();
      addTearDown(api.dispose);
      const current = 'synthetic tablet integration password';
      const next = 'synthetic changed integration password';
      await api.login(url, 'tablet-test@example.com', current);
      expect(api.admin?.name, 'Tablet Test Admin');
      final before = await api.members();
      final saved = await api.addMember({
        'name': 'Synthetic tablet member',
        'phone': '+1 202 555 0100',
        'email': 'tablet-member@example.com',
        'address': 'Test address',
        'emergency_phone': '',
        'notes': 'Synthetic transport fixture only',
      });
      expect(saved.id, isNotNull);
      expect(saved.number, startsWith('M-'));
      expect((await api.members()).total, before.total + 1);
      expect(
        (await api.member(saved.id!)).notes,
        'Synthetic transport fixture only',
      );
      expect((await api.members(q: saved.number)).items.single.id, saved.id);
      expect((await api.dashboard())['total_members'], before.total + 1);
      await api.saveSettings(
        'Synthetic tablet gym',
        '+1 202 555 0100',
        'Test address',
      );
      expect((await api.settings())['gym_name'], 'Synthetic tablet gym');
      await api.addAdmin(
        'Synthetic admin 2',
        'tablet-admin2@example.com',
        current,
      );
      await api.addAdmin(
        'Synthetic admin 3',
        'tablet-admin3@example.com',
        current,
      );
      expect((await api.admins()).length, 3);
      await expectLater(
        api.addAdmin('Synthetic admin 4', 'tablet-admin4@example.com', current),
        throwsA(isA<ApiException>()),
      );
      await api.changePassword(current, next);
      expect(api.signedIn, isFalse);
      await api.login(url, 'tablet-test@example.com', next);
      await api.logout();
      expect(api.signedIn, isFalse);
    },
    skip: url.isEmpty
        ? 'Requires the isolated, freshly seeded replab_test fixture.'
        : false,
  );
}
