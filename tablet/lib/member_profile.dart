import 'sample_attendance.dart';

class MemberProfile {
  const MemberProfile({
    required this.number,
    required this.name,
    required this.phone,
    required this.joined,
    this.email = '',
    this.address = '',
    this.emergencyPhone = '',
    this.notes = '',
    this.plan,
    this.planStart,
    this.planEnd,
  });

  final String number;
  final String name;
  final String phone;
  final DateTime joined;
  final String email;
  final String address;
  final String emergencyPhone;
  final String notes;
  final String? plan;
  final DateTime? planStart;
  final DateTime? planEnd;

  MembershipStatus? get membership {
    final end = planEnd;
    if (end == null) return null;
    final now = gymNow();
    // End dates are inclusive gym-local calendar dates.
    final days = DateTime.utc(
      end.year,
      end.month,
      end.day,
    ).difference(DateTime.utc(now.year, now.month, now.day)).inDays;
    if (days < 0) return MembershipStatus.expired;
    if (days <= 14) return MembershipStatus.expiring;
    return MembershipStatus.active;
  }

  String get initials {
    final words = name.trim().split(RegExp(r'\s+'));
    return '${words.first[0]}${words.length > 1 ? words.last[0] : ''}';
  }
}

// dover-gain-efficient: debug fixtures, not registered members from the server.
// Match the dashboard's 178-member reference and Attendance's member numbers.
List<MemberProfile> sampleMembers() {
  final now = gymNow();
  final today = DateTime(now.year, now.month, now.day);
  final visits = sampleAttendanceFor(today);
  return [
    for (var index = 0; index < 178; index++)
      MemberProfile(
        number: 'M-${(index + 1).toString().padLeft(4, '0')}',
        name: index < 30
            ? visits[index].name
            : 'Sample Member ${(index + 1).toString().padLeft(2, '0')}',
        // Reserved-looking placeholders; no real contact records in fixtures.
        phone: 'Sample phone ${(index + 1).toString().padLeft(3, '0')}',
        email: 'member${index + 1}@example.com',
        address: 'Example address · Preview only',
        joined: today.subtract(Duration(days: 90 + index)),
        notes: 'Example profile, not a live member record.',
        plan: index >= 30 && index % 17 == 0
            ? null
            : ['Monthly', 'Quarterly', 'Annual'][index % 3],
        planStart: index >= 30 && index % 17 == 0
            ? null
            : today.subtract(const Duration(days: 20)),
        planEnd: index >= 30 && index % 17 == 0
            ? null
            : today.add(
                Duration(
                  days: switch (index) {
                    0 => 12,
                    2 => -2,
                    3 => 1,
                    _ => index >= 30 && index % 13 == 0 ? -5 : 60,
                  },
                ),
              ),
      ),
  ];
}
