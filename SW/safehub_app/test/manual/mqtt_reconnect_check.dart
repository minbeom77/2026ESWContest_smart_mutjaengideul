import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:safehub_app/core/event_manager.dart';
import 'package:safehub_app/mqtt/mqtt_receiver.dart';

void main() {
  test('브로커 재시작 후 자동 재연결 및 수어·CSI 재수신', () async {
    final directory = await Directory.systemTemp.createTemp('safehub-mqtt-');
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();

    final config = File('${directory.path}/mosquitto.conf');
    await config.writeAsString(
      'listener $port 127.0.0.1\n'
      'allow_anonymous true\n'
      'persistence false\n',
    );

    Process? broker;
    MqttReceiver? receiver;
    var connectStarted = false;
    final connections = <bool>[];
    final signs = <String>[];
    final events = <Map<String, dynamic>>[];

    Future<void> waitFor(bool Function() ready, String label) async {
      final watch = Stopwatch()..start();
      while (!ready()) {
        if (watch.elapsed > const Duration(seconds: 45)) {
          fail('$label 시간 초과: connections=$connections '
              'signs=$signs events=$events');
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    Future<ProcessResult> publish(String topic, String payload) {
      return Process.run('mosquitto_pub', [
        '-h', '127.0.0.1', '-p', '$port',
        '-t', topic, '-m', payload, '-q', '1',
      ]);
    }

    Future<void> startBroker() async {
      final process = await Process.start('mosquitto', ['-c', config.path]);
      broker = process;
      process.stdout.drain<void>();
      process.stderr.drain<void>();

      final watch = Stopwatch()..start();
      while (true) {
        final result = await publish('safehub/test/probe', 'ready');
        if (result.exitCode == 0) return;
        if (watch.elapsed > const Duration(seconds: 10)) {
          fail('테스트 브로커 시작 실패: ${result.stderr}');
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    Future<void> stopBroker() async {
      final process = broker;
      if (process == null) return;
      process.kill(ProcessSignal.sigterm);
      await process.exitCode.timeout(const Duration(seconds: 5));
      broker = null;
    }

    Future<void> checkReception(String phase) async {
      // 실제 수어 수신으로 재구독 완료를 확인한다.
      final watch = Stopwatch()..start();
      while (!signs.contains(phase)) {
        final result = await publish(
          'safehub/vision/livingroom/translation',
          jsonEncode({'text': phase}),
        );
        expect(result.exitCode, 0, reason: '${result.stderr}');
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (watch.elapsed > const Duration(seconds: 15)) {
          fail('$phase 수어 수신 실패');
        }
      }

      final result = await publish(
        'safehub/csi/bedroom/event',
        jsonEncode({
          'message_id': phase,
          'device': 'test_csi',
          'event': 'fall_detected',
          'confidence': 0.92,
          'priority': 9,
          'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        }),
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      await waitFor(
        () => events.any((event) => event['message_id'] == phase),
        '$phase CSI 수신',
      );
    }

    try {
      await startBroker();
      receiver = MqttReceiver(
        broker: '127.0.0.1',
        port: port,
        eventManager: EventManager(),
        onConnectionChanged: connections.add,
        onSignTextReceived: signs.add,
        onEventReceived: events.add,
      );
      connectStarted = true;
      await receiver.connect();
      await checkReception('before-restart');

      connections.clear();
      await stopBroker();
      await waitFor(() => connections.contains(false), '연결 끊김 감지');

      await startBroker();
      await waitFor(
        () => connections.contains(true),
        '자동 재연결',
      );
      await checkReception('after-restart');

      expect(
        events.map((event) => event['message_id']).toList(),
        ['before-restart', 'after-restart'],
      );
      print('[CHECK] 브로커 재시작 후 수어·CSI 재수신 통과');
    } finally {
      if (connectStarted) receiver?.disconnect();
      await stopBroker();
      await directory.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(seconds: 150)));
}
