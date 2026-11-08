import 'package:http/http.dart' as http;

// Browsers hide TLS/DNS/CORS failure details; use DevTools to distinguish them.
String? apiTransportError(Object error, String host) => null;

Future<http.Client> createApiClient() async => http.Client();
