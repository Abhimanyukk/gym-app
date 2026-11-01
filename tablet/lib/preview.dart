import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'dashboard_screen.dart';
import 'main.dart';

void main() {
  if (!kDebugMode || !kIsWeb) {
    throw UnsupportedError('UI preview is only available in debug web runs.');
  }
  const sample = bool.fromEnvironment('SHOW_SAMPLE_DATA');
  runApp(
    const GymManagementApp(
      home: sample ? DashboardScreen(showSampleData: true) : null,
    ),
  );
}
