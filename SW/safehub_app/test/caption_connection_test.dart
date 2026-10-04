import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:safehub_app/services/caption_connection.dart';

void main() {
  test('real socket delivers partial text, acknowledgement and clear epoch', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    WebSocket? peer;
    var epoch = 0;
    server.listen((request) async {
      peer = await WebSocketTransformer.upgrade(request);
      peer!.add(jsonEncode({'type': 'ready', 'protocol': 'safehub.pcm.v1'}));
      peer!.listen((data) {
        if (data is String) {
          epoch = jsonDecode(data)['epoch'] as int;
        } else {
          peer!.add(jsonEncode({'type': 'caption', 'bytes': (data as List).length,
            'segment': 0, 'epoch': epoch, 'text': '안녕', 'final': false}));
        }
      });
    });
    final connection = await WebSocketCaptionConnection.connect(
        Uri.parse('ws://127.0.0.1:${server.port}'));
    final result = connection.results.first;
    connection.reset(2);
    connection.add(Uint8List(3200));
    final received = await result.timeout(const Duration(seconds: 2));
    expect(received.text, '안녕');
    expect(received.epoch, 2);
    expect(received.isFinal, false);
    await connection.close();
    await peer?.close();
    await server.close(force: true);
  });

  test('unacknowledged audio cannot grow beyond two seconds', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    WebSocket? peer;
    server.listen((request) async {
      peer = await WebSocketTransformer.upgrade(request);
      peer!.add(jsonEncode({'type': 'ready', 'protocol': 'safehub.pcm.v1'}));
      peer!.listen((_) {});
    });
    final connection = await WebSocketCaptionConnection.connect(
        Uri.parse('ws://127.0.0.1:${server.port}'));
    final subscription = connection.results.listen((_) {});
    connection.add(Uint8List(64000));
    expect(() => connection.add(Uint8List(3200)), throwsStateError);
    await subscription.cancel();
    await connection.close();
    await peer?.close();
    await server.close(force: true);
  });
}
