import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:safehub_app/core/event_manager.dart';
import 'package:safehub_app/mqtt/mqtt_receiver.dart';

const _expectedSubscriptions = {
  'safehub/csi/bedroom/event': 1,
  'safehub/csi/bathroom/event': 1,
  'safehub/vision/livingroom/translation': 1,
  'safehub/control/livingroom/aircon/command': 1,
};

List<int> _stringBytes(String value) {
  final bytes = utf8.encode(value);
  return [bytes.length >> 8, bytes.length & 255, ...bytes];
}

List<int> _packet(int header, List<int> body) {
  var remaining = body.length;
  final bytes = <int>[header];
  do {
    var digit = remaining % 128;
    remaining ~/= 128;
    if (remaining > 0) digit |= 128;
    bytes.add(digit);
  } while (remaining > 0);
  return [...bytes, ...body];
}

class _Publication {
  _Publication(this.topic, this.payload, this.qos);
  final String topic;
  final List<int> payload;
  final int qos;
}

// A deliberately small MQTT wire fixture. It only binds an ephemeral loopback
// port and acknowledges CONNECT/SUBSCRIBE/PUBLISH/PINGREQ. No broker package,
// clientFactory mock, hardware, external host or production service is used.
class _LoopbackBroker {
  _LoopbackBroker(this.server) {
    listener = server.listen((socket) {
      connectionCount++;
      sockets.add(socket);
      // IOSink.done reports write-side resets separately from the read stream.
      unawaited(socket.done.then<void>((_) {}, onError: _onSocketError));
      final pending = <int>[];
      socket.listen(
        (bytes) {
          pending.addAll(bytes);
          while (_consume(socket, pending)) {}
        },
        onError: (Object error) {
          sockets.remove(socket);
          _onSocketError(error);
        },
        onDone: () => sockets.remove(socket),
      );
    }, onError: _onSocketError);
  }

  static void _onSocketError(Object error) {
    // Cancelling a connection may reset it while SUBACK bytes are still queued.
    // Each test still checks actual connection, subscription and message results.
    if (error is SocketException &&
        (error.osError?.errorCode == 104 ||
            error.osError?.errorCode == 10054)) {
      return;
    }
    throw error;
  }

  final ServerSocket server;
  late final StreamSubscription<Socket> listener;
  final sockets = <Socket>[];
  final subscriptions = <String, int>{};
  final publications = <_Publication>[];
  final protocolNames = <String>[];
  final protocolLevels = <int>[];
  int connectionCount = 0;
  int disconnectCount = 0;
  int get port => server.port;

  static Future<_LoopbackBroker> open({int port = 0}) async => _LoopbackBroker(
    await ServerSocket.bind(InternetAddress.loopbackIPv4, port),
  );

  bool _consume(Socket socket, List<int> pending) {
    if (pending.length < 2) return false;
    var multiplier = 1;
    var remaining = 0;
    var offset = 1;
    while (true) {
      if (offset >= pending.length) return false;
      final digit = pending[offset++];
      remaining += (digit & 127) * multiplier;
      if ((digit & 128) == 0) break;
      multiplier *= 128;
      if (multiplier > 128 * 128 * 128) {
        throw StateError('Invalid MQTT remaining length');
      }
    }
    if (pending.length < offset + remaining) return false;
    final header = pending.first;
    final body = pending.sublist(offset, offset + remaining);
    pending.removeRange(0, offset + remaining);
    switch (header >> 4) {
      case 1: // CONNECT: both MQTT 3.1 and 3.1.1 share these reply bytes.
        final length = (body[0] << 8) | body[1];
        protocolNames.add(utf8.decode(body.sublist(2, 2 + length)));
        protocolLevels.add(body[2 + length]);
        socket.add([0x20, 2, 0, 0]); // CONNACK accepted, no stored session.
      case 8: // SUBSCRIBE, including its mandatory packet identifier.
        var cursor = 2;
        final granted = <int>[];
        while (cursor < body.length) {
          final length = (body[cursor] << 8) | body[cursor + 1];
          cursor += 2;
          final topic = utf8.decode(body.sublist(cursor, cursor + length));
          cursor += length;
          final qos = body[cursor++];
          subscriptions[topic] = qos;
          granted.add(qos);
        }
        socket.add(_packet(0x90, [body[0], body[1], ...granted]));
      case 3: // PUBLISH from the real client, acknowledged for QoS 1.
        final length = (body[0] << 8) | body[1];
        final topic = utf8.decode(body.sublist(2, 2 + length));
        var cursor = 2 + length;
        final qos = (header >> 1) & 3;
        if (qos == 1) {
          socket.add([0x40, 2, body[cursor], body[cursor + 1]]);
          cursor += 2;
        }
        publications.add(_Publication(topic, body.sublist(cursor), qos));
      case 12:
        socket.add([0xd0, 0]); // PINGRESP.
      case 14:
        disconnectCount++;
    }
    return true;
  }

