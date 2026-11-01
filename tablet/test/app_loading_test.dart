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
      await tester.pumpAndSettle();
      await tester.drag(list, const Offset(0, 15));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.byType(DumbbellLoader), findsNothing);

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
    'all three pages refresh without moving the sidebar or clearing filters',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final preview in [true, false]) {
        for (final section in ['Dashboard', 'Attendance', 'Members']) {
          await tester.pumpWidget(
            GymManagementApp(home: DashboardScreen(showSampleData: preview)),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(ValueKey('nav-$section')));
          await tester.pumpAndSettle();
          final sidebar = find.byKey(const ValueKey('sidebar'));
          final sidebarRect = tester.getRect(sidebar);
          if (section != 'Dashboard') {
            await tester.enterText(
              find.byKey(ValueKey('${section.toLowerCase()}-search')),
              'M-0001',
            );
            await tester.pumpAndSettle();
          }
          final refresh = find.byKey(
            ValueKey('${section.toLowerCase()}-refresh'),
          );
          final scroll = section == 'Dashboard'
              ? find.descendant(
                  of: refresh,
                  matching: find.byType(SingleChildScrollView),
                )
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
          await tester.pumpAndSettle();
          expect(find.byType(DumbbellLoader), findsNothing);
          expect(tester.getRect(sidebar), sidebarRect);
          if (section != 'Dashboard') {
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
            expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    },
  );

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
