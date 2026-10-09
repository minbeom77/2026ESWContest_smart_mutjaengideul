import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safehub_app/services/audio_service.dart';

class _Player extends Fake implements AudioPlayer {
  Future<void> Function() stopping = () async {};
  Future<void> Function(Source) playing = (_) async {};
  Future<void> Function() disposing = () async {};
  int stops = 0;
  final sources = <Source>[];

  @override
  Future<void> stop() {
    stops++;
    return stopping();
  }

  @override
  Future<void> dispose() => disposing();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #play) {
      final source = invocation.positionalArguments.single as Source;
      sources.add(source);
      return playing(source);
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  late _Player player;
  late AudioService audio;
  setUp(() {
    player = _Player();
    audio = AudioService(
      player: player,
      operationTimeout: const Duration(milliseconds: 20),
    );
  });

  test('stops the previous source before playing bytes', () async {
    await audio.playBytes(Uint8List.fromList([1, 2]), mimeType: 'audio/wav');
    expect(player.stops, 1);
    expect(player.sources.single, isA<BytesSource>());
    final source = player.sources.single as BytesSource;
    expect(source.bytes, [1, 2]);
    expect(source.mimeType, 'audio/wav');
  });

  test('no stop response times out before a new source is played', () async {
    player.stopping = () => Completer<void>().future;
    await expectLater(
      audio.playBytes(Uint8List(2)),
      throwsA(isA<TimeoutException>()),
    );
    expect(player.sources, isEmpty);
  });

  test('no play response times out for byte and URL sources', () async {
    player.playing = (_) => Completer<void>().future;
    await expectLater(
      audio.playBytes(Uint8List(2)),
      throwsA(isA<TimeoutException>()),
    );
    await expectLater(
      audio.playUrl('http://localhost/voice.wav'),
      throwsA(isA<TimeoutException>()),
    );
    expect(player.sources, hasLength(2));
  });

  test(
    'play failure reaches the caller instead of reporting success',
    () async {
      player.playing = (_) => Future<void>.error(StateError('load failed'));
      await expectLater(audio.playBytes(Uint8List(2)), throwsStateError);
    },
  );

  test('stop and dispose waits are also bounded', () async {
    player.stopping = () => Completer<void>().future;
    player.disposing = () => Completer<void>().future;
    await expectLater(audio.stop(), throwsA(isA<TimeoutException>()));
    await expectLater(audio.dispose(), throwsA(isA<TimeoutException>()));
  });

  test('empty URL does not call the native player', () async {
    await audio.playUrl('  ');
    expect(player.stops, 0);
    expect(player.sources, isEmpty);
  });

  test(
    'unused audio stops and disposes without creating a native player',
    () async {
      final unused = AudioService();
      await unused.stop();
      await unused.dispose();
      await unused.dispose();
      await expectLater(unused.playBytes(Uint8List(2)), throwsStateError);
    },
  );
}
