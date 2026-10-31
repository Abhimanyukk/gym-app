// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gym_management_app/main.dart';

void main() {
  testWidgets('dumbbell animates to its resting size', (WidgetTester tester) async {
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
      tester.widget<Text>(find.text('Management & Attendance System'))
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
    expect(
      linearGradient.colors,
      [
        const Color.fromRGBO(33, 0, 1, 0.88),
        const Color.fromRGBO(0, 0, 0, 0.88),
      ],
    );
  });
}
