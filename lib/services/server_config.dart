import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'asl_service.dart' show kAslServerDefaultUrl;

const _kServerUrlKey = 'asl_server_url';
const _kGistApiUrl =
    'https://api.github.com/gists/70b3b1fd6d6fa902d42352493b8d1a3a';

class ServerConfig {
  static Future<String> getUrl() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final response = await http
          .get(Uri.parse(_kGistApiUrl))
          .timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content =
            data['files']['asl_tunnel.txt']['content']?.toString().trim() ?? '';
        if (content.isNotEmpty && content != 'placeholder') {
          await prefs.setString(_kServerUrlKey, content);
          return content;
        }
      }
    } catch (_) {}
    return prefs.getString(_kServerUrlKey) ?? kAslServerDefaultUrl;
  }

  static Future<void> setUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kServerUrlKey, url.trim().replaceAll(RegExp(r'/+$'), ''));
  }
}
