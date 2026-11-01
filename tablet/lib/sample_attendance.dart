import 'package:flutter/material.dart';

DateTime gymNow() =>
    DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));

enum MembershipStatus {
  active('Active', Color(0xFF08752B)),
  expiring('Expiring soon', Color(0xFF9B6500)),
  expired('Expired', Color(0xFF830D11));

  const MembershipStatus(this.label, this.color);

  final String label;
  final Color color;
}

typedef SampleCheckIn = ({
  String memberNumber,
  String name,
  DateTime time,
  MembershipStatus membership,
  String statusLabel,
});

// dover-gain-efficient: fixtures only, never terminal events or backend records.
// Keep the Dashboard's four reference visits and Attendance's totals consistent.
List<SampleCheckIn> sampleAttendanceFor(DateTime date) {
  final now = gymNow();
  // Treat these as gym-local calendar dates, independent of the host's DST.
  final today = DateTime.utc(now.year, now.month, now.day);
  final day = DateTime.utc(date.year, date.month, date.day);
  final daysAgo = today.difference(day).inDays;
  if (daysAgo != 0 && daysAgo != 1) return [];

  const members = [
    (
      name: 'Poovalli Induchoodan',
      minute: 8 * 60 + 12,
      membership: MembershipStatus.expiring,
      status: 'Expires in 12 days',
    ),
    (
      name: 'Bilal John Kurishingal',
      minute: 8 * 60 + 4,
      membership: MembershipStatus.active,
      status: 'Active',
    ),
    (
      name: 'Nadeshan',
      minute: 7 * 60 + 46,
      membership: MembershipStatus.expired,
      status: 'Due for 2 days',
    ),
    (
      name: 'Pulikkattil Charlie',
      minute: 7 * 60 + 46,
      membership: MembershipStatus.expiring,
      status: 'Expires tomorrow',
    ),
  ];
  final count = daysAgo == 0 ? 30 : 6;
  return [
    for (var index = 0; index < count; index++)
      (
        memberNumber: 'M-${(index + 1).toString().padLeft(4, '0')}',
        name: index < members.length
            ? members[index].name
            : 'Sample Member ${(index + 1).toString().padLeft(2, '0')}',
        time: day.add(
          Duration(
            minutes: index < members.length
                ? members[index].minute
                : 7 * 60 + 35 - (index - 4) * 2,
          ),
        ),
        membership: index < members.length
            ? members[index].membership
            : MembershipStatus.active,
        statusLabel: index < members.length ? members[index].status : 'Active',
      ),
    if (daysAgo == 0)
      (
        memberNumber: 'M-0002',
        name: members[1].name,
        time: day.add(const Duration(hours: 6, minutes: 12)),
        membership: MembershipStatus.active,
        statusLabel: 'Active',
      ),
  ];
}
