import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:safehub_app/services/voice_recorder_service.dart';

class FakeRecorderBackend implements VoiceRecorderBackend {
  Completer<bool>? permissionGate;
  Completer<void>? startGate;
  Completer<void>? startEntered;
  int startCalls = 0;
  int disposeCalls = 0;
  bool failStop = false;
  String? stopPathOverride;
  bool permission = true;
  bool wavSupported = true;
  bool recording = false;
  bool disposed = false;
  String? recordedPath;
  List<int> outputBytes = [82, 73, 70, 70];

  @override
  Future<bool> hasPermission() async =>
      permissionGate == null ? permission : permissionGate!.future;

  @override
  Future<bool> supportsWav() async => wavSupported;

  @override
  Future<bool> isRecording() async => recording;

  @override
  Future<void> start(String path) async {
    startCalls++;
    recordedPath = path;
    startEntered?.complete();
    await startGate?.future;
    recording = true;
  }

  @override
  Future<String?> stop() async {
    if (failStop) throw StateError('test stop failure');
    if (stopPathOverride != null) return stopPathOverride;
    final path = recordedPath;
    recording = false;

    if (path != null) {
      await File(path).writeAsBytes(outputBytes);
    }

    return path;
  }

  @override
  Future<void> cancel() async {
    recording = false;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    disposed = true;
  }
}

void main() {
  late Directory temporaryDirectory;
  late FakeRecorderBackend backend;
  late VoiceRecorderService service;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'safehub_recorder_test_',
    );

    backend = FakeRecorderBackend();

    service = VoiceRecorderService(
      backend: backend,
      directoryProvider: () async => temporaryDirectory,
    );
  });

  tearDown(() async {
    await service.dispose();

    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('WAV 녹음을 시작하고 파일 경로를 생성한다', () async {
    final path = await service.start();

    expect(path, endsWith('.wav'));
    expect(path, contains(temporaryDirectory.path));
    expect(backend.recording, true);
    expect(backend.recordedPath, path);
  });

  test('마이크 권한이 없으면 녹음을 시작하지 않는다', () async {
    backend.permission = false;

    await expectLater(service.start(), throwsStateError);

    expect(backend.recording, false);
  });

  test('WAV를 지원하지 않으면 녹음을 시작하지 않는다', () async {
    backend.wavSupported = false;

    await expectLater(service.start(), throwsStateError);

    expect(backend.recording, false);
  });

  test('이미 녹음 중이면 중복 시작을 거부한다', () async {
    await service.start();

    await expectLater(service.start(), throwsStateError);
  });

  test('녹음을 종료하고 WAV bytes를 반환한다', () async {
    await service.start();

    final bytes = await service.stopAndRead();

    expect(bytes, backend.outputBytes);
    expect(backend.recording, false);
  });

  test('녹음 중이 아니면 종료를 거부한다', () async {
    await expectLater(service.stopAndRead(), throwsStateError);
  });

  test('빈 녹음 파일은 거부한다', () async {
    backend.outputBytes = [];
    await service.start();

    await expectLater(service.stopAndRead(), throwsStateError);
  });

  test('취소하면 녹음 상태가 종료된다', () async {
    await service.start();
    await service.cancel();

    expect(await service.isRecording, false);
  });

  test('dispose가 녹음 backend를 정리한다', () async {
    await service.dispose();

    expect(backend.disposed, true);
  });

  test('권한 확인 중 반복 시작을 거부한다', () async {
    backend.permissionGate = Completer<bool>();
    final first = service.start();
    final second = service.start();
    final rejected = expectLater(second, throwsStateError);
    backend.permissionGate!.complete(true);
    await first;
    await rejected;
    expect(backend.startCalls, 1);
  });

  test('권한 확인 중 dispose하면 늦게 완료된 시작이 녹음하지 않는다', () async {
    backend.permissionGate = Completer<bool>();
    final starting = service.start();
    final rejected = expectLater(starting, throwsStateError);
    final closing = service.dispose();
    backend.permissionGate!.complete(true);
    await rejected;
    await closing;
    expect(backend.startCalls, 0);
    expect(backend.disposed, isTrue);
  });

  test('읽은 임시 녹음만 삭제하고 기존 파일은 보존한다', () async {
    final existing = File('${temporaryDirectory.path}/existing.wav');
    await existing.writeAsBytes([1, 2, 3]);
    final path = await service.start();
    expect(await service.stopAndRead(), backend.outputBytes);
    expect(await File(path).exists(), isFalse);
    expect(await existing.readAsBytes(), [1, 2, 3]);
  });

  test('native start가 dispose 뒤 완료되어도 취소하고 임시 파일을 정리한다', () async {
    backend.startGate = Completer<void>();
    backend.startEntered = Completer<void>();
    final starting = service.start();
    final rejected = expectLater(starting, throwsStateError);
    await backend.startEntered!.future;
    final file = File(backend.recordedPath!);
    await file.writeAsBytes([1, 2]);
    final closing = service.dispose();
    backend.startGate!.complete();
    await rejected;
    await closing;
    await service.dispose();
    expect(backend.recording, isFalse);
    expect(backend.disposeCalls, 1);
    expect(await file.exists(), isFalse);
  });

  test('시작 준비 중 취소한 뒤 새 녹음을 시작할 수 있다', () async {
    backend.permissionGate = Completer<bool>();
    final starting = service.start();
    final rejected = expectLater(starting, throwsStateError);
    final cancelling = service.cancel();
    backend.permissionGate!.complete(true);
    await rejected;
    await cancelling;
    await service.start();
    expect(backend.recording, isTrue);
    expect(backend.startCalls, 1);
  });

  test('취소와 dispose가 각자 생성한 임시 파일만 삭제한다', () async {
    final existing = File('${temporaryDirectory.path}/keep.wav');
    await existing.writeAsBytes([9]);
    final first = File(await service.start());
    await first.writeAsBytes([1]);
    await service.cancel();
    expect(await first.exists(), isFalse);
    final second = File(await service.start());
    await second.writeAsBytes([2]);
    await service.dispose();
    expect(await second.exists(), isFalse);
    expect(await existing.readAsBytes(), [9]);
    expect(backend.recording, isFalse);
  });

  test('backend 종료 실패에도 녹음을 취소하고 임시 파일을 정리한다', () async {
    final file = File(await service.start());
    await file.writeAsBytes([1]);
    backend.failStop = true;
    await expectLater(service.stopAndRead(), throwsStateError);
    expect(backend.recording, isFalse);
    expect(await file.exists(), isFalse);
  });

  test('backend가 다른 파일을 반환해도 읽거나 삭제하지 않는다', () async {
    final existing = File('${temporaryDirectory.path}/foreign.wav');
    await existing.writeAsBytes([7, 8]);
    await service.start();
    backend.stopPathOverride = existing.path;
    await expectLater(service.stopAndRead(), throwsStateError);
    expect(await existing.readAsBytes(), [7, 8]);
    expect(backend.recording, isFalse);
  });

  test('dispose 뒤에는 새 녹음을 요청할 수 없다', () async {
    await service.dispose();
    await expectLater(service.start(), throwsStateError);
    await expectLater(service.stopAndRead(), throwsStateError);
    expect(await service.isRecording, isFalse);
    expect(backend.startCalls, 0);
  });
}