  void publish(String topic, String payload, {int qos = 0, int id = 1}) {
    final body = <int>[
      ..._stringBytes(topic),
      if (qos == 1) ...[id >> 8, id & 255],
      ...utf8.encode(payload),
    ];
    sockets.single.add(_packet(0x30 | (qos << 1), body));
  }

  Future<void> close() async {
    for (final socket in sockets.toList()) {
      socket.destroy();
    }
    await listener.cancel();
    await server.close();
  }
}

Future<void> _until(bool Function() condition, String reason) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Timed out: $reason');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test(
    'disposing during real TCP connect closes a late socket without callbacks',
    () async {
      final broker = await _LoopbackBroker.open();
      final connections = <bool>[];
      final receiver = MqttReceiver(
        broker: InternetAddress.loopbackIPv4.address,
        port: broker.port,
        eventManager: EventManager(),
        onConnectionChanged: connections.add,
        initialRetryDelay: const Duration(milliseconds: 100),
        maxRetryDelay: const Duration(milliseconds: 200),
      );
      addTearDown(() async {
        receiver.disconnect();
        await broker.close();
      });
      // connect() is still waiting for Socket.connect when disposal runs. The
      // production subclass must close the handler even if it arrives later.
      final connecting = receiver.connect();
      receiver.disconnect();
      await connecting.timeout(const Duration(seconds: 7));
      await _until(() => broker.sockets.isEmpty, 'late connection closed');
      expect(connections, isEmpty);
      expect(broker.subscriptions, isEmpty);
      final countAtDisposal = broker.connectionCount;
      await receiver.connect();
      await Future<void>.delayed(const Duration(milliseconds: 450));
      expect(broker.connectionCount, countAtDisposal);
      expect(receiver.publishShortcutCommand('{}'), isFalse);
    },
  );

  test(
    'real MQTT transport preserves subscriptions, events and shortcut bytes',
    () async {
      final broker = await _LoopbackBroker.open();
      final events = EventManager();
      final signs = <String>[];
      final safetyEvents = <Map<String, dynamic>>[];
      final deviceCommands = <Map<String, dynamic>>[];
      final deviceTopics = <String>[];
      final connections = <bool>[];
      final receiver = MqttReceiver(
        broker: InternetAddress.loopbackIPv4.address,
        port: broker.port,
        eventManager: events,
        onSignTextReceived: signs.add,
        onEventReceived: safetyEvents.add,
        onDeviceCommand: (topic, data) {
          deviceTopics.add(topic);
          deviceCommands.add(data);
        },
        onConnectionChanged: connections.add,
      );
      addTearDown(() async {
        receiver.disconnect();
        await broker.close();
      });

      await receiver.connect();
      await _until(
        () => broker.subscriptions.length == 4,
        'four subscriptions',
      );
      expect(broker.subscriptions, _expectedSubscriptions);
      expect(broker.connectionCount, 1);
      expect(connections, [true]);
      // The installed client supports the MQTT 3.x protocol names and levels.
      expect(broker.protocolNames.single, anyOf('MQTT', 'MQIsdp'));
      expect(broker.protocolLevels.single, anyOf(3, 4));

      broker.publish(
        'safehub/vision/livingroom/translation',
        jsonEncode({'text': '  도와주세요  '}),
      );
      broker.publish(
        'safehub/csi/bedroom/event',
        jsonEncode({'event': 'fall_detected', 'priority': 9}),
        qos: 1,
      );
      broker.publish(
        'safehub/csi/bathroom/event',
        jsonEncode({'event': 'fall_detected', 'priority': 8}),
        qos: 1,
        id: 2,
      );
      final command = {'power': true, 'temperature': 24, 'mode': 'cool'};
      broker.publish(
        'safehub/control/livingroom/aircon/command',
        jsonEncode(command),
        qos: 1,
        id: 3,
      );
      await _until(
        () =>
            signs.length == 1 &&
            safetyEvents.length == 2 &&
            deviceCommands.length == 1,
        'incoming message callbacks',
      );
      expect(signs, ['도와주세요']);
      expect(safetyEvents, [
        {'event': 'fall_detected', 'priority': 9, 'location': 'bedroom'},
        {'event': 'fall_detected', 'priority': 8, 'location': 'bathroom'},
      ]);
      expect(events.getNextEvent(), safetyEvents[0]);
      expect(events.getNextEvent(), safetyEvents[1]);
      expect(events.getNextEvent(), isNull);
      expect(deviceTopics, ['safehub/control/livingroom/aircon/command']);
      expect(deviceCommands, [command]);

      const shortcut = '{"action":"save","text":"도와주세요"}';
      expect(receiver.publishShortcutCommand('  $shortcut\n'), isTrue);
      await _until(
        () => broker.publications.length == 1,
        'shortcut publication',
      );
      final publication = broker.publications.single;
      expect(publication.topic, 'safehub/config/sign_shortcut/command');
      expect(publication.qos, 1);
      expect(publication.payload, utf8.encode(shortcut));

      receiver.disconnect();
      await _until(() => broker.sockets.isEmpty, 'socket closed on disposal');
      await receiver.connect();
      expect(receiver.publishShortcutCommand(shortcut), isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(broker.connectionCount, 1);
      expect(connections, [true]);
    },
  );

  test(
    'refused real TCP connection retries when loopback broker starts later',
    () async {
      // Reserve a dynamic port, then release it so the first TCP attempt fails.
      final reservation = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = reservation.port;
      await reservation.close();
      final connections = <bool>[];
      final receiver = MqttReceiver(
        broker: InternetAddress.loopbackIPv4.address,
        port: port,
        eventManager: EventManager(),
        onConnectionChanged: connections.add,
        initialRetryDelay: const Duration(milliseconds: 100),
        maxRetryDelay: const Duration(milliseconds: 200),
      );
      _LoopbackBroker? broker;
      addTearDown(() async {
        receiver.disconnect();
        await broker?.close();
      });
      await expectLater(receiver.connect(), throwsA(isA<Exception>()));
      expect(connections, [false]);
      broker = await _LoopbackBroker.open(port: port);
      await _until(
        () => broker!.subscriptions.length == 4,
        'delayed broker retry',
      );
      expect(broker.subscriptions, _expectedSubscriptions);
      expect(connections.last, isTrue);

      receiver.disconnect();
      await _until(() => broker!.sockets.isEmpty, 'retried socket disposal');
      final countAtDisposal = broker.connectionCount;
      final callbacksAtDisposal = connections.toList();
      await receiver.connect();
      await Future<void>.delayed(const Duration(milliseconds: 450));
      expect(broker.connectionCount, countAtDisposal);
      expect(connections, callbacksAtDisposal);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );
}
