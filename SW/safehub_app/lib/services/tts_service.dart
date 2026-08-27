import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class TtsService {
  final String baseUrl;

  const TtsService({
    required this.baseUrl,
  });

  Future<Uint8List> synthesize(String text) async {
    final cleanText = text.trim();

    if (cleanText.isEmpty) {
      throw ArgumentError('TTS text는 비어 있을 수 없습니다.');
    }

    final uri = Uri.parse('$baseUrl/tts');

    final response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'text': cleanText,
          }),
        )
        .timeout(
          const Duration(seconds: 15),
        );

    if (response.statusCode != 200) {
      throw StateError(
        'TTS 요청 실패: HTTP ${response.statusCode}',
      );
    }

    if (response.bodyBytes.isEmpty) {
      throw StateError('TTS 응답이 비어 있습니다.');
    }

    return response.bodyBytes;
  }
}
