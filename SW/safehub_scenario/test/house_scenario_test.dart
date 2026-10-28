import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:safehub_app/core/house_scenario.dart';
import 'package:safehub_app/services/situation_service.dart';

void main() {
  test('broadcast is a candidate, repeated/negated/training speech does not alert', () {
    final flow = HouseScenarioFlow();
    final now = DateTime(2026, 10, 24, 12);
    for (final text in ['화재 대피 훈련입니다', '화재가 발생하지 않았습니다', '화재가 아닙니다', '안녕하세요']) {
      expect(flow.broadcast(text, now: now), isFalse);
    }
    expect(flow.broadcast('화재가 발생했습니다.', now: now), isTrue);
    expect(flow.broadcast('화재가 발생했습니다.', now: now), isFalse);
    expect(flow.active!.relevance, contains('미확인'));
    flow.acknowledge();
    expect(flow.active, isNull);
    expect(flow.lastAcknowledged!.toJson()['risk_resolved'], isFalse);
    flow.dispose();
  });

  test('disaster requires recent time and matching or unconfirmed region', () {
    final flow = HouseScenarioFlow();
    final now = DateTime(2026, 10, 24, 12);
    bool event(String id, DateTime? time, String region) => flow.disaster(
      id: id, text: '재난 알림', region: region, homeRegion: '경산시', issuedAt: time, now: now);
    expect(event('old', now.subtract(const Duration(hours: 1)), '경산시'), isFalse);
    expect(event('unknown', null, '경산시'), isFalse);
    expect(event('elsewhere', now, '제주시'), isFalse);
    expect(event('current', now, '경상북도 경산시'), isTrue);
    expect(event('current', now, '경상북도 경산시'), isFalse);
    flow.dispose();
  });

  test('priority preserves waiting incidents and acknowledgement is not resolution', () {
    final flow = HouseScenarioFlow();
    flow.broadcast('화재가 발생했습니다.');
    flow.assistance('fall', '쓰러짐 의심');
    expect(flow.active!.kind, HouseScenario.assistance);
    expect(flow.pendingCount, 1);
    flow.respond('도와주세요');
    flow.acknowledge();
    expect(flow.lastAcknowledged!.response, '도와주세요');
    expect(flow.active!.kind, HouseScenario.broadcast);
    flow.dispose();
  });

  test('three test cases stay isolated, support simulated sign, and real alarms preempt', () {
    final service = SituationService(settings: SituationSettings(enabled: false));
    addTearDown(service.dispose);
    var commands = 0;
    service.onScenarioAlert = () => commands++;
    for (final kind in HouseScenario.values) {
      expect(service.startScenarioTest(kind, '화재가 발생했습니다.'), isTrue);
      expect(service.flow.active!.kind, kind);
      expect(service.flow.active!.delivery, contains('실제 명령 없음'));
      service.receiveSign('실제 카메라 입력');
      expect(service.pendingSign, '실제 카메라 입력');
      service.receiveSign('도와주세요', simulated: true);
      service.confirmSign();
      expect(service.flow.active!.response, contains('도와주세요'));
      expect(service.reportDraft(), startsWith('[테스트]'));
      expect(service.evidence, isEmpty);
      expect(service.liveFlow.active, isNull);
      service.acknowledge();
      expect(service.flow.active, isNull);
      expect(commands, 0);
      service.endScenarioTest();
    }
    service.startScenarioTest(HouseScenario.broadcast, '화재가 발생했습니다.');
    service.observeFall('actual', '실제 센서의 의심 신호');
    expect(service.scenarioTestMode, isFalse);
    expect(service.flow.active!.evidence, '실제 센서의 의심 신호');
    expect(commands, 1);
    expect(service.startScenarioTest(HouseScenario.disaster, '테스트'), isFalse);
  });

  test('LLM receives only test workflow; server failure never blocks touch response', () async {
    final service = SituationService(debounce: const Duration(days: 1), clientFactory: () => MockClient((r) async {
      final payload = jsonDecode(jsonDecode(r.body)['messages'][1]['content']);
      final context = jsonDecode(payload['selected_context']);
      expect(context['test_mode'], isTrue);
      expect(context['workflow']['scenario'], 'assistance');
      expect(r.body, isNot(contains('비공개 실제 대화')));
      return http.Response('offline', 503);
    }));
    addTearDown(service.dispose);
    service.addEvidence('확정 음성자막', '비공개 실제 대화', analyze: false);
    service.startScenarioTest(HouseScenario.assistance, '쓰러짐 의심');
    await service.analyze();
    service.respond('가족이 쓰러졌습니다.');
    expect(service.flow.active!.response, '가족이 쓰러졌습니다.');
    service.acknowledge();
    expect(service.flow.active, isNull);
  });
}
