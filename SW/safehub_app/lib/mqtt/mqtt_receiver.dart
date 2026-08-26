import 'dart:convert';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../core/event_manager.dart';

class MqttReceiver {
  final String broker;
  final int port;
  final EventManager eventManager;
  final void Function(Map<String, dynamic> event)? onEventReceived;

  late final MqttServerClient _client;

MqttReceiver({
  required this.broker,
  required this.port,
  required this.eventManager,
  this.onEventReceived,
});

  Future<void> connect() async {
    _client = MqttServerClient.withPort(
      broker,
      'safehub_rpi5',
      port,
    );

    _client.keepAlivePeriod = 20;

    _client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier('safehub_rpi5')
        .startClean();

    try {
      await _client.connect();
    } catch (e) {
      _client.disconnect();
      rethrow;
    }

    if (_client.connectionStatus?.state != MqttConnectionState.connected) {
      _client.disconnect();
      throw Exception('MQTT 브로커 연결 실패');
    }

    _client.subscribe(
      'safehub/csi/bedroom/event',
      MqttQos.atLeastOnce,
    );

    _client.subscribe(
      'safehub/csi/bathroom/event',
      MqttQos.atLeastOnce,
    );

    _client.updates?.listen(_onMessage);
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage?>> messages) {
    final message = messages.first.payload as MqttPublishMessage;

    final payload = MqttPublishPayload.bytesToStringAsString(
      message.payload.message,
    );

    try {
      final decoded = jsonDecode(payload);

      if (decoded is Map<String, dynamic>) {
        // EventManager에 이벤트 등록
        eventManager.addEvent(decoded);

        // UI 등에 수신 사실 전달
        onEventReceived?.call(decoded);
      }
    } catch (e) {
      print('MQTT 메시지 처리 실패: $e');
    }
  }

  void disconnect() {
    _client.disconnect();
  }
}