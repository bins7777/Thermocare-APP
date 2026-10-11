import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models.dart';

class DeviceApi {
  DeviceApi({http.Client? client}) : client = client ?? http.Client();
  final http.Client client;
  Future<dynamic> _get(
    Uri base,
    String path, [
    Map<String, String>? query,
  ]) async {
    final response = await client
        .get(base.replace(path: path, queryParameters: query))
        .timeout(const Duration(seconds: 4));
    if (response.statusCode != 200) {
      throw FormatException(
        response.statusCode == 503
            ? 'The sensor is unavailable. Check its connection and restart the thermometer.'
            : 'Device returned HTTP ${response.statusCode}.',
      );
    }
    return jsonDecode(response.body);
  }

  Future<Reading> latest(Uri base) async {
    final json = await _get(base, '/api/temperature');
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Invalid device response.');
    }
    final reading = Reading.fromApi(json);
    if ((json['age_ms'] as num) > 5000) {
      throw const FormatException('The device reading is stale.');
    }
    return reading;
  }

  Future<List<Reading>> history(Uri base) async {
    final json = await _get(base, '/api/history');
    if (json is! List || json.length > 120) {
      throw const FormatException('Invalid history response.');
    }
    return json.map((r) => Reading.fromApi(r as Map<String, dynamic>)).toList();
  }

  Future<void> syncClock(Uri base) async {
    await _get(base, '/api/time', {
      'epoch': '${DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000}',
    });
  }

  void dispose() => client.close();
}
