import 'dart:async';
import 'dart:convert';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../core/event_manager.dart';
import '../core/safety_event_normalizer.dart';

// Keep disposal effective if a TCP connect completes after settings were changed.
class _OwnedMqttClient extends MqttServerClient {
  _OwnedMqttClient(String host, String id, int port)
    : super.withPort(host, id, port, maxConnectionAttempts: 1);

  bool _closed = false;

  @override
  Future<MqttClientConnectionStatus?> connect([
    String? username,
    String? password,
  ]) async {
    final pending = super.connect(username, password);
    final pendingHandler = connectionHandler;
    try {
      return await pending;
    } finally {
      // disconnect() clears the public client's handler before a late socket arrives.
      if (_closed) {
        try {
          pendingHandler?.stopListening();
        } catch (_) {}
      }
    }
  }

  @override
  void disconnect() {
    _closed = true;
    autoReconnect = false;
    super.disconnect();
  }
}

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

  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _messages;
  Future<void>? _connecting;
  Timer? _retryTimer;
  bool _disposed = false;
  int _failures = 0;
  bool _connected = false;
  final Duration initialRetryDelay;
  final Duration maxRetryDelay;
  final MqttServerClient Function(String, String, int) _clientFactory;
  final Timer Function(Duration, void Function()) _retryTimerFactory;

  MqttReceiver({
    required this.broker,
    required this.port,
    required this.eventManager,
    this.onEventReceived,
    this.onSignTextReceived,
    this.onDeviceCommand,
    this.onConnectionChanged,
    this.initialRetryDelay = const Duration(seconds: 3),
    this.maxRetryDelay = const Duration(seconds: 15),
    MqttServerClient Function(String, String, int)? clientFactory,
    Timer Function(Duration, void Function())? retryTimerFactory,
  }) : assert(initialRetryDelay > Duration.zero),
       assert(maxRetryDelay >= initialRetryDelay),
       _clientFactory = clientFactory ?? _OwnedMqttClient.new,
       _retryTimerFactory = retryTimerFactory ?? Timer.new;

  Future<void> connect() {
    if (_disposed || _connected) return Future<void>.value();
    if (_connecting != null) return _connecting!;
    // Once connected, the MQTT client's existing auto-reconnect owns recovery.
    if (_client != null) return Future<void>.value();
    _retryTimer?.cancel();
    _retryTimer = null;
    return _connecting = _connectOnce().whenComplete(() => _connecting = null);
  }

  bool _current(MqttServerClient client) =>
      !_disposed && identical(client, _client);

  Future<void> _connectOnce() async {
    final clientId = 'safehub_rpi5_${DateTime.now().millisecondsSinceEpoch}';

    print('[MQTT] connecting broker=$broker port=$port client=$clientId');

    final client = _clientFactory(broker, clientId, port);
    _client = client;

    client.keepAlivePeriod = 20;

    // Initial failures use one capped backoff timer, never a second reconnect loop.
    client.autoReconnect = false;

    // 자동 재연결 성공 후 기존 MQTT 토픽 다시 구독
    client.resubscribeOnAutoReconnect = true;

    client.onConnected = () {
      if (!_current(client)) return;
      _connected = true;
      print('[MQTT] connected broker=$broker port=$port');
      onConnectionChanged?.call(true);
    };

    client.onDisconnected = () {
      if (!_current(client)) return;
      _connected = false;
      print('[MQTT] disconnected state=${client.connectionStatus?.state}');
      onConnectionChanged?.call(false);
    };

    client.onSubscribed = (topic) {
      if (!_current(client)) return;
      print('[MQTT] subscribed topic=$topic');
    };

    client.onSubscribeFail = (topic) {
      if (!_current(client)) return;
      print('[MQTT] subscribe failed topic=$topic');
    };

    client.onAutoReconnect = () {
      if (!_current(client)) return;
      _connected = false;
      print('[MQTT] auto reconnecting');
      onConnectionChanged?.call(false);
    };

    client.onAutoReconnected = () {
      if (!_current(client)) return;
      _connected = true;
      print('[MQTT] auto reconnected');
      onConnectionChanged?.call(true);
    };

    client.connectionMessage =
        MqttConnectMessage().withClientIdentifier(clientId).startClean();

    try {
      await client.connect();
      if (!_current(client)) return;

      if (client.connectionStatus?.state != MqttConnectionState.connected) {
        throw Exception('MQTT 브로커 연결 실패');
      }
      client.autoReconnect = true;
      _failures = 0;

      // 침실 CSI 이벤트
      client.subscribe('safehub/csi/bedroom/event', MqttQos.atLeastOnce);

      // 화장실 CSI 이벤트
      client.subscribe('safehub/csi/bathroom/event', MqttQos.atLeastOnce);

      // 수어 번역 결과
      client.subscribe(
        'safehub/vision/livingroom/translation',
        MqttQos.atMostOnce,
      );

      _messages = client.updates?.listen((messages) {
        if (_current(client)) _onMessage(messages);
      });
      client.subscribe(
        'safehub/control/livingroom/aircon/command',
        MqttQos.atLeastOnce,
      );
    } catch (error) {
      if (!_current(client)) return;
      print('[MQTT] connection failed; waiting to retry');
      _client = null;
      _connected = false;
      _messages?.cancel();
      _messages = null;
      _closeClient(client);
      onConnectionChanged?.call(false);
      _scheduleRetry();
      rethrow;
    } finally {
      if (!_current(client)) {
        _closeClient(client);
      }
    }
  }

  void _scheduleRetry() {
    if (_disposed || _retryTimer != null) return;
    final multiplier = 1 << (_failures > 3 ? 3 : _failures);
    _failures++;
    final millis = (initialRetryDelay.inMilliseconds * multiplier).clamp(
      1,
      maxRetryDelay.inMilliseconds,
    );
    _retryTimer = _retryTimerFactory(Duration(milliseconds: millis), () {
      _retryTimer = null;
      if (_disposed) return;
      unawaited(connect().catchError((Object _, StackTrace __) {}));
    });
  }

  void _closeClient(MqttServerClient client) {
    client.autoReconnect = false;
    client.onConnected = null;
    client.onDisconnected = null;
    client.onAutoReconnect = null;
    client.onAutoReconnected = null;
    client.onSubscribed = null;
    client.onSubscribeFail = null;
    try {
      client.disconnect();
    } catch (_) {}
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage?>> messages) {
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

      final payload = utf8.decode(message.payload.message);

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

      eventManager.addEvent(event);

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
    final client = _client;
    final cleanPayload = payload.trim();

    if (_disposed || client == null || !_connected || cleanPayload.isEmpty) {
      return false;
    }

    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      _connected = false;
      onConnectionChanged?.call(false);
      return false;
    }

    final builder = MqttClientPayloadBuilder()..addUTF8String(cleanPayload);

    final bytes = builder.payload;

    if (bytes == null) {
      return false;
    }

    client.publishMessage(shortcutCommandTopic, MqttQos.atLeastOnce, bytes);

    print(
      '[MQTT] published shortcut command '
      'topic=$shortcutCommandTopic bytes=${cleanPayload.length}',
    );

    return true;
  }

  void disconnect() {
    _disposed = true;
    _connected = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    _messages?.cancel();
    _messages = null;
    final client = _client;
    _client = null;
    if (client != null) _closeClient(client);
  }
}
