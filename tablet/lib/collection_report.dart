typedef DailyCollection = ({
  DateTime date,
  int total,
  int cash,
  int upi,
  int count,
});
typedef PlanCollection = ({String name, String code, int total, int count});
typedef CollectionReceipt = ({
  String invoice,
  String member,
  String memberNumber,
  String plan,
  int months,
  int total,
  String method,
  String reference,
  DateTime receivedAt,
});

class CollectionTotals {
  CollectionTotals.fromJson(Map<String, dynamic> data)
    : total = data['total_paise'] as int,
      cash = data['cash_paise'] as int,
      upi = data['upi_paise'] as int,
      base = data['base_paise'] as int,
      training = data['training_paise'] as int,
      insurance = data['insurance_paise'] as int,
      count = data['receipt_count'] as int {
    if ([
          total,
          cash,
          upi,
          base,
          training,
          insurance,
          count,
        ].any((v) => v < 0) ||
        cash + upi != total ||
        base + training + insurance != total) {
      throw const FormatException('Invalid collection totals');
    }
  }
  final int total, cash, upi, base, training, insurance, count;
}

class CollectionReport {
  CollectionReport.fromJson(Map<String, dynamic> data)
    : today = DateTime.parse(data['today'] as String),
      from = DateTime.parse(data['from'] as String),
      to = DateTime.parse(data['to'] as String),
      generatedAt = DateTime.parse(data['generated_at'] as String).toUtc(),
      totals = CollectionTotals.fromJson(
        data['totals'] as Map<String, dynamic>,
      ),
      highlights = {
        for (final key in ['today', 'yesterday', 'month', 'all_time'])
          key: CollectionTotals.fromJson(
            (data['highlights'] as Map)[key] as Map<String, dynamic>,
          ),
      },
      daily = [
        for (final row in data['daily']['items'] as List)
          (
            date: DateTime.parse(row['date'] as String),
            total: row['total_paise'] as int,
            cash: row['cash_paise'] as int,
            upi: row['upi_paise'] as int,
            count: row['receipt_count'] as int,
          ),
      ],
      plans = [
        for (final row in data['plans'] as List)
          (
            name: row['name'] as String,
            code: row['code'] as String,
            total: row['total_paise'] as int,
            count: row['receipt_count'] as int,
          ),
      ],
      receipts = [
        for (final row in data['receipts']['items'] as List)
          (
            invoice: row['invoice_number'] as String,
            member: row['member_name'] as String,
            memberNumber: row['member_number'] as String,
            plan: row['plan_name'] as String,
            months: row['months'] as int,
            total: row['total_paise'] as int,
            method: row['payment_method'] as String,
            reference: row['payment_reference'] as String,
            receivedAt: DateTime.parse(row['received_at'] as String).toUtc(),
          ),
      ],
      dailyCount = data['daily']['total'] as int,
      dailyLimit = data['daily']['limit'] as int,
      dailyOffset = data['daily']['offset'] as int,
      receiptCount = data['receipts']['total'] as int,
      receiptLimit = data['receipts']['limit'] as int,
      receiptOffset = data['receipts']['offset'] as int {
    if (data['currency'] != 'INR' ||
        data['timezone'] != 'Asia/Kolkata' ||
        from.isAfter(to) ||
        dailyLimit <= 0 ||
        receiptLimit <= 0 ||
        dailyCount < 0 ||
        receiptCount != totals.count ||
        dailyOffset < 0 ||
        receiptOffset < 0 ||
        daily.any(
          (d) =>
              d.total < 0 ||
              d.cash < 0 ||
              d.upi < 0 ||
              d.cash + d.upi != d.total ||
              d.count < 0,
        ) ||
        plans.any((p) => p.total < 0 || p.count < 0) ||
        receipts.any(
          (r) =>
              r.total <= 0 ||
              r.months < 1 ||
              r.months > 120 ||
              !['cash', 'upi'].contains(r.method),
        )) {
      throw const FormatException('Invalid collections response');
    }
  }
  final DateTime today, from, to, generatedAt;
  final CollectionTotals totals;
  final Map<String, CollectionTotals> highlights;
  final List<DailyCollection> daily;
  final List<PlanCollection> plans;
  final List<CollectionReceipt> receipts;
  final int dailyCount, dailyLimit, dailyOffset;
  final int receiptCount, receiptLimit, receiptOffset;
}
