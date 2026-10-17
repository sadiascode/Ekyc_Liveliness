import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/app_config.dart';
import '../models/kyc_data.dart';

class KycApiException implements Exception {
  KycApiException(this.message, [this.statusCode]);
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class KycApiService {
  KycApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Uploads the three images plus form fields. Returns the server reference.
  Future<String> submit(KycData data, {required Map<String, String> fields}) async {
    if (!data.isComplete) {
      throw KycApiException('All three captures are required.');
    }

    if (AppConfig.isDemo) {
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      return 'DEMO-${DateTime.now().millisecondsSinceEpoch}';
    }

    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/v1/kyc/submissions');
    final req = http.MultipartRequest('POST', uri)
      ..headers['Accept'] = 'application/json'
      ..fields.addAll(fields)
      ..fields['liveness'] = jsonEncode(data.liveness!.toJson());
    if (AppConfig.apiToken.isNotEmpty) {
      req.headers['Authorization'] = 'Bearer ${AppConfig.apiToken}';
    }
    req.files.addAll([
      await http.MultipartFile.fromPath('nid_front', data.front!.image.path),
      await http.MultipartFile.fromPath('nid_back', data.back!.image.path),
      await http.MultipartFile.fromPath('selfie', data.liveness!.selfie.path),
    ]);

    final http.Response res;
    try {
      final streamed = await _client.send(req).timeout(const Duration(seconds: 60));
      res = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw KycApiException('The server took too long to respond. Try again.');
    }

    if (res.statusCode == 200 || res.statusCode == 201) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return (body['id'] ?? body['reference'] ?? '').toString();
    }
    if (res.statusCode == 422) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw KycApiException(body['message']?.toString() ?? 'Some details are invalid.', 422);
    }
    if (res.statusCode == 401) {
      throw KycApiException('Your session has expired. Sign in again.', 401);
    }
    throw KycApiException('Submission failed (${res.statusCode}). Try again.', res.statusCode);
  }
}
