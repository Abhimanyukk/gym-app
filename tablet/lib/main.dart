import 'package:flutter/material.dart';

void main() {
  runApp(const GymManagementApp());
}

class GymManagementApp extends StatelessWidget {
  const GymManagementApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gym Management',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF286455),
          surface: const Color(0xFFF7F8F5),
        ),
        useMaterial3: true,
      ),
      home: const Scaffold(),
    );
  }
}
