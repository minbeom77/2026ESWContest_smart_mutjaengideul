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

  @override
  void initState() {
    super.initState();

    _mqttReceiver = MqttReceiver(
      broker: '192.168.0.38',
      port: 1883,
      eventManager: _eventManager,
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
        child: Text(
          _status,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 28),
        ),
      ),
    );
  }
}