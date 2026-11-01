import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _storage = FlutterSecureStorage(
  aOptions: AndroidOptions(resetOnError: false),
);
Future<String?> readDeviceSession() => _storage.read(key: 'replab.device');
Future<void> writeDeviceSession(String value) =>
    _storage.write(key: 'replab.device', value: value);
