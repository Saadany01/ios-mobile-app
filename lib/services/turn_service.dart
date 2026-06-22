import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'server_config.dart';

// Must match _TURN_SECRET in server.py
const _kTurnSecret = 'f6233482ae1ab37f12de7b840833fc37560b86e74522295a71318dd3b14dda11';
const _kTurnHost   = 'asl.servepics.com';
const _kTurnTtl    = 3600; // 1 hour

/// Builds ICE server config locally — no HTTP request needed.
/// Used when port 8000 is blocked on 4G, or server is unreachable.
Map<String, dynamic> _buildLocalIceConfig() {
  final expiry   = (DateTime.now().millisecondsSinceEpoch ~/ 1000) + _kTurnTtl;
  final username = '$expiry:hearmysign';
  final hmac     = Hmac(sha1, utf8.encode(_kTurnSecret));
  final credential = base64Encode(hmac.convert(utf8.encode(username)).bytes);

  return {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {
        'urls': [
          'turn:$_kTurnHost:3478?transport=udp',
          'turn:$_kTurnHost:3478?transport=tcp',
        ],
        'username':   username,
        'credential': credential,
      },
    ],
  };
}

class TurnService {
  /// Returns ICE server config with valid TURN credentials.
  /// Tries the server first; falls back to local HMAC computation when
  /// the server is unreachable (e.g. port 8000 blocked on 4G).
  Future<Map<String, dynamic>> fetchIceServers() async {
    try {
      final base     = await ServerConfig.getUrl();
      final uri      = Uri.parse('$base/api/turn');
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data.containsKey('iceServers')) return data;
      }
    } catch (_) {}
    // Server unreachable — compute credentials locally so calls still work on 4G
    return _buildLocalIceConfig();
  }
}
