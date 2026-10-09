import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:safehub_app/services/camera_stream_service.dart';

class CameraPeer {
  final ServerSocket server;
  final arrivals = StreamController<Socket>.broadcast();
  final sockets = <Socket>[];
  late final StreamSubscription<Socket> subscription;

  CameraPeer._(this.server) {
    subscription = server.listen((socket) {
      sockets.add(socket);
      socket.listen((_) {}, onError: (Object _) {});
      arrivals.add(socket);
    });
  }

  static Future<CameraPeer> open({int port = 0}) async =>
      CameraPeer._(await ServerSocket.bind(InternetAddress.loopbackIPv4, port));

  Future<void> close() async {
    for (final socket in sockets) {
      socket.destroy();
    }
    await subscription.cancel();
    await server.close();
    await arrivals.close();
  }
}

Future<void> until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Camera state did not settle');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Uint8List packet(List<int> frame) {
  final bytes = Uint8List(frame.length + 4);
  ByteData.sublistView(bytes).setUint32(0, frame.length, Endian.big);
  bytes.setRange(4, bytes.length, frame);
  return bytes;
}

void main() {
  test('TCP connection alone does not report a working camera', () async {
    final peer = await CameraPeer.open();
    final service = CameraStreamService();
    addTearDown(peer.close);
    addTearDown(service.dispose);
    final states = <bool>[];
    final accepted = peer.arrivals.stream.first;
    await service.connect(
      host: InternetAddress.loopbackIPv4.address,
      port: peer.server.port,
      onFrame: (_) {},
      onConnectionChanged: states.add,
    );
    await accepted;
    expect(states, isNot(contains(true)));
  });

  test(
    'fragmented and coalesced RGBA packets retain exact frame bytes',
    () async {
      final peer = await CameraPeer.open();
      final service = CameraStreamService();
      addTearDown(peer.close);
      addTearDown(service.dispose);
      final frames = <Uint8List>[];
      final states = <bool>[];
      final accepted = peer.arrivals.stream.first;
      await service.connect(
        host: InternetAddress.loopbackIPv4.address,
        port: peer.server.port,
        onFrame: frames.add,
        onConnectionChanged: states.add,
      );
      final socket = await accepted;
      final first = Uint8List.fromList(
        List.generate(320 * 240 * 4, (index) => index % 251),
      );
      final second = Uint8List(320 * 240 * 4)..fillRange(0, 320 * 240 * 4, 17);
      final third = Uint8List(320 * 240 * 4)..fillRange(0, 320 * 240 * 4, 231);
      final firstPacket = packet(first);
      socket.add(firstPacket.sublist(0, 2));
      await socket.flush();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(frames, isEmpty);
      socket.add(firstPacket.sublist(2, 51));
      await socket.flush();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(frames, isEmpty);
      socket.add(firstPacket.sublist(51));
      socket.add(Uint8List.fromList([...packet(second), ...packet(third)]));
      await socket.flush();
      await until(() => frames.length == 3);
      expect(frames[0], orderedEquals(first));
      expect(frames[1], orderedEquals(second));
      expect(frames[2], orderedEquals(third));
      expect(states, [true]);
    },
  );

  test('wrong frame length disconnects and a new stream can recover', () async {
    final peer = await CameraPeer.open();
    final service = CameraStreamService(
      frameByteLength: 16,
      watchdogInterval: const Duration(milliseconds: 25),
    );
    addTearDown(peer.close);
    addTearDown(service.dispose);
    final frames = <Uint8List>[];
    final states = <bool>[];
    final accepted = peer.arrivals.stream.first;
    await service.connect(
      host: InternetAddress.loopbackIPv4.address,
      port: peer.server.port,
      onFrame: frames.add,
      onConnectionChanged: states.add,
    );
    final socket = await accepted;
    socket.add(packet(List.filled(16, 1)));
    await socket.flush();
    await until(() => frames.length == 1);
    final reconnected = peer.arrivals.stream.first;
    socket.add(packet(List.filled(8, 2)));
    await socket.flush();
    await until(() => states.contains(false));
    final next = await reconnected.timeout(const Duration(seconds: 3));
    next.add(packet(List.filled(16, 3)));
    await next.flush();
    await until(() => frames.length == 2);
    expect(states, [true, false, true]);
    expect(frames.last, everyElement(3));
  });

  test(
    'partial packet traffic cannot keep the last camera frame live',
    () async {
      final peer = await CameraPeer.open();
      final service = CameraStreamService(
        frameByteLength: 1000,
        watchdogInterval: const Duration(milliseconds: 25),
        frameTimeout: const Duration(milliseconds: 180),
      );
      addTearDown(peer.close);
      addTearDown(service.dispose);
      final states = <bool>[];
      final accepted = peer.arrivals.stream.first;
      await service.connect(
        host: InternetAddress.loopbackIPv4.address,
        port: peer.server.port,
        onFrame: (_) {},
        onConnectionChanged: states.add,
      );
      final socket = await accepted;
      socket.add(packet(List.filled(1000, 1)));
      await socket.flush();
      await until(() => states.contains(true));
      socket.add(packet(List.filled(1000, 2)).sublist(0, 4));
      await socket.flush();
      for (var i = 0; i < 15 && !states.contains(false); i++) {
        socket.add([2]);
        await socket.flush();
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      expect(states, contains(false));
    },
  );

  test('initial refusal retries once the camera server starts', () async {
    final reservation = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final port = reservation.port;
    await reservation.close();
    final service = CameraStreamService(
      frameByteLength: 16,
      watchdogInterval: const Duration(milliseconds: 25),
    );
    addTearDown(service.dispose);
    final states = <bool>[];
    await service.connect(
      host: InternetAddress.loopbackIPv4.address,
      port: port,
      onFrame: (_) {},
      onConnectionChanged: states.add,
    );
    expect(states, isNot(contains(true)));
    final peer = await CameraPeer.open(port: port);
    addTearDown(peer.close);
    final socket = await peer.arrivals.stream.first.timeout(
      const Duration(seconds: 3),
    );
    socket.add(packet(List.filled(16, 7)));
    await socket.flush();
    await until(() => states.contains(true));
    expect(states, [true]);
  });

  test('disposed service cannot deliver or reconnect', () async {
    final peer = await CameraPeer.open();
    final service = CameraStreamService(
      watchdogInterval: const Duration(milliseconds: 20),
    );
    addTearDown(peer.close);
    final states = <bool>[];
    final accepted = peer.arrivals.stream.first;
    await service.connect(
      host: InternetAddress.loopbackIPv4.address,
      port: peer.server.port,
      onFrame: (_) => fail('Disposed camera delivered a frame'),
      onConnectionChanged: states.add,
    );
    await accepted;
    await service.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(states, isEmpty);
    expect(peer.sockets, hasLength(1));
  });
}
