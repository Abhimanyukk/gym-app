import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/main.dart';
import 'package:gym_management_app/replab_api.dart';

import 'api_fixture.dart';
import 'registration_fixture.dart';
import 'reports_fixture.dart';

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
    await tester.tap(find.byKey(const ValueKey('setup-skip-biometrics')));
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
    expect(find.textContaining('Cannot reach the server'), findsOneWidget);
    api.clearSession();
  });

  testWidgets(
    'dashboard refresh wires catalogue plans and Reports collections, preserving unavailable states',
    (tester) async {
      final (fixture, api) = await signIn(tester);
      String? value(String field) => tester
          .widget<Text>(find.byKey(ValueKey('dashboard-value-$field')))
          .data;
      Future<void> refresh() async {
        await tester.drag(
          find.byKey(const PageStorageKey('Dashboard')),
          const Offset(0, 500),
        );
        await tester.pumpAndSettle();
      }

      expect(value('active_plans'), '2');
      expect(value('collections_today_paise'), '₹100.01');
      (fixture.catalog['plans'] as List)[1]['active'] = false;
      fixture.reportResponse = reportsFixture();
      fixture.reportResponse!['highlights']['today'] = {
        'total_paise': 123456,
        'cash_paise': 123456,
        'upi_paise': 0,
        'base_paise': 123456,
        'training_paise': 0,
        'insurance_paise': 0,
        'receipt_count': 1,
      };
      final calls = fixture.requests
          .where((r) => r.url.path == '/api/v1/dashboard/summary')
          .length;
      await refresh();
      expect(value('active_plans'), '1');
      expect(value('collections_today_paise'), '₹1,234.56');
      expect(
        fixture.requests
            .where((r) => r.url.path == '/api/v1/dashboard/summary')
            .length,
        calls + 1,
      );
      fixture.failReads = true;
      await refresh();
      expect(value('active_plans'), '1');
      expect(value('collections_today_paise'), '₹1,234.56');
      expect(find.textContaining('Previously loaded totals'), findsOneWidget);
      fixture.failReads = false;
      fixture.dashboardResponse = {
        'total_members': 2,
        'active_member_records': 2,
        'present_today': null,
        'active_plans': null,
        'revenue_today': null,
      };
      await refresh();
      expect(value('active_plans'), '—');
      expect(value('collections_today_paise'), '—');
      expect(
        find.textContaining('Update the gym server to 0.6.1'),
        findsOneWidget,
      );
      fixture.dashboardResponse!['active_plans'] = 0;
      fixture.dashboardResponse!['collections_today_paise'] = 0;
      await refresh();
      expect(value('active_plans'), '0');
      expect(value('collections_today_paise'), '₹0');
      expect(value('present_today'), '—');
      expect(tester.takeException(), isNull);
      api.clearSession();
    },
  );

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
      await advanceRegistrationToPayment(tester);
      await tester.tap(save);
      await tester.pump();
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byKey(const ValueKey('member-add-dialog')), findsOneWidget);
      expect(
        fixture.requests
            .where(
              (r) =>
                  r.method == 'POST' && r.url.path == '/api/v1/members/enroll',
            )
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
      await advanceRegistrationToPayment(tester);
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
      expect(find.text('—'), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('dashboard-value-active_plans')),
            )
            .data,
        '2',
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(
                const ValueKey('dashboard-value-collections_today_paise'),
              ),
            )
            .data,
        '₹100.01',
      );
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
      await advanceRegistrationToPayment(tester);
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
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('dashboard-value-total_members')),
            )
            .data,
        '2',
      );
      expect(tester.takeException(), isNull);
      api.clearSession();
    },
  );

  testWidgets('settings save and password change revokes session', (
    tester,
  ) async {
    final (fixture, _) = await signIn(tester);
    await tester.tap(find.byKey(const ValueKey('nav-Settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-add-admin')), findsNothing);
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
  });

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
