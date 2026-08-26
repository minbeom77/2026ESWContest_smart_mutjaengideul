import 'dart:convert';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../core/event_manager.dart';

class MqttReceiver {
  final String broker;
  final int port;
  final EventManager eventManager;

  // CSI 안전 이벤트 수신 콜백
  final void Function(Map<String, dynamic> event)? onEventReceived;

  // 수어 번역 결과 수신 콜백
  final void Function(String text)? onSignTextReceived;

  late final MqttServerClient _client;

  MqttReceiver({
    required this.broker,
    required this.port,
    required this.eventManager,
    this.onEventReceived,
    this.onSignTextReceived,
  });

  Future<void> connect() async {
    _client = MqttServerClient.withPort(
      broker,
      'safehub_rpi5',
      port,
    );

    _client.keepAlivePeriod = 20;

    _client.connectionMessage =
        MqttConnectMessage().withClientIdentifier('safehub_rpi5').startClean();

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

    // 침실 CSI 이벤트
    _client.subscribe(
      'safehub/csi/bedroom/event',
      MqttQos.atLeastOnce,
    );

    // 화장실 CSI 이벤트
    _client.subscribe(
      'safehub/csi/bathroom/event',
      MqttQos.atLeastOnce,
    );

    // 수어 번역 결과
    _client.subscribe(
      'safehub/vision/livingroom/translation',
      MqttQos.atMostOnce,
    );

    _client.updates?.listen(_onMessage);
  }

  void _onMessage(
    List<MqttReceivedMessage<MqttMessage?>> messages,
  ) {
    final receivedMessage = messages.first;
    final message = receivedMessage.payload as MqttPublishMessage;

    final topic = receivedMessage.topic;

    final payload = MqttPublishPayload.bytesToStringAsString(
      message.payload.message,
    );

    try {
      final decoded = jsonDecode(payload);

      // 수어 번역 결과 처리
      if (topic == 'safehub/vision/livingroom/translation') {
        if (decoded is Map<String, dynamic>) {
          final text = decoded['text'];

          if (text is String && text.isNotEmpty) {
            onSignTextReceived?.call(text);
          }
        }

        return;
      }

      // CSI 안전 이벤트 처리
      if (decoded is Map<String, dynamic>) {
        final event = Map<String, dynamic>.from(decoded);

        // MQTT 토픽을 기반으로 실제 위치 지정
        if (topic == 'safehub/csi/bedroom/event') {
          event['location'] = 'bedroom';
        } else if (topic == 'safehub/csi/bathroom/event') {
          event['location'] = 'bathroom';
        } else {
          return;
        }

        // 안전 이벤트만 EventManager에 등록
        eventManager.addEvent(event);

        // GUI에 이벤트 전달
        onEventReceived?.call(event);
      }
    } catch (e) {
      print('MQTT 메시지 처리 실패: $e');
    }
  }

  void disconnect() {
    _client.disconnect();
  }
}
