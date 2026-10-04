import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

class AudioService {
  final AudioPlayer _player = AudioPlayer();

  Future<void> playBytes(
    Uint8List bytes, {
    String mimeType = 'audio/mpeg',
  }) async {
    await _player.stop();

    await _player.play(
      BytesSource(
        bytes,
        mimeType: mimeType,
      ),
    );
  }

  Future<void> playUrl(String url) async {
    if (url.trim().isEmpty) {
      return;
    }

    await _player.stop();
    await _player.play(
      UrlSource(url),
    );
  }

  Future<void> stop() async {
    await _player.stop();
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}
