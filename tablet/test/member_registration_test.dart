import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/main.dart';
import 'package:gym_management_app/member_enrollment.dart';
import 'package:gym_management_app/member_profile.dart';
import 'package:gym_management_app/member_registration_dialog.dart';
import 'package:gym_management_app/replab_api.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'api_fixture.dart';
import 'registration_fixture.dart';

void main() {
  test('exact prices, add-on totals, inclusive dates and UPI payload', () {
    final options = EnrollmentOptions.fromJson(EnrollmentOptions.previewData);
    expect(options.plans[0].prices, {
      1: 120000,
      3: 320000,
      6: 600000,
      12: 1200000,
    });
    expect(options.plans[1].prices, {
      1: 170000,
      3: 470000,
      6: 900000,
      12: 1800000,
    });
    expect(rupees(1010000), '₹10,100');
    expect(rupees(12345678), '₹1,23,456.78');
    for (final (start, months, end) in [
      ('2026-11-02', 1, '2026-12-01'),
      ('2026-01-31', 1, '2026-02-27'),
      ('2024-02-29', 12, '2025-02-27'),
    ]) {
      expect(isoDate(enrollmentEnd(DateTime.parse(start), months)), end);
    }
    final uri = Uri.parse(upiPaymentUri(options, 1010000, 'test-registration'));
    expect(uri.scheme, 'upi');
    expect(uri.host, 'pay');
    expect(uri.queryParameters, {
      'pa': '8943521009@yescred',
      'pn': 'RepLab Fitness',
      'am': '10100.00',
      'cu': 'INR',
      'tn': 'Gym membership',
      'tr': 'test-registration',
    });
  });

  Future<void> choose(WidgetTester tester, String key, String text) async {
    final field = find.byKey(ValueKey(key));
    await tester.ensureVisible(field);
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> open(
    WidgetTester tester, {
    RepLabApi? api,
    bool camera = false,
  }) async {
    final photo = await tester.runAsync(registrationPhoto);
    await tester.pumpWidget(
      GymManagementApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showDialog<MemberProfile>(
                context: context,
                barrierDismissible: false,
                builder: (_) => camera
                    ? MemberRegistrationDialog(
                        members: const [],
                        canSave: true,
                        api: api,
                      )
                    : MemberRegistrationDialog(
                        members: const [],
                        canSave: true,
                        api: api,
                        capturePhoto: (_) async => photo,
                      ),
              ),
              child: const Text('Open registration'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open registration'));
    await tester.pumpAndSettle();
  }

  Future<void> basic(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const ValueKey('member-name')),
      'Test member',
    );
    await tester.enterText(
      find.byKey(const ValueKey('member-phone')),
      '+91 9876543210',
    );
    await fillRequiredMemberDetails(tester);
    await tap(tester, 'member-add-next');
  }

  testWidgets(
    'mandatory steps, independent add-ons, amount QR and manual full payment',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fixture = ApiFixture();
      final api = RepLabApi(client: fixture.client);
      addTearDown(api.dispose);
      await api.login('https://localhost:8443', 'synthetic');
      await open(tester, api: api);
      await basic(tester);
      await tap(tester, 'member-add-next');
      expect(find.text('Take a member photo to continue.'), findsOneWidget);
      await tap(tester, 'member-take-photo');
      expect(
        find.byKey(const ValueKey('member-photo-preview')),
        findsOneWidget,
      );
      await tap(tester, 'member-add-next');
      await tap(tester, 'member-add-next');
      expect(find.text('Select a plan to continue.'), findsOneWidget);
      await tap(tester, 'member-plan-gold');
      await choose(tester, 'member-plan-months', 'Quarterly · 3 months');
      await choose(tester, 'member-training-months', '1 month · ₹5,000');
      await choose(tester, 'member-insurance-months', '2 months · ₹400');
      await tap(tester, 'member-add-next');
      expect(find.text('Full payment: ₹10,100'), findsOneWidget);
      final save = find.byKey(const ValueKey('member-add-save'));
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      expect(
        fixture.requests.where((r) => r.url.path == '/api/v1/members/enroll'),
        isEmpty,
      );
      await tester.ensureVisible(find.text('UPI'));
      await tester.tap(find.text('UPI'));
      await tester.pumpAndSettle();
      final qr = tester.widget<QrImageView>(
        find.byKey(const ValueKey('member-upi-qr')),
      );
      expect(qr.size, 220);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label ==
                  'UPI payment QR for ₹10,100 to RepLab Fitness',
        ),
        findsOneWidget,
      );
      await tap(tester, 'member-payment-confirm');
      await tap(tester, 'member-add-back');
      await choose(tester, 'member-plan-months', 'Monthly · 1 month');
      expect(
        tester
            .widget<DropdownButton<int>>(
              find.byKey(const ValueKey('member-insurance-months')),
            )
            .value,
        1,
      );
      await tap(tester, 'member-add-next');
      expect(find.text('Full payment: ₹6,900'), findsOneWidget);
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      final updated = tester.widget<QrImageView>(
        find.byKey(const ValueKey('member-upi-qr')),
      );
      expect(updated, isNot(same(qr)));
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label ==
                  'UPI payment QR for ₹6,900 to RepLab Fitness',
        ),
        findsOneWidget,
      );
      await tap(tester, 'member-payment-confirm');
      await tap(tester, 'member-add-save');
      expect(find.byKey(const ValueKey('member-add-dialog')), findsNothing);
      expect(fixture.enrollments, hasLength(1));
      final submitted = jsonDecode(
        fixture.requests
            .singleWhere((r) => r.url.path == '/api/v1/members/enroll')
            .body,
      ) as Map;
      expect(submitted['payment_confirmed'], true);
      expect(submitted.containsKey('total_paise'), false);
      expect(submitted['insurance_months'], 1);
      expect(submitted['photo_base64'], isNotEmpty);
      api.clearSession();
    },
  );

  testWidgets(
    'camera denial is recoverable and preview never exposes a real payment QR',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final camera = await installRegistrationCamera(
        tester,
        width: 300,
        height: 1800,
      );
      camera.denied = true;
      await open(tester, camera: true);
      await basic(tester);
      await tap(tester, 'member-take-photo');
      expect(find.textContaining('Camera unavailable'), findsOneWidget);
      await tester.tap(find.text('Cancel camera'));
      await tester.pumpAndSettle();
      await tap(tester, 'member-add-next');
      expect(find.text('Take a member photo to continue.'), findsOneWidget);
      camera.denied = false;
      await tap(tester, 'member-take-photo');
      await tester.tap(find.byKey(const ValueKey('member-camera-capture')));
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      final preview = tester.widget<Image>(
        find.byKey(const ValueKey('member-photo-preview')),
      );
      final dimensions = await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(
          (preview.image as MemoryImage).bytes,
        );
        final frame = await codec.getNextFrame();
        final dimensions = (frame.image.width, frame.image.height);
        frame.image.dispose();
        codec.dispose();
        return dimensions;
      });
      expect(dimensions, (85, 512));
      await tap(tester, 'member-add-next');
      await tap(tester, 'member-plan-silver');
      await tap(tester, 'member-add-next');
      await tester.tap(find.text('UPI'));
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsNothing);
      expect(find.textContaining('payment QR disabled'), findsOneWidget);
      expect(camera.captures, 1);
    },
  );

  testWidgets('uncertain registration retries preserve one exact request ID', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = ApiFixture();
    final api = RepLabApi(client: fixture.client);
    addTearDown(api.dispose);
    await api.login('https://localhost:8443', 'synthetic');
    await open(tester, api: api);
    await basic(tester);
    await tap(tester, 'member-take-photo');
    await tap(tester, 'member-add-next');
    await tap(tester, 'member-plan-silver');
    await tap(tester, 'member-add-next');
    await tap(tester, 'member-payment-confirm');
    fixture.failWrites = true;
    await tap(tester, 'member-add-save');
    expect(
      find.textContaining('The change may have been saved'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('member-add-save')))
          .onPressed,
      isNull,
    );
    final check = find.text('Check registration');
    await tester.ensureVisible(check);
    await tester.tap(check);
    await tester.pumpAndSettle();
    expect(find.textContaining('Registration not found yet'), findsOneWidget);
    fixture.failWrites = false;
    final retry = find.text('Retry same registration');
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    final requests = fixture.requests
        .where((r) => r.url.path == '/api/v1/members/enroll')
        .toList();
    expect(requests, hasLength(2));
    expect(requests.first.body, requests.last.body);
    expect(fixture.enrollments, hasLength(1));
    api.clearSession();
  });

  testWidgets('changed prices require reload and fresh payment confirmation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = ApiFixture();
    final api = RepLabApi(client: fixture.client);
    addTearDown(api.dispose);
    await api.login('https://localhost:8443', 'synthetic');
    await open(tester, api: api);
    await basic(tester);
    await tap(tester, 'member-take-photo');
    await tap(tester, 'member-add-next');
    await tap(tester, 'member-plan-silver');
    await tap(tester, 'member-add-next');
    expect(find.text('Full payment: ₹1,200'), findsOneWidget);
    await tap(tester, 'member-payment-confirm');

    fixture.catalog['revision'] = 2;
    (fixture.catalog['plans'] as List).first['prices_paise']['1'] = 135050;
    await tap(tester, 'member-add-save');
    expect(find.textContaining('Plans changed'), findsOneWidget);
    expect(fixture.enrollments, isEmpty);
    await tester.tap(find.text('Retry plans'));
    await tester.pumpAndSettle();
    await tap(tester, 'member-plan-silver');
    await tap(tester, 'member-add-next');
    expect(find.text('Full payment: ₹1,350.50'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('member-add-save')))
          .onPressed,
      isNull,
    );
    await tap(tester, 'member-payment-confirm');
    await tap(tester, 'member-add-save');
    expect(fixture.enrollments, hasLength(1));
    final requests = fixture.requests
        .where((r) => r.url.path == '/api/v1/members/enroll')
        .map((r) => jsonDecode(r.body) as Map)
        .toList();
    expect(requests.map((r) => r['catalog_revision']), [1, 2]);
    expect(requests.last['member'], requests.first['member']);
    expect(requests.last['photo_base64'], requests.first['photo_base64']);
    expect(requests.last['request_id'], requests.first['request_id']);
    expect(tester.takeException(), isNull);
    api.clearSession();
  });

  testWidgets('each registration step fits narrow and large-text layouts', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (final (size, scale) in [
      (const Size(360, 740), 1.0),
      (const Size(800, 600), 2.0),
    ]) {
      await tester.binding.setSurfaceSize(size);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      await open(tester);
      await basic(tester);
      expect(tester.takeException(), isNull);
      await tap(tester, 'member-take-photo');
      await tap(tester, 'member-add-next');
      expect(tester.takeException(), isNull);
      await tap(tester, 'member-plan-gold');
      await choose(tester, 'member-plan-months', 'Annual · 12 months');
      await tap(tester, 'member-add-next');
      expect(tester.takeException(), isNull);
      await tap(tester, 'member-payment-confirm');
      await tap(tester, 'member-add-cancel');
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
