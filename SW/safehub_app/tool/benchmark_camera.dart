import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../lib/services/camera_stream_service.dart';

// Loopback transport only: this does not measure a camera, renderer, or Pi.
Future<void> main(List<String> args) async {
  final frameCount = args.isEmpty ? 120 : int.parse(args.first);
  if (frameCount < 20 || frameCount > 10000) {
    throw ArgumentError('Use 20..10000 measured frames.');
  }
  final service = CameraStreamService();
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final packet = Uint8List(320 * 240 * 4 + 4);
  ByteData.sublistView(packet).setUint32(0, packet.length - 4, Endian.big);
  packet.fillRange(4, packet.length, 127);
  final finished = Completer<void>();
  final watch = Stopwatch();
  final samples = <int>[];
  const warmupFrames = 20;
  var delivered = 0;
  var receivedBytes = 0;
  var baselineRss = 0;
  Socket? peer;
  final subscription = server.listen((socket) {
    peer = socket;
    socket.listen((_) {}, onError: finished.completeError);
    watch.start();
    socket.add(packet);
  });
  try {
    await service.connect(
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      onFrame: (frame) {
        if (frame.length != packet.length - 4 || frame.first != 127) {
          finished.completeError(StateError('Invalid benchmark frame'));
          return;
        }
        delivered++;
        if (delivered > warmupFrames) {
          samples.add(watch.elapsedMicroseconds);
          receivedBytes += frame.length;
        }
        if (delivered == warmupFrames) baselineRss = ProcessInfo.currentRss;
        if (samples.length == frameCount) {
          finished.complete();
          return;
        }
        watch.reset();
        peer!.add(packet);
      },
      onConnectionChanged: (_) {},
    );
    await finished.future.timeout(const Duration(minutes: 3));
    samples.sort();
    final totalMicros = samples.fold<int>(0, (sum, value) => sum + value);
    stdout.writeln(
      jsonEncode({
        'kind': 'loopback_rgba_transport',
        'hardware_tested': false,
        'frame_bytes': packet.length - 4,
        'warmup_frames': warmupFrames,
        'measured_frames': samples.length,
        'received_bytes': receivedBytes,
        'median_ms': samples[samples.length ~/ 2] / 1000,
        'p95_ms': samples[(samples.length * .95).floor()] / 1000,
        'mean_ms': totalMicros / samples.length / 1000,
        'rss_after_warmup_bytes': baselineRss,
        'rss_end_bytes': ProcessInfo.currentRss,
        'peak_rss_bytes': ProcessInfo.maxRss,
        'dart_version': Platform.version.split(' ').first,
        'os': Platform.operatingSystem,
      }),
    );
  } finally {
    await service.dispose();
    peer?.destroy();
    await subscription.cancel();
    await server.close();
  }
}
