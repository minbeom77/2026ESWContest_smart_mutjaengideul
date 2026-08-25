import 'package:flutter/material.dart';

import 'core/event_manager.dart';
import 'mqtt/mqtt_receiver.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MqttTestPage(),
    );
  }
}

class MqttTestPage extends StatefulWidget {
  const MqttTestPage({super.key});

  @override
  State<MqttTestPage> createState() => _MqttTestPageState();
}

class _MqttTestPageState extends State<MqttTestPage> {
  final EventManager _eventManager = EventManager();

  late final MqttReceiver _mqttReceiver;

  String _status = 'MQTT 연결 중...';
  Map<String, dynamic>? _lastEvent;

  @override
  void initState() {
    super.initState();

    _mqttReceiver = MqttReceiver(
      broker: '192.168.0.38',
      port: 1883,
      eventManager: _eventManager,
      onEventReceived: (event) {
        if (!mounted) {
          return;
        }

        setState(() {
          _lastEvent = event;
        });
      },
    );

    _connectMqtt();
  }

  Future<void> _connectMqtt() async {
    try {
      await _mqttReceiver.connect();

      if (!mounted) {
        return;
      }

      setState(() {
        _status = 'MQTT 연결 성공';
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _status = 'MQTT 연결 실패\n$e';
      });
    }
  }

  @override
  void dispose() {
    _mqttReceiver.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SafeHub MQTT Test'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _status,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 28),
            ),
            const SizedBox(height: 30),
            if (_lastEvent != null) ...[
              const Text(
                '수신 이벤트',
                style: TextStyle(fontSize: 22),
              ),
              const SizedBox(height: 10),
              Text(
                'event: ${_lastEvent!['event']}',
                style: const TextStyle(fontSize: 26),
              ),
              Text(
                'priority: ${_lastEvent!['priority']}',
                style: const TextStyle(fontSize: 26),
              ),
            ],
          ],
        ),
      ),
    );
  }
}