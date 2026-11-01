import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/main.dart';
import 'package:gym_management_app/replab_api.dart';

import 'api_fixture.dart';

void main() {
  const device = MethodChannel('plugins.flutter.io/local_auth');

  Future<(ApiFixture, RepLabApi)> signIn(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      device,
      (_) async => true,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        device,
        null,
      ),
    );
    final fixture = ApiFixture();
    final api = RepLabApi(client: fixture.client);
    addTearDown(api.dispose);
    await tester.pumpWidget(GymManagementApp(api: api));
    await tester.pumpAndSettle();
    await enterServerLogin(tester);
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();
    return (fixture, api);
  }

  testWidgets('failed initial reads never invent zero member or admin counts', (
    tester,
  ) async {
    final (fixture, api) = await signIn(tester);
    fixture.failReads = true;
    await tester.tap(find.byKey(const ValueKey('nav-Members')));
    await tester.pumpAndSettle();
    expect(find.text('Member records unavailable'), findsOneWidget);
    expect(find.text('0 of 0 members'), findsNothing);
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nav-Settings')));
    await tester.pumpAndSettle();
    expect(find.text('0 of 3 admin slots used'), findsNothing);
    expect(
      find.text('Admin records unavailable · Maximum 3 admins'),
      findsOneWidget,
    );
    api.clearSession();
  });

  testWidgets(
    'pending writes prevent duplicate submissions and Android back dismissal',
    (tester) async {
      final (fixture, api) = await signIn(tester);
      final completion = Completer<void>();
      fixture.writeBarrier = completion.future;
      await tester.tap(find.byKey(const ValueKey('nav-Members')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('members-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('member-name')),
        'Pending member',
      );
      await tester.enterText(
        find.byKey(const ValueKey('member-phone')),
        '+1 202 555 0103',
      );
      final save = find.byKey(const ValueKey('member-add-save'));
      await tester.tap(save);
      await tester.pump();
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byKey(const ValueKey('member-add-dialog')), findsOneWidget);
      expect(
        fixture.requests
            .where((r) => r.method == 'POST' && r.url.path == '/api/v1/members')
            .length,
        1,
      );
      completion.complete();
      await tester.pumpAndSettle();
      expect(fixture.members.length, 2);
      await tester.tap(find.byKey(const ValueKey('member-details-close')));
      await tester.pumpAndSettle();
      fixture.failWrites = true;
      await tester.tap(find.byKey(const ValueKey('members-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('member-name')),
        'Unconfirmed member',
      );
      await tester.enterText(
        find.byKey(const ValueKey('member-phone')),
        '+1 202 555 0104',
      );
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('The change may have been saved'),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      api.clearSession();
    },
  );

  testWidgets(
    'server login, real totals, searchable members and persisted registration',
    (tester) async {
      final (fixture, api) = await signIn(tester);
      expect(
        find.text('Good Morning, Server Admin').evaluate().isNotEmpty ||
            find.text('Good Afternoon, Server Admin').evaluate().isNotEmpty ||
            find.text('Good Evening, Server Admin').evaluate().isNotEmpty,
        isTrue,
      );
      expect(find.text('1'), findsOneWidget);
      expect(find.text('178'), findsNothing);
      expect(find.text('—'), findsNWidgets(3));
      await tester.tap(find.byKey(const ValueKey('nav-Members')));
      await tester.pumpAndSettle();
      expect(find.text('1 of 1 members'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('member-M-0042')));
      await tester.pumpAndSettle();
      expect(find.text('Saved staff notes'), findsOneWidget);
      expect(find.text('Preview profile · Not a server record.'), findsNothing);
      expect(
        fixture.requests.last.url.path,
        endsWith('/00000000-0000-0000-0000-000000000042'),
      );
      await tester.tap(find.byKey(const ValueKey('member-details-close')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('members-search')),
        'missing',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('No matching members'), findsOneWidget);
      expect(fixture.requests.last.url.queryParameters['q'], 'missing');
      await tester.tap(find.byKey(const ValueKey('members-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('member-name')),
        'New server member',
      );
      await tester.enterText(
        find.byKey(const ValueKey('member-phone')),
        '+1 202 555 0102',
      );
      await tester.tap(find.byKey(const ValueKey('member-add-save')));
      await tester.pumpAndSettle();
      expect(fixture.members.length, 2);
      expect(fixture.members.last['name'], 'New server member');
      expect(find.text('Member saved to the server.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('member-details-close')));
      await tester.pumpAndSettle();
      expect(find.text('2 of 2 members'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nav-Dashboard')));
      await tester.pumpAndSettle();
      expect(find.text('2'), findsOneWidget);
      expect(tester.takeException(), isNull);
      api.clearSession();
    },
  );

  testWidgets(
    'settings save, real admin cap, password change revokes session',
    (tester) async {
      final (fixture, _) = await signIn(tester);
      await tester.tap(find.byKey(const ValueKey('nav-Settings')));
      await tester.pumpAndSettle();
      expect(find.text('1 of 3 admin slots used'), findsOneWidget);
      final edit = find.byKey(const ValueKey('settings-edit-preferences'));
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('settings-gym-name')),
        'Updated server gym',
      );
      await tester.tap(find.byKey(const ValueKey('settings-dialog-save')));
      await tester.pumpAndSettle();
      expect(fixture.settings['gym_name'], 'Updated server gym');
      for (var n = 2; n <= 3; n++) {
        final add = find.byKey(const ValueKey('settings-add-admin'));
        await tester.ensureVisible(add);
        await tester.tap(add);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('settings-admin-name')),
          'Admin $n',
        );
        await tester.enterText(
          find.byKey(const ValueKey('settings-admin-email')),
          'admin$n@example.com',
        );
        await tester.enterText(
          find.byKey(const ValueKey('settings-new-password')),
          'synthetic admin password',
        );
        await tester.enterText(
          find.byKey(const ValueKey('settings-confirm-password')),
          'synthetic admin password',
        );
        await tester.tap(find.byKey(const ValueKey('settings-dialog-save')));
        await tester.pumpAndSettle();
      }
      expect(find.text('3 of 3 admin slots used'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('settings-add-admin')),
            )
            .onPressed,
        isNull,
      );
      final change = find.byKey(const ValueKey('settings-change-password'));
      await tester.ensureVisible(change);
      await tester.tap(change);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('settings-current-password')),
        'synthetic old password',
      );
      await tester.enterText(
        find.byKey(const ValueKey('settings-new-password')),
        'synthetic new password',
      );
      await tester.enterText(
        find.byKey(const ValueKey('settings-confirm-password')),
        'synthetic new password',
      );
      await tester.tap(find.byKey(const ValueKey('settings-dialog-save')));
      await tester.pumpAndSettle();
      expect(find.byType(SplashScreen), findsOneWidget);
      expect(
        find.textContaining('All your sessions were revoked'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('settings-dialog')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'offline refresh keeps old data; revocation closes details and returns to login',
    (tester) async {
      final (fixture, _) = await signIn(tester);
      await tester.tap(find.byKey(const ValueKey('nav-Members')));
      await tester.pumpAndSettle();
      fixture.failReads = true;
      await tester.drag(
        find.byKey(const ValueKey('members-list')),
        const Offset(0, 500),
      );
      await tester.pumpAndSettle();
      expect(find.text('Saved Member'), findsOneWidget);
      expect(find.textContaining('Cannot reach the server'), findsOneWidget);
      fixture.failReads = false;
      fixture.expired = true;
      await tester.tap(find.byKey(const ValueKey('member-M-0042')));
      await tester.pumpAndSettle();
      expect(find.byType(SplashScreen), findsOneWidget);
      expect(find.textContaining('expired or was revoked'), findsOneWidget);
      expect(find.byKey(const ValueKey('member-details')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
