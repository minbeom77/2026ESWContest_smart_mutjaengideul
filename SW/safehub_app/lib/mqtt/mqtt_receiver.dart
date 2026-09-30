import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../core/event_manager.dart';
import '../core/safety_event_normalizer.dart';

class MqttReceiver {
  static const String shortcutCommandTopic =
      'safehub/config/sign_shortcut/command';

  final String broker;
  final int port;
  final EventManager eventManager;

  // CSI 안전 이벤트 수신
  final void Function(Map<String, dynamic> event)? onEventReceived;

  // 수어 번역 결과 수신
  final void Function(String text)? onSignTextReceived;

  final void Function(String topic, Map<String, dynamic> data)? onDeviceCommand;

  // MQTT 연결 상태 변경
  final void Function(bool connected)? onConnectionChanged;

  late final MqttServerClient _client;
  bool _connected = false;

  // 최근 사건 ID만 보관해 메모리 사용량을 제한한다.
  final LinkedHashSet<String> _seenSafetyMessageIds =
      LinkedHashSet<String>();
  static const int _maxSeenSafetyMessageIds = 2000;

  MqttReceiver({
    required this.broker,
    required this.port,
    required this.eventManager,
    this.onEventReceived,
    this.onSignTextReceived,
    this.onDeviceCommand,
    this.onConnectionChanged,
  });

  Future<void> connect() async {
    final clientId = 'safehub_rpi5_${DateTime.now().millisecondsSinceEpoch}';

    print('[MQTT] connecting broker=$broker port=$port client=$clientId');

    _client = MqttServerClient.withPort(
      broker,
      clientId,
      port,
    );

    _client.keepAlivePeriod = 20;

    // 연결이 끊어지면 자동 재연결
    _client.autoReconnect = true;

    // 자동 재연결 성공 후 기존 MQTT 토픽 다시 구독
    _client.resubscribeOnAutoReconnect = true;

    _client.onConnected = () {
      _connected = true;
      print('[MQTT] connected broker=$broker port=$port');
      onConnectionChanged?.call(true);
    };

    _client.onDisconnected = () {
      _connected = false;
      print('[MQTT] disconnected state=${_client.connectionStatus?.state}');
      onConnectionChanged?.call(false);
    };

    _client.onSubscribed = (topic) {
      print('[MQTT] subscribed topic=$topic');
    };

    _client.onSubscribeFail = (topic) {
      print('[MQTT] subscribe failed topic=$topic');
    };

    _client.onAutoReconnect = () {
      _connected = false;
      print('[MQTT] auto reconnecting');
      onConnectionChanged?.call(false);
    };

    _client.onAutoReconnected = () {
      _connected = true;
      print('[MQTT] auto reconnected');
      onConnectionChanged?.call(true);
    };

    _client.connectionMessage =
        MqttConnectMessage().withClientIdentifier(clientId).startClean();

    try {
      await _client.connect();
    } catch (e) {
      print('[MQTT] connection failed: $e');
      _client.disconnect();
      rethrow;
    }

    if (_client.connectionStatus?.state != MqttConnectionState.connected) {
      _client.disconnect();
      throw Exception('MQTT 브로커 연결 실패');
    }

    _client.updates?.listen(_onMessage);

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
      MqttQos.atLeastOnce,
    );

    _client.subscribe(
        'safehub/control/livingroom/aircon/command', MqttQos.atLeastOnce);
  }

  void _onMessage(
    List<MqttReceivedMessage<MqttMessage?>> messages,
  ) {
    for (final receivedMessage in messages) {
      _handleMessage(receivedMessage);
    }
  }

  void _handleMessage(MqttReceivedMessage<MqttMessage?> receivedMessage) {
    try {
      final message = receivedMessage.payload;

      if (message is! MqttPublishMessage) {
        return;
      }

      final topic = receivedMessage.topic;

      final payload = utf8.decode(
        message.payload.message,
      );

      handlePayload(topic, payload);
    } catch (e) {
      print('[MQTT] message decoding failed: $e');
    }
  }

  // 브로커 없이 수신 처리 동작을 검사하기 위한 진입점.
  @visibleForTesting
  void handlePayload(String topic, String payload) {
    try {
      print('[MQTT] received topic=$topic bytes=${payload.length}');

      final decoded = jsonDecode(payload);

      if (topic == 'safehub/control/livingroom/aircon/command') {
        if (decoded is Map<String, dynamic>)
          onDeviceCommand?.call(topic, decoded);
        return;
      }

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

      final event = SafetyEventNormalizer.normalize(
        decoded: decoded,
        topic: topic,
      );

      if (event == null) {
        print(
          '[MQTT] ignored invalid safety event '
          'topic=$topic payload=$payload',
        );
        return;
      }

      final rawMessageId = event['message_id'];

      if (rawMessageId == null) {
        // 기존 테스트 메시지 호환. ID가 없으면 중복을 판별할 수 없다.
        print('[MQTT] legacy safety event without message_id topic=$topic');
      } else {
        if (rawMessageId is! String || rawMessageId.trim().isEmpty) {
          print('[MQTT] ignored invalid message_id topic=$topic');
          return;
        }

        final messageId = rawMessageId.trim();
        event['message_id'] = messageId;

        if (_seenSafetyMessageIds.contains(messageId)) {
          print('[MQTT] duplicate safety event ignored id=$messageId');
          return;
        }
      }

      eventManager.addEvent(event);

      // 이벤트 등록 성공 후에만 처리한 ID로 기억한다.
      if (rawMessageId is String) {
        _seenSafetyMessageIds.add(rawMessageId.trim());

        while (_seenSafetyMessageIds.length > _maxSeenSafetyMessageIds) {
          _seenSafetyMessageIds.remove(_seenSafetyMessageIds.first);
        }
      }

      print(
        '[MQTT] event queued event=${event['event']} '
        'location=${event['location']} priority=${event['priority']}',
      );

      onEventReceived?.call(event);
    } catch (e) {
      print('[MQTT] message handling failed: $e');
    }
  }

  bool publishShortcutCommand(String payload) {
    final cleanPayload = payload.trim();

    if (!_connected || cleanPayload.isEmpty) {
      return false;
    }

    if (_client.connectionStatus?.state != MqttConnectionState.connected) {
      _connected = false;
      onConnectionChanged?.call(false);
      return false;
    }

    final builder = MqttClientPayloadBuilder()..addUTF8String(cleanPayload);

    final bytes = builder.payload;

    if (bytes == null) {
      return false;
    }

    _client.publishMessage(
      shortcutCommandTopic,
      MqttQos.atLeastOnce,
      bytes,
    );

    print(
      '[MQTT] published shortcut command '
      'topic=$shortcutCommandTopic bytes=${cleanPayload.length}',
    );

    return true;
  }

  void disconnect() {
    _connected = false;
    _client.disconnect();
  }
}
