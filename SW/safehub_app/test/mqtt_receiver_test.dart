import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:safehub_app/core/event_manager.dart';
import 'package:safehub_app/mqtt/mqtt_receiver.dart';

void main() {
  const topic = 'safehub/csi/bedroom/event';
  late EventManager manager;
  late MqttReceiver receiver;
  late List<Map<String, dynamic>> notifications;

  setUp(() {
    manager = EventManager();
    notifications = [];
    receiver = MqttReceiver(
      broker: 'localhost',
      port: 1883,
      eventManager: manager,
      onEventReceived: notifications.add,
    );
  });

  void send(Object? id) {
    receiver.handlePayload(
      topic,
      jsonEncode({
        'message_id': id,
        'device': 'csi_bedroom',
        'event': 'fall_detected',
        'confidence': 0.92,
        'priority': 9,
        'timestamp': 1790740000,
      }),
    );
  }

  test('같은 ID 재전송은 큐와 알림에 한 번만 전달한다', () {
    send('incident-1');
    send('incident-1');
    expect(manager.getNextEvent()?['message_id'], 'incident-1');
    expect(manager.getNextEvent(), isNull);
    expect(notifications, hasLength(1));
  });

  test('서로 다른 ID는 각각 전달한다', () {
    send('incident-1');
    send('incident-2');
    expect(manager.getNextEvent()?['message_id'], 'incident-1');
    expect(manager.getNextEvent()?['message_id'], 'incident-2');
    expect(manager.getNextEvent(), isNull);
    expect(notifications, hasLength(2));
  });

  test('ID 없는 기존 메시지는 호환되며 중복 판별하지 않는다', () {
    final payload = jsonEncode({'event': 'fall_detected', 'priority': 9});
    receiver.handlePayload(topic, payload);
    receiver.handlePayload(topic, payload);
    expect(manager.getNextEvent()?['event'], 'fall_detected');
    expect(manager.getNextEvent()?['event'], 'fall_detected');
    expect(manager.getNextEvent(), isNull);
    expect(notifications, hasLength(2));
  });

  test('잘못된 ID와 JSON 이후에도 정상 메시지를 처리한다', () {
    send(123);
    send('');
    send('   ');
    receiver.handlePayload(topic, '{broken');
    send('valid-1');
    expect(manager.getNextEvent()?['message_id'], 'valid-1');
    expect(manager.getNextEvent(), isNull);
    expect(notifications, hasLength(1));
  });

  test('ID 앞뒤 공백을 제거한 뒤 중복을 판별한다', () {
    send(' incident-1 ');
    send('incident-1');
    expect(manager.getNextEvent()?['message_id'], 'incident-1');
    expect(manager.getNextEvent(), isNull);
    expect(notifications, hasLength(1));
  });
}
