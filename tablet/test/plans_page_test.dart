import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/main.dart';
import 'package:gym_management_app/dashboard_screen.dart';
import 'package:gym_management_app/member_enrollment.dart';
import 'package:gym_management_app/plans_page.dart';
import 'package:gym_management_app/replab_api.dart';
import 'package:gym_management_app/settings_preview.dart';

import 'api_fixture.dart';
import 'registration_fixture.dart';

Future<void> tapPlanControl(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> enterPlanField(
  WidgetTester tester,
  String key,
  String value,
) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.enterText(finder, value);
  await tester.pumpAndSettle();
}

Future<RepLabApi> openLivePlans(WidgetTester tester, ApiFixture fixture) async {
  final api = RepLabApi(client: fixture.client);
  addTearDown(api.dispose);
  await api.login('https://localhost:8443', 'synthetic');
  await tester.pumpWidget(GymManagementApp(api: api));
  await tester.pumpAndSettle();
  await tapPlanControl(tester, 'nav-Settings');
  await tapPlanControl(tester, 'settings-manage-plans');
  return api;
}

void main() {
  test('currency parsing keeps exact paise and rejects ambiguous money', () {
    expect(parseRupees('1350.50'), 135050);
    expect(parseRupees('0.01'), 1);
    expect(parseRupees('0'), 0);
    expect(parseRupees('10000000.00'), 1000000000);
    for (final value in [
      '-1',
      '1.001',
      '1e3',
      'NaN',
      '10000000.01',
      '',
      '1,200',
    ]) {
      expect(parseRupees(value), isNull, reason: value);
    }
    expect(priceInput(123456), '1234.56');
    expect(planDuration(2), '2 months');
  });

  testWidgets(
    'Settings opens a sticky plan editor; custom pricing reaches registration',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fixture = ApiFixture();
      final api = await openLivePlans(tester, fixture);
      expect(find.byKey(const ValueKey('sidebar')), findsOneWidget);
      expect(find.byKey(const ValueKey('nav-Plans')), findsNothing);
      final title = find.byKey(const ValueKey('plans-title'));
      final titleRect = tester.getRect(title);

      await tapPlanControl(tester, 'plans-edit-silver');
      await enterPlanField(tester, 'plan-name', 'Strength Flex');
      await enterPlanField(tester, 'plan-price-0', '1350.50');
      await tapPlanControl(tester, 'plan-apply');
      await tapPlanControl(tester, 'plans-archive-gold');

      await tapPlanControl(tester, 'plans-add');
      await enterPlanField(tester, 'plan-name', 'Weekend Plan');
      await enterPlanField(tester, 'plan-description', 'Custom access');
      await enterPlanField(tester, 'plan-duration-0', '2');
      await enterPlanField(tester, 'plan-price-0', '2500.25');
      await tapPlanControl(tester, 'plan-add-duration');
      await enterPlanField(tester, 'plan-duration-1', '2');
      await enterPlanField(tester, 'plan-price-1', '6000');
      await tapPlanControl(tester, 'plan-apply');
      expect(find.text('Duration already added'), findsNWidgets(2));
      await enterPlanField(tester, 'plan-duration-1', '5');
      await tapPlanControl(tester, 'plan-apply');
      await enterPlanField(tester, 'plans-training-price', '4000.75');
      await enterPlanField(tester, 'plans-insurance-price', '250.10');
      expect(tester.getRect(title), titleRect);
      expect(
        fixture.catalog['revision'],
        1,
      ); // Applying dialogs edits only a draft.
      await tapPlanControl(tester, 'plans-save');
      expect(fixture.catalog['revision'], 2);
      final plans = fixture.catalog['plans'] as List;
      final custom =
          plans.singleWhere((plan) => plan['name'] == 'Weekend Plan') as Map;
      expect(custom['prices_paise'], {'2': 250025, '5': 600000});
      expect(plans.first['prices_paise']['1'], 135050);
      expect(plans[1]['active'], false);
      expect(fixture.catalog['training_monthly_paise'], 400075);
      expect(fixture.catalog['insurance_monthly_paise'], 25010);
      final saved = jsonDecode(
        fixture.requests
            .singleWhere(
              (request) =>
                  request.method == 'PUT' &&
                  request.url.path == '/api/v1/plans',
            )
            .body,
      ) as Map;
      expect(saved.containsKey('upi_id'), false);
      expect(saved.containsKey('payee_name'), false);

      await tapPlanControl(tester, 'plans-back');
      expect(find.byKey(const ValueKey('settings-title')), findsOneWidget);
      await tapPlanControl(tester, 'nav-Members');
      await tapPlanControl(tester, 'members-add');
      await enterPlanField(tester, 'member-name', 'Custom member');
      await enterPlanField(tester, 'member-phone', '+91 9876543210');
      await fillRequiredMemberDetails(tester);
      await tapPlanControl(tester, 'member-add-next');
      await installRegistrationCamera(tester);
      await tapPlanControl(tester, 'member-take-photo');
      await tester.tap(find.byKey(const ValueKey('member-camera-capture')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      await tapPlanControl(tester, 'member-add-next');
      expect(find.byKey(const ValueKey('member-plan-gold')), findsNothing);
      await tapPlanControl(tester, 'member-plan-${custom['code']}');
      expect(
        tester
            .widget<DropdownButtonFormField<int>>(
              find.byKey(const ValueKey('member-plan-months')),
            )
            .initialValue,
        2,
      );
      for (final (key, text) in [
        ('member-training-months', '1 month · ₹4,000.75'),
        ('member-insurance-months', '2 months · ₹500.20'),
      ]) {
        final finder = find.byKey(ValueKey(key));
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pumpAndSettle();
        await tester.tap(find.text(text).last);
        await tester.pumpAndSettle();
      }
      await tapPlanControl(tester, 'member-add-next');
      expect(find.text('Full payment: ₹7,001.20'), findsOneWidget);
      await tapPlanControl(tester, 'member-payment-confirm');
      await tapPlanControl(tester, 'member-add-save');
      expect(
        fixture.enrollments.values.single['enrollment']['total_paise'],
        700120,
      );
      final registration = jsonDecode(
        fixture.requests
            .singleWhere((r) => r.url.path == '/api/v1/members/enroll')
            .body,
      ) as Map;
      expect(registration['catalog_revision'], 2);
      expect(tester.takeException(), isNull);
      api.clearSession();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'pending saves are guarded; conflicts and uncertain results require reload',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fixture = ApiFixture();
      final api = await openLivePlans(tester, fixture);
      await tapPlanControl(tester, 'plans-edit-silver');
      await enterPlanField(tester, 'plan-name', 'Changed plan');
      await tapPlanControl(tester, 'plan-apply');
      final completion = Completer<void>();
      fixture.writeBarrier = completion.future;
      await tester.tap(find.byKey(const ValueKey('plans-save')));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('plans-save')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const ValueKey('plans-add')))
            .onPressed,
        isNull,
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byKey(const ValueKey('plans-page')), findsOneWidget);
      completion.complete();
      await tester.pumpAndSettle();
      fixture.writeBarrier = null;
      expect(fixture.catalog['revision'], 2);

      await tapPlanControl(tester, 'plans-edit-silver');
      await enterPlanField(tester, 'plan-name', 'Stale draft');
      await tapPlanControl(tester, 'plan-apply');
      fixture.catalog['revision'] = 3;
      await tapPlanControl(tester, 'plans-save');
      expect(
        find.textContaining('Plans were changed elsewhere'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('plans-save')))
            .onPressed,
        isNull,
      );
      await tapPlanControl(tester, 'plans-reload');
      await tapPlanControl(tester, 'plans-discard');
      expect(find.text('Changed plan'), findsOneWidget);
      expect(find.text('Stale draft'), findsNothing);

      await tapPlanControl(tester, 'plans-edit-silver');
      await enterPlanField(tester, 'plan-name', 'Unconfirmed draft');
      await tapPlanControl(tester, 'plan-apply');
      fixture.failWrites = true;
      await tapPlanControl(tester, 'plans-save');
      expect(
        find.textContaining('The change may have been saved'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const ValueKey('plans-add')))
            .onPressed,
        isNull,
      );
      fixture.failWrites = false;
      await tapPlanControl(tester, 'plans-reload');
      await tapPlanControl(tester, 'plans-discard');
      expect(find.text('Changed plan'), findsOneWidget);
      expect(fixture.catalog['revision'], 3);
      expect(tester.takeException(), isNull);
      api.clearSession();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('drafts warn on exit; offline plans never show sample prices', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1024, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      GymManagementApp(home: DashboardScreen(showSampleData: true)),
    );
    await tester.pumpAndSettle();
    await tapPlanControl(tester, 'nav-Settings');
    await tapPlanControl(tester, 'settings-manage-plans');
    await tapPlanControl(tester, 'plans-edit-silver');
    await enterPlanField(tester, 'plan-name', 'Preview draft');
    await tapPlanControl(tester, 'plan-apply');
    await tapPlanControl(tester, 'plans-back');
    expect(find.text('Discard your draft?'), findsOneWidget);
    await tapPlanControl(tester, 'plans-discard');
    expect(find.byKey(const ValueKey('settings-title')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      GymManagementApp(
        home: Scaffold(
          body: PlansPage(preview: SettingsPreview(), onClose: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Silver Plan'), findsNothing);
    expect(find.textContaining('Backend not connected'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('plans-add')))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('plan editor fits narrow, large-text and keyboard layouts', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.resetViewInsets);
    for (final (size, scale, keyboard) in [
      (const Size(360, 740), 1.0, 0.0),
      (const Size(800, 600), 2.0, 0.0),
      (const Size(1024, 768), 1.0, 300.0),
    ]) {
      await tester.binding.setSurfaceSize(size);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      tester.view.viewInsets = FakeViewPadding(
        bottom: keyboard * tester.view.devicePixelRatio,
      );
      await tester.pumpWidget(
        GymManagementApp(
          home: Scaffold(
            body: PlansPage(
              preview: SettingsPreview(enabled: true),
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tapPlanControl(tester, 'plans-add');
      await enterPlanField(tester, 'plan-name', 'Layout plan');
      await enterPlanField(tester, 'plan-price-0', '1200');
      await tapPlanControl(tester, 'plan-add-duration');
      await tapPlanControl(tester, 'plan-remove-duration-1');
      await tapPlanControl(tester, 'plan-apply');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
