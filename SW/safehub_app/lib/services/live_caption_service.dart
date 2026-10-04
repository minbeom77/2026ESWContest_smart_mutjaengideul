import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import 'caption_connection.dart';

abstract interface class CaptionMicrophone {
  Future<Stream<Uint8List>> start();
  Future<void> stop();
  Future<void> close();
}

class RecordCaptionMicrophone implements CaptionMicrophone {
  final AudioRecorder _recorder = AudioRecorder();

  @override
  Future<Stream<Uint8List>> start() async {
    if (!await _recorder.hasPermission()) {
      throw StateError('마이크 사용 권한이 없습니다');
    }
    return _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        noiseSuppress: true,
      ),
    );
  }

  @override
  Future<void> stop() async => _recorder.cancel();

  @override
  Future<void> close() async => _recorder.dispose();
}

class SpeechChunk {
  SpeechChunk(this.id, this.wav, this.isFinal) : createdAt = DateTime.now();
  final int id;
  final Uint8List wav;
  final bool isFinal;
  final DateTime createdAt;
}

/// Frames 16 kHz mono PCM without stopping the microphone between requests.
class SpeechSegmenter {
  final void Function(SpeechChunk) onChunk;
  SpeechSegmenter(this.onChunk);

  static const frameBytes = 640; // 20 ms of signed 16-bit PCM.
  static const partialFrames = 120; // 2.4 s of context before interim decoding.
  static const silenceFrames = 40; // Keep natural pauses within one utterance.
  static const maximumFrames = 600;
  final _preRoll = Queue<Uint8List>();
  final _speech = <Uint8List>[];
  Uint8List _remainder = Uint8List(0);
  int _id = 0;
  int _voiced = 0;
  int _quiet = 0;
  int _sincePartial = 0;
  double level = 0;
  double _noise = .001;
  double _previousInput = 0;
  double _previousOutput = 0;

  void reset() {
    _id++;
    _preRoll.clear();
    _speech.clear();
    _remainder = Uint8List(0);
    _voiced = _quiet = _sincePartial = 0;
    level = 0;
    _previousInput = _previousOutput = 0;
  }

  void add(Uint8List bytes) {
    final joined =
        Uint8List(_remainder.length + bytes.length)
          ..setAll(0, _remainder)
          ..setAll(_remainder.length, bytes);
    var offset = 0;
    while (offset + frameBytes <= joined.length) {
      _frame(Uint8List.fromList(joined.sublist(offset, offset + frameBytes)));
      offset += frameBytes;
    }
    _remainder = Uint8List.fromList(joined.sublist(offset));
  }

  void _frame(Uint8List bytes) {
    final samples = ByteData.sublistView(bytes);
    var square = 0.0;
    for (var i = 0; i < bytes.length; i += 2) {
      final sample = samples.getInt16(i, Endian.little) / 32768;
      // Remove microphone DC offset with a ~20 Hz high-pass filter. Keep its
      // state between frames so sample boundaries do not create clicks.
      final filtered = sample - _previousInput + .99217678 * _previousOutput;
      _previousInput = sample;
      _previousOutput = filtered;
      final cleaned = filtered.clamp(-1.0, 32767 / 32768);
      samples.setInt16(i, (cleaned * 32768).round(), Endian.little);
      square += cleaned * cleaned;
    }
    level = math.sqrt(square / (bytes.length / 2));
    final voiced = level > math.max(.006, _noise * 3);
    if (_speech.isEmpty) {
      _preRoll.add(bytes);
      if (_preRoll.length > 20) _preRoll.removeFirst();
      if (!voiced) {
        _noise = .98 * _noise + .02 * math.min(level, .006);
        return;
      }
      _id++;
      _speech.addAll(_preRoll);
      _preRoll.clear();
      _voiced = 1;
      _quiet = _sincePartial = 0;
    } else {
      _speech.add(bytes);
      _voiced += voiced ? 1 : 0;
      _quiet = voiced ? 0 : _quiet + 1;
      _sincePartial++;
    }
    final end = _quiet >= silenceFrames || _speech.length >= maximumFrames;
    if (end || _sincePartial >= partialFrames) {
      if (_voiced >= 15) {
        onChunk(SpeechChunk(_id, pcmToWav(_speech), end));
      }
      _sincePartial = 0;
      if (end) {
        _speech.clear();
        _voiced = _quiet = 0;
      }
    }
  }

