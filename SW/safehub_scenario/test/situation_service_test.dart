import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safehub_app/services/situation_service.dart';
import 'package:safehub_app/core/alert_signal.dart';

Map<String, dynamic> output({
  String quote = '화재가 발생했습니다',
  String id = 'e1',
  bool drill = false,
}) => {
  'title': '화재 관련 방송',
  'summary': '방송 내용을 확인하세요.',
  'urgency': 'emergency',
  'confidence': .95,
  'is_drill': drill,
  'evidence': [
    {'source_id': id, 'quote': quote},
  ],
};
http.Response reply(Map<String, dynamic> data) => http.Response.bytes(
  utf8.encode(
    jsonEncode({
      'choices': [
        {
          'message': {'content': jsonEncode(data)},
        },
      ],
    }),
  ),
  200,
);

void main() {
  test('fall sign delivers one alarm per incident and preserves confirmation', () {
    final service = SituationService(settings: SituationSettings(enabled: false));
    addTearDown(service.dispose);
    var alerts = 0;
    service.onScenarioAlert = () => alerts++;
    service.receiveSign('점등');
    expect(alerts, 0);
    service.receiveSign('쓰러지다');
    expect(service.helpOpen, isTrue);
    expect(service.helpSign, '쓰러지다');
    expect(alerts, 1);
    service.receiveSign('쓰러짐');
    expect(alerts, 1);
    service.receiveSign('괜찮다');
    expect(service.helpOpen, isFalse);
    service.receiveSign('쓰러지다');
    expect(alerts, 2);
    service.receiveSign('괜찮다');
    service.receiveSign('구조');
    expect(service.helpOpen, isTrue);
    expect(alerts, 3);
  });

  test('fall sign in screen-only scenario test sends no real alarm', () {
    final service = SituationService(settings: SituationSettings(enabled: false));
    addTearDown(service.dispose);
    var alerts = 0;
    service.onScenarioAlert = () => alerts++;
    service.scenarioTestMode = true;
    service.receiveSign('쓰러지다', simulated: true);
    expect(service.helpOpen, isTrue);
    expect(alerts, 0);
  });

  test(
    'legacy protocol fixture preserves supplied model and finalized text',
    () async {
      late http.Request request;
      final service = SituationService(
        settings: SituationSettings(
          model: 'legacy-contract-fixture',
          fastProtocol: false,
          endpoint: 'http://127.0.0.1:9379/v1/chat/completions',
        ),
        clientFactory: () => MockClient((r) async {
          request = r;
          return reply(output());
        }),
      );
      addTearDown(service.dispose);
      service.addEvidence('확정 음성자막', '화재가 발생했습니다. 안내방송입니다.', analyze: false);
      await service.analyze();
      final body = jsonDecode(request.body);
      expect(
        request.url.toString(),
        'http://127.0.0.1:9379/v1/chat/completions',
      );
      expect(body['model'], 'legacy-contract-fixture');
      expect(body['stream'], false);
      expect(body.containsKey('audio'), false);
      expect(service.announcement, contains('화재'));
      expect(service.busy, false);
    },
  );

  test('fabricated evidence cannot open an alarm', () async {
    final service = SituationService(
      settings: SituationSettings(
        model: 'legacy-contract-fixture',
        fastProtocol: false,
        endpoint: 'http://127.0.0.1:9379/v1/chat/completions',
      ),
      clientFactory: () =>
          MockClient((_) async => reply(output(quote: '없는 원문'))),
    );
    addTearDown(service.dispose);
    service.addEvidence('확정 음성자막', '화재가 발생했습니다', analyze: false);
    await service.analyze();
    expect(service.announcement, isNull);
    expect(service.assessment, isNull);
    expect(service.status, contains('검증 실패'));
  });

  for (final text in ['화재가 발생했습니다는 훈련 예시입니다', '화재가 발생했습니다가 아닙니다']) {
    test('training and negated speech are not alarms: $text', () async {
      final service = SituationService(
        settings: SituationSettings(
          model: 'legacy-contract-fixture',
          fastProtocol: false,
          endpoint: 'http://127.0.0.1:9379/v1/chat/completions',
        ),
        clientFactory: () => MockClient((_) async => reply(output())),
      );
      addTearDown(service.dispose);
      service.addEvidence('확정 음성자막', text, analyze: false);
      await service.analyze();
      expect(service.announcement, isNull);
    });
  }

  test('old API record does not become a new broadcast alarm', () async {
    final service = SituationService(
      settings: SituationSettings(
        model: 'legacy-contract-fixture',
        fastProtocol: false,
        endpoint: 'http://127.0.0.1:9379/v1/chat/completions',
      ),
      clientFactory: () => MockClient((_) async => reply(output())),
    );
    addTearDown(service.dispose);
    service.addEvidence(
      '기존 재난 API 기록 (현재 경보 아님)',
      '화재가 발생했습니다',
      analyze: false,
    );
    await service.analyze();
    expect(service.announcement, isNull);
  });

  test('acknowledged source is not shown again on reevaluation', () async {
    final service = SituationService(
      settings: SituationSettings(
        model: 'legacy-contract-fixture',
        fastProtocol: false,
        endpoint: 'http://127.0.0.1:9379/v1/chat/completions',
      ),
      clientFactory: () => MockClient((_) async => reply(output())),
    );
    addTearDown(service.dispose);
    service.addEvidence('확정 음성자막', '화재가 발생했습니다', analyze: false);
    await service.analyze();
    service.acknowledge();
    await service.analyze();
    expect(service.needsAttention, false);
  });

  test(
    'timeout clears analysis but does not dismiss an existing alert',
    () async {
      final service = SituationService(
        settings: SituationSettings(
          model: 'legacy-contract-fixture',
          fastProtocol: false,
          endpoint: 'http://127.0.0.1:9379/v1/chat/completions',
        ),
        timeout: const Duration(milliseconds: 5),
        clientFactory: () =>
            MockClient((_) => Completer<http.Response>().future),
      );
      addTearDown(service.dispose);
      service.openHelp();
      service.addEvidence('확정 음성자막', '안녕하세요', analyze: false);
      await service.analyze();
      expect(service.busy, false);
      expect(service.helpOpen, true);
      expect(service.status, contains('응답 지연'));
    },
  );

  test(
    'in-flight requests do not overlap; disposing discards the response',
    () async {
      final response = Completer<http.Response>();
      var calls = 0;
      final service = SituationService(
        settings: SituationSettings(
          model: 'legacy-contract-fixture',
          fastProtocol: false,
          endpoint: 'http://127.0.0.1:9379/v1/chat/completions',
        ),
        clientFactory: () => MockClient((_) {
          calls++;
          return response.future;
        }),
      );
      service.addEvidence('확정 음성자막', '화재가 발생했습니다', analyze: false);
      final first = service.analyze();
      await service.analyze();
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      service.dispose();
      response.complete(reply(output()));
      await first;
      expect(service.assessment, isNull);
    },
  );

  test('dummy CSI cannot be represented as a real household observation', () {
    final service = SituationService(
      settings: SituationSettings(
        model: 'legacy-contract-fixture',
        fastProtocol: false,
        endpoint: 'http://127.0.0.1:9379/v1/chat/completions',
      ),
    );
    addTearDown(service.dispose);
    service.setSensor({
      'mode': 'dummy',
      'dummy_allowed': true,
      'fresh': true,
      'connected': true,
      'recognition': {
        'running': true,
        'result': {'label': '정지'},
      },
    });
    expect(service.sensorAt, isNull);
    expect(service.sensorStatus, '실측 신호 연결 필요');
  });

  test('stale CSI classification is explicitly invalidated', () {
    final service = SituationService(
      settings: SituationSettings(
        model: 'legacy-contract-fixture',
        fastProtocol: false,
        endpoint: 'http://127.0.0.1:9379/v1/chat/completions',
      ),
    );
    addTearDown(service.dispose);
    service.sensorAt = DateTime.now().subtract(const Duration(seconds: 6));
    service.sensorStatus = 'CSI 분류: 걷기';
    service.expireSensor();
    expect(service.sensorAt, isNull);
    expect(service.sensorStatus, isNot(contains('걷기')));
  });

  test('a sign becomes user-confirmed report text only after confirmation', () {
    final service = SituationService(
      settings: SituationSettings(
        model: 'legacy-contract-fixture',
        fastProtocol: false,
        endpoint: 'http://127.0.0.1:9379/v1/chat/completions',
      ),
    );
    addTearDown(service.dispose);
    service.openHelp();
    service.receiveSign('아프다');
    expect(service.reportDraft(), isNot(contains('아프다')));
    service.confirmSign();
    expect(service.reportDraft(), contains('아프다'));
    expect(service.reportDraft(), contains('아직 전송하지 않음'));
  });

  test('actuator commands keep the existing keys and bounded duration', () {
    final first = AlertSignal.payload('bedshaker', 'on', duration: 1000);
    final second = AlertSignal.payload('bedshaker', 'off');
    expect(first.keys.toSet(), {
      'message_id',
      'device',
      'event',
      'action',
      'timestamp',
      'duration_sec',
    });
    expect(first['duration_sec'], 10);
    expect(second['duration_sec'], 0);
    expect(
      first['message_id'],
      matches(RegExp(r'^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$')),
    );
    expect(first['message_id'], isNot(second['message_id']));
    expect(
      AlertSignal.payload('led', 'firmware_action').containsKey('duration_sec'),
      false,
    );
  });
}
