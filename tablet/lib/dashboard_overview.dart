import 'dart:async';

import 'package:flutter/material.dart';

import 'sample_attendance.dart';
import 'member_enrollment.dart';

class DashboardOverview extends StatelessWidget {
  const DashboardOverview({
    super.key,
    this.showSampleData = false,
    this.summary,
    this.adminName,
  });

  final bool showSampleData;
  final Map<String, dynamic>? summary;
  final String? adminName;

  // dover-gain-efficient: reference data is only enabled by the debug preview;
  // do not invent live totals, attendance, staff identity, or revenue calculations.
  static const _metrics = [
    (title: 'Total Members', value: '178', field: 'total_members'),
    (title: 'Present Today', value: '30', field: 'present_today'),
    (title: 'Active Plans', value: '3', field: 'active_plans'),
    (
      title: 'Collections (Today)',
      value: '₹12,346',
      field: 'collections_today_paise',
    ),
  ];

  String _metricValue(String field) {
    final value = summary?[field];
    if (value is! int || value < 0) return '—';
    return field == 'collections_today_paise' ? rupees(value) : '$value';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final checkIns = showSampleData
        ? sampleAttendanceFor(gymNow()).take(4).toList()
        : <SampleCheckIn>[];
    return LayoutBuilder(
      builder: (context, constraints) {
        final readableWidth =
            constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1);
        final columns = readableWidth >= 760
            ? 4
            : readableWidth >= 360
            ? 2
            : 1;
        final cardWidth = (constraints.maxWidth - 20 * (columns - 1)) / columns;

        return Column(
          key: const ValueKey('dashboard-overview'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DashboardHeader(
              showSampleData: showSampleData,
              adminName: adminName,
            ),
            const SizedBox(height: 28),
            Wrap(
              spacing: 20,
              runSpacing: 20,
              children: [
                for (final metric in _metrics)
                  SizedBox(
                    width: cardWidth,
                    child: DecoratedBox(
                      key: ValueKey('summary-${metric.title}'),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F0F0),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              metric.title,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              showSampleData
                                  ? metric.value
                                  : _metricValue(metric.field),
                              key: ValueKey('dashboard-value-${metric.field}'),
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 28),
            Container(
              key: const ValueKey('recent-check-ins'),
              constraints: const BoxConstraints(minHeight: 360),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFDDDDDD)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Recent Check-ins',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (showSampleData)
                    for (var index = 0; index < checkIns.length; index++) ...[
                      if (index > 0)
                        const Divider(height: 1, color: Color(0xFFDDDDDD)),
                      _CheckInRow(
                        name: checkIns[index].name,
                        time: MaterialLocalizations.of(context).formatTimeOfDay(
                          TimeOfDay.fromDateTime(checkIns[index].time),
                        ),
                        status: checkIns[index].statusLabel,
                        statusColor: checkIns[index].membership.color,
                        compact: readableWidth < 640,
                      ),
                    ]
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Column(
                        children: [
                          Icon(
                            Icons.cloud_off_outlined,
                            size: 36,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Waiting for attendance connection',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Check-ins will appear here once attendance is connected.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              showSampleData
                  ? 'Sample data · Backend and staff authorization are not connected.'
                  : summary != null
                  ? '${summary!['active_member_records']} active member records · Active Plans counts enabled catalogue plans. Collections are payments received today (IST), not earned revenue or profit. Attendance is not connected.${summary?['active_plans'] is! int || summary?['collections_today_paise'] is! int ? ' Update the gym server to 0.6.1 for dashboard plan and collection totals.' : ''}'
                  : 'Backend and staff authorization are not connected. Totals are unavailable.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DashboardHeader extends StatefulWidget {
  const _DashboardHeader({required this.showSampleData, this.adminName});

  final bool showSampleData;
  final String? adminName;

  @override
  State<_DashboardHeader> createState() => _DashboardHeaderState();
}

class _DashboardHeaderState extends State<_DashboardHeader> {
  late final Timer _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _clock.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Asia/Kolkata has a fixed UTC+05:30 offset; ignore the preview host's timezone.
    final now = gymNow();
    final period = now.hour < 12
        ? 'Morning'
        : now.hour < 17
        ? 'Afternoon'
        : 'Evening';
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final greeting = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Good $period${widget.adminName != null
              ? ', ${widget.adminName}'
              : widget.showSampleData
              ? ', Admin'
              : ''}',
          key: const ValueKey('dashboard-greeting'),
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Welcome to RepLab Fitness',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    final clock = Text(
      '${localizations.formatMediumDate(now)} ${now.year}   '
      '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(now))} IST',
      key: const ValueKey('dashboard-clock'),
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final readableWidth =
            constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1);
        if (readableWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [greeting, const SizedBox(height: 16), clock],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: greeting),
            const SizedBox(width: 24),
            clock,
          ],
        );
      },
    );
  }
}

class _CheckInRow extends StatelessWidget {
  const _CheckInRow({
    required this.name,
    required this.time,
    required this.status,
    required this.statusColor,
    required this.compact,
  });

  final String name;
  final String time;
  final String status;
  final Color statusColor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final member = Row(
      children: [
        const CircleAvatar(radius: 20, backgroundColor: Color(0xFF2D9CBE)),
        const SizedBox(width: 20),
        Expanded(
          child: Text(
            name,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
    final checkInTime = Text(
      time,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: statusColor,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        status,
        textAlign: TextAlign.center,
        style: theme.textTheme.labelMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                member,
                const SizedBox(height: 12),
                Wrap(
                  spacing: 20,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [checkInTime, badge],
                ),
              ],
            )
          : Row(
              children: [
                Expanded(child: member),
                const SizedBox(width: 24),
                checkInTime,
                const SizedBox(width: 20),
                badge,
              ],
            ),
    );
  }
}
