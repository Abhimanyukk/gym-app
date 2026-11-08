import 'package:flutter/foundation.dart';

import 'member_enrollment.dart';

typedef PreviewAdmin = ({String name, String email});

// dover-gain-efficient: preview identities/preferences only, not authentication.
// Keep passwords out of this state. Real authorization and the single-admin limit
// must also be enforced transactionally by the backend when it is integrated.
class SettingsPreview {
  SettingsPreview({bool enabled = false}) : enabled = kDebugMode && enabled {
    if (this.enabled) {
      _admins.add((name: 'Sample Admin', email: 'admin@example.com'));
    }
  }

  static const maxAdmins = 1;
  final bool enabled;
  final List<PreviewAdmin> _admins = [];
  List<PreviewAdmin> get admins => List.unmodifiable(_admins);
  bool get canAddAdmin => enabled && _admins.length < maxAdmins;

  String gymName = 'RepLab Fitness';
  String phone = '';
  String address = '';
  String serverUrl = '';
  EnrollmentOptions plans = EnrollmentOptions.fromJson(
    EnrollmentOptions.previewData,
  );

  String? adminEmailError(String? value) {
    if (!enabled) return 'Admin management requires the backend.';
    if (_admins.length >= maxAdmins) {
      return 'Only one server administrator is allowed.';
    }
    final email = (value ?? '').trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Enter a valid email address';
    }
    if (_admins.any((admin) => admin.email.toLowerCase() == email)) {
      return 'An admin with this email already exists';
    }
    return null;
  }

  String? addAdmin(PreviewAdmin admin) {
    final error = adminEmailError(admin.email);
    if (error != null) return error;
    if (admin.name.trim().isEmpty) return 'Enter the admin’s full name';
    _admins.add((
      name: admin.name.trim(),
      email: admin.email.trim().toLowerCase(),
    ));
    return null;
  }
}

String? serverAddressError(String? value) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return null; // Unconfigured is valid in the preview.
  final uri = Uri.tryParse(text);
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      RegExp(r'\s').hasMatch(text) ||
      uri.port < 1 ||
      uri.port > 65535) {
    return 'Enter an HTTP(S) server address without credentials or query parameters';
  }
  return null;
}