  static Uint8List pcmToWav(List<Uint8List> frames) {
    final size = frames.fold<int>(0, (count, frame) => count + frame.length);
    final wav = Uint8List(44 + size);
    final header = ByteData.sublistView(wav);
    void text(int offset, String value) => wav.setAll(offset, value.codeUnits);
    text(0, 'RIFF');
    header.setUint32(4, 36 + size, Endian.little);
    text(8, 'WAVEfmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, 16000, Endian.little);
    header.setUint32(28, 32000, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    text(36, 'data');
    header.setUint32(40, size, Endian.little);
    var offset = 44;
    for (final frame in frames) {
      wav.setAll(offset, frame);
      offset += frame.length;
    }
    return wav;
  }
}

/// One request in flight, at most two pending utterances, no audio files on disk.
class LiveCaptionService extends ChangeNotifier {
  LiveCaptionService({
    required this.transcribe,
    this.connectStream,
    CaptionMicrophone? microphone,
  }) : _microphone = microphone ?? RecordCaptionMicrophone() {
    _segmenter = SpeechSegmenter(_enqueue);
  }

  final Future<String> Function(Uint8List) transcribe;
  final Future<CaptionConnection?> Function()? connectStream;
  CaptionConnection? _connection;
  StreamSubscription<CaptionResult>? _resultsSubscription;
  Timer? _reconnectTimer;
  bool _recovering = false;
  int _streamBase = 0;
  Uint8List _pcmRemainder = Uint8List(0);
  double _dcInput = 0;
  double _dcOutput = 0;
  final CaptionMicrophone _microphone;
  late final SpeechSegmenter _segmenter;
  final _pending = <SpeechChunk>[];
  final _lines = LinkedHashMap<int, String>();
  StreamSubscription<Uint8List>? _subscription;
  Future<void>? _starting;
  Future<void>? _stopping;
  Future<void>? _closing;
  bool _closed = false;
  bool _requestBusy = false;
  int _generation = 0;
  int _captionEpoch = 0;
  DateTime _retryAfter = DateTime(0);
  DateTime _lastLevelUpdate = DateTime(0);
  bool enabled = false;
  bool listening = false;
  bool serverError = false;
  String status = '음성 서버 미설정';
  double level = 0;
  String get text => _lines.values.join('\n');
  int get pendingCount => _pending.length;

  void _notify() {
    if (!_closed) notifyListeners();
  }

  Future<void> start() {
    if (_closed || listening) return Future.value();
    if (_starting != null) return _starting!;
    if (_stopping != null) return _stopping!.then((_) => start());
    enabled = true;
    _reconnectTimer?.cancel();
    serverError = false;
    status = '마이크 준비 중';
    _notify();
    final generation = ++_generation;
    return _starting = _start(generation).whenComplete(() => _starting = null);
  }

  Future<void> _start(int generation) async {
    try {
      if (_closed || generation != _generation) return;
      final connection = connectStream == null ? null : await connectStream!();
      if (_closed || generation != _generation) {
        await connection?.close();
        return;
      }
      _connection = connection;
      if (connection != null) {
        _streamBase = _lines.isEmpty ? 0 : _lines.keys.reduce(math.max) + 1;
        connection.reset(_captionEpoch);
        _resultsSubscription = connection.results.listen(
          (result) {
            if (_closed ||
                generation != _generation ||
                !enabled ||
                result.epoch != _captionEpoch)
              return;
            final id = _streamBase + result.segment;
            if (result.text.trim().isNotEmpty) {
              _lines[id] = result.text.trim();
            } else {
              _lines.remove(id);
            }
            while (_lines.length > 8) _lines.remove(_lines.keys.first);
            serverError = false;
            status =
                result.isFinal
                    ? '듣는 중 · 기기 내 실시간 인식'
                    : '실시간 자막 · 말하는 중에도 수정됩니다';
            _notify();
          },
          onError: (Object _) => _recover(generation),
          onDone: () => _recover(generation),
        );
      }
      final stream = await _microphone.start();
      if (_closed || generation != _generation) {
        await _microphone.stop();
        return;
      }
      listening = true;
      status = connection == null ? '듣는 중 · 자동 자막' : '듣는 중 · 기기 내 실시간 인식';
      _subscription = stream.listen(
        (bytes) {
          if (generation != _generation || !enabled) return;
          if (connection != null) {
            try {
              connection.add(_cleanPcm(bytes));
            } catch (_) {
              _recover(generation);
              return;
            }
          } else {
            _segmenter.add(bytes);
            level = _segmenter.level;
          }
          final now = DateTime.now();
          if (now.difference(_lastLevelUpdate).inMilliseconds >= 150) {
            _lastLevelUpdate = now;
            _notify();
          }
        },
        onError: (Object error) {
          if (generation == _generation) {
            unawaited(pause(reason: '마이크 연결을 확인하고 다시 시작하세요'));
          }
        },
        onDone: () {
          if (generation == _generation && enabled) {
            unawaited(pause(reason: '마이크 연결이 끊겼습니다'));
          }
        },
      );
      _notify();
    } catch (_) {
      if (generation != _generation || _closed) return;
      if (connectStream != null) {
        _recover(generation);
      } else {
        enabled = listening = false;
        status = '마이크 연결·권한을 확인하고 다시 시작하세요';
        _notify();
      }
    }
  }

  Uint8List _cleanPcm(Uint8List bytes) {
    final joined =
        Uint8List(_pcmRemainder.length + bytes.length)
          ..setAll(0, _pcmRemainder)
          ..setAll(_pcmRemainder.length, bytes);
    final count = joined.length - joined.length % 2;
    _pcmRemainder = Uint8List.fromList(joined.sublist(count));
    final pcm = Uint8List.sublistView(joined, 0, count);
    final data = ByteData.sublistView(pcm);
    var square = 0.0;
    for (var i = 0; i < count; i += 2) {
      final sample = data.getInt16(i, Endian.little) / 32768;
      final filtered = sample - _dcInput + .99217678 * _dcOutput;
      _dcInput = sample;
      _dcOutput = filtered;
      final cleaned = filtered.clamp(-1.0, 32767 / 32768);
      data.setInt16(i, (cleaned * 32768).round(), Endian.little);
      square += cleaned * cleaned;
    }
    if (count > 0) level = math.sqrt(square / (count / 2));
    return pcm;
  }

  void _recover(int generation) {
    if (_closed || !enabled || generation != _generation || _recovering) return;
    _recovering = true;
    unawaited(() async {
      await pause(reason: '음성 연결 복구 중 · 잠시 후 다시 듣습니다');
      _recovering = false;
      if (_closed || _generation != generation + 1) return;
      enabled = true;
      serverError = true;
      _notify();
      _reconnectTimer = Timer(const Duration(seconds: 2), () {
        if (!_closed && enabled) unawaited(start());
      });
    }());
  }

  void _enqueue(SpeechChunk chunk) {
    if (_closed || !enabled || DateTime.now().isBefore(_retryAfter)) return;
    // Intermediate hypotheses become stale while the server is busy. Preserve
    // completed utterances instead of making them wait behind those requests.
    if (_requestBusy && !chunk.isFinal) return;
    _pending.removeWhere((pending) => pending.id == chunk.id);
    if (_pending.length == 2) {
      _pending.removeAt(0);
      status = '서버 처리 지연 · 일부 자막 생략';
    }
    _pending.add(chunk);
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_requestBusy || _closed) return;
    _requestBusy = true;
    try {
      while (_pending.isNotEmpty && enabled && !_closed) {
        final chunk = _pending.removeAt(0);
        final generation = _generation;
        final captionEpoch = _captionEpoch;
        final queueMs =
            DateTime.now().difference(chunk.createdAt).inMilliseconds;
        final timer = Stopwatch()..start();
        status = '음성 변환 중 · 계속 듣고 있습니다';
        _notify();
        try {
          final transcript = await transcribe(chunk.wav);
          debugPrint(
            '[STT] final=${chunk.isFinal} '
            'audio_ms=${((chunk.wav.length - 44) / 32).round()} '
            'queue_ms=$queueMs request_ms=${timer.elapsedMilliseconds}',
          );
          if (_closed ||
              generation != _generation ||
              captionEpoch != _captionEpoch ||
              !enabled)
            continue;
          if (transcript.trim().isNotEmpty) {
            _lines[chunk.id] = transcript.trim();
            while (_lines.length > 8) _lines.remove(_lines.keys.first);
          }
          serverError = false;
          status = chunk.isFinal ? '듣는 중 · 자동 자막' : '임시 자막 · 문장 끝에서 다시 인식합니다';
        } catch (_) {
          if (_closed || generation != _generation || !enabled) continue;
          _pending.clear();
          _retryAfter = DateTime.now().add(const Duration(seconds: 5));
          serverError = true;
          status = '음성 서버 연결 확인 · 자동 재시도';
        }
        _notify();
      }
    } finally {
      _requestBusy = false;
    }
  }

  Future<void> pause({String reason = '자막 일시정지'}) {
    _reconnectTimer?.cancel();
    enabled = listening = false;
    _generation++;
    _pending.clear();
    _segmenter.reset();
    _pcmRemainder = Uint8List(0);
    _dcInput = _dcOutput = 0;
    level = 0;
    status = reason;
    _notify();
    return _stopping ??= _stop().whenComplete(() => _stopping = null);
  }

  Future<void> _stop() async {
    await _resultsSubscription?.cancel();
    _resultsSubscription = null;
    await _connection?.close();
    _connection = null;
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _starting;
      await _microphone.stop();
    } catch (_) {
      status = '마이크 중단 상태를 확인하세요';
      _notify();
    }
  }

  void clear() {
    _lines.clear();
    // Do not let an older in-flight response repopulate cleared subtitles.
    _pending.clear();
    _segmenter.reset();
    _captionEpoch++;
    _connection?.reset(_captionEpoch);
    _notify();
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    return _closing = pause().then((_) => _microphone.close()).catchError((
      Object error,
    ) {
      debugPrint('Caption microphone cleanup failed: $error');
    });
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }
}
