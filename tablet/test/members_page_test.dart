import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderSliver;
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/dashboard_screen.dart';
import 'package:gym_management_app/main.dart';
import 'package:gym_management_app/member_profile.dart';
import 'package:gym_management_app/members_page.dart';
import 'package:gym_management_app/sample_attendance.dart';

import 'registration_fixture.dart';

Future<void> openMembers(WidgetTester tester, {bool preview = true}) async {
  await tester.pumpWidget(
    GymManagementApp(home: DashboardScreen(showSampleData: preview)),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('nav-Members')));
  await tester.pumpAndSettle();
}

void main() {
  test('member fixtures match attendance and inclusive expiry dates', () {
    final members = sampleMembers();
    expect(members.length, 178);
    expect(members.map((member) => member.number).toSet().length, 178);
    for (final visit in sampleAttendanceFor(gymNow())) {
      final member = members.singleWhere((m) => m.number == visit.memberNumber);
      expect(member.name, visit.name);
      expect(member.membership, visit.membership);
    }
    final today = DateUtils.dateOnly(gymNow());
    for (final (offset, status) in [
      (-1, MembershipStatus.expired),
      (0, MembershipStatus.expiring),
      (14, MembershipStatus.expiring),
      (15, MembershipStatus.active),
    ]) {
      expect(
        MemberProfile(
          number: 'test',
          name: 'Test Person',
          phone: '',
          joined: today,
          planEnd: today.add(Duration(days: offset)),
        ).membership,
        status,
      );
    }
  });

  testWidgets('directory searches, filters, sorts and opens full profiles', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await openMembers(tester);
    expect(find.byType(MembersPage), findsOneWidget);
    expect(find.text('178 of 178 members'), findsOneWidget);
    final search = find.byKey(const ValueKey('members-search'));
    await tester.enterText(search, '  bILal  ');
    await tester.pumpAndSettle();
    expect(find.text('1 of 178 members'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('member-M-0002')));
    await tester.pumpAndSettle();
    final details = find.byKey(const ValueKey('member-details'));
    expect(
      find.descendant(
        of: details,
        matching: find.text('Bilal John Kurishingal'),
      ),
      findsNWidgets(2),
    );
    for (final text in [
      'Personal & contact details',
      'Sample phone 002',
      'member2@example.com',
      'Quarterly',
      'Joined on',
      'Valid through',
      'Recent attendance',
      '8:04 AM IST',
      '6:12 AM IST',
      'Payments & subscription history',
    ]) {
      expect(
        find.descendant(of: details, matching: find.text(text)),
        findsWidgets,
      );
    }
    await tester.tap(find.byKey(const ValueKey('member-details-close')));
    await tester.pumpAndSettle();
    await tester.enterText(search, 'sample phone 003');
    await tester.pumpAndSettle();
    expect(find.text('Nadeshan'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('members-filter-Active')));
    await tester.pumpAndSettle();
    expect(find.text('No matching members'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('members-reset')));
    await tester.pumpAndSettle();
    expect(find.text('178 of 178 members'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('members-sort')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Name A–Z'), findsOneWidget);
    await tester.enterText(search, 'm-0001');
    await tester.pumpAndSettle();
    expect(find.text('Poovalli Induchoodan'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('members-clear-search')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('members-filter-No plan')),
    );
    await tester.tap(find.byKey(const ValueKey('members-filter-No plan')));
    await tester.pumpAndSettle();
    expect(find.text('No matching members'), findsNothing);
    expect(find.text('Poovalli Induchoodan'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'member controls collapse into the list and return on reverse scroll',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await openMembers(tester);
      final list = find.byKey(const ValueKey('members-list'));
      final controls = find.byKey(const ValueKey('members-controls'));
      final sliver = find.byKey(
        const ValueKey('members-controls-sliver'),
        skipOffstage: false,
      );
      final search = find.byKey(const ValueKey('members-search'));
      final filter = find.byKey(const ValueKey('members-filter-Active'));
      await tester.enterText(search, 'Sample');
      await tester.pumpAndSettle();
      await tester.tap(filter);
      await tester.pumpAndSettle();

      final header = find.byKey(const ValueKey('members-header'));
      final add = find.byKey(const ValueKey('members-add'));
      final sidebar = find.byKey(const ValueKey('sidebar'));
      final headerRect = tester.getRect(header);
      final addRect = tester.getRect(add);
      final sidebarRect = tester.getRect(sidebar);
      final controlsHeight = tester.getSize(controls).height;
      final scroll = tester.widget<CustomScrollView>(list).controller!;
      double visibleControls() =>
          tester.renderObject<RenderSliver>(sliver).geometry!.paintExtent;
      expect(visibleControls(), closeTo(controlsHeight, .1));

      await tester.drag(list, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(controlsHeight));
      expect(visibleControls(), 0);
      expect(search.hitTestable(), findsNothing);
      expect(filter.hitTestable(), findsNothing);
      expect(tester.getRect(header), headerRect);
      expect(tester.getRect(add), addRect);
      expect(tester.getRect(sidebar), sidebarRect);
      expect(
        find.byKey(const ValueKey('pull-refresh-indicator')),
        findsNothing,
      );

      final previousOffset = scroll.offset;
      await tester.drag(list, const Offset(0, 60));
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
      expect(scroll.offset, lessThan(previousOffset));
      expect(visibleControls(), closeTo(controlsHeight, .1));
      expect(search.hitTestable(), findsOneWidget);
      expect(tester.widget<TextField>(search).controller!.text, 'Sample');
      expect(tester.widget<ChoiceChip>(filter).selected, isTrue);
      expect(tester.getRect(header), headerRect);
      expect(
        find.byKey(const ValueKey('pull-refresh-indicator')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('members-sort')));
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
      expect(visibleControls(), closeTo(controlsHeight, .1));
      expect(tester.widget<TextField>(search).controller!.text, 'Sample');
      expect(tester.widget<ChoiceChip>(filter).selected, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('add validates, assigns a number and survives sidebar changes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await openMembers(tester);
    await tester.tap(find.byKey(const ValueKey('members-add')));
    await tester.pumpAndSettle();
    final next = find.byKey(const ValueKey('member-add-next'));
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('Enter the member’s full name'), findsOneWidget);
    expect(find.text('Enter a phone number'), findsNWidgets(2));
    expect(find.text('Enter the address'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('member-name')),
      ' Test Member ',
    );
    await tester.enterText(find.byKey(const ValueKey('member-phone')), '123');
    await tester.enterText(
      find.byKey(const ValueKey('member-email')),
      'not-an-email',
    );
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(
      find.text('Enter a valid phone number (7–15 digits)'),
      findsOneWidget,
    );
    expect(find.text('Enter a valid email address'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('member-phone')),
      '+1 (202) 555-0101',
    );
    await tester.enterText(
      find.byKey(const ValueKey('member-email')),
      'test@example.com',
    );
    await advanceRegistrationToPayment(tester);
    await tester.tap(find.byKey(const ValueKey('member-add-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('member-add-dialog')), findsNothing);
    final details = find.byKey(const ValueKey('member-details'));
    for (final text in [
      'Test Member',
      'M-0179',
      'test@example.com',
      'Silver Plan',
    ]) {
      expect(
        find.descendant(of: details, matching: find.text(text)),
        findsAtLeastNWidgets(1),
      );
    }
    await tester.tap(find.byKey(const ValueKey('member-details-close')));
    await tester.pumpAndSettle();
    expect(find.text('179 of 179 members'), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('members-list')),
      const Offset(0, 500),
    );
    await tester.pumpAndSettle();
    expect(find.text('179 of 179 members'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nav-Settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-Members')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('members-search')),
      'm-0179',
    );
    await tester.pumpAndSettle();
    expect(find.text('Test Member'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('members-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('member-add-cancel')));
    await tester.pumpAndSettle();
    expect(find.text('1 of 179 members'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'normal app has no invented members and cannot save registration',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await openMembers(tester, preview: false);
      expect(find.text('Waiting for member connection'), findsOneWidget);
      expect(find.text('178 of 178 members'), findsNothing);
      expect(find.textContaining('Sample data'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('members-add')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('member-add-next')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('member-add-cancel')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'members, profiles and add form fit tablet and large-text layouts',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.view.resetViewInsets);
      for (final (size, scale, keyboardHeight) in const [
        (Size(1024, 768), 1.0, 0.0),
        (Size(1024, 768), 1.0, 300.0),
        (Size(800, 600), 2.0, 0.0),
        (Size(360, 740), 1.0, 0.0),
      ]) {
        await tester.binding.setSurfaceSize(size);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        tester.view.viewInsets = FakeViewPadding(
          bottom: keyboardHeight * tester.view.devicePixelRatio,
        );
        await tester.pumpWidget(
          const GymManagementApp(home: DashboardScreen(showSampleData: true)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('nav-Members')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byKey(const ValueKey('members-list'))).height,
          greaterThan(0),
        );
        final sidebarRect = tester.getRect(
          find.byKey(const ValueKey('sidebar')),
        );
        await tester.enterText(
          find.byKey(const ValueKey('members-search')),
          'M-0001',
        );
        await tester.pumpAndSettle();
        final first = find.byKey(const ValueKey('member-M-0001'));
        await tester.ensureVisible(first);
        await tester.tapAt(tester.getTopLeft(first) + const Offset(24, 24));
        await tester.pumpAndSettle();
        await tester.drag(
          find.byKey(const ValueKey('member-details-scroll')),
          const Offset(0, -300),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('member-details-close')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('members-add')));
        await tester.pumpAndSettle();
        await tester.drag(
          find.byKey(const ValueKey('member-form-scroll')),
          const Offset(0, -300),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('member-add-cancel')));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byKey(const ValueKey('sidebar'))),
          sidebarRect,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
}
