import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:safehub_app/services/live_caption_service.dart';

Uint8List pcm(int frames, [int amplitude = 3000]) {
  final bytes = Uint8List(frames * SpeechSegmenter.frameBytes);
  final data = ByteData.sublistView(bytes);
  for (var i = 0; i < bytes.length; i += 2) {
    data.setInt16(
      i,
      (amplitude * math.sin(2 * math.pi * 300 * (i / 2) / 16000)).round(),
      Endian.little,
    );
  }
  return bytes;
}

class FakeMicrophone implements CaptionMicrophone {
  final controller = StreamController<Uint8List>.broadcast(sync: true);
  Completer<void>? permission;
  int starts = 0;
  int stops = 0;
  @override
  Future<Stream<Uint8List>> start() async {
    starts++;
    await permission?.future;
    return controller.stream;
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> close() => controller.close();
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('busy server skips queued interim audio but retains completed sentence', () async {
    final mic = FakeMicrophone();
    final response = Completer<String>();
    var calls = 0;
    final service = LiveCaptionService(microphone: mic, transcribe: (_) {
      calls++;
      return response.future;
    });
    await service.start();
    mic.controller.add(pcm(260));
    expect(calls, 1);
    expect(service.pendingCount, 0);
    mic.controller.add(pcm(41, 0));
    expect(service.pendingCount, 1);
    response.complete('완료');
    await settle();
    expect(calls, 2);
    expect(service.pendingCount, 0);
    await service.close();
  });
  test('a 7.4-second sentence is not cut at the former six-second limit', () {
    final chunks = <SpeechChunk>[];
    final segmenter = SpeechSegmenter(chunks.add);
    segmenter.add(pcm(370));
    expect(chunks.where((chunk) => chunk.isFinal), isEmpty);
    segmenter.add(pcm(41, 0));
    expect(chunks.last.isFinal, true);
    expect(chunks.map((chunk) => chunk.id).toSet().length, 1);
    expect(chunks.last.wav.length, greaterThan(7.4 * 32000));
  });
  test('constant microphone offset does not create speech requests', () {
    final chunks = <SpeechChunk>[];
    final bytes = Uint8List(640 * 400);
    final samples = ByteData.sublistView(bytes);
    for (var i = 0; i < bytes.length; i += 2) {
      samples.setInt16(i, 1200, Endian.little);
    }
    SpeechSegmenter(chunks.add).add(bytes);
    expect(chunks, isEmpty);
  });

  test('half-second pause stays inside the same utterance', () {
    final chunks = <SpeechChunk>[];
    final segmenter = SpeechSegmenter(chunks.add);
    segmenter.add(pcm(130));
    segmenter.add(pcm(25, 0));
    expect(chunks.where((chunk) => chunk.isFinal), isEmpty);
    segmenter.add(pcm(30));
    segmenter.add(pcm(41, 0));
    expect(chunks.last.isFinal, true);
    expect(chunks.last.id, chunks.first.id);
  });

  test('brief impact does not become an utterance', () {
    final chunks = <SpeechChunk>[];
    final segmenter = SpeechSegmenter(chunks.add);
    segmenter.add(pcm(5));
    segmenter.add(pcm(45, 0));
    expect(chunks, isEmpty);
  });

  test('silence does not create requests', () {
    final chunks = <SpeechChunk>[];
    SpeechSegmenter(chunks.add).add(pcm(1000, 0));
    expect(chunks, isEmpty);
  });

  test('continuous speech produces partial WAV and updates same utterance', () {
    final chunks = <SpeechChunk>[];
    final segmenter = SpeechSegmenter(chunks.add);
    final bytes = pcm(130);
    // Device stdout may split PCM samples across arbitrary byte boundaries.
    for (var i = 0; i < bytes.length; i += 713) {
      segmenter.add(
        Uint8List.sublistView(
          bytes,
          i,
          i + 713 < bytes.length ? i + 713 : bytes.length,
        ),
      );
    }
    expect(chunks.length, 1);
    expect(chunks.first.isFinal, false);
    final header = ByteData.sublistView(chunks.first.wav);
    expect(String.fromCharCodes(chunks.first.wav.take(4)), 'RIFF');
    expect(header.getUint32(24, Endian.little), 16000);
    expect(header.getUint16(22, Endian.little), 1);
    expect(header.getUint32(40, Endian.little), chunks.first.wav.length - 44);
    segmenter.add(pcm(40, 0));
    expect(chunks.length, 2);
    expect(chunks.last.isFinal, true);
    expect(chunks.last.id, chunks.first.id);
  });

  test(
    'partial caption arrives without stopping microphone; final replaces it',
    () async {
      final mic = FakeMicrophone();
      var calls = 0;
      final service = LiveCaptionService(
        microphone: mic,
        transcribe: (_) async => ++calls == 1 ? '안녕' : '안녕하세요',
      );
      await service.start();
      mic.controller.add(pcm(130));
      await settle();
      expect(service.text, '안녕');
      expect(mic.stops, 0);
      mic.controller.add(pcm(40, 0));
      await settle();
      expect(service.text, '안녕하세요');
      expect(mic.starts, 1);
      expect(mic.stops, 0);
      await service.close();
    },
  );

  test(
    'clear ignores in-flight result without interrupting microphone',
    () async {
      final mic = FakeMicrophone();
      final response = Completer<String>();
      final service = LiveCaptionService(
        microphone: mic,
        transcribe: (_) => response.future,
      );
      await service.start();
      mic.controller.add(pcm(130));
      service.clear();
      response.complete('오래된 자막');
      await settle();
      expect(service.text, isEmpty);
      expect(service.listening, true);
      expect(mic.stops, 0);
      await service.close();
    },
  );

  test('pause discards delayed results and bounds server backlog', () async {
    final mic = FakeMicrophone();
    final response = Completer<String>();
    var calls = 0;
    final service = LiveCaptionService(
      microphone: mic,
      transcribe: (_) {
        calls++;
        return response.future;
      },
    );
    await service.start();
    for (var i = 0; i < 10; i++) {
      mic.controller.add(pcm(130));
      mic.controller.add(pcm(40, 0));
    }
    expect(calls, 1);
    expect(service.pendingCount, 2);
    await service.pause();
    response.complete('늦은 결과');
    await settle();
    expect(service.text, isEmpty);
    expect(service.pendingCount, 0);
    expect(service.listening, false);
    await service.close();
  });

  test('pause during permission does not resurrect recording', () async {
    final mic = FakeMicrophone()..permission = Completer<void>();
    final service = LiveCaptionService(
      microphone: mic,
      transcribe: (_) async => '',
    );
    final start = service.start();
    final duplicate = service.start();
    final stop = service.pause();
    mic.permission!.complete();
    await Future.wait([start, duplicate, stop]);
    expect(mic.starts, 1);
    expect(service.listening, false);
    expect(service.enabled, false);
    await service.close();
  });

  test(
    'server error keeps microphone open and throttles retry requests',
    () async {
      final mic = FakeMicrophone();
      var calls = 0;
      final service = LiveCaptionService(
        microphone: mic,
        transcribe: (_) async {
          calls++;
          throw StateError('offline');
        },
      );
      await service.start();
      mic.controller.add(pcm(130));
      await settle();
      mic.controller.add(pcm(400));
      expect(calls, 1);
      expect(service.status, contains('자동 재시도'));
      expect(service.serverError, true);
      expect(service.listening, true);
      await service.close();
    },
  );
}
