import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_loading.dart';
import 'collection_report.dart';
import 'member_enrollment.dart';
import 'replab_api.dart';
import 'sample_attendance.dart';
import 'warning_ribbon.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key, this.api, this.padding = EdgeInsets.zero});
  final RepLabApi? api;
  final EdgeInsets padding;

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final _scroll = ScrollController();
  late DateTime _today;
  DateTime? _from;
  DateTime? _to;
  String _period = 'This month';
  CollectionReport? _report;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final now = gymNow();
    _today = DateTime.utc(now.year, now.month, now.day);
    _from = DateTime.utc(_today.year, _today.month);
    if (widget.api != null) _load();
  }

  Future<void> _load({int dailyOffset = 0, int receiptOffset = 0}) async {
    if (_loading || widget.api == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final loaded = CollectionReport.fromJson(
        await widget.api!.collections(
          from: _from,
          to: _to,
          dailyOffset: dailyOffset,
          receiptOffset: receiptOffset,
        ),
      );
      if (mounted) {
        setState(() {
          _report = loaded;
          _today = DateTime.utc(
            loaded.today.year,
            loaded.today.month,
            loaded.today.day,
          );
        });
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not read the financial report. Pull down to retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() => widget.api == null
      ? refreshLocalView(
          context,
          preview: false,
          rebuild: () => setState(() {}),
        )
      : _load(
          dailyOffset: _report?.dailyOffset ?? 0,
          receiptOffset: _report?.receiptOffset ?? 0,
        );

  Future<void> _selectPeriod(String period) async {
    if (_loading) return;
    if (period == 'Custom') {
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(_today.year, _today.month, _today.day),
        initialDateRange: DateTimeRange(
          start: _from ?? _report?.from ?? _today,
          end: _to ?? _today,
        ),
        helpText: 'Collection dates (IST)',
      );
      if (range == null || !mounted) return;
      setState(() {
        _period = period;
        _from = DateTime.utc(
          range.start.year,
          range.start.month,
          range.start.day,
        );
        _to = DateTime.utc(range.end.year, range.end.month, range.end.day);
        _report = null;
      });
    } else {
      setState(() {
        _period = period;
        _to = period == 'Yesterday'
            ? _today.subtract(const Duration(days: 1))
            : null;
        _from = switch (period) {
          'Today' => _today,
          'Yesterday' => _to,
          'Last 7 days' => _today.subtract(const Duration(days: 6)),
          'This month' => DateTime.utc(_today.year, _today.month),
          _ => null,
        };
        // Never display a previous range's figures under a newly selected range.
        _report = null;
      });
    }
    await _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String _date(DateTime day) =>
      MaterialLocalizations.of(context).formatMediumDate(day);
  String _time(DateTime utc) {
    final ist = utc.add(const Duration(hours: 5, minutes: 30));
    return '${_date(ist)} · ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(ist))} IST';
  }

  Widget _panel(String title, List<Widget> children, {String? subtitle}) =>
      Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Color(0xFFDDDDDD)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              ...children,
            ],
          ),
        ),
      );

  Widget _metrics(CollectionReport report) => LayoutBuilder(
    builder: (context, constraints) {
      final readableWidth =
          constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1);
      final columns = readableWidth >= 760
          ? 4
          : readableWidth >= 360
          ? 2
          : 1;
      final width = (constraints.maxWidth - 16 * (columns - 1)) / columns;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final item in const [
            ('Today', 'today', Icons.today_outlined),
            ('Yesterday', 'yesterday', Icons.history_rounded),
            ('This month', 'month', Icons.calendar_month_outlined),
            ('All time', 'all_time', Icons.account_balance_wallet_outlined),
          ])
            SizedBox(
              width: width,
              child: Container(
                key: ValueKey('reports-metric-${item.$2}'),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: item.$2 == 'today'
                      ? const Color(0xFFEAF4EF)
                      : const Color(0xFFF0F0F0),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(item.$3, size: 22, color: const Color(0xFF286455)),
                    const SizedBox(height: 12),
                    Text(item.$1),
                    const SizedBox(height: 8),
                    Text(
                      rupees(report.highlights[item.$2]!.total),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${report.highlights[item.$2]!.count} payments',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );

  Widget _amountRow(String label, int amount, {int? total, IconData? icon}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: const Color(0xFF286455)),
                  const SizedBox(width: 12),
                ],
                Expanded(child: Text(label)),
                const SizedBox(width: 12),
                Text(
                  rupees(amount),
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            if (total != null) ...[
              const SizedBox(height: 8),
              Semantics(
                label: '$label: ${rupees(amount)} of ${rupees(total)}',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : amount / total,
                    minHeight: 6,
                    backgroundColor: const Color(0xFFF0F0F0),
                    color: const Color(0xFF286455),
                  ),
                ),
              ),
            ],
          ],
        ),
      );

  Widget _pager({
    required String prefix,
    required int offset,
    required int limit,
    required int total,
    required int count,
    required ValueChanged<int> onPage,
  }) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 12,
    runSpacing: 8,
    children: [
      Text(
        total == 0 ? '0 records' : '${offset + 1}–${offset + count} of $total',
      ),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: ValueKey('reports-$prefix-previous'),
            tooltip: prefix == 'daily' ? 'Newer days' : 'Newer payments',
            onPressed: !_loading && offset > 0
                ? () => onPage(math.max(0, offset - limit))
                : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          IconButton(
            key: ValueKey('reports-$prefix-next'),
            tooltip: prefix == 'daily' ? 'Older days' : 'Older payments',
            onPressed: !_loading && offset + count < total
                ? () => onPage(offset + limit)
                : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    ],
  );

  Widget _dailyHistory(CollectionReport report) => _panel(
    'Daily collections',
    [
      for (final day in report.daily) ...[
        Semantics(
          label:
              '${_date(day.date)}, ${day.count} payments, total ${rupees(day.total)}, cash ${rupees(day.cash)}, UPI ${rupees(day.upi)}',
          child: Padding(
            key: ValueKey('reports-day-${isoDate(day.date)}'),
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(_date(day.date))),
                    const SizedBox(width: 12),
                    Text(
                      rupees(day.total),
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${day.count} payments · Cash ${rupees(day.cash)} · UPI ${rupees(day.upi)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
      ],
      const SizedBox(height: 12),
      _pager(
        prefix: 'daily',
        offset: report.dailyOffset,
        limit: report.dailyLimit,
        total: report.dailyCount,
        count: report.daily.length,
        onPage: (offset) =>
            _load(dailyOffset: offset, receiptOffset: report.receiptOffset),
      ),
    ],
    subtitle:
        'Newest first, including days with no collections. All dates are IST.',
  );

  void _showReceipt(CollectionReceipt receipt) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(receipt.invoice),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${receipt.member} · ${receipt.memberNumber}'),
            const SizedBox(height: 12),
            Text('${receipt.plan} · ${receipt.months} months'),
            const SizedBox(height: 12),
            Text('Full payment: ${rupees(receipt.total)}'),
            Text('Method: ${receipt.method == 'cash' ? 'Cash' : 'UPI'}'),
            Text('Received: ${_time(receipt.receivedAt)}'),
            if (receipt.reference.isNotEmpty)
              SelectableText('Reference: ${receipt.reference}'),
            const SizedBox(height: 16),
            const Text(
              'Manually confirmed by staff. This is a saved receipt, not automatic bank verification.',
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

  Widget _receipts(CollectionReport report) => _panel('Payment history', [
    for (final receipt in report.receipts) ...[
      ListTile(
        key: ValueKey('reports-receipt-${receipt.invoice}'),
        contentPadding: EdgeInsets.zero,
        title: Text('${receipt.invoice} · ${receipt.member}'),
        subtitle: Text(
          '${receipt.plan}\n${_time(receipt.receivedAt)} · ${receipt.method == 'cash' ? 'Cash' : 'UPI'}\n${rupees(receipt.total)}',
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => _showReceipt(receipt),
      ),
      const Divider(height: 1),
    ],
    const SizedBox(height: 12),
    _pager(
      prefix: 'receipts',
      offset: report.receiptOffset,
      limit: report.receiptLimit,
      total: report.receiptCount,
      count: report.receipts.length,
      onPage: (offset) =>
          _load(dailyOffset: report.dailyOffset, receiptOffset: offset),
    ),
  ], subtitle: 'Tap a payment to view its receipt and reference.');

  List<Widget> _contents(CollectionReport report) {
    final total = report.totals;
    return [
      _metrics(report),
      const SizedBox(height: 24),
      _panel(
        'Selected period',
        [
          Text(
            rupees(total.total),
            key: const ValueKey('reports-selected-total'),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: const Color(0xFF286455),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text('${total.count} fully paid registrations'),
        ],
        subtitle:
            '${_date(report.from)} – ${_date(report.to)} · Money collected',
      ),
      if (total.count == 0) ...[
        const SizedBox(height: 24),
        _panel('No payments in this period', [
          const Text(
            'Confirmed registration payments will appear here. Try another date range.',
          ),
        ]),
      ],
      const SizedBox(height: 24),
      LayoutBuilder(
        builder: (context, constraints) {
          final panels = [
            _panel('Payment methods', [
              _amountRow(
                'Cash',
                total.cash,
                total: total.total,
                icon: Icons.payments_outlined,
              ),
              _amountRow(
                'UPI',
                total.upi,
                total: total.total,
                icon: Icons.qr_code_rounded,
              ),
            ]),
            _panel('Collection breakdown', [
              _amountRow('Membership plans', total.base, total: total.total),
              _amountRow(
                'Personal training',
                total.training,
                total: total.total,
              ),
              _amountRow('Insurance', total.insurance, total: total.total),
            ]),
          ];
          if (constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1) <
              700) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [panels[0], const SizedBox(height: 24), panels[1]],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: panels[0]),
              const SizedBox(width: 24),
              Expanded(child: panels[1]),
            ],
          );
        },
      ),
      if (report.plans.isNotEmpty) ...[
        const SizedBox(height: 24),
        _panel(
          'Collections by plan',
          [
            for (final plan in report.plans)
              _amountRow(
                '${plan.name} · ${plan.count} payments',
                plan.total,
                total: total.total,
              ),
          ],
          subtitle: 'Includes add-ons. Uses the plan name saved on each receipt, even if renamed or archived.',
        ),
      ],
      const SizedBox(height: 24),
      _dailyHistory(report),
      const SizedBox(height: 24),
      _receipts(report),
      const SizedBox(height: 16),
      Text(
        'Updated ${_time(report.generatedAt)}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) => DumbbellRefresh(
    key: const ValueKey('reports-refresh'),
    padding: widget.padding,
    scrollController: _scroll,
    onRefresh: _refresh,
    child: Column(
      key: const ValueKey('reports-page'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Reports',
          key: const ValueKey('reports-title'),
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text('Track collections, payment history and plan performance.'),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final period in const [
              'Today',
              'Yesterday',
              'Last 7 days',
              'This month',
              'All time',
              'Custom',
            ])
              ChoiceChip(
                key: ValueKey('reports-period-$period'),
                label: Text(period),
                selected: _period == period,
                onSelected: _loading ? null : (_) => _selectPeriod(period),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Expanded(
          child: SingleChildScrollView(
            key: const PageStorageKey('reports-scroll'),
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_loading) ...[
                  const Center(child: DumbbellLoader(label: 'Loading reports')),
                  const SizedBox(height: 16),
                ],
                if (_error != null || widget.api == null) ...[
                  WarningRibbon(
                    key: const ValueKey('reports-warning'),
                    message: _error ?? 'Server not connected. Financial records are not available.',
                  ),
                  if (_report != null) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Previously loaded figures · Pull down to retry.',
                    ),
                  ],
                  if (widget.api != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: _loading ? null : _refresh,
                        child: const Text('Retry'),
                      ),
                    ),
                  const SizedBox(height: 16),
                ],
                const Text(
                  'Collections are full payments manually confirmed at registration, dated when received (IST). Prepaid memberships are not earned revenue or profit. Expenses, refunds and older unrecorded payments are not included.',
                ),
                const SizedBox(height: 24),
                if (_report case final report?) ..._contents(report),
                if (!_loading && _report == null && widget.api == null)
                  _panel('Waiting for financial connection', [
                    Icon(
                      Icons.cloud_off_outlined,
                      size: 36,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Connect to the gym server to load saved payment receipts. No estimated or sample income is shown.',
                      textAlign: TextAlign.center,
                    ),
                  ]),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
