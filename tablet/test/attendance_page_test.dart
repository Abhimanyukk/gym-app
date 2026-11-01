import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/attendance_page.dart';
import 'package:gym_management_app/dashboard_screen.dart';
import 'package:gym_management_app/main.dart';
import 'package:gym_management_app/sample_attendance.dart';

Finder entryRows() => find.byWidgetPredicate(
  (widget) =>
      widget.key is ValueKey<String> &&
      (widget.key! as ValueKey<String>).value.startsWith('attendance-entry-'),
);

Finder attendanceScrollable() => find.descendant(
  of: find.byKey(const ValueKey('attendance-scroll')),
  matching: find.byType(Scrollable),
);

Future<void> revealAttendance(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    100,
    scrollable: attendanceScrollable(),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('sample dates and repeat visits are consistent', () {
    final today = gymNow();
    final entries = sampleAttendanceFor(today);
    expect(entries.length, 31);
    expect(entries.map((entry) => entry.memberNumber).toSet().length, 30);
    expect(
      entries
          .where((entry) => entry.membership != MembershipStatus.active)
          .length,
      3,
    );
    expect(
      sampleAttendanceFor(DateTime(today.year, today.month, today.day - 1))
          .length,
      6,
    );
    expect(
      sampleAttendanceFor(DateTime(today.year, today.month, today.day - 2)),
      isEmpty,
    );
    expect(
      sampleAttendanceFor(DateTime(today.year, today.month, today.day + 1)),
      isEmpty,
    );
  });

  testWidgets('attendance search, status, sorting and clear actions work', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const GymManagementApp(home: DashboardScreen(showSampleData: true)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-Attendance')));
    await tester.pumpAndSettle();

    expect(find.byType(AttendancePage), findsOneWidget);
    expect(find.text("Today's check-ins"), findsOneWidget);
    expect(find.text('31 of 31 check-ins'), findsOneWidget);
    expect(find.textContaining('Sample data'), findsAtLeastNWidgets(1));
    for (final (title, value) in [
      ('Members checked in', '30'),
      ('Total check-ins', '31'),
      ('Needs attention', '3'),
    ]) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey('attendance-summary-$title')),
          matching: find.text(value),
        ),
        findsOneWidget,
      );
    }
    final firstRow = entryRows().first;
    expect(
      find.descendant(
        of: firstRow,
        matching: find.text('Poovalli Induchoodan'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: firstRow, matching: find.text('8:12 AM')),
      findsOneWidget,
    );

    final search = find.byKey(const ValueKey('attendance-search'));
    await tester.enterText(search, '  bILal ');
    await tester.pumpAndSettle();
    expect(find.text('2 of 31 check-ins'), findsOneWidget);
    expect(find.text('Bilal John Kurishingal'), findsNWidgets(2));
    expect(find.text('M-0002 · 2 check-ins'), findsNWidgets(2));
    expect(find.text('Poovalli Induchoodan'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('attendance-sort')));
    await tester.pumpAndSettle();
    expect(find.text('Earliest first'), findsOneWidget);
    expect(
      find.descendant(of: entryRows().first, matching: find.text('6:12 AM')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('attendance-filter-expiring')));
    await tester.pumpAndSettle();
    expect(find.text('No matching check-ins'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('attendance-reset-filters')),
    );
    await tester.tap(find.byKey(const ValueKey('attendance-reset-filters')));
    await tester.pumpAndSettle();
    expect(find.text('31 of 31 check-ins'), findsOneWidget);
    expect(tester.widget<TextField>(search).controller!.text, isEmpty);

    await tester.ensureVisible(
      find.byKey(const ValueKey('attendance-filter-expired')),
    );
    await tester.tap(find.byKey(const ValueKey('attendance-filter-expired')));
    await tester.pumpAndSettle();
    expect(find.text('1 of 31 check-ins'), findsOneWidget);
    expect(find.text('Nadeshan'), findsOneWidget);
    expect(find.text('Due for 2 days'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('attendance-filter-all')));
    await tester.enterText(search, 'm-0001');
    await tester.pumpAndSettle();
    expect(find.text('1 of 31 check-ins'), findsOneWidget);
    expect(find.text('Poovalli Induchoodan'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('attendance-clear-search')));
    await tester.pumpAndSettle();
    expect(find.text('31 of 31 check-ins'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('date picker changes the day and Today restores it', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const GymManagementApp(
        home: Scaffold(
          body: Padding(
            padding: EdgeInsets.all(32),
            child: AttendancePage(showSampleData: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final now = gymNow();
    final today = DateTime(now.year, now.month, now.day);
    for (final (daysAgo, expected) in [
      (1, '6 of 6 check-ins'),
      (2, 'No sample check-ins for this date'),
    ]) {
      await tester.tap(find.byKey(const ValueKey('attendance-date')));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      final dialog = find.byType(DatePickerDialog);
      final localizations = MaterialLocalizations.of(tester.element(dialog));
      await tester.tap(find.byTooltip(localizations.inputDateModeButtonLabel));
      await tester.pumpAndSettle();
      final target = DateTime(today.year, today.month, today.day - daysAgo);
      await tester.enterText(
        find.descendant(of: dialog, matching: find.byType(TextField)),
        localizations.formatCompactDate(target),
      );
      await tester.tap(find.text(localizations.okButtonLabel));
      await tester.pumpAndSettle();
      expect(find.text(expected), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('attendance-scroll')),
        const Offset(0, 500),
      );
      await tester.pumpAndSettle();
      expect(find.text(expected), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('attendance-today')))
            .onPressed,
        isNotNull,
      );
    }
    await tester.tap(find.byKey(const ValueKey('attendance-today')));
    await tester.pumpAndSettle();
    expect(find.text('31 of 31 check-ins'), findsOneWidget);
    expect(find.text("Today's check-ins"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('normal app shows unavailable attendance, not sample totals', (
    tester,
  ) async {
    await tester.pumpWidget(
      const GymManagementApp(home: Scaffold(body: AttendancePage())),
    );
    await tester.pumpAndSettle();
    expect(find.text('—'), findsNWidgets(3));
    expect(find.text('Waiting for attendance connection'), findsOneWidget);
    expect(find.text('Check-ins unavailable'), findsOneWidget);
    expect(find.textContaining('Sample data'), findsNothing);
    expect(entryRows(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('attendance adapts to tablet, narrow and enlarged-text layouts', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final (size, scale, keyboardHeight) in const [
      (Size(1024, 768), 1.0, 0.0),
      (Size(1024, 768), 1.0, 300.0),
      (Size(800, 600), 2.0, 0.0),
      (Size(360, 740), 1.0, 0.0),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        GymManagementApp(
          home: MediaQuery(
            data: MediaQueryData(
              textScaler: TextScaler.linear(scale),
              viewInsets: EdgeInsets.only(bottom: keyboardHeight),
            ),
            child: const DashboardScreen(showSampleData: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-Attendance')));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('attendance-scroll'))).height,
        greaterThan(0),
      );
      expect(tester.takeException(), isNull);
      if (scale == 1 && size.width == 1024) {
        final heights = [
          for (final title in [
            'Members checked in',
            'Total check-ins',
            'Needs attention',
          ])
            tester
                .getSize(find.byKey(ValueKey('attendance-summary-$title')))
                .height,
        ];
        expect(heights[1], heights[0]);
        expect(heights[2], heights[0]);
      }
      final sidebar = find.byKey(const ValueKey('sidebar'));
      final position = tester.getTopLeft(sidebar);
      await tester.ensureVisible(
        find.byKey(const ValueKey('attendance-search')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('attendance-search')),
        'M-0001',
      );
      await tester.pumpAndSettle();
      expect(find.text('1 of 31 check-ins'), findsOneWidget);
      final first = sampleAttendanceFor(gymNow()).first;
      await revealAttendance(
        tester,
        find.byKey(
          ValueKey(
            'attendance-entry-${first.memberNumber}-${first.time.millisecondsSinceEpoch}',
          ),
        ),
      );
      expect(tester.getTopLeft(sidebar), position);
      expect(find.text('Poovalli Induchoodan'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('scrolling shutters the overview and keeps the header fixed', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const GymManagementApp(home: DashboardScreen(showSampleData: true)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-Attendance')));
    await tester.pumpAndSettle();

    final header = find.byKey(const ValueKey('attendance-header'));
    final date = find.byKey(const ValueKey('attendance-date'));
    final card = find.byKey(const ValueKey('attendance-list'));
    final shutter = find.byKey(const ValueKey('attendance-overview-shutter'));
    final list = find.byKey(const ValueKey('attendance-scroll'));
    final headerRect = tester.getRect(header);
    final dateRect = tester.getRect(date);
    final initialCard = tester.getRect(card);
    final factor = tester.widget<SizeTransition>(shutter).sizeFactor;
    final scroll = tester.widget<ListView>(list).controller!;
    final search = find.byKey(const ValueKey('attendance-search'));
    final filters = find.byKey(const ValueKey('attendance-filters'));
    final searchOffset = tester.getTopLeft(search).dy - initialCard.top;
    final filterOffset = tester.getTopLeft(filters).dy - initialCard.top;
    expect(factor.value, 1);
    expect(
      find.byKey(const ValueKey('attendance-info-ribbon')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('section-body')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.vertical,
        ),
      ),
      findsNothing,
    );

    await tester.drag(list, const Offset(0, -260));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(factor.value, greaterThan(0));
    expect(factor.value, lessThan(1));
    expect(tester.getRect(header), headerRect);
    expect(tester.getRect(date), dateRect);
    await tester.pumpAndSettle();
    expect(factor.value, 0);
    expect(tester.getSize(shutter).height, 0);
    expect(tester.getRect(card).top, lessThan(initialCard.top));
    expect(tester.getRect(card).height, greaterThan(initialCard.height));
    expect(tester.getRect(card).bottom, initialCard.bottom);
    expect(scroll.offset, greaterThan(0));
    final focusedCard = tester.getRect(card);
    final searchRect = tester.getRect(search);
    final filterRect = tester.getRect(filters);
    expect(searchRect.top - focusedCard.top, closeTo(searchOffset, 0.01));
    expect(filterRect.top - focusedCard.top, closeTo(filterOffset, 0.01));
    await tester.drag(list, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(tester.getRect(card), focusedCard);
    expect(tester.getRect(header), headerRect);
    expect(tester.getRect(date), dateRect);
    expect(tester.getRect(search), searchRect);
    expect(tester.getRect(filters), filterRect);
    expect(find.text("Today's check-ins"), findsOneWidget);
    expect(find.textContaining('Sample data · Times in IST'), findsOneWidget);

    // Reversing direction reopens the overview before reaching the first row.
    final previousOffset = scroll.offset;
    await tester.drag(list, const Offset(0, 60));
    await tester.pumpAndSettle();
    expect(factor.value, 1);
    expect(scroll.offset, greaterThan(0));
    expect(scroll.offset, lessThan(previousOffset));
    expect(tester.getRect(header), headerRect);
    expect(tester.getRect(date), dateRect);
    await tester.drag(
      find.byKey(const ValueKey('attendance-card-title')),
      const Offset(0, -80),
    );
    await tester.pumpAndSettle();
    expect(factor.value, 0);

    await tester.enterText(search, 'M-0001');
    await tester.pumpAndSettle();
    expect(find.text('1 of 31 check-ins'), findsOneWidget);
    expect(factor.value, 0);
    expect(tester.getRect(search), searchRect);
    await tester.tap(find.byKey(const ValueKey('attendance-clear-search')));
    await tester.pumpAndSettle();
    await tester.drag(list, const Offset(0, -300));
    await tester.pumpAndSettle();

    // Returning to the top reopens the summary, without moving the header.
    await tester.drag(list, const Offset(0, 1800));
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
    expect(factor.value, 1);
    expect(tester.getRect(header), headerRect);
    expect(tester.getRect(date), dateRect);

    // Summary cards are not the gesture area.
    await tester.drag(
      find.byKey(const ValueKey('attendance-summary-Members checked in')),
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();
    expect(factor.value, 1);
    await tester.drag(
      find.byKey(const ValueKey('attendance-card-title')),
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();
    expect(factor.value, 0);
    await tester.tap(find.byKey(const ValueKey('attendance-toggle-summary')));
    await tester.pumpAndSettle();
    expect(factor.value, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('only the whole check-ins card handles shutter gestures', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final showSampleData in [true, false]) {
      await tester.pumpWidget(
        GymManagementApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(32),
              child: AttendancePage(showSampleData: showSampleData),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final factor = tester
          .widget<SizeTransition>(
            find.byKey(const ValueKey('attendance-overview-shutter')),
          )
          .sizeFactor;
      final list = tester
          .widget<ListView>(find.byKey(const ValueKey('attendance-scroll')))
          .controller!;
      for (final key in [
        'attendance-info-ribbon',
        'attendance-summary-Members checked in',
      ]) {
        final area = find.byKey(ValueKey(key));
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getCenter(area),
            scrollDelta: const Offset(0, 120),
          ),
        );
        await tester.drag(area, const Offset(0, -80));
        await tester.pumpAndSettle();
        expect(factor.value, 1, reason: 'Gestures on $key must not collapse');
      }

      for (final key in [
        'attendance-card-title',
        'attendance-search',
        'attendance-filters',
        'attendance-result-count',
        'attendance-scroll',
      ]) {
        final area = find.byKey(ValueKey(key));
        await tester.drag(area, const Offset(0, -80));
        await tester.pumpAndSettle();
        expect(factor.value, 0, reason: 'Swipe on $key');
        final offset = list.offset;
        await tester.drag(area, const Offset(0, 80));
        await tester.pumpAndSettle();
        expect(factor.value, 1, reason: 'Downward swipe on $key');
        if (key != 'attendance-scroll') {
          expect(
            list.offset,
            offset,
            reason: 'Pinned controls do not scroll rows',
          );
        }
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getCenter(area),
            scrollDelta: const Offset(0, 120),
          ),
        );
        await tester.pumpAndSettle();
        expect(factor.value, 0, reason: 'Wheel on $key');
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getCenter(area),
            scrollDelta: const Offset(0, -120),
          ),
        );
        await tester.pumpAndSettle();
        expect(factor.value, 1, reason: 'Reverse wheel on $key');
      }
      // Empty padding at the card edge must also respond.
      await tester.dragFrom(
        tester.getTopLeft(find.byKey(const ValueKey('attendance-list'))) +
            const Offset(4, 20),
        const Offset(0, -80),
      );
      await tester.pumpAndSettle();
      expect(factor.value, 0);
      await tester.dragFrom(
        tester.getTopLeft(find.byKey(const ValueKey('attendance-list'))) +
            const Offset(4, 20),
        const Offset(0, 80),
      );
      await tester.pumpAndSettle();
      expect(factor.value, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
    'summary respects reduced motion and stays available on narrow screens',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final size in [const Size(1600, 1000), const Size(360, 740)]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(
          GymManagementApp(
            home: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: const DashboardScreen(showSampleData: true),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('nav-Attendance')));
        await tester.pumpAndSettle();
        final shutter = find.byKey(
          const ValueKey('attendance-overview-shutter'),
        );
        if (size.width > 600) {
          await tester.tap(
            find.byKey(const ValueKey('attendance-toggle-summary')),
          );
          await tester.pump();
          expect(tester.widget<SizeTransition>(shutter).sizeFactor.value, 0);
          expect(tester.getSize(shutter).height, 0);
        } else {
          expect(tester.getSize(shutter).height, 0);
          await tester.tap(
            find.byKey(const ValueKey('attendance-toggle-summary')),
          );
          await tester.pumpAndSettle();
          expect(find.text('Daily attendance summary'), findsOneWidget);
          expect(find.text('Members checked in: 30'), findsOneWidget);
          expect(find.text('Total check-ins: 31'), findsOneWidget);
          await tester.tap(find.text('Close'));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
}
