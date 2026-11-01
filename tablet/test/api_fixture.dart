import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> enterServerLogin(WidgetTester tester) async {
  if (find.byKey(const ValueKey('setup-next')).evaluate().isNotEmpty) {
    await tester.tap(find.text('Hostname'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('server-hostname')),
      'localhost',
    );
    await tester.tap(find.byKey(const ValueKey('setup-next')));
    await tester.pumpAndSettle();
  }
  await tester.enterText(
    find.byKey(const ValueKey('login-password')),
    'synthetic test password',
  );
  await tester.ensureVisible(find.text('Login'));
}

/// Synthetic API contract only; production code never imports this fixture.
class ApiFixture {
  ApiFixture({this.sessionToken = 'synthetic-session-token'});
  final String sessionToken;
  final requests = <http.Request>[];
  bool allowLogin = true;
  bool expired = false;
  bool failWrites = false;
  bool failReads = false;
  Future<void>? writeBarrier;
  Future<void>? loginBarrier;
  Map<String, dynamic> settings = {
    'gym_name': 'Server Gym',
    'phone': '',
    'address': '',
    'timezone': 'Asia/Kolkata',
    'max_admins': 1,
  };
  final admins = <Map<String, dynamic>>[
    {
      'id': '00000000-0000-0000-0000-000000000001',
      'name': 'Server Admin',
      'email': 'admin@example.com',
    },
  ];
  final members = <Map<String, dynamic>>[member(42)];
  static Map<String, dynamic> member(int n) => {
    'id': '00000000-0000-0000-0000-${n.toString().padLeft(12, '0')}',
    'number': 'M-${n.toString().padLeft(4, '0')}',
    'name': 'Saved Member',
    'phone': '+1 202 555 0101',
    'email': 'member@example.com',
    'address': 'Saved address',
    'emergency_phone': '',
    'notes': 'Saved staff notes',
    'joined': '2026-01-01',
    'is_active': true,
  };
  http.Response json(Object data, [int status = 200]) => http.Response(
    jsonEncode(data),
    status,
    headers: {'content-type': 'application/json'},
  );
  http.Response error(String code, String message, [int status = 400]) => json({
    'error': {'code': code, 'message': message},
  }, status);
  late final http.Client client = MockClient((request) async {
    requests.add(request);
    final path = request.url.path;
    final body = request.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(request.body) as Map<String, dynamic>;
    if (path == '/api/v1/auth/login') {
      if (loginBarrier != null) await loginBarrier;
      if (!allowLogin) {
        return error(
          'invalid_credentials',
          'Server password is incorrect.',
          401,
        );
      }
      return json({
        'access_token': sessionToken,
        'token_type': 'bearer',
        'expires_at': DateTime.now()
            .toUtc()
            .add(const Duration(days: 90))
            .toIso8601String(),
        'admin': admins.first,
      });
    }
    if (path == '/health/ready') {
      return json({'status': 'ready', 'schema': '2', 'database': 'ok'});
    }
    if (expired) return error('unauthorized', 'Authentication required.', 401);
    if (request.headers['Authorization'] != 'Bearer $sessionToken') {
      return error('unauthorized', 'Authentication required.', 401);
    }
    if (request.method != 'GET' && writeBarrier != null) {
      await writeBarrier;
    }
    if (failReads && request.method == 'GET') {
      throw http.ClientException('Synthetic offline state');
    }
    if (failWrites && request.method != 'GET') {
      return error('internal_error', 'Server error.', 500);
    }
    if (path == '/api/v1/auth/resume') {
      return json({
        'admin': admins.first,
        'expires_at': DateTime.now()
            .toUtc()
            .add(const Duration(days: 90))
            .toIso8601String(),
      });
    }
    if (path == '/api/v1/dashboard/summary') {
      return json({
        'total_members': members.length,
        'active_member_records': members.length,
        'present_today': null,
        'active_plans': null,
        'revenue_today': null,
      });
    }
    if (path == '/api/v1/admins') {
      if (request.method == 'POST') {
        if (admins.isNotEmpty) {
          return error(
            'admin_limit',
            'Only one server administrator is allowed.',
            409,
          );
        }
        admins.add({
          'id': 'admin-${admins.length}',
          'name': body['name'],
          'email': body['email'],
        });
        return json(admins.last, 201);
      }
      return json(admins);
    }
    if (path == '/api/v1/settings') {
      if (request.method == 'PUT') settings = {...settings, ...body};
      return json(settings);
    }
    if (path == '/api/v1/auth/logout' ||
        path == '/api/v1/auth/change-password') {
      return http.Response('', 204);
    }
    if (path == '/api/v1/members') {
      if (request.method == 'POST') {
        members.add({...member(43 + members.length - 1), ...body});
        return json(members.last, 201);
      }
      final query = request.url.queryParameters['q']?.toLowerCase() ?? '';
      final visible = members
          .where(
            (m) => [
              m['name'],
              m['phone'],
              m['number'],
            ].any((v) => '$v'.toLowerCase().contains(query)),
          )
          .toList();
      final offset = int.parse(request.url.queryParameters['offset'] ?? '0');
      return json({
        'items': visible.skip(offset).take(50).toList(),
        'total': visible.length,
        'limit': 50,
        'offset': offset,
      });
    }
    if (path.startsWith('/api/v1/members/')) {
      return json(members.singleWhere((m) => path.endsWith(m['id'] as String)));
    }
    return error('not_found', 'Route not found.', 404);
  });
}
