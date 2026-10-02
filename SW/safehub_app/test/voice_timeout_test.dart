import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safehub_app/services/stt_service.dart';
import 'package:safehub_app/services/tts_service.dart';

class BodyStreamClient extends http.BaseClient {
  final Stream<List<int>> body;

  BodyStreamClient(this.body);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(body, 200);
  }
}

void main() {
  testWidgets('STT 응답 대기가 30초를 넘으면 종료한다', (tester) async {
    final pending = Completer<http.Response>();
    final service = SttService(
      baseUrl: 'http://localhost:8000',
      client: MockClient((_) => pending.future),
    );

    final check = expectLater(
      service.transcribe(Uint8List.fromList([1])),
      throwsA(isA<TimeoutException>()),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 31));
    await check;

    pending.complete(http.Response('{"text":"late"}', 200));
    await tester.pump();
    service.dispose();
  });

  testWidgets('STT 헤더 수신 후 본문이 멈춰도 30초에 종료한다',
      (tester) async {
    final body = StreamController<List<int>>();
    final service = SttService(
      baseUrl: 'http://localhost:8000',
      client: BodyStreamClient(body.stream),
    );

    final check = expectLater(
      service.transcribe(Uint8List.fromList([1])),
      throwsA(isA<TimeoutException>()),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 31));
    await check;

    body.add('{"text":"late"}'.codeUnits);
    await body.close();
    await tester.pump();
    service.dispose();
  });

  testWidgets('TTS는 15초 이후에도 기다리고 35초 초과 시 종료한다',
      (tester) async {
    final pending = Completer<http.Response>();
    final service = TtsService(
      baseUrl: 'http://localhost:8000',
      client: MockClient((_) => pending.future),
    );
    var finished = false;

    final check = expectLater(
      service.synthesize('안녕하세요').whenComplete(() {
        finished = true;
      }),
      throwsA(isA<TimeoutException>()),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 16));
    expect(finished, isFalse);

    await tester.pump(const Duration(seconds: 20));
    await check;
    expect(finished, isTrue);

    pending.complete(http.Response.bytes([1, 2, 3], 200));
    await tester.pump();
    service.dispose();
  });
}
