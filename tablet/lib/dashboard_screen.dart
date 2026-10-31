/*  */
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'dashboard_overview.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.showSampleData = false});

  final bool showSampleData;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const _sidebarHighlight = Color.fromRGBO(228, 226, 226, 0.2);
  static const _sections = [
    (title: 'Dashboard', icon: 'assets/icons/dashboard.svg', message: ''),
    (
      title: 'Attendance',
      icon: 'assets/icons/attendance.svg',
      message: 'Attendance records will appear here.',
    ),
    (
      title: 'Members',
      icon: 'assets/icons/members.svg',
      message: 'Member management will appear here.',
    ),
    (
      title: 'Settings',
      icon: 'assets/icons/settings.svg',
      message: 'App settings will appear here.',
    ),
  ];

  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final section = _sections[_selectedIndex];

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final extended = constraints.maxWidth >= 800;
          final sidebarWidth = extended ? 256.0 : 80.0;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: sidebarWidth,
                child: Material(
                  key: const ValueKey('sidebar'),
                  color: const Color(0xFF140101),
                  child: SafeArea(
                    right: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: extended
                              ? const EdgeInsets.all(24)
                              : const EdgeInsets.symmetric(vertical: 16),
                          child: Align(
                            alignment: extended
                                ? Alignment.centerLeft
                                : Alignment.center,
                            child: CircleAvatar(
                              key: const ValueKey('sidebar-logo'),
                              radius: extended ? 32 : 24,
                              backgroundColor: _sidebarHighlight,
                              child: SvgPicture.asset(
                                'assets/icons/dumbell.svg',
                                width: extended ? 44 : 32,
                                height: extended ? 44 : 32,
                                colorFilter: const ColorFilter.mode(
                                  Colors.white,
                                  BlendMode.srcIn,
                                ),
                                semanticsLabel: 'RepLab Fitness',
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListView.separated(
                            key: const ValueKey('sidebar-navigation'),
                            padding: EdgeInsets.zero,
                            itemCount: _sections.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final item = _sections[index];
                              final icon = SizedBox.square(
                                key: ValueKey('nav-icon-${item.title}'),
                                dimension: 24,
                                child: Center(
                                  child: SvgPicture.asset(
                                    item.icon,
                                    width: 24,
                                    height: 24,
                                    colorFilter: const ColorFilter.mode(
                                      Colors.white,
                                      BlendMode.srcIn,
                                    ),
                                  ),
                                ),
                              );
                              return Tooltip(
                                message: extended ? '' : item.title,
                                child: ListTile(
                                  key: ValueKey('nav-${item.title}'),
                                  selected: index == _selectedIndex,
                                  selectedTileColor: _sidebarHighlight,
                                  selectedColor: Colors.white,
                                  textColor: Colors.white,
                                  minTileHeight: 64,
                                  minVerticalPadding: 18,
                                  minLeadingWidth: 24,
                                  horizontalTitleGap: 24,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: extended ? 24 : 0,
                                  ),
                                  titleTextStyle: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: index == _selectedIndex
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    height: 20 / 16,
                                  ),
                                  leading: extended ? icon : null,
                                  title: extended
                                      ? Text(item.title)
                                      : Center(child: icon),
                                  onTap: () {
                                    setState(() => _selectedIndex = index);
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                key: const ValueKey('section-body'),
                child: SafeArea(
                  left: false,
                  child: SingleChildScrollView(
                    key: PageStorageKey(section.title),
                    padding: const EdgeInsets.all(32),
                    child: _selectedIndex == 0
                        ? DashboardOverview(
                            showSampleData: kDebugMode && widget.showSampleData,
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                section.title,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                section.message,
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                              const SizedBox(height: 24),
                              // dover-gain-efficient: these are UI placeholders, not staff-authorized backend screens.
                              Text(
                                'Staff authorization is not connected yet.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
