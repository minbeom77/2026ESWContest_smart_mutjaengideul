import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:safehub_app/services/caption_connection.dart';
import 'package:safehub_app/services/live_caption_service.dart';

import 'live_caption_service_test.dart' show FakeMicrophone, pcm, settle;

class FakeConnection implements CaptionConnection {
  final controller = StreamController<CaptionResult>.broadcast(sync: true);
  int received = 0;
  int epoch = 0;
  bool closed = false;
  @override
  Stream<CaptionResult> get results => controller.stream;
  @override
  void add(Uint8List bytes) => received += bytes.length;
  @override
  void reset(int value) => epoch = value;
  @override
  Future<void> close() async {
    closed = true;
    await controller.close();
  }
}

void main() {
  test(
    'streams immediately and revises the same line without file requests',
    () async {
      final mic = FakeMicrophone();
      final connection = FakeConnection();
      final service = LiveCaptionService(
        microphone: mic,
        connectStream: () async => connection,
        transcribe: (_) => throw StateError('File API must not be called'),
      );
      await service.start();
      mic.controller.add(pcm(5)); // 100 ms, not the batch 2.4-second threshold.
      expect(connection.received, 3200);
      connection.controller.add(const CaptionResult(0, '안녕', false, 0));
      expect(service.text, '안녕');
      connection.controller.add(const CaptionResult(0, '안녕하세요', true, 0));
      expect(service.text, '안녕하세요');
      expect(mic.stops, 0);
      service.clear();
      connection.controller.add(const CaptionResult(0, '지난 문장', true, 0));
      expect(service.text, isEmpty);
      connection.controller.add(
        CaptionResult(1, '새 문장', false, connection.epoch),
      );
      expect(service.text, '새 문장');
      await service.close();
      expect(connection.closed, true);
    },
  );

  test(
    'pause during streaming handshake closes late connection and leaves mic off',
    () async {
      final mic = FakeMicrophone();
      final connection = FakeConnection();
      final handshake = Completer<CaptionConnection?>();
      final service = LiveCaptionService(
        microphone: mic,
        connectStream: () => handshake.future,
        transcribe: (_) async => '',
      );
      final starting = service.start();
      final stopping = service.pause();
      handshake.complete(connection);
      await starting;
      await stopping;
      expect(mic.starts, 0);
      expect(connection.closed, true);
      expect(service.enabled, false);
      await service.close();
    },
  );

  test(
    'disconnect releases microphone and pause cancels scheduled recovery',
    () async {
      final mic = FakeMicrophone();
      final connection = FakeConnection();
      var connections = 0;
      final service = LiveCaptionService(
        microphone: mic,
        connectStream: () async {
          connections++;
          return connection;
        },
        transcribe: (_) async => '',
      );
      await service.start();
      connection.controller.addError(StateError('Disconnected'));
      await settle();
      await settle();
      expect(service.serverError, true);
      expect(service.listening, false);
      expect(connection.closed, true);
      await service.pause();
      await Future<void>.delayed(const Duration(milliseconds: 2100));
      expect(connections, 1);
      expect(service.enabled, false);
      await service.close();
    },
  );

  test('odd microphone chunks remain sample aligned', () async {
    final mic = FakeMicrophone();
    final connection = FakeConnection();
    final service = LiveCaptionService(
      microphone: mic,
      connectStream: () async => connection,
      transcribe: (_) async => '',
    );
    await service.start();
    mic.controller.add(Uint8List(641));
    expect(connection.received, 640);
    mic.controller.add(Uint8List(639));
    expect(connection.received, 1280);
    await service.close();
  });
}
