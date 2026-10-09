import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

class AudioService {
  AudioService({
    AudioPlayer? player,
    this.operationTimeout = const Duration(seconds: 5),
  }) : assert(operationTimeout > Duration.zero),
       _player = player;

  AudioPlayer? _player;
  bool _disposed = false;
  final Duration operationTimeout;

  AudioPlayer get _activePlayer {
    if (_disposed) throw StateError('AudioService is disposed');
    return _player ??= AudioPlayer();
  }

  Future<void> playBytes(
    Uint8List bytes, {
    String mimeType = 'audio/mpeg',
  }) async {
    final player = _activePlayer;
    await player.stop().timeout(operationTimeout);

    await player
        .play(BytesSource(bytes, mimeType: mimeType))
        .timeout(operationTimeout);
  }

  Future<void> playUrl(String url) async {
    if (url.trim().isEmpty) {
      return;
    }

    final player = _activePlayer;
    await player.stop().timeout(operationTimeout);
    await player.play(UrlSource(url)).timeout(operationTimeout);
  }

  Future<void> stop() async {
    await _player?.stop().timeout(operationTimeout);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final player = _player;
    _player = null;
    await player?.dispose().timeout(operationTimeout);
  }
}
