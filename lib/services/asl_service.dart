import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const kAslServerDefaultUrl = 'https://placeholder.trycloudflare.com';

class AslPrediction {
  final String predictedClass;
  final double confidence;
  final List<AslTopK> topK;
  final bool handDetected;
  final String modelUsed;
  // 21 landmarks × 3 coords — null when not available
  final List<List<double>>? normLandmarks;

  const AslPrediction({
    required this.predictedClass,
    required this.confidence,
    required this.topK,
    required this.handDetected,
    required this.modelUsed,
    this.normLandmarks,
  });

  factory AslPrediction.fromJson(Map<String, dynamic> json) {
    List<List<double>>? lm;
    final raw = json['norm_landmarks'];
    if (raw is List && raw.isNotEmpty) {
      if (raw.first is List) {
        // nested: [[x,y,z], [x,y,z], ...]
        lm = raw
            .map<List<double>>(
              (e) => (e as List).map<double>((v) => (v as num).toDouble()).toList(),
            )
            .toList();
      } else {
        // flat list of 63 floats → reshape to 21×3
        final flat = raw.map<double>((v) => (v as num).toDouble()).toList();
        if (flat.length == 63) {
          lm = List.generate(21, (i) => flat.sublist(i * 3, i * 3 + 3));
        }
      }
    }
    return AslPrediction(
      predictedClass: json['predicted_class'] as String? ?? '?',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      topK: (json['top_k'] as List<dynamic>? ?? [])
          .map((e) => AslTopK.fromJson(e as Map<String, dynamic>))
          .toList(),
      handDetected: json['hand_detected'] as bool? ?? false,
      modelUsed: json['model_used'] as String? ?? 'cnn',
      normLandmarks: lm,
    );
  }
}

class AslTopK {
  final String className;
  final double confidence;

  const AslTopK({required this.className, required this.confidence});

  factory AslTopK.fromJson(Map<String, dynamic> json) {
    return AslTopK(
      className: json['class_name'] as String? ?? '?',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class AslWordPrediction {
  final String predictedClass;
  final double confidence;
  final List<AslTopK> topK;

  const AslWordPrediction({
    required this.predictedClass,
    required this.confidence,
    required this.topK,
  });

  factory AslWordPrediction.fromJson(Map<String, dynamic> json) {
    return AslWordPrediction(
      predictedClass: json['predicted_class'] as String? ?? '?',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      topK: (json['top_k'] as List<dynamic>? ?? [])
          .map((e) => AslTopK.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class AslService {
  AslService({this.serverUrl = kAslServerDefaultUrl});

  final String serverUrl;

  Future<AslPrediction> predictFromFile(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    return predictFromBytes(bytes);
  }

  Future<AslPrediction> predictFromBytes(List<int> bytes) async {
    final b64 = base64Encode(bytes);
    final uri = Uri.parse('$serverUrl/api/predict');
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'image_base64': b64}),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('ASL server error ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json.containsKey('error')) throw Exception(json['error']);
    return AslPrediction.fromJson(json);
  }

  // sequence: list of 30 frames, each frame = 21 landmarks × [x,y,z]
  Future<AslWordPrediction?> predictWord(
    List<List<List<double>>> sequence,
  ) async {
    try {
      // flatten each frame: 21×3 → 63 floats
      final flat = sequence
          .map((frame) => frame.expand((lm) => lm).toList())
          .toList();
      final uri = Uri.parse('$serverUrl/api/predict_word');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'sequence': flat}),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json.containsKey('error')) return null;
      return AslWordPrediction.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<bool> isReachable() async {
    try {
      final uri = Uri.parse('$serverUrl/health');
      final response = await http.get(uri).timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
