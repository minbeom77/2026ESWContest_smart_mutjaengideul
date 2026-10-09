import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:safehub_app/core/event_manager.dart';
import 'package:safehub_app/mqtt/mqtt_receiver.dart';

class _ManualTimer implements Timer {
  _ManualTimer(this.delay, this.callback);
  final Duration delay;
  final void Function() callback;
  bool active = true;
  @override
  bool get isActive => active;
  @override
  int get tick => active ? 0 : 1;
  @override
  void cancel() => active = false;
  void fire() {
    if (!active) return;
    active = false;
    callback();
  }
}

class _Client extends MqttServerClient {
  _Client() : super.withPort('localhost', 'test', 1883);
  final completion = Completer<MqttClientConnectionStatus?>();
  final status = MqttClientConnectionStatus();
  final stream =
      StreamController<List<MqttReceivedMessage<MqttMessage>>>.broadcast(
        sync: true,
      );
  final subscriptions = <String>[];
  final subscriptionQos = <String, MqttQos>{};
  MqttPublishMessage? retainedEvent;
  int connects = 0, disconnects = 0;

  @override
  MqttClientConnectionStatus get connectionStatus => status;
  @override
  Stream<List<MqttReceivedMessage<MqttMessage>>> get updates => stream.stream;
  @override
  Future<MqttClientConnectionStatus?> connect([
    String? username,
    String? password,
  ]) {
    connects++;
    return completion.future;
  }

  @override
  Subscription? subscribe(String topic, MqttQos qosLevel) {
    subscriptions.add(topic);
    subscriptionQos[topic] = qosLevel;
    if (topic == 'safehub/csi/bedroom/event' && retainedEvent != null) {
      stream.add([MqttReceivedMessage<MqttMessage>(topic, retainedEvent!)]);
    }
    return null;
  }

  @override
  void disconnect() {
    disconnects++;
    status.state = MqttConnectionState.disconnected;
  }

  void accept() {
    status.state = MqttConnectionState.connected;
    onConnected?.call();
    completion.complete(status);
  }
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late List<_Client> clients;
  late List<_ManualTimer> timers;
  late List<bool> changes;
  late MqttReceiver receiver;

  setUp(() {
    clients = [];
    timers = [];
    changes = [];
    receiver = MqttReceiver(
      broker: 'localhost',
      port: 1883,
      eventManager: EventManager(),
      onConnectionChanged: changes.add,
      clientFactory: (_, __, ___) {
        final client = _Client();
        clients.add(client);
        return client;
      },
      retryTimerFactory: (delay, callback) {
        final timer = _ManualTimer(delay, callback);
        timers.add(timer);
        return timer;
      },
    );
  });

  tearDown(() async {
    receiver.disconnect();
    for (final client in clients) {
      await client.stream.close();
    }
  });

  test(
    'initial failure retries and subscribes when a broker starts later',
    () async {
      final first = receiver.connect();
      final failed = expectLater(first, throwsStateError);
      clients.single.completion.completeError(StateError('broker unavailable'));
      await failed;
      expect(timers.single.delay, const Duration(seconds: 3));
      timers.single.fire();
      expect(clients.length, 2);
      clients.last.accept();
      await _settle();
      expect(changes.last, isTrue);
      expect(clients.last.autoReconnect, isTrue);
      expect(clients.last.subscriptions, [
        'safehub/csi/bedroom/event',
        'safehub/csi/bathroom/event',
        'safehub/vision/livingroom/translation',
        'safehub/control/livingroom/aircon/command',
      ]);
      expect(timers.where((timer) => timer.isActive), isEmpty);
    },
  );

  test('repeated failure caps backoff and never overlaps attempts', () async {
    final first = receiver.connect();
    expect(identical(first, receiver.connect()), isTrue);
    final failed = expectLater(first, throwsStateError);
    clients.single.completion.completeError(StateError('offline'));
    await failed;
    for (var attempt = 0; attempt < 4; attempt++) {
      timers.last.fire();
      final clientCount = clients.length;
      receiver.connect();
      expect(clients.length, clientCount);
      clients.last.completion.completeError(StateError('still offline'));
      await _settle();
    }
    expect(timers.map((timer) => timer.delay.inSeconds), [3, 6, 12, 15, 15]);
    expect(timers.where((timer) => timer.isActive).length, 1);
  });

  test('disposing cancels a scheduled retry permanently', () async {
    final first = receiver.connect();
    final failed = expectLater(first, throwsStateError);
    clients.single.completion.completeError(StateError('offline'));
    await failed;
    receiver.disconnect();
    timers.single.fire();
    await receiver.connect();
    expect(clients.length, 1);
    expect(timers.single.isActive, isFalse);
  });

  test(
    'late connect completion after disposal cannot subscribe or notify',
    () async {
      final connecting = receiver.connect();
      final lateCallback = clients.single.onConnected;
      receiver.disconnect();
      lateCallback?.call();
      clients.single.accept();
      await connecting;
      expect(changes, isEmpty);
      expect(clients.single.subscriptions, isEmpty);
      expect(clients.single.disconnects, greaterThanOrEqualTo(2));
      expect(timers, isEmpty);
      expect(receiver.publishShortcutCommand('{}'), isFalse);
    },
  );

  test(
    'established auto reconnect does not also schedule initial retry',
    () async {
      final connecting = receiver.connect();
      clients.single.accept();
      await connecting;
      clients.single.onAutoReconnect?.call();
      expect(changes.last, isFalse);
      await receiver.connect();
      expect(clients.length, 1);
      expect(timers, isEmpty);
      clients.single.onAutoReconnected?.call();
      expect(changes.last, isTrue);
    },
  );

  test(
    'subscription-time event is received and retry ID remains deduplicated',
    () async {
      const topic = 'safehub/csi/bedroom/event';
      const payload =
          '{"event":"fall_detected","priority":9,"message_id":"retry-1"}';
      final connecting = receiver.connect();
      final builder = MqttClientPayloadBuilder()..addUTF8String(payload);
      clients.single.retainedEvent = MqttPublishMessage()
          .toTopic(topic)
          .publishData(builder.payload!);
      clients.single.accept();
      await connecting;
      expect(receiver.eventManager.getNextEvent()?['message_id'], 'retry-1');
      expect(
        clients.single.subscriptionQos['safehub/vision/livingroom/translation'],
        MqttQos.atLeastOnce,
      );
      clients.single.onAutoReconnect?.call();
      clients.single.onAutoReconnected?.call();
      receiver.handlePayload(topic, payload);
      expect(receiver.eventManager.getNextEvent(), isNull);
    },
  );
}
