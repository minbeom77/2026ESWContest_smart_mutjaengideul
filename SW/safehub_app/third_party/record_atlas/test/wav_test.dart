import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:record_atlas/record_atlas.dart';
import 'package:record_platform_interface/record_platform_interface.dart';

class PendingRecorder implements Process {
  final exited = Completer<int>();
  final killed = Completer<void>();

  @override
  Stream<List<int>> get stdout => const Stream.empty();
  @override
  Stream<List<int>> get stderr => const Stream.empty();
  @override
  Future<int> get exitCode => exited.future;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!killed.isCompleted) killed.complete();
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('live PCM uses one raw recorder with no encoding process', () async {
    final process = PendingRecorder();
    var starts = 0;
    final recorder = RecordAtlas(startProcess: (executable, args) async {
      starts++;
      expect(executable, endsWith('/parecord'));
      expect(args, containsAll(['--raw', '--format=s16le', '--rate=16000', '--channels=1']));
      expect(args.where((arg) => arg.startsWith('--file-format')), isEmpty);
      return process;
    });
    final stream = await recorder.startStream('live', const RecordConfig(
      encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1,
    ));
    await stream.drain<void>();
    expect(starts, 1);
    final stopping = recorder.cancel('live');
    await process.killed.future;
    process.exited.complete(0);
    await stopping;
    expect(await recorder.isRecording('live'), isFalse);
    await recorder.dispose('live');
  });

  test('WAV starts one recorder and waits for its file to finish', () async {
    final directory = await Directory.systemTemp.createTemp('atlas-wav-test-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/record.wav';
    final process = PendingRecorder();
    var starts = 0;
    final recorder = RecordAtlas(startProcess: (executable, args) async {
      starts++;
      expect(executable, endsWith('/parecord'));
      expect(args, contains('--file-format=wav'));
      expect(args, contains('--rate=16000'));
      expect(args, contains('--channels=1'));
      expect(args, isNot(contains('--raw')));
      expect(args.last, path);
      return process;
    });
    await recorder.start('test', const RecordConfig(
      encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1,
    ), path: path);
    expect(starts, 1);
    expect(await recorder.isRecording('test'), isTrue);
    var stopped = false;
    final pending = recorder.stop('test').then((value) {
      stopped = true;
      return value;
    });
    await process.killed.future;
    expect(stopped, isFalse);
    process.exited.complete(0);
    expect(await pending, path);
    expect(await recorder.isRecording('test'), isFalse);
    await recorder.dispose('test');
  });
}
