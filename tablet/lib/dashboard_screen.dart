/*  */
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'app_loading.dart';
import 'attendance_page.dart';
import 'dashboard_overview.dart';
import 'member_profile.dart';
import 'members_page.dart';
import 'settings_page.dart';
import 'settings_preview.dart';
import 'replab_api.dart';
import 'device_session.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    this.showSampleData = false,
    this.api,
    this.device,
  });

  final bool showSampleData;
  final RepLabApi? api;
  final DeviceSession? device;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const _sidebarHighlight = Color.fromRGBO(228, 226, 226, 0.2);
  static const _sections = [
    (title: 'Dashboard', icon: 'assets/icons/dashboard.svg', message: ''),
    (title: 'Attendance', icon: 'assets/icons/attendance.svg', message: ''),
    (title: 'Members', icon: 'assets/icons/members.svg', message: ''),
    (title: 'Settings', icon: 'assets/icons/settings.svg', message: ''),
  ];

  int _selectedIndex = 0;
  Map<String, dynamic>? _summary;
  String? _error;
  bool _loading = false;
  final _scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    if (widget.api != null) _refresh();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary = await widget.api!.dashboard();
      if (mounted) setState(() => _summary = summary);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // Keep preview registrations when switching sidebar sections; never persist
  // test member details or pretend this is the staff-authorized backend.
  late final _members = kDebugMode && widget.showSampleData
      ? sampleMembers()
      : <MemberProfile>[];
  late final _settings = SettingsPreview(
    enabled: kDebugMode && widget.showSampleData,
  );

  @override
  Widget build(BuildContext context) {
    final section = _sections[_selectedIndex];

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Keep all four buttons reachable without scrolling on short displays.
          final compactHeight =
              constraints.maxHeight - MediaQuery.paddingOf(context).vertical <
              392;
          final extended = constraints.maxWidth >= 800 && !compactHeight;
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
                          child: Column(
                            key: const ValueKey('sidebar-navigation'),
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (
                                var index = 0;
                                index < _sections.length;
                                index++
                              ) ...[
                                if (index > 0)
                                  SizedBox(height: compactHeight ? 0 : 8),
                                Builder(
                                  builder: (context) {
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
                                        minTileHeight: compactHeight ? 48 : 64,
                                        minVerticalPadding: compactHeight
                                            ? 12
                                            : 18,
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
                                          setState(
                                            () => _selectedIndex = index,
                                          );
                                          if (index == 0 &&
                                              widget.api != null) {
                                            _refresh();
                                          }
                                        },
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ],
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
                  child: _selectedIndex != 0
                      ? switch (_selectedIndex) {
                          1 => AttendancePage(
                            padding: const EdgeInsets.all(32),
                            api: widget.api,
                            showSampleData: kDebugMode && widget.showSampleData,
                          ),
                          2 => MembersPage(
                            padding: const EdgeInsets.all(32),
                            api: widget.api,
                            members: _members,
                            showSampleData: kDebugMode && widget.showSampleData,
                          ),
                          _ => SettingsPage(
                            padding: const EdgeInsets.all(32),
                            preview: _settings,
                            api: widget.api,
                            device: widget.device,
                          ),
                        }
                      : DumbbellRefresh(
                          key: const ValueKey('dashboard-refresh'),
                          padding: const EdgeInsets.all(32),
                          scrollController: _scroll,
                          onRefresh: widget.api != null
                              ? _refresh
                              : () => refreshLocalView(
                                  context,
                                  preview: kDebugMode && widget.showSampleData,
                                  rebuild: () => setState(() {}),
                                ),
                          child: SingleChildScrollView(
                            key: PageStorageKey(section.title),
                            controller: _scroll,
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: ClampingScrollPhysics(),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_loading)
                                  const Center(child: DumbbellLoader()),
                                if (_error != null) ...[
                                  Text(
                                    _error!,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: _refresh,
                                    child: const Text('Retry'),
                                  ),
                                  if (_summary != null)
                                    const Text(
                                      'Previously loaded totals · Pull down to retry.',
                                    ),
                                  const SizedBox(height: 16),
                                ],
                                DashboardOverview(
                                  showSampleData:
                                      kDebugMode && widget.showSampleData,
                                  summary: _summary,
                                  adminName: widget.api?.admin?.name,
                                ),
                              ],
                            ),
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
