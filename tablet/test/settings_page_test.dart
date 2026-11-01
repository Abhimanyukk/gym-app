import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/dashboard_screen.dart';
import 'package:gym_management_app/main.dart';
import 'package:gym_management_app/settings_preview.dart';

Future<void> openSettings(WidgetTester tester, {bool preview = true}) async {
  await tester.pumpWidget(
    GymManagementApp(home: DashboardScreen(showSampleData: preview)),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('nav-Settings')));
  await tester.pumpAndSettle();
}

Future<void> enterSetting(WidgetTester tester, String key, String value) async {
  final field = find.byKey(ValueKey(key));
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pumpAndSettle();
}

Future<void> tapSetting(WidgetTester tester, String key) async {
  final button = find.byKey(ValueKey(key));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  test(
    'shared admin state rejects duplicates, a fourth admin and live changes',
    () {
      final state = SettingsPreview(enabled: true);
      expect(state.admins.length, 1);
      expect(
        state.addAdmin((name: 'Duplicate', email: ' ADMIN@example.com ')),
        'An admin with this email already exists',
      );
      expect(state.addAdmin((name: 'Test', email: 'bad')), isNotNull);
      expect(state.addAdmin((name: '', email: 'valid@example.com')), isNotNull);
      for (var index = 2; index <= 3; index++) {
        expect(
          state.addAdmin((
            name: 'Admin $index',
            email: 'admin$index@example.com',
          )),
          isNull,
        );
      }
      expect(state.canAddAdmin, isFalse);
      expect(
        state.addAdmin((name: 'Fourth', email: 'fourth@example.com')),
        'Maximum of 3 admins reached.',
      );
      expect(state.admins.length, 3);
      expect(() => state.admins.clear(), throwsUnsupportedError);
      final live = SettingsPreview();
      expect(live.admins, isEmpty);
      expect(
        live.addAdmin((name: 'Test', email: 'test@example.com')),
        isNotNull,
      );
      expect(live.admins, isEmpty);
    },
  );

  test('server preferences reject credentials and malformed addresses', () {
    for (final address in [
      '',
      'https://gym.example',
      'http://192.168.1.4:8000/api',
    ]) {
      expect(serverAddressError(address), isNull);
    }
    for (final address in [
      '192.168.1.4',
      'ftp://gym.example',
      'https://user:password@gym.example',
      'https://gym.example?token=secret',
      'https://gym.example#secret',
      'https://gym.example:99999',
      'https://gym .example',
    ]) {
      expect(serverAddressError(address), isNotNull, reason: address);
    }
  });

  testWidgets('add admin validates identity and passwords and caps at three', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await openSettings(tester);
    expect(find.text('1 of 3 admin slots used'), findsOneWidget);
    await tapSetting(tester, 'settings-add-admin');
    await tapSetting(tester, 'settings-dialog-save');
    expect(find.text('Enter the admin’s full name'), findsOneWidget);
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Use 15–128 characters'), findsOneWidget);
    await enterSetting(tester, 'settings-admin-name', 'Test Admin Two');
    await enterSetting(tester, 'settings-admin-email', 'ADMIN@example.com');
    await enterSetting(tester, 'settings-new-password', 'preview password two');
    await enterSetting(
      tester,
      'settings-confirm-password',
      'different password',
    );
    await tapSetting(tester, 'settings-dialog-save');
    expect(
      find.text('An admin with this email already exists'),
      findsOneWidget,
    );
    expect(find.text('Passwords do not match'), findsOneWidget);
    await enterSetting(tester, 'settings-admin-email', 'two@example.com');
    await enterSetting(
      tester,
      'settings-confirm-password',
      'preview password two',
    );
    await tapSetting(tester, 'settings-dialog-save');
    expect(find.text('2 of 3 admin slots used'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nav-Members')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-Settings')));
    await tester.pumpAndSettle();
    expect(find.text('Test Admin Two'), findsOneWidget);
    await tapSetting(tester, 'settings-add-admin');
    await enterSetting(tester, 'settings-admin-name', 'Test Admin Three');
    await enterSetting(tester, 'settings-admin-email', 'three@example.com');
    await enterSetting(
      tester,
      'settings-new-password',
      'preview password three',
    );
    await enterSetting(
      tester,
      'settings-confirm-password',
      'preview password three',
    );
    await tapSetting(tester, 'settings-dialog-save');
    expect(find.text('3 of 3 admin slots used'), findsOneWidget);
    expect(find.text('Maximum of 3 admins reached.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('settings-add-admin')),
          )
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await openSettings(tester);
    expect(find.text('1 of 3 admin slots used'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('password form validates without storing or claiming a change', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await openSettings(tester);
    await tapSetting(tester, 'settings-change-password');
    await tapSetting(tester, 'settings-dialog-save');
    expect(find.text('Enter the current password'), findsOneWidget);
    await enterSetting(
      tester,
      'settings-current-password',
      'preview current pass',
    );
    await enterSetting(tester, 'settings-new-password', 'preview current pass');
    await enterSetting(
      tester,
      'settings-confirm-password',
      'preview current pass',
    );
    await tapSetting(tester, 'settings-dialog-save');
    expect(find.text('Choose a different password'), findsOneWidget);
    await enterSetting(
      tester,
      'settings-new-password',
      'preview updated password',
    );
    await enterSetting(
      tester,
      'settings-confirm-password',
      'preview updated password',
    );
    final field = find.byKey(const ValueKey('settings-new-password'));
    expect(tester.widget<TextFormField>(field).controller!.text, isNotEmpty);
    final passwordController = tester.widget<TextFormField>(field).controller!;
    await tapSetting(tester, 'settings-dialog-save');
    expect(passwordController.text, isEmpty);
    expect(
      find.text(
        'Preview validation passed. No password was verified or changed.',
      ),
      findsOneWidget,
    );
    await tapSetting(tester, 'settings-change-password');
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('settings-current-password')),
          )
          .controller!
          .text,
      isEmpty,
    );
    await tapSetting(tester, 'settings-dialog-cancel');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'preferences validate and keep preview changes across navigation',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await openSettings(tester);
      await tapSetting(tester, 'settings-edit-preferences');
      await enterSetting(tester, 'settings-gym-name', '');
      await enterSetting(tester, 'settings-server-url', 'wrong-address');
      await tapSetting(tester, 'settings-dialog-save');
      expect(find.text('Enter the gym name'), findsOneWidget);
      expect(
        find.textContaining('Enter an HTTP(S) server address'),
        findsOneWidget,
      );
      await enterSetting(tester, 'settings-gym-name', 'Preview Gym');
      await enterSetting(
        tester,
        'settings-server-url',
        'https://gym.example:8000',
      );
      await tapSetting(tester, 'settings-dialog-save');
      expect(find.text('Preview Gym'), findsOneWidget);
      expect(find.text('https://gym.example:8000'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nav-Members')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-Settings')));
      await tester.pumpAndSettle();
      expect(find.text('Preview Gym'), findsOneWidget);
      await tapSetting(tester, 'settings-edit-preferences');
      await enterSetting(tester, 'settings-gym-name', 'Not saved');
      await tapSetting(tester, 'settings-dialog-cancel');
      expect(find.text('Preview Gym'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'normal app shows no fictional accounts and cannot mutate settings',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await openSettings(tester, preview: false);
      expect(find.text('Sample Admin'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('settings-add-admin')),
            )
            .onPressed,
        isNull,
      );
      for (final key in [
        'settings-change-password',
        'settings-edit-preferences',
      ]) {
        await tapSetting(tester, key);
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('settings-dialog-save')),
              )
              .onPressed,
          isNull,
        );
        await tapSetting(tester, 'settings-dialog-cancel');
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'settings title stays fixed while the body scrolls in either direction',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final (size, scale) in const [
        (Size(1024, 768), 1.0),
        (Size(800, 1280), 1.0),
        (Size(800, 600), 2.0),
        (Size(360, 740), 1.0),
        (Size(360, 280), 2.0),
      ]) {
        await tester.binding.setSurfaceSize(size);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        await openSettings(tester);
        final title = find.byKey(const ValueKey('settings-title'));
        final sidebar = find.byKey(const ValueKey('sidebar'));
        final body = find.byKey(const PageStorageKey('settings-scroll'));
        final notice = find.byKey(const ValueKey('settings-notice'));
        final titleRect = tester.getRect(title);
        final sidebarRect = tester.getRect(sidebar);
        final noticeTop = tester.getTopLeft(notice).dy;
        await tester.drag(body, const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(notice).dy, lessThan(noticeTop));
        expect(tester.getRect(title), titleRect);
        expect(tester.getRect(sidebar), sidebarRect);

        await tester.ensureVisible(find.text('Backups & data'));
        await tester.pumpAndSettle();
        expect(tester.getRect(title), titleRect);
        final scrolledTop = tester.getTopLeft(notice).dy;
        await tester.drag(body, const Offset(0, 300));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(notice).dy, greaterThan(scrolledTop));
        expect(tester.getRect(title), titleRect);
        expect(tester.getRect(sidebar), sidebarRect);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets(
    'settings and dialogs adapt to tablets, large text and keyboard',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.view.resetViewInsets);
      for (final (size, scale, keyboard) in const [
        (Size(1024, 768), 1.0, 0.0),
        (Size(800, 600), 2.0, 0.0),
        (Size(360, 740), 1.0, 0.0),
        (Size(1024, 768), 1.0, 300.0),
      ]) {
        await tester.binding.setSurfaceSize(size);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        tester.view.viewInsets = FakeViewPadding(
          bottom: keyboard * tester.view.devicePixelRatio,
        );
        await openSettings(tester);
        final sidebar = find.byKey(const ValueKey('sidebar'));
        final rect = tester.getRect(sidebar);
        for (final key in [
          'settings-add-admin',
          'settings-change-password',
          'settings-edit-preferences',
        ]) {
          await tapSetting(tester, key);
          await tester.drag(
            find.byKey(const ValueKey('settings-form-scroll')),
            const Offset(0, -200),
          );
          await tester.pumpAndSettle();
          await tapSetting(tester, 'settings-dialog-cancel');
          expect(tester.getRect(sidebar), rect);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
}
