import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_loading.dart';
import 'member_profile.dart';
import 'member_registration_dialog.dart';
import 'member_enrollment.dart';
import 'sample_attendance.dart';
import 'replab_api.dart';

class MembersPage extends StatefulWidget {
  const MembersPage({
    super.key,
    required this.members,
    this.showSampleData = false,
    this.api,
    this.previewPlans,
    this.padding = EdgeInsets.zero,
  });

  final List<MemberProfile> members;
  final bool showSampleData;
  final RepLabApi? api;
  final EnrollmentOptions? previewPlans;
  final EdgeInsets padding;

  @override
  State<MembersPage> createState() => _MembersPageState();
}

class _MembersPageState extends State<MembersPage> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  String _filter = 'All members';
  bool _nameOrder = false;
  final _liveMembers = <MemberProfile>[];
  int _total = 0;
  int _request = 0;
  bool _loading = false;
  String? _error;
  Timer? _debounce;

  bool get _isPreview => kDebugMode && widget.showSampleData;

  @override
  void initState() {
    super.initState();
    if (widget.api != null) _load();
  }

  Future<void> _load({bool append = false}) async {
    final request = ++_request;
    _debounce?.cancel();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.api!.members(
        q: _search.text.trim(),
        active: _filter == 'Active records'
            ? true
            : _filter == 'Inactive records'
            ? false
            : null,
        offset: append ? _liveMembers.length : 0,
      );
      if (!mounted || request != _request) return;
      setState(() {
        if (!append) _liveMembers.clear();
        _liveMembers.addAll(result.items);
        _total = result.total;
      });
    } on ApiException catch (error) {
      if (mounted && request == _request) {
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  void _queryChanged() {
    _update(() {});
    if (widget.api == null) return;
    ++_request; // Ignore any previous query still in flight.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    ++_request;
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _update(VoidCallback change) {
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(change);
  }

  Future<void> _addMember() async {
    final member = await showDialog<MemberProfile>(
      context: context,
      barrierDismissible: false,
      builder: (_) => MemberRegistrationDialog(
        previewPlans: widget.previewPlans,
        members: widget.members,
        canSave: _isPreview || widget.api != null,
        api: widget.api,
      ),
    );
    if (member == null || !mounted) return;
    _update(() {
      if (_isPreview) widget.members.add(member);
      _search.clear();
      _filter = 'All members';
      _nameOrder = false;
    });
    if (widget.api != null) await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.api != null
              ? 'Member saved to the server.'
              : 'Member added to preview only · Not saved to the server.',
        ),
      ),
    );
    _openMember(member);
  }

  void _openMember(MemberProfile member) {
    showDialog<void>(
      context: context,
      builder: (_) => widget.api != null
          ? _LiveMemberDetails(api: widget.api!, member: member)
          : _MemberDetails(member: member),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final members = widget.api != null
        ? _liveMembers
        : _isPreview
        ? widget.members
        : <MemberProfile>[];
    final query = _search.text.trim().toLowerCase();
    final visible =
        members.where((member) {
          if (widget.api != null) {
            return true; // Server owns search/filter/pagination.
          }
          return (_filter == 'All members' ||
                  _filter == (member.membership?.label ?? 'No plan')) &&
              [
                member.name,
                member.number,
                member.phone,
              ].any((value) => value.toLowerCase().contains(query));
        }).toList()..sort(
          (a, b) => _nameOrder
              ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
              : a.number.compareTo(b.number),
        );

    final layout = LayoutBuilder(
      builder: (context, constraints) {
        final readableWidth =
            constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1);
        final wide = readableWidth >= 640;
        final compact =
            readableWidth < 600 ||
            constraints.maxHeight / MediaQuery.textScalerOf(context).scale(1) <
                600;
        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Members',
              style:
                  (readableWidth < 400
                          ? theme.textTheme.headlineSmall
                          : theme.textTheme.headlineMedium)
                      ?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (!compact) ...[
              const SizedBox(height: 8),
              Text(
                'All registered members, in one place.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        );
        final add = FilledButton.icon(
          key: const ValueKey('members-add'),
          onPressed: _addMember,
          icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
          label: const Text('Add member'),
        );

        final page = Column(
          key: const ValueKey('members-page'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              key: const ValueKey('members-header'),
              color: theme.scaffoldBackgroundColor,
              child: readableWidth >= 400
                  ? Row(
                      children: [
                        Expanded(child: title),
                        const SizedBox(width: 20),
                        add,
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [title, const SizedBox(height: 12), add],
                    ),
            ),
            SizedBox(height: compact ? 12 : 24),
            Expanded(
              child: Container(
                key: const ValueKey('members-card'),
                decoration: _panelDecoration,
                padding: EdgeInsets.all(compact ? 12 : 20),
                child: Scrollbar(
                  controller: _scroll,
                  child: CustomScrollView(
                    key: const ValueKey('members-list'),
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: ClampingScrollPhysics(),
                    ),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    slivers: [
                      // Native floating controls share the list's scroll and
                      // refresh lifecycle; no second gesture/animation state.
                      SliverFloatingHeader(
                        key: const ValueKey('members-controls-sliver'),
                        snapMode: FloatingHeaderSnapMode.scroll,
                        animationStyle: MediaQuery.disableAnimationsOf(context)
                            ? AnimationStyle.noAnimation
                            : const AnimationStyle(
                                duration: Duration(milliseconds: 280),
                                reverseDuration: Duration(milliseconds: 280),
                                curve: Curves.easeInOutCubic,
                                reverseCurve: Curves.easeInOutCubic,
                              ),
                        child: Material(
                          color: Colors.white,
                          child: Column(
                            key: const ValueKey('members-controls'),
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                widget.api != null
                                    ? _error ??
                                          'Registered members · Server records'
                                    : _isPreview
                                    ? compact
                                          ? 'Sample data · Temporary preview'
                                          : 'Sample data · Changes last until preview restart.'
                                    : compact
                                    ? 'Backend not connected'
                                    : 'Backend and staff authorization are not connected.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              SizedBox(height: compact ? 12 : 20),
                              TextField(
                                key: const ValueKey('members-search'),
                                controller: _search,
                                onChanged: (_) => _queryChanged(),
                                decoration: InputDecoration(
                                  labelText: 'Search name, number or phone',
                                  prefixIcon: const Icon(Icons.search_rounded),
                                  suffixIcon: _search.text.isEmpty
                                      ? null
                                      : IconButton(
                                          key: const ValueKey(
                                            'members-clear-search',
                                          ),
                                          tooltip: 'Clear search',
                                          onPressed: () {
                                            _search.clear();
                                            _queryChanged();
                                          },
                                          icon: const Icon(Icons.close_rounded),
                                        ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                              SizedBox(height: compact ? 8 : 16),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  spacing: 8,
                                  children: [
                                    for (final filter in [
                                      'All members',
                                      if (widget.api != null) ...[
                                        'Active records',
                                        'Inactive records',
                                      ] else ...[
                                        ...MembershipStatus.values.map(
                                          (s) => s.label,
                                        ),
                                        'No plan',
                                      ],
                                    ])
                                      ChoiceChip(
                                        key: ValueKey('members-filter-$filter'),
                                        label: Text(filter),
                                        selected: _filter == filter,
                                        onSelected: (_) {
                                          _filter = filter;
                                          _queryChanged();
                                        },
                                      ),
                                  ],
                                ),
                              ),
                              SizedBox(height: compact ? 8 : 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      widget.api != null
                                          ? visible.isEmpty &&
                                                    (_loading || _error != null)
                                                ? _loading
                                                      ? 'Loading member records…'
                                                      : 'Member records unavailable'
                                                : '${visible.length} of $_total members'
                                          : _isPreview
                                          ? '${visible.length} of ${members.length} members'
                                          : 'Member records unavailable',
                                      key: const ValueKey('members-count'),
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ),
                                  IconButton(
                                    key: const ValueKey('members-sort'),
                                    tooltip: widget.api != null
                                        ? 'Sort loaded records: ${_nameOrder ? 'Name A–Z' : 'Member number'}'
                                        : _nameOrder
                                        ? 'Name A–Z'
                                        : 'Member number',
                                    onPressed: () =>
                                        _update(() => _nameOrder = !_nameOrder),
                                    icon: const Icon(
                                      Icons.sort_by_alpha_rounded,
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(color: Color(0xFFDDDDDD)),
                              if (wide)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: DefaultTextStyle(
                                    style: theme.textTheme.labelLarge!.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                    child: Row(
                                      children: [
                                        const Expanded(child: Text('Member')),
                                        const SizedBox(width: 20),
                                        SizedBox(
                                          width: 140,
                                          child: Text(
                                            widget.api != null
                                                ? 'Phone'
                                                : 'Plan',
                                          ),
                                        ),
                                        const SizedBox(width: 20),
                                        SizedBox(
                                          width: 144,
                                          child: Text(
                                            widget.api != null
                                                ? 'Record status'
                                                : 'Membership',
                                          ),
                                        ),
                                        const SizedBox(width: 36),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      SliverList.separated(
                        itemCount:
                            (visible.isEmpty ? 1 : visible.length) +
                            (widget.api != null &&
                                    visible.isNotEmpty &&
                                    (_loading ||
                                        _error != null ||
                                        _liveMembers.length < _total)
                                ? 1
                                : 0),
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, color: Color(0xFFDDDDDD)),
                        itemBuilder: (context, index) {
                          if (index == visible.length && visible.isNotEmpty) {
                            return Padding(
                              padding: const EdgeInsets.all(16),
                              child: _loading
                                  ? const Center(child: DumbbellLoader())
                                  : TextButton(
                                      key: const ValueKey('members-load-more'),
                                      onPressed: () =>
                                          _load(append: _error == null),
                                      child: Text(
                                        _error != null
                                            ? 'Retry loading members'
                                            : 'Load more members',
                                      ),
                                    ),
                            );
                          }
                          if (visible.isEmpty) {
                            if (_loading) {
                              return const Padding(
                                padding: EdgeInsets.all(32),
                                child: Center(child: DumbbellLoader()),
                              );
                            }
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 32),
                              child: Column(
                                children: [
                                  Icon(
                                    widget.api != null && _error != null
                                        ? Icons.cloud_off_outlined
                                        : widget.api != null || _isPreview
                                        ? Icons.person_search_rounded
                                        : Icons.cloud_off_outlined,
                                    size: 36,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    widget.api != null
                                        ? _error != null
                                              ? 'Unable to load members'
                                              : 'No matching members'
                                        : _isPreview
                                        ? 'No matching members'
                                        : 'Waiting for member connection',
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    widget.api != null
                                        ? _error ?? 'No registered members match this search.'
                                        : _isPreview
                                        ? 'Try another search or membership filter.'
                                        : 'Registered members will appear once the backend is connected.',
                                    textAlign: TextAlign.center,
                                  ),
                                  if (widget.api != null)
                                    TextButton(
                                      onPressed: () => _load(),
                                      child: const Text('Refresh members'),
                                    ),
                                  if (_isPreview)
                                    TextButton(
                                      key: const ValueKey('members-reset'),
                                      onPressed: () => _update(() {
                                        _search.clear();
                                        _filter = 'All members';
                                      }),
                                      child: const Text('Clear filters'),
                                    ),
                                ],
                              ),
                            );
                          }
                          final member = visible[index];
                          final identity = Row(
                            children: [
                              _MemberAvatar(member: member),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      member.name,
                                      style: theme.textTheme.bodyLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      member.number,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                          return Semantics(
                            button: true,
                            child: InkWell(
                              key: ValueKey('member-${member.number}'),
                              onTap: () => _openMember(member),
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                  horizontal: 4,
                                ),
                                child: wide
                                    ? Row(
                                        children: [
                                          Expanded(child: identity),
                                          const SizedBox(width: 20),
                                          SizedBox(
                                            width: 140,
                                            child: Text(
                                              widget.api != null
                                                  ? member.phone
                                                  : member.plan ?? 'No plan',
                                            ),
                                          ),
                                          const SizedBox(width: 20),
                                          SizedBox(
                                            width: 144,
                                            child: Align(
                                              alignment: Alignment.centerLeft,
                                              child: _MembershipBadge(
                                                member: member,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          const Icon(
                                            Icons.chevron_right_rounded,
                                            size: 24,
                                          ),
                                        ],
                                      )
                                    : Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          identity,
                                          const SizedBox(height: 12),
                                          Wrap(
                                            spacing: 16,
                                            runSpacing: 8,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              Text(
                                                widget.api != null
                                                    ? member.phone
                                                    : member.plan ?? 'No plan',
                                              ),
                                              _MembershipBadge(member: member),
                                              const Icon(
                                                Icons.chevron_right_rounded,
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
        return page;
      },
    );
    return DumbbellRefresh(
      key: const ValueKey('members-refresh'),
      padding: widget.padding,
      scrollController: _scroll,
      onRefresh: widget.api != null
          ? () => _load()
          : () => refreshLocalView(
              context,
              preview: _isPreview,
              rebuild: () => setState(() {}),
            ),
      child: layout,
    );
  }
}

final _panelDecoration = BoxDecoration(
  color: Colors.white,
  border: Border.all(color: const Color(0xFFDDDDDD)),
  borderRadius: BorderRadius.circular(14),
);

class _MemberAvatar extends StatelessWidget {
  const _MemberAvatar({required this.member});
  final MemberProfile member;

  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: 20,
    backgroundColor: const Color(0xFFE4F0ED),
    foregroundColor: Theme.of(context).colorScheme.primary,
    backgroundImage: member.photo == null ? null : MemoryImage(member.photo!),
    child: member.photo == null ? Text(member.initials) : null,
  );
}

class _MembershipBadge extends StatelessWidget {
  const _MembershipBadge({required this.member});
  final MemberProfile member;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: member.id != null
          ? member.isActive
                ? const Color(0xFF286455)
                : const Color(0xFF616161)
          : member.membership?.color ?? const Color(0xFF616161),
      borderRadius: BorderRadius.circular(100),
    ),
    child: Text(
      member.id != null
          ? member.isActive
                ? 'Active record'
                : 'Inactive record'
          : member.membership?.label ?? 'No plan',
      style: Theme.of(context).textTheme.labelMedium
          ?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
    ),
  );
}

class _LiveMemberDetails extends StatefulWidget {
  const _LiveMemberDetails({required this.api, required this.member});
  final RepLabApi api;
  final MemberProfile member;
  @override
  State<_LiveMemberDetails> createState() => _LiveMemberDetailsState();
}

class _LiveMemberDetailsState extends State<_LiveMemberDetails> {
  late Future<MemberProfile> _details = widget.api.member(widget.member.id!);
  @override
  Widget build(BuildContext context) => FutureBuilder<MemberProfile>(
    future: _details,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return _MemberDetails(member: snapshot.data!, preview: false);
      }
      return Dialog(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (snapshot.hasError) ...[
                Text(snapshot.error.toString()),
                TextButton(
                  onPressed: () => setState(() {
                    _details = widget.api.member(widget.member.id!);
                  }),
                  child: const Text('Retry'),
                ),
              ] else
                const DumbbellLoader(label: 'Loading member details'),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _MemberDetails extends StatelessWidget {
  const _MemberDetails({required this.member, this.preview = true});
  final MemberProfile member;
  final bool preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    String date(DateTime? value) => value == null
        ? 'Not available'
        : '${localizations.formatMediumDate(value)} ${value.year}';
    final now = gymNow();
    final visits =
        !preview
              ? <SampleCheckIn>[]
              : [
                  ...sampleAttendanceFor(now),
                  ...sampleAttendanceFor(
                    DateTime(now.year, now.month, now.day - 1),
                  ),
                ].where((entry) => entry.memberNumber == member.number).toList()
          ..sort((a, b) => b.time.compareTo(a.time));

    return Dialog(
      key: const ValueKey('member-details'),
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Member details',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('member-details-close'),
                    tooltip: 'Close member details',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                key: const ValueKey('member-details-scroll'),
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        _MemberAvatar(member: member),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                member.name,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(member.number),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _MembershipBadge(member: member),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      preview
                          ? 'Preview profile · Not a server record.'
                          : member.enrollment == null
                          ? 'Saved server record · No subscription or payment registered.'
                          : 'Saved server record · Payment was confirmed by staff.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 24),
                    _DetailsSection(
                      title: 'Personal & contact details',
                      fields: [
                        ('Member number', member.number),
                        ('Full name', member.name),
                        ('Phone', member.phone),
                        ('Email', member.email),
                        ('Address', member.address),
                        ('Emergency phone', member.emergencyPhone),
                        ('Joined on', date(member.joined)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _DetailsSection(
                      title: 'Membership',
                      fields: [
                        (
                          'Plan',
                          !preview && member.enrollment == null
                              ? 'No plan registered'
                              : member.plan ?? 'No plan assigned',
                        ),
                        (
                          'Status',
                          !preview && member.enrollment == null
                              ? 'Unavailable'
                              : member.planStart != null &&
                                    DateUtils.dateOnly(member.planStart!)
                                        .isAfter(DateUtils.dateOnly(now))
                              ? 'Not started'
                              : member.membership?.label ?? 'No plan',
                        ),
                        ('Starts on', date(member.planStart)),
                        ('Valid through', date(member.planEnd)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _DetailsSection(
                      title: 'Notes',
                      fields: [('Staff notes', member.notes)],
                    ),
                    const SizedBox(height: 20),
                    _DetailsSection(
                      title: 'Recent attendance',
                      fields: !preview
                          ? [
                              (
                                'Attendance',
                                'Attendance is not implemented on the server.',
                              ),
                            ]
                          : visits.isEmpty
                          ? [
                              (
                                'Sample check-ins',
                                'No sample visits in the last two days.',
                              ),
                            ]
                          : [
                              for (final visit in visits)
                                (
                                  date(visit.time),
                                  '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(visit.time))} IST',
                                ),
                            ],
                    ),
                    const SizedBox(height: 20),
                    _DetailsSection(
                      title: 'Payments & subscription history',
                      fields: member.enrollment != null
                          ? [
                              (
                                'Receipt',
                                member.enrollment!['invoice_number'] as String,
                              ),
                              (
                                'Plan duration',
                                '${member.enrollment!['months']} months',
                              ),
                              (
                                'Personal training',
                                '${member.enrollment!['training_months']} months',
                              ),
                              (
                                'Insurance',
                                '${member.enrollment!['insurance_months']} months',
                              ),
                              (
                                'Full payment',
                                rupees(
                                  member.enrollment!['total_paise'] as int,
                                ),
                              ),
                              (
                                'Payment method',
                                (member.enrollment!['payment_method'] as String)
                                    .toUpperCase(),
                              ),
                              (
                                'UPI reference',
                                member.enrollment!['payment_reference']
                                    as String,
                              ),
                              (
                                'Confirmation',
                                preview
                                    ? 'Simulated only · No money collected'
                                    : 'Staff confirmed · Not bank-verified automatically',
                              ),
                            ]
                          : [
                              (
                                'Records unavailable',
                                preview
                                    ? 'Billing and subscription history will appear once the backend is connected. No payments are recorded in this preview.'
                                    : 'No subscription or payment registered for this member.',
                              ),
                            ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailsSection extends StatelessWidget {
  const _DetailsSection({required this.title, required this.fields});
  final String title;
  final List<(String, String)> fields;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _panelDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns =
                  constraints.maxWidth /
                          MediaQuery.textScalerOf(context).scale(1) >=
                      480
                  ? 2
                  : 1;
              return Wrap(
                spacing: 24,
                runSpacing: 20,
                children: [
                  for (final (label, value) in fields)
                    SizedBox(
                      width:
                          (constraints.maxWidth - 24 * (columns - 1)) / columns,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(value.isEmpty ? 'Not provided' : value),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
