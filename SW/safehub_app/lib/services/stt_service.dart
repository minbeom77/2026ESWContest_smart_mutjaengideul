import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'caption_connection.dart';

class SttService {
  final String baseUrl;
  final http.Client _client;
  final Duration timeout;

  SttService({
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  Future<CaptionConnection?> connectCaptions() async {
    final base = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final response = await _client
        .get(Uri.parse('$base/health'))
        .timeout(const Duration(seconds: 3));
    // Existing team servers retain their file-based API.
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) throw StateError('음성 서버 준비 중');
    final health = jsonDecode(utf8.decode(response.bodyBytes));
    if (health is! Map || health['streaming_protocol'] != 'safehub.pcm.v1') {
      return null;
    }
    if (health['ready'] != true) throw StateError('음성 모델 준비 중');
    final uri = Uri.parse('$base/stt/stream');
    return WebSocketCaptionConnection.connect(
      uri.replace(scheme: uri.scheme == 'https' ? 'wss' : 'ws'),
    );
  }

  Future<String> transcribe(
    Uint8List audioBytes, {
    String filename = 'speech.wav',
  }) async {
    if (audioBytes.isEmpty) {
      throw ArgumentError('STT 음성 데이터는 비어 있을 수 없습니다.');
    }

    final cleanBaseUrl = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');

    if (cleanBaseUrl.isEmpty) {
      throw StateError('STT 서버 URL이 설정되지 않았습니다.');
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$cleanBaseUrl/stt'),
    );

    request.files.add(
      http.MultipartFile.fromBytes('audio', audioBytes, filename: filename),
    );

    final response = await (() async {
      final streamedResponse = await _client.send(request);
      return http.Response.fromStream(streamedResponse);
    })().timeout(timeout);

    // The speech server uses 422 when no speech is found in a valid WAV.
    if (response.statusCode == 422) return '';

    if (response.statusCode != 200) {
      throw StateError('STT 요청 실패: HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));

    if (decoded is! Map<String, dynamic>) {
      throw StateError('STT 응답 형식이 올바르지 않습니다.');
    }

    final value = decoded['text'] ?? decoded['transcript'];

    if (value is! String || value.trim().isEmpty) {
      throw StateError('STT 인식 결과가 비어 있습니다.');
    }

    return value.trim();
  }

  void dispose() {
    _client.close();
  }
}
