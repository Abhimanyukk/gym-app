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
  testWidgets('shows the splash image without the temporary button', (WidgetTester tester) async {
    await tester.pumpWidget(const GymManagementApp());

    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Temporary Button'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is AssetImage,
      ),
      findsOneWidget,
    );

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
