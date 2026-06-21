import 'dart:convert';
import 'package:http/http.dart' as http;
import 'server_config.dart';

class TurnService {
  Future<Map<String, dynamic>?> fetchIceServers() async {
    try {
      final base = await ServerConfig.getUrl();
      final uri = Uri.parse('$base/api/turn');
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data.containsKey('iceServers') ? data : null;
    } catch (_) {
      return null;
    }
  }
}
