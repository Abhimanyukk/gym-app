import 'dart:convert';
import 'dart:typed_data';

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
    this.id,
    this.isActive = true,
    this.enrollment,
    this.photo,
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
  final String? id;
  final bool isActive;
  final Map<String, dynamic>? enrollment;
  final Uint8List? photo;

  factory MemberProfile.fromJson(Map<String, dynamic> data) => MemberProfile(
    id: data['id'] as String,
    number: data['number'] as String,
    name: data['name'] as String,
    phone: data['phone'] as String,
    joined: DateTime.parse(data['joined'] as String),
    email: data['email'] as String,
    address: data['address'] as String,
    emergencyPhone: data['emergency_phone'] as String,
    notes: data['notes'] as String,
    isActive: data['is_active'] as bool,
    enrollment: data['enrollment'] as Map<String, dynamic>?,
    photo: data['photo_base64'] == null
        ? null
        : base64Decode(data['photo_base64'] as String),
    plan: (data['enrollment'] as Map?)?['plan_name'] as String?,
    planStart: (data['enrollment'] as Map?)?['starts_on'] == null
        ? null
        : DateTime.parse(data['enrollment']['starts_on'] as String),
    planEnd: (data['enrollment'] as Map?)?['ends_on'] == null
        ? null
        : DateTime.parse(data['enrollment']['ends_on'] as String),
  );

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
    if (words.first.isEmpty) return '?';
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
