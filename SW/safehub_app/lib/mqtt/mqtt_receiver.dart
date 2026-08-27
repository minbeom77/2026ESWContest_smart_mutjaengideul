import 'dart:convert';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../core/event_manager.dart';

class MqttReceiver {
  final String broker;
  final int port;
  final EventManager eventManager;

  // CSI 안전 이벤트 수신
  final void Function(Map<String, dynamic> event)? onEventReceived;

  // 수어 번역 결과 수신
  final void Function(String text)? onSignTextReceived;

  // MQTT 연결 상태 변경
  final void Function(bool connected)? onConnectionChanged;

  late final MqttServerClient _client;

  MqttReceiver({
    required this.broker,
    required this.port,
    required this.eventManager,
    this.onEventReceived,
    this.onSignTextReceived,
    this.onConnectionChanged,
  });

  Future<void> connect() async {
    _client = MqttServerClient.withPort(
      broker,
      'safehub_rpi5',
      port,
    );

    _client.keepAlivePeriod = 20;

    // 연결이 끊어지면 자동 재연결
    _client.autoReconnect = true;

    // 자동 재연결 성공 후 기존 MQTT 토픽 다시 구독
    _client.resubscribeOnAutoReconnect = true;

    _client.onConnected = () {
      onConnectionChanged?.call(true);
    };

    _client.onAutoReconnect = () {
      onConnectionChanged?.call(false);
    };

    _client.onAutoReconnected = () {
      onConnectionChanged?.call(true);
    };

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
    try {
      if (messages.isEmpty) {
        return;
      }

      final receivedMessage = messages.first;
      final message = receivedMessage.payload;

      if (message is! MqttPublishMessage) {
        return;
      }

      final topic = receivedMessage.topic;

      final payload = utf8.decode(
        message.payload.message,
      );

      final decoded = jsonDecode(payload);

      // 수어 번역 결과
      if (topic == 'safehub/vision/livingroom/translation') {
        if (decoded is! Map<String, dynamic>) {
          return;
        }

        final text = decoded['text'];

        if (text is! String || text.trim().isEmpty) {
          return;
        }

        onSignTextReceived?.call(text.trim());
        return;
      }

      // CSI 안전 이벤트가 아니면 무시
      if (topic != 'safehub/csi/bedroom/event' &&
          topic != 'safehub/csi/bathroom/event') {
        return;
      }

      if (decoded is! Map<String, dynamic>) {
        return;
      }

      final event = Map<String, dynamic>.from(decoded);

      final eventType = event['event'];

      // event 필드가 없거나 문자열이 아니면 무시
      if (eventType is! String || eventType.isEmpty) {
        return;
      }

      if (topic == 'safehub/csi/bedroom/event') {
        event['location'] = 'bedroom';
      } else {
        event['location'] = 'bathroom';
      }

      // priority 검증은 EventManager가 담당
      eventManager.addEvent(event);

      onEventReceived?.call(event);
    } catch (e) {
      print('MQTT 메시지 처리 실패: $e');
    }
  }

  void disconnect() {
    _client.disconnect();
  }
}
