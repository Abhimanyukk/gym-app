// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gym_management_app/dashboard_screen.dart';
import 'package:gym_management_app/main.dart';
import 'package:gym_management_app/preview.dart' as preview;

void main() {
  test('browser preview cannot run on a native target', () {
    expect(preview.main, throwsUnsupportedError);
  });

  testWidgets('dumbbell animates to its resting size', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const GymManagementApp());

    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Temporary Button'), findsNothing);
    expect(find.text('RepLab Fitness'), findsOneWidget);
    expect(find.text('Management & Attendance System'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    expect(
      find.text('Use your tablet PIN or biometrics to continue.'),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(find.text('RepLab Fitness')).style?.color,
      Colors.white,
    );
    expect(
      tester
          .widget<Text>(find.text('Management & Attendance System'))
          .style
          ?.color,
      Colors.white,
    );

    expect(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is AssetImage,
      ),
      findsOneWidget,
    );

    final scale = tester
        .widget<ScaleTransition>(find.byKey(const ValueKey('dumbbell-scale')))
        .scale;
    expect(scale.value, 3);

    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(scale.value, closeTo(1, 0.001));

    final gradientLayer = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('splash-gradient')),
    );
    final gradient = gradientLayer.decoration as BoxDecoration;
    final linearGradient = gradient.gradient! as LinearGradient;

    expect(linearGradient.begin, Alignment.topCenter);
    expect(linearGradient.end, Alignment.bottomCenter);
    expect(linearGradient.colors, [
      const Color.fromRGBO(33, 0, 1, 0.88),
      const Color.fromRGBO(0, 0, 0, 0.88),
    ]);
  });

  testWidgets('dashboard opens only after successful login', (tester) async {
    const channel = MethodChannel('plugins.flutter.io/local_auth');
    final messenger = tester.binding.defaultBinaryMessenger;
    var authenticated = false;
    var authenticationCalls = 0;

    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'authenticate');
      expect(call.arguments['biometricOnly'], isFalse);
      authenticationCalls++;
      return authenticated;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(const GymManagementApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    expect(authenticationCalls, 1);
    expect(find.byType(DashboardScreen), findsNothing);
    expect(find.text('Authentication was not completed.'), findsOneWidget);

    authenticated = true;
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    expect(authenticationCalls, 2);
    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('section-body')),
        matching: find.text('Welcome to RepLab Fitness'),
      ),
      findsOneWidget,
    );
    expect(find.byType(SplashScreen), findsNothing);
    expect(
      Navigator.of(tester.element(find.byType(DashboardScreen))).canPop(),
      isFalse,
    );
  });

  testWidgets('sidebar switches between all four section bodies', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const GymManagementApp(home: DashboardScreen()));
    await tester.pumpAndSettle();

    final sidebar = find.byKey(const ValueKey('sidebar'));
    final sidebarPosition = tester.getTopLeft(sidebar);
    final body = find.byKey(const ValueKey('section-body'));
    final logoFinder = find.byKey(const ValueKey('sidebar-logo'));
    final logo = tester.widget<CircleAvatar>(logoFinder);
    final logoSvg = tester.widget<SvgPicture>(
      find.descendant(of: logoFinder, matching: find.byType(SvgPicture)),
    );

    expect(logo.backgroundColor, isNotNull);
    expect(
      (logoSvg.bytesLoader as SvgAssetLoader).assetName,
      'assets/icons/dumbell.svg',
    );
    expect(find.byType(SvgPicture), findsNWidgets(5));
    expect(
      tester
          .widget<ListTile>(find.byKey(const ValueKey('nav-Dashboard')))
          .selected,
      isTrue,
    );
    for (final (title, asset) in const [
      ('Dashboard', 'dashboard'),
      ('Attendance', 'attendance'),
      ('Members', 'members'),
      ('Settings', 'settings'),
    ]) {
      final svg = tester.widget<SvgPicture>(
        find.descendant(
          of: find.byKey(ValueKey('nav-$title')),
          matching: find.byType(SvgPicture),
        ),
      );
      expect(
        (svg.bytesLoader as SvgAssetLoader).assetName,
        'assets/icons/$asset.svg',
      );
      expect(
        svg.colorFilter,
        const ColorFilter.mode(Colors.white, BlendMode.srcIn),
      );
      expect(
        tester.getSize(find.byKey(ValueKey('nav-icon-$title'))),
        const Size(24, 24),
      );
      expect(
        tester
            .getTopLeft(
              find.descendant(
                of: find.byKey(ValueKey('nav-$title')),
                matching: find.text(title),
              ),
            )
            .dx,
        sidebarPosition.dx + 72,
      );
    }
    expect(find.text('Welcome to RepLab Fitness'), findsOneWidget);
    expect(find.text('178'), findsNothing);
    expect(find.text('—'), findsNWidgets(4));
    expect(
      find.text('Check-ins will appear here once attendance is connected.'),
      findsOneWidget,
    );

    const sections = [
      ('Attendance', 'Attendance records will appear here.'),
      ('Members', 'Member management will appear here.'),
      ('Settings', 'App settings will appear here.'),
      ('Dashboard', 'Welcome to RepLab Fitness'),
    ];
    var previousMessage = 'Welcome to RepLab Fitness';

    for (final (title, message) in sections) {
      final destination = find.byKey(ValueKey('nav-$title'));
      await tester.tap(destination);
      await tester.pumpAndSettle();

      expect(tester.widget<ListTile>(destination).selected, isTrue);
      for (final tile in tester.widgetList<ListTile>(
        find.descendant(of: sidebar, matching: find.byType(ListTile)),
      )) {
        expect(
          tile.titleTextStyle?.fontWeight,
          tile.selected ? FontWeight.w600 : FontWeight.w400,
        );
        expect(
          tester.getTopLeft(find.byWidget(tile.title!)).dx,
          sidebarPosition.dx + 72,
        );
      }
      expect(
        find.byWidgetPredicate(
          (widget) => widget is ListTile && widget.selected,
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: body,
          matching: find.text(title == 'Dashboard' ? message : title),
        ),
        findsOneWidget,
      );
      expect(find.text(message), findsOneWidget);
      expect(find.text(previousMessage), findsNothing);
      expect(tester.getTopLeft(sidebar), sidebarPosition);
      previousMessage = message;
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('sidebar keeps compact tablet proportions and dark styling', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: DashboardScreen()));
    await tester.pumpAndSettle();

    const highlight = Color.fromRGBO(228, 226, 226, 0.2);
    final sidebar = find.byKey(const ValueKey('sidebar'));
    final logo = find.byKey(const ValueKey('sidebar-logo'));
    final dashboard = find.byKey(const ValueKey('nav-Dashboard'));
    final tile = tester.widget<ListTile>(dashboard);
    final icon = tester.widget<SvgPicture>(
      find.descendant(of: dashboard, matching: find.byType(SvgPicture)),
    );

    expect(tester.widget<Material>(sidebar).color, const Color(0xFF140101));
    expect(tester.getSize(sidebar), const Size(256, 1200));
    expect(tester.getTopLeft(logo), const Offset(24, 24));
    expect(tester.getSize(logo), const Size(64, 64));
    expect(tester.widget<CircleAvatar>(logo).backgroundColor, highlight);
    expect(tester.getTopLeft(dashboard), const Offset(0, 112));
    expect(tester.getSize(dashboard), const Size(256, 64));
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('nav-Attendance'))).dy,
      tester.getBottomLeft(dashboard).dy + 8,
    );
    expect(tile.selectedTileColor, highlight);
    expect(tile.contentPadding, const EdgeInsets.symmetric(horizontal: 24));
    expect(tile.horizontalTitleGap, 24);
    expect(tile.titleTextStyle?.color, Colors.white);
    expect(tile.titleTextStyle?.fontSize, 16);
    expect(tile.titleTextStyle?.fontWeight, FontWeight.w600);
    expect(tile.titleTextStyle?.height, 20 / 16);
    expect(icon.width, 24);
    expect(icon.height, 24);
    expect(tester.takeException(), isNull);

    await tester.binding.setSurfaceSize(const Size(800, 600));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: const DashboardScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(sidebar).width, 256);
    expect(
      tester.getSize(find.byKey(const ValueKey('section-body'))).width,
      544,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('sidebar stays fixed while narrow-screen content scrolls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 280));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: const DashboardScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final sidebar = find.byKey(const ValueKey('sidebar'));
    final sidebarPosition = tester.getTopLeft(sidebar);
    final logo = find.byKey(const ValueKey('sidebar-logo'));
    final logoPosition = tester.getTopLeft(logo);
    final body = find.byKey(const ValueKey('section-body'));
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: body, matching: find.byType(Scrollable)),
    );

    expect(tester.getSize(sidebar).width, 80);
    await tester.drag(body, const Offset(0, -160));
    await tester.pumpAndSettle();

    expect(scrollable.position.pixels, greaterThan(0));
    expect(tester.getTopLeft(sidebar), sidebarPosition);
    expect(tester.getTopLeft(logo), logoPosition);

    await tester.drag(
      find.byKey(const ValueKey('sidebar-navigation')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    final settings = find.byKey(const ValueKey('nav-Settings'));
    await tester.tap(settings);
    await tester.pumpAndSettle();

    expect(tester.widget<ListTile>(settings).selected, isTrue);
    expect(
      find.descendant(of: body, matching: find.text('Settings')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Tooltip>(
            find.ancestor(of: settings, matching: find.byType(Tooltip)),
          )
          .message,
      'Settings',
    );
    expect(tester.getTopLeft(sidebar), sidebarPosition);
    expect(tester.getTopLeft(logo), logoPosition);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'backgrounds fill the display while controls avoid screen insets',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const insets = EdgeInsets.fromLTRB(32, 24, 20, 28);
      const screenData = MediaQueryData(padding: insets, viewPadding: insets);
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(data: screenData, child: DashboardScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final sidebar = find.byKey(const ValueKey('sidebar'));
      final body = find.byKey(const ValueKey('section-body'));
      expect(tester.getRect(sidebar), const Rect.fromLTWH(0, 0, 256, 800));
      expect(tester.getRect(body), const Rect.fromLTWH(256, 0, 944, 800));
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('sidebar-logo'))),
        const Offset(56, 48),
      );
      for (final title in ['Dashboard', 'Attendance', 'Members', 'Settings']) {
        expect(
          tester
              .getTopLeft(
                find.descendant(of: sidebar, matching: find.text(title)),
              )
              .dx,
          32 + 72,
        );
      }
      final contentScroll = find.descendant(
        of: body,
        matching: find.byType(SingleChildScrollView),
      );
      expect(tester.getTopLeft(contentScroll), const Offset(256, 24));
      expect(tester.getSize(contentScroll).width, 944 - 20);

      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(data: screenData, child: SplashScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const ValueKey('splash-gradient'))),
        const Rect.fromLTWH(0, 0, 1200, 800),
      );
      final safeContent = find
          .descendant(of: find.byType(SafeArea), matching: find.byType(Center))
          .first;
      expect(
        tester.getRect(safeContent),
        const Rect.fromLTWH(32, 24, 1148, 748),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dashboard preview shows reference contents and adapts to width',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const summaries = [
        'Total Members',
        'Present Today',
        'Active Plans',
        'Revenue (Today)',
      ];

      for (final (size, scale, columns) in const [
        (Size(1600, 1000), 1.0, 4),
        (Size(1024, 768), 1.0, 2),
        (Size(800, 600), 2.0, 1),
        (Size(360, 740), 1.0, 1),
      ]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(
          GymManagementApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: const DashboardScreen(showSampleData: true),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Welcome to RepLab Fitness'), findsOneWidget);
        expect(find.textContaining('Sample data'), findsOneWidget);
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('dashboard-greeting')))
              .data,
          matches(r'^Good (Morning|Afternoon|Evening), Admin$'),
        );
        final clock = tester.widget<Text>(
          find.byKey(const ValueKey('dashboard-clock')),
        );
        final today = DateTime.now().toUtc().add(
          const Duration(hours: 5, minutes: 30),
        );
        expect(clock.data, contains('${today.year}'));
        expect(clock.data, endsWith('IST'));
        for (final value in ['178', '30', '3', '\$12,346']) {
          expect(find.text(value), findsOneWidget);
        }
        for (final text in [
          'Recent Check-ins',
          'Poovalli Induchoodan',
          'Bilal John Kurishingal',
          'Nadeshan',
          'Pulikkattil Charlie',
          '08:12 AM',
          '08:04 AM',
          'Expires in 12 days',
          'Active',
          'Due for 2 days',
          'Expires tomorrow',
        ]) {
          expect(find.text(text), findsOneWidget);
        }
        expect(find.text('07:46 AM'), findsNWidgets(2));
        final cards = [
          for (final title in summaries)
            tester.getRect(find.byKey(ValueKey('summary-$title'))),
        ];
        for (var index = 1; index < cards.length; index++) {
          expect(cards[index].width, closeTo(cards.first.width, 0.01));
          if (index < columns) {
            expect(cards[index].top, cards.first.top);
          } else {
            expect(cards[index].top, greaterThan(cards.first.top));
          }
        }
        expect(tester.takeException(), isNull);

        // Leaving Dashboard disposes its clock.
        await tester.drag(
          find.byKey(const ValueKey('sidebar-navigation')),
          const Offset(0, -300),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('nav-Settings')));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 2));
        expect(find.byKey(const ValueKey('dashboard-overview')), findsNothing);
        expect(find.text('App settings will appear here.'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
}
