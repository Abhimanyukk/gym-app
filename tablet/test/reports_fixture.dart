import 'package:gym_management_app/member_enrollment.dart';
import 'package:gym_management_app/sample_attendance.dart';

// Synthetic receipt history only; production reporting reads PostgreSQL.
Map<String, dynamic> reportsFixture({
  String? from,
  String? to,
  int dailyOffset = 0,
  int receiptOffset = 0,
}) {
  final now = gymNow();
  final today = DateTime.utc(now.year, now.month, now.day);
  final start = DateTime.parse(
    from ?? isoDate(today.subtract(const Duration(days: 20))),
  ).toUtc();
  final end = DateTime.parse(to ?? isoDate(today)).toUtc();
  final payments = [
    for (var i = 0; i < 21; i++)
      {
        'invoice_number': 'RL-${(21 - i).toString().padLeft(6, '0')}',
        'member_id': 'synthetic-member-$i',
        'member_number': 'M-${(i + 1).toString().padLeft(4, '0')}',
        'member_name': 'Report Member ${i + 1}',
        'plan_name': i.isEven ? 'Historical Silver' : 'Gold Plan',
        'months': 1,
        'total_paise': 10001,
        'base_paise': 9001,
        'training_paise': 900,
        'insurance_paise': 100,
        'payment_method': i.isEven ? 'cash' : 'upi',
        'payment_reference': i.isEven ? '' : 'SYNTHETIC-UPI-$i',
        'received_at': today
            .subtract(Duration(days: i))
            .add(const Duration(hours: 8))
            .toIso8601String(),
      },
  ];
  List<Map<String, dynamic>> between(DateTime a, DateTime b) =>
      payments.where((p) {
        final day = DateTime.parse(p['received_at'] as String);
        return !day.isBefore(a) && day.isBefore(b.add(const Duration(days: 1)));
      }).toList();
  Map<String, dynamic> totals(List<Map<String, dynamic>> rows) => {
    'total_paise': rows.length * 10001,
    'base_paise': rows.length * 9001,
    'training_paise': rows.length * 900,
    'insurance_paise': rows.length * 100,
    'cash_paise':
        rows.where((p) => p['payment_method'] == 'cash').length * 10001,
    'upi_paise': rows.where((p) => p['payment_method'] == 'upi').length * 10001,
    'receipt_count': rows.length,
  };
  final selected = between(start, end);
  final days = [
    for (var i = 0; i <= end.difference(start).inDays; i++)
      {
        'date': isoDate(end.subtract(Duration(days: i))),
        ...totals(
          between(
            end.subtract(Duration(days: i)),
            end.subtract(Duration(days: i)),
          ),
        ),
      },
  ];
  return {
    'currency': 'INR',
    'timezone': 'Asia/Kolkata',
    'today': isoDate(today),
    'from': isoDate(start),
    'to': isoDate(end),
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'totals': totals(selected),
    'highlights': {
      'today': totals(between(today, today)),
      'yesterday': totals(
        between(
          today.subtract(const Duration(days: 1)),
          today.subtract(const Duration(days: 1)),
        ),
      ),
      'month': totals(between(DateTime.utc(today.year, today.month), today)),
      'all_time': totals(payments),
    },
    'daily': {
      'items': days.skip(dailyOffset).take(14).toList(),
      'total': days.length,
      'limit': 14,
      'offset': dailyOffset,
    },
    'receipts': {
      'items': selected.skip(receiptOffset).take(20).toList(),
      'total': selected.length,
      'limit': 20,
      'offset': receiptOffset,
    },
    'plans': [
      for (final name in ['Historical Silver', 'Gold Plan'])
        if (selected.any((p) => p['plan_name'] == name))
          {
            'name': name,
            'code': name == 'Historical Silver' ? 'silver' : 'gold',
            'total_paise':
                selected.where((p) => p['plan_name'] == name).length * 10001,
            'receipt_count': selected
                .where((p) => p['plan_name'] == name)
                .length,
          },
    ],
  };
}
