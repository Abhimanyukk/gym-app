import 'dart:math';

class EnrollmentPlan {
  const EnrollmentPlan({
    required this.code,
    required this.name,
    required this.description,
    required this.prices,
    this.active = true,
  });
  EnrollmentPlan.fromJson(Map<String, dynamic> data)
    : code = data['code'] as String,
      name = data['name'] as String,
      description = data['description'] as String,
      active = data['active'] != false,
      prices = {
        for (final entry in (data['prices_paise'] as Map).entries)
          int.parse(entry.key as String): entry.value as int,
      };
  final String code, name, description;
  final bool active;
  final Map<int, int> prices;
  Map<String, dynamic> toJson() => {
    'code': code,
    'name': name,
    'description': description,
    'active': active,
    'prices_paise': {
      for (final entry in prices.entries) '${entry.key}': entry.value,
    },
  };
}

class EnrollmentOptions {
  EnrollmentOptions.fromJson(Map<String, dynamic> data)
    : plans = [
        for (final plan in data['plans'] as List)
          EnrollmentPlan.fromJson(plan as Map<String, dynamic>),
      ],
      trainingMonthly = data['training_monthly_paise'] as int,
      insuranceMonthly = data['insurance_monthly_paise'] as int,
      upiId = data['upi_id'] as String,
      payeeName = data['payee_name'] as String,
      revision = data['revision'] as int?;
  final List<EnrollmentPlan> plans;
  final int trainingMonthly, insuranceMonthly;
  final String upiId, payeeName;
  final int? revision;
  Map<String, dynamic> toJson() => {
    if (revision != null) 'revision': revision,
    'plans': [for (final plan in plans) plan.toJson()],
    'training_monthly_paise': trainingMonthly,
    'insurance_monthly_paise': insuranceMonthly,
    'upi_id': upiId,
    'payee_name': payeeName,
  };

  // Only explicitly enabled debug previews use this catalogue.
  static Map<String, dynamic> get previewData => {
    'revision': 1,
    'plans': [
      {
        'code': 'silver',
        'name': 'Silver Plan',
        'description': 'Strength & Fitness',
        'prices_paise': {'1': 120000, '3': 320000, '6': 600000, '12': 1200000},
      },
      {
        'code': 'gold',
        'name': 'Gold Plan',
        'description': 'Silver + Cardio Access',
        'prices_paise': {'1': 170000, '3': 470000, '6': 900000, '12': 1800000},
      },
    ],
    'training_monthly_paise': 500000,
    'insurance_monthly_paise': 20000,
    'upi_id': '8943521009@yescred',
    'payee_name': 'RepLab Fitness',
  };
}

// Parse currency directly into integer paise, never through floating point.
int? parseRupees(String input) {
  final value = input.trim();
  if (!RegExp(r'^\d{1,8}(?:\.\d{1,2})?$').hasMatch(value)) return null;
  final parts = value.split('.');
  final paise =
      int.parse(parts[0]) * 100 +
      (parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0')));
  return paise <= 1000000000 ? paise : null;
}

String priceInput(int paise) =>
    '${paise ~/ 100}.${(paise % 100).toString().padLeft(2, '0')}';

String planDuration(int months) => switch (months) {
  1 => 'Monthly · 1 month',
  3 => 'Quarterly · 3 months',
  6 => 'Half-yearly · 6 months',
  12 => 'Annual · 12 months',
  _ => '$months months',
};

String rupees(int paise) {
  final whole = (paise ~/ 100).toString();
  final grouped = whole.length <= 3
      ? whole
      : '${whole.substring(0, whole.length - 3).replaceAllMapped(RegExp(r'(\d)(?=(\d{2})+$)'), (m) => '${m[1]},')},${whole.substring(whole.length - 3)}';
  return '₹$grouped${paise % 100 == 0 ? '' : '.${(paise % 100).toString().padLeft(2, '0')}'}';
}

String enrollmentRequestId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

String isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

DateTime enrollmentEnd(DateTime start, int months) {
  final lastDay = DateTime(start.year, start.month + months + 1, 0).day;
  final anniversary = DateTime(
    start.year,
    start.month + months,
    min(start.day, lastDay),
  );
  return DateTime(anniversary.year, anniversary.month, anniversary.day - 1);
}

String upiPaymentUri(EnrollmentOptions options, int paise, String requestId) =>
    Uri(
      scheme: 'upi',
      host: 'pay',
      queryParameters: {
        'pa': options.upiId,
        'pn': options.payeeName,
        'am': '${paise ~/ 100}.${(paise % 100).toString().padLeft(2, '0')}',
        'cu': 'INR',
        'tn': 'Gym membership',
        'tr': requestId,
      },
    ).toString();
