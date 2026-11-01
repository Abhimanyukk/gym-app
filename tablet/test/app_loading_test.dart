import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/app_loading.dart';
import 'package:gym_management_app/dashboard_screen.dart';
import 'package:gym_management_app/main.dart';
import 'package:gym_management_app/replab_api.dart';

import 'api_fixture.dart';

void main() {
  testWidgets(
    'shared loader rotates the existing asset and respects reduced motion',
    (tester) async {
      await tester.pumpWidget(
        const GymManagementApp(home: Scaffold(body: DumbbellLoader())),
      );
      final rotation = tester
          .widget<RotationTransition>(
            find.descendant(
              of: find.byType(DumbbellLoader),
              matching: find.byType(RotationTransition),
            ),
          )
          .turns;
      final start = rotation.value;
      await tester.pump(const Duration(milliseconds: 250));
      expect(rotation.value, isNot(start));
      final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
      expect(
        (svg.bytesLoader as SvgAssetLoader).assetName,
        'assets/icons/dumbell.svg',
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.pumpWidget(
        const GymManagementApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Scaffold(body: DumbbellLoader()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final stopped = tester
          .widget<RotationTransition>(
            find.descendant(
              of: find.byType(DumbbellLoader),
              matching: find.byType(RotationTransition),
            ),
          )
          .turns;
      expect(stopped.value, 0);
      await tester.pump(const Duration(seconds: 2));
      expect(stopped.value, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'native pull refresh works on an empty list and prevents concurrent refreshes',
    (tester) async {
      final completion = Completer<void>();
      var calls = 0;
      await tester.pumpWidget(
        GymManagementApp(
          home: Scaffold(
            body: DumbbellRefresh(
              onRefresh: () {
                calls++;
                return completion.future;
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: ClampingScrollPhysics(),
                ),
                children: const [Text('Empty list')],
              ),
            ),
          ),
        ),
      );
      final list = find.byType(ListView);
      final icons = find.descendant(
        of: find.byType(DumbbellRefresh),
        matching: find.byType(SvgPicture),
      );
      await tester.pumpAndSettle();
      final restingPosition = tester.getTopLeft(find.text('Empty list'));
      final touch = await tester.startGesture(tester.getCenter(list));
      await tester.pump();
      expect(icons, findsNothing);
      // Enough movement to start a native drag, but not a deliberate pull.
      await touch.moveBy(const Offset(0, 36));
      await tester.pump();
      expect(icons, findsNothing);
      expect(calls, 0);
      await touch.up();
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(icons, findsNothing);

      final partial = await tester.startGesture(tester.getCenter(list));
      await partial.moveBy(const Offset(0, 100));
      await tester.pump();
      expect(icons, findsOneWidget);
      expect(
        find.byType(DumbbellLoader),
        findsNothing,
      ); // Rotate only on release.
      expect(calls, 0);
      expect(
        tester.getTopLeft(find.text('Empty list')).dy,
        greaterThan(restingPosition.dy),
      );
      expect(
        find.descendant(
          of: find.byType(DumbbellRefresh),
          matching: find.byType(Material),
        ),
        findsNothing, // No floating circle, background, or shadow.
      );
      await partial.up();
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(icons, findsNothing);
      expect(tester.getTopLeft(find.text('Empty list')), restingPosition);

      await tester.drag(list, const Offset(0, 500));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(calls, 1);
      expect(find.byType(DumbbellLoader), findsOneWidget);
      final turns = tester
          .widget<RotationTransition>(
            find.descendant(
              of: find.byType(DumbbellLoader),
              matching: find.byType(RotationTransition),
            ),
          )
          .turns;
      final start = turns.value;
      await tester.pump(const Duration(milliseconds: 250));
      expect(turns.value, isNot(start));
      await tester.drag(list, const Offset(0, 500));
      await tester.pump(const Duration(milliseconds: 200));
      expect(calls, 1);
      completion.complete();
      await tester.pumpAndSettle();
      expect(find.byType(DumbbellLoader), findsNothing);
      expect(icons, findsNothing); // Done must remove the static logo as well.
      expect(tester.getTopLeft(find.text('Empty list')), restingPosition);
      await tester.drag(list, const Offset(0, 500));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(icons, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'refresh errors are visible and disposal during refresh is safe',
    (tester) async {
      final completion = Completer<void>();
      Future<void> render(RefreshCallback callback) async {
        await tester.pumpWidget(
          GymManagementApp(
            home: Scaffold(
              body: DumbbellRefresh(
                onRefresh: callback,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [Text('Empty list')],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView), const Offset(0, 500));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
      }

      await render(() async => throw StateError('Test request failed'));
      await tester.pumpAndSettle();
      expect(find.text('Unable to refresh. Please try again.'), findsOneWidget);
      expect(find.byType(DumbbellLoader), findsNothing);
      expect(
        find.byKey(const ValueKey('pull-refresh-indicator')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await render(() => completion.future);
      expect(find.byType(DumbbellLoader), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      completion.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'all four pages refresh above the page, not inside cards, and retain filters',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final preview in [true, false]) {
        for (final section in [
          'Dashboard',
          'Attendance',
          'Members',
          'Settings',
        ]) {
          await tester.pumpWidget(
            GymManagementApp(home: DashboardScreen(showSampleData: preview)),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(ValueKey('nav-$section')));
          await tester.pumpAndSettle();
          final sidebar = find.byKey(const ValueKey('sidebar'));
          final sidebarRect = tester.getRect(sidebar);
          final searchable = section == 'Attendance' || section == 'Members';
          if (searchable) {
            await tester.enterText(
              find.byKey(ValueKey('${section.toLowerCase()}-search')),
              'M-0001',
            );
            await tester.pumpAndSettle();
          }
          final refresh = find.byKey(
            ValueKey('${section.toLowerCase()}-refresh'),
          );
          if (section != 'Dashboard') {
            expect(
              find.descendant(
                of: refresh,
                matching: find.byKey(ValueKey('${section.toLowerCase()}-page')),
              ),
              findsOneWidget,
              reason: '$section refresh must wrap the whole page',
            );
          }
          if (searchable) {
            final card = find.byKey(
              ValueKey(
                section == 'Attendance' ? 'attendance-list' : 'members-card',
              ),
            );
            expect(
              find.descendant(
                of: card,
                matching: find.byType(RefreshIndicator),
              ),
              findsNothing,
            );
          }
          final scroll = section == 'Dashboard'
              ? find.descendant(
                  of: refresh,
                  matching: find.byType(SingleChildScrollView),
                )
              : section == 'Settings'
              ? find.byKey(const PageStorageKey('settings-scroll'))
              : find.byKey(
                  ValueKey(
                    section == 'Attendance'
                        ? 'attendance-scroll'
                        : 'members-list',
                  ),
                );
          await tester.drag(
            scroll,
            const Offset(0, 500),
            kind: section == 'Dashboard'
                ? PointerDeviceKind.mouse
                : PointerDeviceKind.touch,
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          expect(find.byType(DumbbellLoader), findsOneWidget, reason: section);
          final indicator = find.byKey(
            const ValueKey('pull-refresh-indicator'),
          );
          expect(
            tester.getTopLeft(indicator).dy,
            tester.getTopLeft(refresh).dy +
                tester.widget<DumbbellRefresh>(refresh).padding.top,
          );
          if (section != 'Dashboard') {
            final heading = find.byKey(
              ValueKey(
                section == 'Attendance'
                    ? 'attendance-header'
                    : section == 'Settings'
                    ? 'settings-title'
                    : 'members-page',
              ),
            );
            expect(
              tester.getRect(indicator).bottom,
              lessThanOrEqualTo(tester.getRect(heading).top),
            );
          }
          await tester.pumpAndSettle();
          expect(find.byType(DumbbellLoader), findsNothing);
          expect(
            find.byKey(const ValueKey('pull-refresh-indicator')),
            findsNothing,
          );
          expect(tester.getRect(sidebar), sidebarRect);
          if (searchable) {
            expect(
              tester
                  .widget<TextField>(
                    find.byKey(ValueKey('${section.toLowerCase()}-search')),
                  )
                  .controller!
                  .text,
              'M-0001',
            );
          }
          if (preview) {
            expect(
              find.text(
                section == 'Attendance'
                    ? '1 of 31 check-ins'
                    : section == 'Members'
                    ? '1 of 178 members'
                    : section == 'Settings'
                    ? 'RepLab Fitness'
                    : '178',
              ),
              findsOneWidget,
            );
          } else {
            expect(
              find.text(
                'Backend not connected. Live data cannot be refreshed yet.',
              ),
              findsOneWidget,
            );
            if (section != 'Settings') {
              expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
            }
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    },
  );

  testWidgets(
    'page refreshes reuse one dumbbell for live requests, including settings',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fixture = ApiFixture();
      final api = RepLabApi(client: fixture.client);
      addTearDown(api.dispose);
      await api.login('https://localhost:8443', 'synthetic');
      await tester.pumpWidget(
        GymManagementApp(home: DashboardScreen(api: api)),
      );
      await tester.pumpAndSettle();
      for (final (section, path, key) in const [
        ('Dashboard', '/api/v1/dashboard/summary', PageStorageKey('Dashboard')),
        ('Attendance', '/health/ready', ValueKey('attendance-scroll')),
        ('Members', '/api/v1/members', ValueKey('members-list')),
        ('Settings', '/api/v1/settings', PageStorageKey('settings-scroll')),
      ]) {
        await tester.tap(find.byKey(ValueKey('nav-$section')));
        await tester.pumpAndSettle();
        if (section == 'Members') {
          await tester.enterText(
            find.byKey(const ValueKey('members-search')),
            'M-0042',
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('members-filter-Active records')),
          );
          await tester.pumpAndSettle();
        }
        if (section == 'Settings') {
          fixture.settings['gym_name'] = 'Refreshed Gym';
        }
        final calls = fixture.requests.where((r) => r.url.path == path).length;
        final completion = Completer<void>();
        fixture.readBarrier = completion.future;
        addTearDown(() {
          if (!completion.isCompleted) completion.complete();
        });
        await tester.drag(find.byKey(key), const Offset(0, 500));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        final refresh = find.byKey(
          ValueKey('${section.toLowerCase()}-refresh'),
        );
        expect(
          find.descendant(of: refresh, matching: find.byType(SvgPicture)),
          findsOneWidget,
          reason:
              '$section must reuse the pull indicator for the pending request',
        );
        final loaders = find.descendant(
          of: refresh,
          matching: find.byType(DumbbellLoader),
        );
        expect(
          find.descendant(
            of: loaders,
            matching: find.byType(RotationTransition),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('pull-refresh-indicator')),
            matching: find.byType(RotationTransition),
          ),
          findsOneWidget,
        );
        completion.complete();
        fixture.readBarrier = null;
        await tester.pumpAndSettle();
        expect(
          fixture.requests.where((r) => r.url.path == path).length,
          calls + 1,
        );
        if (section == 'Members') {
          expect(fixture.requests.last.url.queryParameters['q'], 'M-0042');
          expect(fixture.requests.last.url.queryParameters['active'], 'true');
        }
        if (section == 'Settings') {
          expect(find.text('Refreshed Gym'), findsOneWidget);
          fixture.failReads = true;
          await tester.drag(find.byKey(key), const Offset(0, 500));
          await tester.pumpAndSettle();
          expect(
            find.textContaining('Cannot reach the server'),
            findsOneWidget,
          );
          expect(find.text('Refreshed Gym'), findsOneWidget);
          fixture.failReads = false;
          final retry = Completer<void>();
          fixture.readBarrier = retry.future;
          await tester.tap(find.text('Retry settings'));
          await tester.pump();
          expect(
            find.byKey(const ValueKey('pull-refresh-indicator')),
            findsNothing,
          );
          expect(
            find.descendant(
              of: loaders,
              matching: find.byType(RotationTransition),
            ),
            findsOneWidget,
            reason: 'A normal retry must still show its own loader',
          );
          retry.complete();
          fixture.readBarrier = null;
          await tester.pumpAndSettle();
        }
        expect(
          find.byKey(const ValueKey('pull-refresh-indicator')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      }
      expect(api.signedIn, isTrue);
      api.clearSession();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'every page body refreshes from headers, controls and padding at the same position',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Rect? indicatorRect;
      for (final section in [
        'Dashboard',
        'Attendance',
        'Members',
        'Settings',
      ]) {
        await tester.pumpWidget(
          const GymManagementApp(home: DashboardScreen(showSampleData: true)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('nav-$section')));
        await tester.pumpAndSettle();
        final body = find.byKey(const ValueKey('section-body'));
        final bodyRect = tester.getRect(body);
        final sidebar = find.byKey(const ValueKey('sidebar'));
        final sidebarRect = tester.getRect(sidebar);
        final areas = <Offset>[
          bodyRect.topLeft + const Offset(140, 48),
          bodyRect.topLeft + Offset(8, bodyRect.height / 2),
          Offset(bodyRect.right - 8, bodyRect.center.dy),
          if (section == 'Attendance' || section == 'Members')
            tester.getCenter(
              find.byKey(ValueKey('${section.toLowerCase()}-search')),
            ),
          if (section == 'Attendance') ...[
            tester.getCenter(find.byKey(const ValueKey('attendance-filters'))),
            tester.getCenter(
              find.byKey(const ValueKey('attendance-info-ribbon')),
            ),
            tester.getCenter(
              find.byKey(
                const ValueKey('attendance-summary-Members checked in'),
              ),
            ),
            tester.getCenter(
              find.byKey(const ValueKey('attendance-card-title')),
            ),
          ],
          if (section == 'Members')
            tester.getCenter(
              find.byKey(const ValueKey('members-filter-All members')),
            ),
          if (section == 'Settings')
            tester.getCenter(find.byKey(const ValueKey('settings-notice'))),
        ];
        for (final area in areas) {
          final touch = await tester.startGesture(area);
          await touch.moveBy(const Offset(0, 36));
          await tester.pump();
          expect(
            find.byKey(const ValueKey('pull-refresh-indicator')),
            findsNothing,
          );
          await touch.up();
          await tester.pumpAndSettle();
          await tester.dragFrom(
            area,
            const Offset(0, 500),
            kind: section == 'Dashboard'
                ? PointerDeviceKind.mouse
                : PointerDeviceKind.touch,
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          final indicator = find.byKey(
            const ValueKey('pull-refresh-indicator'),
          );
          expect(indicator, findsOneWidget, reason: '$section body area $area');
          indicatorRect ??= tester.getRect(indicator);
          expect(tester.getRect(indicator), indicatorRect);
          expect(tester.getRect(sidebar), sidebarRect);
          await tester.pumpAndSettle();
          expect(indicator, findsNothing);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets(
    'body drags use native scrolling and cancel safely when removed',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      var calls = 0;
      await tester.pumpWidget(
        GymManagementApp(
          home: Scaffold(
            body: DumbbellRefresh(
              padding: const EdgeInsets.all(32),
              scrollController: scroll,
              onRefresh: () async => calls++,
              child: ListView(
                controller: scroll,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: ClampingScrollPhysics(),
                ),
                children: List.generate(
                  40,
                  (i) => SizedBox(height: 50, child: Text('Row $i')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      scroll.jumpTo(400);
      await tester.dragFrom(const Offset(8, 150), const Offset(0, 100));
      await tester.pumpAndSettle();
      expect(scroll.offset, lessThan(400));
      expect(calls, 0);
      expect(
        find.byKey(const ValueKey('pull-refresh-indicator')),
        findsNothing,
      );
      scroll.jumpTo(0);
      final reverse = await tester.startGesture(const Offset(8, 150));
      await reverse.moveBy(const Offset(0, 120));
      await tester.pump();
      await reverse.moveBy(const Offset(0, -120));
      await reverse.up();
      await tester.pumpAndSettle();
      expect(calls, 0);
      scroll.jumpTo(0);
      final active = await tester.startGesture(const Offset(8, 150));
      await active.moveBy(const Offset(0, 100));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await active.up();
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('scrolling away from the top never reveals the refresh logo', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    var calls = 0;
    await tester.pumpWidget(
      GymManagementApp(
        home: Scaffold(
          body: DumbbellRefresh(
            onRefresh: () async => calls++,
            child: ListView(
              controller: scroll,
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              children: List.generate(
                50,
                (i) => SizedBox(height: 50, child: Text('Row $i')),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    scroll.jumpTo(400);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ListView)),
    );
    await gesture.moveBy(const Offset(0, 100));
    await tester.pump();
    expect(find.byKey(const ValueKey('pull-refresh-indicator')), findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(calls, 0);
    scroll.jumpTo(0);
    final reverse = await tester.startGesture(
      tester.getCenter(find.byType(ListView)),
    );
    await reverse.moveBy(const Offset(0, -150));
    await tester.pump();
    await reverse.moveBy(const Offset(0, 100));
    await tester.pump();
    expect(scroll.offset, greaterThan(0));
    expect(find.byKey(const ValueKey('pull-refresh-indicator')), findsNothing);
    await reverse.up();
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a short list viewport does not refresh from a small drag', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      GymManagementApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: 120,
              child: DumbbellRefresh(
                onRefresh: () async {
                  calls++;
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: ClampingScrollPhysics(),
                  ),
                  children: const [Text('Short list')],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final list = find.byType(ListView);
    final gesture = await tester.startGesture(tester.getCenter(list));
    await gesture.moveBy(const Offset(0, 36));
    await tester.pump();
    expect(find.byType(SvgPicture), findsNothing);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(DumbbellLoader), findsNothing);
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.drag(list, const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.byType(SvgPicture), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending login uses the shared dumbbell loader', (tester) async {
    const channel = MethodChannel('plugins.flutter.io/local_auth');
    final completion = Completer<void>();
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => false);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final fixture = ApiFixture()
      ..allowLogin = false
      ..loginBarrier = completion.future;
    final api = RepLabApi(client: fixture.client);
    addTearDown(api.dispose);
    await tester.pumpWidget(GymManagementApp(api: api));
    await tester.pumpAndSettle();
    await enterServerLogin(tester);
    await tester.tap(find.text('Login'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(DumbbellLoader), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    completion.complete();
    await tester.pumpAndSettle();
    expect(find.byType(DumbbellLoader), findsNothing);
    expect(find.text('Server password is incorrect.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
