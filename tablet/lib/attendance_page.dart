import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

import 'sample_attendance.dart';

class AttendancePage extends StatefulWidget {
  const AttendancePage({super.key, this.showSampleData = false});

  final bool showSampleData;

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage>
    with SingleTickerProviderStateMixin {
  final _search = TextEditingController();
  final _listScroll = ScrollController();
  late final AnimationController _shutter;
  late final Animation<double> _shutterSize;
  bool _overviewExpanded = true;
  bool _resettingList = false;
  DateTime _date = DateUtils.dateOnly(gymNow());
  MembershipStatus? _status;
  bool _latestFirst = true;

  bool get _isPreview => kDebugMode && widget.showSampleData;

  @override
  void initState() {
    super.initState();
    _shutter = AnimationController(
      vsync: this,
      value: 1,
      duration: const Duration(milliseconds: 280),
    );
    _shutterSize = _shutter.drive(CurveTween(curve: Curves.easeInOutCubic));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _shutter.duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 280);
  }

  @override
  void dispose() {
    _search.dispose();
    _listScroll.dispose();
    _shutter.dispose();
    super.dispose();
  }

  void _showOverview(bool expanded) {
    if (_overviewExpanded == expanded) return;
    setState(() => _overviewExpanded = expanded);
    if (expanded) {
      _shutter.forward();
    } else {
      _shutter.reverse();
    }
  }

  bool _onListScroll(ScrollNotification notification) {
    if (_resettingList ||
        notification.depth != 0 ||
        notification.metrics.axis != Axis.vertical) {
      return false;
    }
    final expanded = switch (notification) {
      UserScrollNotification(direction: ScrollDirection.forward) => true,
      UserScrollNotification(direction: ScrollDirection.reverse) => false,
      OverscrollNotification() when notification.overscroll != 0 =>
        notification.overscroll < 0,
      _ => null,
    };
    // Follow user direction, not offset corrections caused by the animation.
    if (expanded != null) _showOverview(expanded);
    return false;
  }

  void _resetList() {
    if (!_listScroll.hasClients) return;
    _resettingList = true;
    try {
      _listScroll.jumpTo(0);
    } finally {
      _resettingList = false;
    }
  }

