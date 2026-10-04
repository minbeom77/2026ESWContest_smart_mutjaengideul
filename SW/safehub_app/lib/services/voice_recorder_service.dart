import 'dart:io';
import 'dart:typed_data';

import 'package:record/record.dart';

abstract interface class VoiceRecorderBackend {
  Future<bool> hasPermission();
  Future<bool> supportsWav();
  Future<bool> isRecording();
  Future<void> start(String path);
  Future<String?> stop();
  Future<void> cancel();
  Future<void> dispose();
}

class AtlasVoiceRecorderBackend implements VoiceRecorderBackend {
  final AudioRecorder _recorder = AudioRecorder();

  @override
  Future<bool> hasPermission() {
    return _recorder.hasPermission();
  }

  @override
  Future<bool> supportsWav() {
    return _recorder.isEncoderSupported(AudioEncoder.wav);
  }

  @override
  Future<bool> isRecording() {
    return _recorder.isRecording();
  }

  @override
  Future<void> start(String path) {
    return _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        noiseSuppress: true,
      ),
      path: path,
    );
  }

  @override
  Future<String?> stop() {
    return _recorder.stop();
  }

  @override
  Future<void> cancel() {
    return _recorder.cancel();
  }

  @override
  Future<void> dispose() {
    return _recorder.dispose();
  }
}

typedef RecordingDirectoryProvider = Future<Directory> Function();

class VoiceRecorderService {
  final VoiceRecorderBackend _backend;
  final RecordingDirectoryProvider _directoryProvider;
  final Set<String> _ownedPaths = {};
  Future<String>? _starting;
  Future<Uint8List>? _stopping;
  Future<void>? _cancelling;
  Future<void>? _disposing;
  String? _recordingPath;
  bool _disposed = false;
  int _generation = 0;

  VoiceRecorderService({
    VoiceRecorderBackend? backend,
    RecordingDirectoryProvider? directoryProvider,
  }) : _backend = backend ?? AtlasVoiceRecorderBackend(),
       _directoryProvider = directoryProvider ?? _defaultRecordingDirectory;

  static Future<Directory> _defaultRecordingDirectory() async {
    final home =
        (Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'])
            ?.trim();
    final base =
        home == null || home.isEmpty ? Directory.systemTemp.path : home;

    final directory = Directory('$base/safehub_recordings');

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    return directory;
  }

  Future<String> start() {
    if (_disposed) return Future.error(StateError('녹음 서비스가 종료되었습니다.'));
    if (_starting != null ||
        _stopping != null ||
        _cancelling != null ||
        _recordingPath != null) {
      return Future.error(StateError('이미 음성을 녹음하거나 준비하고 있습니다.'));
    }
    return _starting = _start(_generation).whenComplete(() => _starting = null);
  }

  void _checkActive(int generation) {
    if (_disposed || generation != _generation) {
      throw StateError('녹음이 중단되었습니다.');
    }
  }

  Future<String> _start(int generation) async {
    String? path;
    bool startRequested = false;
    try {
      final recording = await _backend.isRecording();
      _checkActive(generation);
      if (recording) throw StateError('이미 음성을 녹음하고 있습니다.');

      final permitted = await _backend.hasPermission();
      _checkActive(generation);
      if (!permitted) throw StateError('마이크 사용 권한이 없습니다.');

      final supported = await _backend.supportsWav();
      _checkActive(generation);
      if (!supported) throw StateError('이 장치에서 WAV 녹음을 지원하지 않습니다.');

      final directory = await _directoryProvider();
      _checkActive(generation);
      await directory.create(recursive: true);
      _checkActive(generation);

      path =
          '${directory.path}/safehub_speech_${DateTime.now().microsecondsSinceEpoch}.wav';
      _recordingPath = path;
      _ownedPaths.add(path);
      startRequested = true;
      await _backend.start(path);
      _checkActive(generation);
      return path;
    } catch (_) {
      if (startRequested) {
        try {
          await _backend.cancel();
        } catch (_) {}
      }
      if (path != null) await _deleteOwnedFile(path);
      if (_recordingPath == path) _recordingPath = null;
      rethrow;
    }
  }

  Future<Uint8List> stopAndRead() {
    if (_disposed) return Future.error(StateError('녹음 서비스가 종료되었습니다.'));
    if (_starting != null ||
        _stopping != null ||
        _cancelling != null ||
        _recordingPath == null) {
      return Future.error(StateError('종료할 녹음이 없거나 다른 작업이 진행 중입니다.'));
    }
    return _stopping = _stopAndRead(
      _generation,
      _recordingPath!,
    ).whenComplete(() => _stopping = null);
  }

  Future<Uint8List> _stopAndRead(int generation, String ownedPath) async {
    try {
      final recording = await _backend.isRecording();
      _checkActive(generation);
      if (!recording) throw StateError('진행 중인 음성 녹음이 없습니다.');

      final path = await _backend.stop();
      _checkActive(generation);
      if (path == null || path.trim().isEmpty)
        throw StateError('녹음 파일 경로를 받지 못했습니다.');
      final actual = File(path).absolute.uri.normalizePath().toString();
      final expected = File(ownedPath).absolute.uri.normalizePath().toString();
      if (Platform.isWindows
          ? actual.toLowerCase() != expected.toLowerCase()
          : actual != expected) {
        throw StateError('현재 녹음 파일과 반환된 경로가 다릅니다.');
      }

      final file = File(ownedPath);
      if (!await file.exists()) throw StateError('녹음 파일을 찾을 수 없습니다.');
      _checkActive(generation);
      final bytes = await file.readAsBytes();
      _checkActive(generation);
      if (bytes.isEmpty) throw StateError('녹음 파일이 비어 있습니다.');
      return bytes;
    } catch (_) {
      try {
        await _backend.cancel();
      } catch (_) {}
      rethrow;
    } finally {
      await _deleteOwnedFile(ownedPath);
      if (_recordingPath == ownedPath) _recordingPath = null;
    }
  }

  Future<void> _deleteOwnedFile(String path) async {
    if (!_ownedPaths.contains(path)) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
      _ownedPaths.remove(path);
    } on FileSystemException {
      // Retry these owned temporary paths during disposal if a plugin still holds one.
    }
  }

  Future<void> _waitForOperations() async {
    try {
      await _starting;
    } catch (_) {}
    try {
      await _stopping;
    } catch (_) {}
  }

  Future<void> cancel() {
    if (_disposed) return _disposing ?? Future.value();
    if (_cancelling != null) return _cancelling!;
    _generation++;
    return _cancelling = _cancel().whenComplete(() => _cancelling = null);
  }

  Future<void> _cancel() async {
    await _waitForOperations();
    try {
      await _backend.cancel();
    } finally {
      _recordingPath = null;
      for (final path in _ownedPaths.toList()) {
        await _deleteOwnedFile(path);
      }
    }
  }

  Future<bool> get isRecording =>
      _disposed ? Future.value(false) : _backend.isRecording();

  Future<void> dispose() {
    if (_disposing != null) return _disposing!;
    _disposed = true;
    _generation++;
    return _disposing = _dispose();
  }

  Future<void> _dispose() async {
    await _waitForOperations();
    try {
      await _cancelling;
    } catch (_) {}
    try {
      if (_recordingPath != null) await _backend.cancel();
    } finally {
      try {
        await _backend.dispose();
      } finally {
        _recordingPath = null;
        for (final path in _ownedPaths.toList()) {
          await _deleteOwnedFile(path);
        }
      }
    }
  }
}
