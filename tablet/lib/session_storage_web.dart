import 'dart:convert';
import 'dart:js_interop';

@JS('window.localStorage')
external _BrowserStorage get _storage;

extension type _BrowserStorage(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
}

Future<String?> readDeviceSession() async => _storage.getItem('replab.device');
Future<void> writeDeviceSession(String value) async {
  final data = jsonDecode(value) as Map<String, dynamic>;
  // Browser preview never persists a bearer token in DOM-accessible storage.
  data.remove('token');
  data['biometrics'] = false;
  _storage.setItem('replab.device', jsonEncode(data));
}