  Future<void> _chooseDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateUtils.dateOnly(gymNow()),
      helpText: 'View attendance date',
    );
    if (date != null && mounted) {
      setState(() => _date = date);
      _resetList();
      _showOverview(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final today = DateUtils.dateOnly(gymNow());
    final isToday = DateUtils.isSameDay(_date, today);
    final entries = _isPreview ? sampleAttendanceFor(_date) : <SampleCheckIn>[];
    final memberVisits = <String, int>{};
    final needsAttention = <String>{};
    for (final entry in entries) {
      memberVisits.update(
        entry.memberNumber,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      if (entry.membership != MembershipStatus.active) {
        needsAttention.add(entry.memberNumber);
      }
    }
    final query = _search.text.trim().toLowerCase();
    final visible =
        entries.where((entry) {
          return (_status == null || entry.membership == _status) &&
              (entry.name.toLowerCase().contains(query) ||
                  entry.memberNumber.toLowerCase().contains(query));
        }).toList()..sort((a, b) {
          final order = _latestFirst
              ? b.time.compareTo(a.time)
              : a.time.compareTo(b.time);
          return order != 0 ? order : a.memberNumber.compareTo(b.memberNumber);
        });
    final dateLabel = '${localizations.formatMediumDate(_date)} ${_date.year}';

    return LayoutBuilder(
      builder: (context, constraints) {
        final readableWidth =
            constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1);
        final readableHeight =
            constraints.maxHeight / MediaQuery.textScalerOf(context).scale(1);
        final wide = readableWidth >= 640;
        final compactControls = readableWidth < 600 || readableHeight < 820;
        // On narrow/large-text displays, reserve the viewport for the list.
        // The same summary remains available from the header's summary button.
        final roomForOverview = readableWidth >= 600 && readableHeight >= 660;
        final dateControls = Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('attendance-date'),
              onPressed: _chooseDate,
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text(
                compactControls
                    ? localizations.formatCompactDate(_date)
                    : '${isToday ? 'Today · ' : ''}$dateLabel',
              ),
            ),
            if (!compactControls || !isToday)
              TextButton(
                key: const ValueKey('attendance-today'),
                onPressed: isToday
                    ? null
                    : () {
                        setState(() => _date = today);
                        _resetList();
                        _showOverview(true);
                      },
                child: const Text('Today'),
              ),
            IconButton(
              key: const ValueKey('attendance-toggle-summary'),
              tooltip: roomForOverview
                  ? (_overviewExpanded
                        ? 'Hide daily summary'
                        : 'Show daily summary')
                  : 'View daily summary',
              icon: Icon(
                _overviewExpanded && roomForOverview
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
              ),
              onPressed: () {
                if (roomForOverview) {
                  _showOverview(!_overviewExpanded);
                } else {
                  showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Daily attendance summary'),
                      content: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _isPreview
                                  ? 'Sample data · $dateLabel'
                                  : 'Attendance is not connected yet.',
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Members checked in: ${_isPreview ? memberVisits.length : '—'}',
                            ),
                            Text(
                              'Total check-ins: ${_isPreview ? entries.length : '—'}',
                            ),
                            Text(
                              'Needs attention: ${_isPreview ? needsAttention.length : '—'}',
                            ),
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                }
              },
            ),
          ],
        );
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Attendance',
              style:
                  (readableWidth < 400
                          ? theme.textTheme.headlineSmall
                          : theme.textTheme.headlineMedium)
                      ?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (wide && readableHeight >= 660) ...[
              const SizedBox(height: 8),
              Text(
                'See who checked in and when.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        );
        final summaries = [
          (
            title: 'Members checked in',
            value: '${memberVisits.length}',
            hint: 'Unique members on this date',
          ),
          (
            title: 'Total check-ins',
            value: '${entries.length}',
            hint: 'Repeat visits counted separately',
          ),
          (
            title: 'Needs attention',
            value: '${needsAttention.length}',
            hint: 'Expiring or expired memberships',
          ),
        ];
        final summaryCards = [
          for (final summary in summaries)
            Container(
              key: ValueKey('attendance-summary-${summary.title}'),
              padding: EdgeInsets.all(compactControls ? 16 : 20),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F0F0),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(summary.title, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 8),
                  Text(
                    _isPreview ? summary.value : '—',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (!compactControls) ...[
                    const SizedBox(height: 8),
                    Text(
                      summary.hint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ];

        return Column(
          key: const ValueKey('attendance-page'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              key: const ValueKey('attendance-header'),
              color: theme.scaffoldBackgroundColor,
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: heading),
                        const SizedBox(width: 24),
                        dateControls,
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        heading,
                        const SizedBox(height: 12),
                        dateControls,
                      ],
                    ),
            ),
            SizedBox(height: compactControls ? 12 : 24),
            SizeTransition(
              key: const ValueKey('attendance-overview-shutter'),
              sizeFactor: roomForOverview
                  ? _shutterSize
                  : const AlwaysStoppedAnimation(0.0),
              alignment: Alignment.topLeft,
              child: ExcludeSemantics(
                excluding: !roomForOverview || !_overviewExpanded,
                child: IgnorePointer(
                  ignoring: !roomForOverview || !_overviewExpanded,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        key: const ValueKey('attendance-info-ribbon'),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.07,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 20,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _isPreview
                                    ? compactControls
                                          ? 'Sample data · Not live attendance.'
                                          : 'Sample data · Example visits, not live attendance. Today and yesterday are available to preview.'
                                    : compactControls
                                    ? 'Attendance is not connected yet.'
                                    : 'Attendance is not connected yet. Check-ins will appear here once the backend and terminal are connected.',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: compactControls ? 12 : 24),
                      if (readableWidth >= 600)
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (
                                var index = 0;
                                index < summaryCards.length;
                                index++
                              ) ...[
                                if (index > 0) const SizedBox(width: 20),
                                Expanded(child: summaryCards[index]),
                              ],
                            ],
                          ),
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (
                              var index = 0;
                              index < summaryCards.length;
                              index++
                            ) ...[
                              if (index > 0) const SizedBox(height: 20),
                              summaryCards[index],
                            ],
                          ],
                        ),
                      SizedBox(height: compactControls ? 20 : 28),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent &&
                      event.scrollDelta.dy != 0) {
                    _showOverview(event.scrollDelta.dy < 0);
                  }
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (details) {
                    if (details.delta.dy != 0) {
                      _showOverview(details.delta.dy > 0);
                    }
                  },
                  child: Container(
                    key: const ValueKey('attendance-list'),
                    padding: EdgeInsets.all(compactControls ? 12 : 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: const Color(0xFFDDDDDD)),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          key: const ValueKey('attendance-card-title'),
                          readableWidth < 400
                              ? 'Check-ins'
                              : isToday
                              ? "Today's check-ins"
                              : 'Check-ins · $dateLabel',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          compactControls
                              ? '${_isPreview ? 'Sample data' : 'Not connected'} · IST'
                              : '${_isPreview ? 'Sample data' : 'Not connected'} · '
                                    'Times in IST · Membership status at check-in',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        SizedBox(height: compactControls ? 8 : 20),
                        TextField(
                          key: const ValueKey('attendance-search'),
                          controller: _search,
                          onChanged: (_) {
                            _resetList();
                            setState(() {});
                          },
                          decoration: InputDecoration(
                            labelText: 'Search name or member number',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: _search.text.isEmpty
                                ? null
                                : IconButton(
                                    key: const ValueKey(
                                      'attendance-clear-search',
                                    ),
                                    tooltip: 'Clear search',
                                    onPressed: () {
                                      _resetList();
                                      setState(_search.clear);
                                    },
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        SizedBox(height: compactControls ? 8 : 16),
                        SingleChildScrollView(
                          key: const ValueKey('attendance-filters'),
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            spacing: 8,
                            children: [
                              for (final status in [
                                null,
                                ...MembershipStatus.values,
                              ])
                                ChoiceChip(
                                  key: ValueKey(
                                    'attendance-filter-${status?.name ?? 'all'}',
                                  ),
                                  label: Text(status?.label ?? 'All members'),
                                  selected: _status == status,
                                  onSelected: (_) {
                                    _resetList();
                                    setState(() => _status = status);
                                  },
                                ),
                            ],
                          ),
                        ),
                        SizedBox(height: compactControls ? 8 : 16),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _isPreview
                                    ? '${visible.length} of ${entries.length} check-ins'
                                    : 'Check-ins unavailable',
                                key: const ValueKey('attendance-result-count'),
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                            const SizedBox(width: 16),
                            if (compactControls)
                              IconButton(
                                key: const ValueKey('attendance-sort'),
                                tooltip: _latestFirst
                                    ? 'Latest first'
                                    : 'Earliest first',
                                onPressed: () {
                                  _resetList();
                                  setState(() => _latestFirst = !_latestFirst);
                                },
                                icon: Icon(
                                  _latestFirst
                                      ? Icons.arrow_downward_rounded
                                      : Icons.arrow_upward_rounded,
                                  size: 18,
                                ),
                              )
                            else
                              TextButton.icon(
                                key: const ValueKey('attendance-sort'),
                                onPressed: () {
                                  _resetList();
                                  setState(() => _latestFirst = !_latestFirst);
                                },
                                icon: Icon(
                                  _latestFirst
                                      ? Icons.arrow_downward_rounded
                                      : Icons.arrow_upward_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  _latestFirst
                                      ? 'Latest first'
                                      : 'Earliest first',
                                ),
                              ),
                          ],
                        ),
                        const Divider(color: Color(0xFFDDDDDD)),
                        if (wide && visible.isNotEmpty)
                          Padding(
                            padding: EdgeInsets.symmetric(
                              vertical: compactControls ? 8 : 12,
                            ),
                            child: DefaultTextStyle(
                              style: theme.textTheme.labelLarge!.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              child: const Row(
                                children: [
                                  Expanded(child: Text('Member')),
                                  SizedBox(width: 20),
                                  SizedBox(width: 112, child: Text('Check-in')),
                                  SizedBox(width: 20),
                                  SizedBox(
                                    width: 160,
                                    child: Text('Membership'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        Expanded(
                          child: NotificationListener<ScrollNotification>(
                            onNotification: _onListScroll,
                            child: Scrollbar(
                              controller: _listScroll,
                              child: ListView(
                                key: const ValueKey('attendance-scroll'),
                                controller: _listScroll,
                                primary: false,
                                physics: const AlwaysScrollableScrollPhysics(
                                  parent: ClampingScrollPhysics(),
                                ),
                                padding: EdgeInsets.zero,
                                children: [
                                  if (visible.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 36,
                                      ),
                                      child: Column(
                                        children: [
                                          Icon(
                                            _isPreview
                                                ? Icons.search_off_rounded
                                                : Icons.cloud_off_outlined,
                                            size: 36,
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            !_isPreview
                                                ? 'Waiting for attendance connection'
                                                : entries.isEmpty
                                                ? 'No sample check-ins for this date'
                                                : 'No matching check-ins',
                                            textAlign: TextAlign.center,
                                            style: theme.textTheme.titleMedium,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            !_isPreview
                                                ? 'No live records or totals are available yet.'
                                                : entries.isEmpty
                                                ? 'Choose today or yesterday to explore the sample list.'
                                                : 'Try a different name, member number, or status.',
                                            textAlign: TextAlign.center,
                                            style: theme.textTheme.bodyMedium,
                                          ),
                                          if (query.isNotEmpty ||
                                              _status != null)
                                            TextButton(
                                              key: const ValueKey(
                                                'attendance-reset-filters',
                                              ),
                                              onPressed: () {
                                                _resetList();
                                                setState(() {
                                                  _search.clear();
                                                  _status = null;
                                                });
                                              },
                                              child: const Text(
                                                'Clear filters',
                                              ),
                                            ),
                                        ],
                                      ),
                                    )
                                  else ...[
                                    for (
                                      var index = 0;
                                      index < visible.length;
                                      index++
                                    ) ...[
                                      if (index > 0)
                                        const Divider(
                                          height: 1,
                                          color: Color(0xFFDDDDDD),
                                        ),
                                      _AttendanceRow(
                                        key: ValueKey(
                                          'attendance-entry-${visible[index].memberNumber}-${visible[index].time.millisecondsSinceEpoch}',
                                        ),
                                        entry: visible[index],
                                        visits:
                                            memberVisits[visible[index]
                                                .memberNumber]!,
                                        wide: wide,
                                      ),
                                    ],
                                  ],
                                  const SizedBox(height: 16),
                                  Text(
                                    'Check-ins record visits, not who is currently inside the gym. Staff authorization is not connected yet.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
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
    );
  }
}

class _AttendanceRow extends StatelessWidget {
  const _AttendanceRow({
    super.key,
    required this.entry,
    required this.visits,
    required this.wide,
  });

  final SampleCheckIn entry;
  final int visits;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final words = entry.name.split(' ');
    final initials =
        '${words.first[0]}${words.length > 1 ? words.last[0] : ''}';
    final member = Row(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: const Color(0xFFE4F0ED),
          foregroundColor: theme.colorScheme.primary,
          child: Text(
            initials,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.name,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${entry.memberNumber}${visits > 1 ? ' · $visits check-ins' : ''}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final time = Text(
      MaterialLocalizations.of(context)
          .formatTimeOfDay(TimeOfDay.fromDateTime(entry.time)),
      style: theme.textTheme.bodyMedium,
    );
    final status = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: entry.membership.color,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        entry.statusLabel,
        textAlign: TextAlign.center,
        style: theme.textTheme.labelMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: wide
          ? Row(
              children: [
                Expanded(child: member),
                const SizedBox(width: 20),
                SizedBox(width: 112, child: time),
                const SizedBox(width: 20),
                SizedBox(
                  width: 160,
                  child: Align(alignment: Alignment.centerLeft, child: status),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                member,
                const SizedBox(height: 12),
                Wrap(
                  spacing: 20,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [time, status],
                ),
              ],
            ),
    );
  }
}
