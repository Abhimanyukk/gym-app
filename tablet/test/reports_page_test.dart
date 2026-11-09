import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/app_loading.dart';
import 'package:gym_management_app/collection_report.dart';
import 'package:gym_management_app/main.dart';
import 'package:gym_management_app/member_enrollment.dart';
import 'package:gym_management_app/replab_api.dart';
import 'package:gym_management_app/reports_page.dart';
import 'package:gym_management_app/sample_attendance.dart';

import 'api_fixture.dart';
import 'reports_fixture.dart';

Future<RepLabApi> openReports(WidgetTester tester, ApiFixture fixture) async {
  final api = RepLabApi(client: fixture.client);
  addTearDown(api.dispose);
  await api.login('https://localhost:8443', 'synthetic');
  await tester.pumpWidget(
    GymManagementApp(
      home: Scaffold(
        body: ReportsPage(api: api, padding: const EdgeInsets.all(32)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return api;
}

Future<void> tapReport(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  test('parses exact paise and rejects incompatible/unbalanced reports', () {
    final data = reportsFixture();
    final report = CollectionReport.fromJson(data);
    expect(report.highlights['today']!.total, 10001);
    expect(report.totals.total, 210021);
    expect(report.totals.cash + report.totals.upi, report.totals.total);
    expect(report.receipts.first.invoice, 'RL-000021');
    expect(rupees(report.totals.total), '₹2,100.21');
    data['totals']['cash_paise'] = 1;
    expect(() => CollectionReport.fromJson(data), throwsFormatException);
    final unsupported = reportsFixture()..['currency'] = 'USD';
    expect(() => CollectionReport.fromJson(unsupported), throwsFormatException);
  });

  testWidgets('shows real totals, filters and a payment receipt', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = ApiFixture();
    final api = await openReports(tester, fixture);
    expect(find.byKey(const ValueKey('reports-metric-today')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('reports-metric-all_time')),
      findsOneWidget,
    );
    expect(
      find.text('Prepaid memberships are not earned revenue or profit.'),
      findsNothing,
    );
    expect(
      find.textContaining(
        'Prepaid memberships are not earned revenue or profit.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('reports-warning')), findsNothing);
    expect(find.text('Cash'), findsOneWidget);
    expect(find.text('UPI'), findsOneWidget);
    final titlePosition = tester.getTopLeft(
      find.byKey(const ValueKey('reports-title')),
    );
    await tapReport(tester, 'reports-period-Today');
    final today = isoDate(gymNow());
    final query = fixture.requests.last.url.queryParameters;
    expect(query['from'], today);
    expect(query['daily_offset'], '0');
    expect(find.text('1 fully paid registrations'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('reports-selected-total')))
          .data,
      '₹100.01',
    );
    await tapReport(tester, 'reports-receipt-RL-000021');
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Full payment: ₹100.01'), findsOneWidget);
    expect(
      find.textContaining('not automatic bank verification'),
      findsOneWidget,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('reports-title'))),
      titlePosition,
    );
    await tapReport(tester, 'reports-period-All time');
    expect(
      fixture.requests.last.url.queryParameters.containsKey('from'),
      isFalse,
    );
    await tapReport(tester, 'reports-daily-next');
    expect(fixture.requests.last.url.queryParameters['daily_offset'], '14');
    expect(find.text('15–21 of 21'), findsOneWidget);
    await tapReport(tester, 'reports-receipts-next');
    expect(fixture.requests.last.url.queryParameters['receipt_offset'], '20');
    expect(fixture.requests.last.url.queryParameters['daily_offset'], '14');
    expect(find.text('21–21 of 21'), findsOneWidget);
    expect(tester.takeException(), isNull);
    api.clearSession();
  });

  testWidgets(
    'old server, malformed data and offline states do not invent money',
    (tester) async {
      final fixture = ApiFixture()..reportsAvailable = false;
      final api = await openReports(tester, fixture);
      expect(
        find.textContaining('Update the gym server to RepLab 0.6'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('reports-selected-total')),
        findsNothing,
      );
      fixture.reportsAvailable = true;
      fixture.reportResponse = {'currency': 'INR'};
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not read the financial report. Pull down to retry.'),
        findsOneWidget,
      );
      fixture.reportResponse = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('reports-selected-total')),
        findsOneWidget,
      );
      fixture.failReads = true;
      final body = find.byKey(const PageStorageKey('reports-scroll'));
      await tester.drag(body, const Offset(0, 800));
      await tester.pumpAndSettle();
      expect(
        find.text('Previously loaded figures · Pull down to retry.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('reports-selected-total')),
        findsOneWidget,
      );
      await tapReport(tester, 'reports-period-Yesterday');
      expect(
        find.byKey(const ValueKey('reports-selected-total')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      api.clearSession();
    },
  );

  testWidgets('one body-wide dumbbell refresh works over the sticky title', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = ApiFixture();
    final api = await openReports(tester, fixture);
    final barrier = Completer<void>();
    addTearDown(() {
      if (!barrier.isCompleted) barrier.complete();
    });
    fixture.readBarrier = barrier.future;
    final before = fixture.requests
        .where((r) => r.url.path == '/api/v1/reports/collections')
        .length;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('reports-title'))),
    );
    await gesture.moveBy(const Offset(0, 10));
    await tester.pump();
    expect(find.byKey(const ValueKey('pull-refresh-indicator')), findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('reports-title')),
      const Offset(0, 500),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      fixture.requests
          .where((r) => r.url.path == '/api/v1/reports/collections')
          .length,
      before + 1,
    );
    expect(
      find.byKey(const ValueKey('pull-refresh-indicator')),
      findsOneWidget,
    );
    final visibleLoaders = find
        .byType(DumbbellLoader)
        .evaluate()
        .where(
          (element) => find
              .descendant(
                of: find.byWidget(element.widget),
                matching: find.byType(RotationTransition),
              )
              .evaluate()
              .isNotEmpty,
        );
    expect(visibleLoaders.length, 1);
    barrier.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pull-refresh-indicator')), findsNothing);
    expect(tester.takeException(), isNull);
    api.clearSession();
  });

  testWidgets('empty/no-server reports stay usable with large text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const GymManagementApp(
        home: Scaffold(body: ReportsPage(padding: EdgeInsets.all(32))),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Waiting for financial connection'), findsOneWidget);
    expect(find.byKey(const ValueKey('reports-selected-total')), findsNothing);
    final fixture = ApiFixture()
      ..reportResponse = reportsFixture(from: '2024-03-01', to: '2024-03-01');
    final api = RepLabApi(client: fixture.client);
    addTearDown(api.dispose);
    await api.login('https://localhost:8443', 'synthetic');
    await tester.pumpWidget(
      GymManagementApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: ReportsPage(api: api, padding: const EdgeInsets.all(32)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No payments in this period'), findsOneWidget);
    await tester.drag(
      find.byKey(const PageStorageKey('reports-scroll')),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    api.clearSession();
  });
}
