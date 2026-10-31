import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'dashboard_screen.dart';
import 'main.dart';

void main() {
  if (!kDebugMode || !kIsWeb) {
    throw UnsupportedError('UI preview is only available in debug web runs.');
  }
  runApp(const GymManagementApp(home: DashboardScreen(showSampleData: true)));
}
