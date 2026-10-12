import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api_client.dart' if (dart.library.js_interop) 'api_client_web.dart';

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class Api {
  final client = createClient();
  String? token;
  String get base {
    const configured = String.fromEnvironment('API_URL');
    if (configured.isNotEmpty) return configured;
    // The Node.js server uses port 8080. Flutter's development server can use
    // any other port, so requests must not be sent back to the Flutter server.
    if (kIsWeb && Uri.base.port == 8080) return Uri.base.origin;
    return 'http://localhost:8080';
  }

  Future<Map<String, dynamic>> call(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    try {
      final uri = Uri.parse('$base/api$path');
      final response =
          await (method == 'DELETE'
                  ? client.delete(
                      uri,
                      headers: headers,
                      body: jsonEncode(body ?? {}),
                    )
                  : method == 'GET'
                  ? client.get(uri, headers: headers)
                  : method == 'PATCH'
                  ? client.patch(
                      uri,
                      headers: headers,
                      body: jsonEncode(body ?? {}),
                    )
                  : client.post(
                      uri,
                      headers: headers,
                      body: jsonEncode(body ?? {}),
                    ))
              .timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode >= 400) {
        throw ApiException(data['error'] as String? ?? 'Сұрау орындалмады.');
      }
      return data;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(
        'Серверге қосылу мүмкін болмады. Байланысты тексеріп, қайталаңыз.',
      );
    }
  }

  void close() => client.close();
}
