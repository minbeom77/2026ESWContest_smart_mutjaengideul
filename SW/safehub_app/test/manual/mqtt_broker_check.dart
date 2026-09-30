import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:safehub_app/core/event_manager.dart';
import 'package:safehub_app/mqtt/mqtt_receiver.dart';

void main() {
  test('실제 브로커에서 수어·CSI 수신 및 중복 방지', () async {
    final manager = EventManager();
    final events = <Map<String, dynamic>>[];
    final signs = <String>[];
    final receiver = MqttReceiver(
      broker: '127.0.0.1',
      port: 18883,
      eventManager: manager,
      onEventReceived: events.add,
      onSignTextReceived: signs.add,
    );

    Future<void> publish(String topic, String payload) async {
      final result = await Process.run('mosquitto_pub', [
        '-h', '127.0.0.1', '-p', '18883',
        '-t', topic, '-m', payload, '-q', '1',
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    }

    Future<void> waitFor(bool Function() ready) async {
      final watch = Stopwatch()..start();
      while (!ready()) {
        if (watch.elapsed > const Duration(seconds: 10)) {
          fail('수신 시간 초과: events=$events signs=$signs');
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }

    await receiver.connect();
    try {
      // SUBACK 처리를 위한 초기 대기. 메시지가 안 오면 테스트는 실패한다.
      await Future<void>.delayed(const Duration(milliseconds: 500));

      const topic = 'safehub/csi/bedroom/event';
      final id = 'broker-test-${DateTime.now().microsecondsSinceEpoch}';
      String event(String messageId) => jsonEncode({
        'message_id': messageId,
        'device': 'test_csi',
        'event': 'fall_detected',
        'confidence': 0.92,
        'priority': 9,
        'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      });

      await publish(topic, event(id));
      await waitFor(() => events.length == 1);
      await publish(topic, event(id));
      await publish(topic, '{broken');
      await publish(topic, event('$id-next'));

      await publish(
        'safehub/vision/livingroom/translation',
        jsonEncode({'text': '아프다'}),
      );
      await waitFor(() => events.length >= 2 && signs.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(events, hasLength(2));
      expect(signs, ['아프다']);
      expect(manager.getNextEvent()?['message_id'], id);
      expect(manager.getNextEvent()?['message_id'], '$id-next');
      expect(manager.getNextEvent(), isNull);
    } finally {
      receiver.disconnect();
    }
  }, timeout: const Timeout(Duration(seconds: 30)));
}
