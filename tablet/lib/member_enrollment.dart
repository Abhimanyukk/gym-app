import 'dart:math';

class EnrollmentPlan {
  EnrollmentPlan.fromJson(Map<String, dynamic> data)
    : code = data['code'] as String,
      name = data['name'] as String,
      description = data['description'] as String,
      prices = {
        for (final entry in (data['prices_paise'] as Map).entries)
          int.parse(entry.key as String): entry.value as int,
      };
  final String code, name, description;
  final Map<int, int> prices;
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
      payeeName = data['payee_name'] as String;
  final List<EnrollmentPlan> plans;
  final int trainingMonthly, insuranceMonthly;
  final String upiId, payeeName;

  // Only explicitly enabled debug previews use this catalogue.
  static Map<String, dynamic> get previewData => {
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
