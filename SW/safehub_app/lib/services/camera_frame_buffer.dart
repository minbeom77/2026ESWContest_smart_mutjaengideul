import 'dart:typed_data';

/// Parses the existing big-endian length + RGBA protocol.
/// In a received batch only the newest complete frame is copied for display.
class CameraFrameBuffer {
  final List<int> _bytes = [];
  static const int maxFrameBytes = 10 * 1024 * 1024;

  Uint8List? addAndTakeLatest(Uint8List data) {
    _bytes.addAll(data);
    var consumed = 0;
    int? latestStart;
    var latestLength = 0;
    while (_bytes.length - consumed >= 4) {
      final length = (_bytes[consumed] << 24) |
          (_bytes[consumed + 1] << 16) |
          (_bytes[consumed + 2] << 8) |
          _bytes[consumed + 3];
      if (length <= 0 || length > maxFrameBytes) {
        clear();
        throw const FormatException('Invalid camera frame length');
      }
      if (_bytes.length - consumed < 4 + length) break;
      latestStart = consumed + 4;
      latestLength = length;
      consumed += 4 + length;
    }
    final latest = latestStart == null ? null :
        Uint8List.fromList(_bytes.sublist(latestStart, latestStart + latestLength));
    if (consumed == _bytes.length) {
      clear();
    } else if (consumed > 0) {
      _bytes.removeRange(0, consumed);
    }
    return latest;
  }

  void clear() => _bytes.clear();
}
