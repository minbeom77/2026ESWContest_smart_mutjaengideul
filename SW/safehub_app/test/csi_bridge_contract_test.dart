import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:safehub_app/core/event_manager.dart';
import 'package:safehub_app/mqtt/mqtt_receiver.dart';

void main() {
  // Run the Python exporter before this test. No broker or sensor is used.
  final fixture = jsonDecode(
    File('test/fixtures/csi_bridge_contract.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  if (fixture['format_version'] != 1 ||
      fixture['cases'] is! List ||
      (fixture['cases'] as List).length != 4) {
    throw StateError('Generate the four CSI adapter cases before testing.');
  }

  for (final rawCase in fixture['cases'] as List) {
    final scenario = rawCase as Map<String, dynamic>;
    test('Python CSI adapter -> Flutter: ${scenario['name']}', () {
      final manager = EventManager();
      final notifications = <Map<String, dynamic>>[];
      final receiver = MqttReceiver(
        broker: 'localhost',
        port: 1883,
        eventManager: manager,
        onEventReceived: notifications.add,
      );
      final messages = scenario['messages'] as List;
      final expected = scenario['expected'] as List;
      expect(expected, hasLength(scenario['expected_count'] as int));

      for (final rawEnvelope in messages) {
        final envelope = rawEnvelope as Map<String, dynamic>;
        expect(envelope['qos'], 1);
        expect(envelope['retain'], false);
        expect(envelope['topic'], 'safehub/csi/${scenario['room']}/event');
        receiver.handlePayload(
          envelope['topic'] as String,
          jsonEncode(envelope['payload']),
        );
      }

      expect(notifications, hasLength(scenario['expected_count'] as int));
      for (var i = 0; i < expected.length; i++) {
        final envelope = expected[i] as Map<String, dynamic>;
        final payload = envelope['payload'] as Map<String, dynamic>;
        expect(payload['event'], 'fall_detected');
        expect(payload['priority'], 9);
        expect(payload['confidence'], 0.92);
        expect(payload['timestamp'], isA<int>());
        expect(payload['timestamp'], i == 0 ? 1800000000 : 1800000006);
        expect(payload['message_id'], matches(RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        )));
        final normalized = <String, dynamic>{
          ...payload,
          'location': scenario['room'],
        };
        expect(manager.getNextEvent(), equals(normalized));
        expect(notifications[i], equals(normalized));
      }
      expect(manager.getNextEvent(), isNull);
    });
  }
}
