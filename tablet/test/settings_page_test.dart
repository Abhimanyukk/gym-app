import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gym_management_app/dashboard_screen.dart';
import 'package:gym_management_app/device_session.dart';
import 'package:gym_management_app/main.dart';
import 'package:gym_management_app/replab_api.dart';

import 'api_fixture.dart';

Future<void> openSettings(WidgetTester tester, {bool preview = true}) async {
  await tester.pumpWidget(
    GymManagementApp(home: DashboardScreen(showSampleData: preview)),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('nav-Settings')));
  await tester.pumpAndSettle();
}

Future<void> tapSetting(WidgetTester tester, String key) async {
  final button = find.byKey(ValueKey(key));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> enterSetting(WidgetTester tester, String key, String value) async {
  final field = find.byKey(ValueKey(key));
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('settings shows amber warnings only, not a Connected ribbon', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1024, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = ApiFixture();
    final api = RepLabApi(client: fixture.client);
    await api.login('https://localhost:8443', 'synthetic');
    await tester.pumpWidget(GymManagementApp(home: DashboardScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-Settings')));
    await tester.pumpAndSettle();
    final notice = find.byKey(const ValueKey('settings-notice'));
    expect(notice, findsNothing);
    expect(
      find.textContaining('Connected · Single-administrator'),
      findsNothing,
    );
    fixture.failReads = true;
    await tester.drag(
      find.byKey(const PageStorageKey('settings-scroll')),
      const Offset(0, 500),
    );
    await tester.pumpAndSettle();
    expect(notice, findsOneWidget);
    expect(
      find.descendant(
        of: notice,
        matching: find.byIcon(Icons.warning_amber_rounded),
      ),
      findsOneWidget,
    );
    final warning = tester.widget<Container>(
      find.descendant(of: notice, matching: find.byType(Container)).first,
    );
    expect((warning.decoration as BoxDecoration).color, Colors.amber.shade50);
    expect(find.textContaining('Cannot reach the server'), findsOneWidget);
    fixture.failReads = false;
    await tester.tap(find.text('Retry settings'));
    await tester.pumpAndSettle();
    expect(notice, findsNothing);
    api.clearSession();
    await tester.pumpWidget(const SizedBox.shrink());
    api.dispose();
    await openSettings(tester, preview: false);
    expect(
      find.descendant(
        of: notice,
        matching: find.byIcon(Icons.warning_amber_rounded),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Backend not connected'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'advanced settings survives navigation with independent scroll and expansion state',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await openSettings(tester);
      final scroll = find.byKey(const PageStorageKey('settings-scroll'));
      final title = find.byKey(const ValueKey('settings-title'));
      final titleRect = tester.getRect(title);
      ScrollPosition position() => tester
          .state<ScrollableState>(
            find
                .descendant(of: scroll, matching: find.byType(Scrollable))
                .first,
          )
          .position;
      Future<void> revisit(String section) async {
        final offset = position().pixels;
        expect(offset, greaterThan(0));
        await tester.tap(find.byKey(ValueKey('nav-$section')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('nav-Settings')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(ErrorWidget), findsNothing);
        expect(find.byType(ExpansionTile), findsOneWidget);
        expect(position().pixels, closeTo(offset, .01));
        expect(tester.getRect(title), titleRect);
      }

      await tester.drag(scroll, const Offset(0, -300));
      await tester.pumpAndSettle();
      await revisit('Dashboard');
      expect(
        find.byKey(const ValueKey('settings-change-server')),
        findsNothing,
      );

      await tapSetting(tester, 'settings-advanced');
      await tester.ensureVisible(
        find.byKey(const ValueKey('settings-change-server')),
      );
      await tester.pumpAndSettle();
      await revisit('Attendance');
      expect(
        find.byKey(const ValueKey('settings-change-server')),
        findsOneWidget,
      );
      await tapSetting(tester, 'settings-change-server');
      expect(find.byKey(const ValueKey('settings-dialog')), findsOneWidget);
      await tapSetting(tester, 'settings-dialog-cancel');

      await tapSetting(tester, 'settings-advanced');
      await revisit('Members');
      expect(
        find.byKey(const ValueKey('settings-change-server')),
        findsNothing,
      );
      await tapSetting(tester, 'settings-advanced');
      expect(
        find.byKey(const ValueKey('settings-change-server')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'server changes verify independently and preserve the old connection on failure',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final oldServer = ApiFixture();
      final newServer = ApiFixture(
        sessionToken: 'synthetic-new-server-session',
      );
      final api = RepLabApi(
        client: MockClient((request) async {
          final server = request.url.host == 'localhost'
              ? oldServer
              : newServer;
          final copy = http.Request(request.method, request.url)
            ..headers.addAll(request.headers)
            ..bodyBytes = request.bodyBytes;
          return http.Response.fromStream(await server.client.send(copy));
        }),
      );
      String? stored;
      var storageFails = false;
      final device = DeviceSession(
        read: () async => stored,
        write: (value) async {
          if (storageFails) throw StateError('Synthetic storage failure');
          stored = value;
        },
      );
      await api.login('https://localhost:8443', 'synthetic');
      await device.save(
        host: 'localhost',
        token: api.sessionKey,
        biometrics: false,
      );
      await tester.pumpWidget(GymManagementApp(api: api, device: device));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-Settings')));
      await tester.pumpAndSettle();
      await tapSetting(tester, 'settings-advanced');
      await tapSetting(tester, 'settings-change-server');
      await enterSetting(tester, 'server-hostname', 'lovin.local');
      await enterSetting(tester, 'settings-server-password', 'synthetic');
      newServer.allowLogin = false;
      await tapSetting(tester, 'settings-dialog-save');
      expect(find.text('Server password is incorrect.'), findsOneWidget);
      expect(api.baseUrl, 'https://localhost:8443');
      expect(device.host, 'localhost');
      newServer.allowLogin = true;
      storageFails = true;
      await tapSetting(tester, 'settings-dialog-save');
      expect(api.baseUrl, 'https://localhost:8443');
      expect(device.token, oldServer.sessionToken);
      expect(jsonDecode(stored!)['host'], 'localhost');
      storageFails = false;
      await tapSetting(tester, 'settings-dialog-save');
      expect(api.baseUrl, 'https://lovin.local:8443');
      expect(device.host, 'lovin.local');
      expect(jsonDecode(stored!)['token'], newServer.sessionToken);
      expect(
        newServer.requests.every(
          (r) =>
              !r.headers.values.any((v) => v.contains(oldServer.sessionToken)),
        ),
        true,
      );
      await api.dashboard();
      expect(
        newServer.requests.last.headers['Authorization'],
        'Bearer ${newServer.sessionToken}',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      api.dispose();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('single admin, advanced connection separated from gym details', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await openSettings(tester);
    expect(find.byKey(const ValueKey('settings-add-admin')), findsNothing);
    await tapSetting(tester, 'settings-edit-preferences');
    expect(find.byKey(const ValueKey('settings-server-url')), findsNothing);
    await enterSetting(tester, 'settings-gym-name', '');
    await tapSetting(tester, 'settings-dialog-save');
    expect(find.text('Enter the gym name'), findsOneWidget);
    await enterSetting(tester, 'settings-gym-name', 'Preview Gym');
    await tapSetting(tester, 'settings-dialog-save');
    expect(find.text('Preview Gym'), findsOneWidget);
    await tapSetting(tester, 'settings-advanced');
    await tapSetting(tester, 'settings-change-server');
    expect(find.byKey(const ValueKey('server-ip-0')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('settings-dialog-save')),
          )
          .onPressed,
      isNull,
    );
    await tapSetting(tester, 'settings-dialog-cancel');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'password validation clears secrets; normal preview cannot change passwords',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await openSettings(tester);
      await tapSetting(tester, 'settings-change-password');
      await tapSetting(tester, 'settings-dialog-save');
      expect(find.text('Enter the current password'), findsOneWidget);
      await enterSetting(
        tester,
        'settings-current-password',
        'synthetic current password',
      );
      await enterSetting(
        tester,
        'settings-new-password',
        'synthetic changed password',
      );
      await enterSetting(
        tester,
        'settings-confirm-password',
        'synthetic changed password',
      );
      final controller = tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('settings-new-password')),
          )
          .controller!;
      await tapSetting(tester, 'settings-dialog-save');
      expect(controller.text, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await openSettings(tester, preview: false);
      await tapSetting(tester, 'settings-change-password');
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('settings-dialog-save')),
            )
            .onPressed,
        isNull,
      );
      await tapSetting(tester, 'settings-dialog-cancel');
    },
  );
  testWidgets(
    'settings stays sticky and dialogs adapt to tablets, keyboard and enlarged text',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.view.resetViewInsets);
      for (final (size, scale, keyboard) in const [
        (Size(1024, 768), 1.0, 0.0),
        (Size(800, 600), 2.0, 0.0),
        (Size(360, 740), 1.0, 0.0),
        (Size(1024, 768), 1.0, 300.0),
      ]) {
        await tester.binding.setSurfaceSize(size);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        tester.view.viewInsets = FakeViewPadding(
          bottom: keyboard * tester.view.devicePixelRatio,
        );
        await openSettings(tester);
        final title = find.byKey(const ValueKey('settings-title'));
        final rect = tester.getRect(title);
        await tester.drag(
          find.byKey(const PageStorageKey('settings-scroll')),
          const Offset(0, -400),
        );
        await tester.pumpAndSettle();
        expect(tester.getRect(title), rect);
        for (final key in [
          'settings-change-password',
          'settings-edit-preferences',
        ]) {
          await tapSetting(tester, key);
          await tapSetting(tester, 'settings-dialog-cancel');
          expect(tester.getRect(title), rect);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
}
