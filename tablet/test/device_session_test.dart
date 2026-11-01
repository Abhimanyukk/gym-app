import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/dashboard_screen.dart';
import 'package:gym_management_app/device_session.dart';
import 'package:gym_management_app/main.dart';
import 'package:gym_management_app/replab_api.dart';

import 'api_fixture.dart';

void main() {
  test('the server port is fixed, independent of build configuration', () {
    expect(serverPort, 8443);
    expect(serverUrl('lovin.local'), 'https://lovin.local:8443');
    expect(serverUrl('192.168.31.239'), 'https://192.168.31.239:8443');
    expect(apiAddressError('https://lovin.local:8001'), isNotNull);
    expect(apiAddressError('https://lovin.local'), isNotNull);
  });
  test('host-only validation rejects URLs, ports, malformed IPs and saved passwords', () async {
    for (final host in ['192.168.31.239', 'lovin', 'lovin.local']) {
      expect(serverHostError(host), isNull);
    }
    for (final host in [
      '',
      'https://lovin',
      'lovin:8443',
      '256.2.3.4',
      '1.2.3',
      '01.2.3.4',
      'u:p@lovin',
      'lovin/path',
    ]) {
      expect(serverHostError(host), isNotNull);
    }
    String? stored;
    final device = DeviceSession(
      read: () async => stored,
      write: (value) async => stored = value,
    );
    await device.save(
      host: 'lovin.local',
      token: 'synthetic-key',
      biometrics: false,
    );
    expect(jsonDecode(stored!), {
      'host': 'lovin.local',
      'token': 'synthetic-key',
      'biometrics': false,
    });
    final restored = DeviceSession(read: () async => stored);
    await restored.load();
    expect(restored.host, 'lovin.local');
    expect(restored.token, 'synthetic-key');
  });

  test(
    'a failed persistence write keeps the previous device connection',
    () async {
      final device = DeviceSession(
        read: () async => null,
        write: (_) async => throw StateError('Synthetic full storage'),
      );
      device.host = 'old.local';
      device.token = 'old-key';
      await expectLater(
        device.save(host: 'new.local', token: 'new-key', biometrics: false),
        throwsStateError,
      );
      expect(device.host, 'old.local');
      expect(device.token, 'old-key');
    },
  );

  for (final biometric in [false, true]) {
    testWidgets(
      'setup remembers the session; restart ${biometric ? 'requires biometrics' : 'opens dashboard without password'}',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        String? stored;
        DeviceSession device() => DeviceSession(
          read: () async => stored,
          write: (value) async {
            stored = value;
          },
        );
        const channel = MethodChannel('plugins.flutter.io/local_auth');
        var unlock = true;
        var calls = 0;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            expect(call.arguments['biometricOnly'], true);
            calls++;
            return unlock;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        final fixture = ApiFixture();
        final first = RepLabApi(client: fixture.client);
        await tester.pumpWidget(GymManagementApp(api: first, device: device()));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('server-ip-0')), findsOneWidget);
        expect(find.byKey(const ValueKey('login-email')), findsNothing);
        await enterServerLogin(tester);
        await tester.tap(find.text('Login'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            ValueKey(
              biometric ? 'setup-enable-biometrics' : 'setup-skip-biometrics',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(DashboardScreen), findsOneWidget);
        expect(stored, isNot(contains('synthetic test password')));
        expect(jsonDecode(stored!)['biometrics'], biometric);
        await tester.pumpWidget(const SizedBox.shrink());
        first.dispose();
        fixture.requests.clear();
        unlock = !biometric;
        final restarted = RepLabApi(client: fixture.client);
        final restoredDevice = device();
        await tester.pumpWidget(
          GymManagementApp(api: restarted, device: restoredDevice),
        );
        await tester.pumpAndSettle();
        if (biometric) {
          expect(find.byType(DashboardScreen), findsNothing);
          expect(fixture.requests, isEmpty);
          unlock = true;
          await tester.tap(find.text('Unlock & connect'));
          await tester.pumpAndSettle();
          expect(calls, 3); // Enable, denied restart, successful retry.
        } else {
          expect(calls, 0);
        }
        expect(find.byType(DashboardScreen), findsOneWidget);
        expect(find.byKey(const ValueKey('login-password')), findsNothing);
        expect(
          fixture.requests.where((r) => r.url.path.endsWith('/login')),
          isEmpty,
        );
        expect(
          fixture.requests.any((r) => r.url.path.endsWith('/resume')),
          true,
        );
        if (biometric) {
          unlock = false;
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          expect(restarted.signedIn, false);
          expect(restoredDevice.token, 'synthetic-session-token');
          expect(jsonDecode(stored!)['token'], 'synthetic-session-token');
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pumpAndSettle();
          expect(find.byType(DashboardScreen), findsNothing);
          unlock = true;
          await tester.tap(find.text('Unlock & connect'));
          await tester.pumpAndSettle();
          expect(find.byType(DashboardScreen), findsOneWidget);
        }
        fixture.expired = true;
        await restarted.dashboard().catchError((_) => <String, dynamic>{});
        await tester.pumpAndSettle();
        expect(find.byType(SplashScreen), findsOneWidget);
        expect(find.byKey(const ValueKey('setup-next')), findsNothing);
        expect(find.byKey(const ValueKey('login-password')), findsOneWidget);
        expect(restoredDevice.token, isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        restarted.dispose();
      },
    );
  }
  testWidgets('storage failure cannot bypass initial enrollment', (
    tester,
  ) async {
    final fixture = ApiFixture();
    final api = RepLabApi(client: fixture.client);
    final device = DeviceSession(
      read: () async => null,
      write: (_) async => throw StateError('Synthetic unavailable storage'),
    );
    await tester.pumpWidget(GymManagementApp(api: api, device: device));
    await tester.pumpAndSettle();
    await enterServerLogin(tester);
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('setup-skip-biometrics')));
    await tester.pumpAndSettle();
    expect(api.signedIn, false);
    expect(device.token, isNull);
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpAndSettle();
    expect(find.byType(DashboardScreen), findsNothing);
    expect(
      find.textContaining('Could not save the device session'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    api.dispose();
  });
  testWidgets(
    'offline resume keeps the saved session and does not bypass server authentication',
    (tester) async {
      final fixture = ApiFixture()..failReads = true;
      final api = RepLabApi(client: fixture.client);
      final device = DeviceSession(
        read: () async => jsonEncode({
          'host': 'lovin.local',
          'token': 'synthetic-session-token',
          'biometrics': false,
        }),
      );
      // Make the resume request fail too, not merely the dashboard's initial read.
      fixture.failWrites = true;
      await tester.pumpWidget(GymManagementApp(api: api, device: device));
      await tester.pumpAndSettle();
      expect(find.byType(DashboardScreen), findsNothing);
      expect(device.token, 'synthetic-session-token');
      expect(find.text('Unlock & connect'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      api.dispose();
    },
  );
}
