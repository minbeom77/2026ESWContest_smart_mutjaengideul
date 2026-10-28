import 'package:flutter_test/flutter_test.dart';
import 'package:safehub_app/core/house_scenario.dart';
import 'package:safehub_app/services/situation_service.dart';

void main() {
  test('okay sign closes live help without touching or resolving a hazard', () {
    final s = SituationService(settings: SituationSettings(enabled: false));
    addTearDown(s.dispose);
    s.receiveSign('아프다');
    expect(s.helpOpen, isTrue);
    s.receiveSign('괜찮다');
    expect(s.helpOpen, isFalse);
    expect(s.flow.active, isNull);
    expect(s.pendingSign, isEmpty);
    expect(s.flow.lastAcknowledged!.response, contains('괜찮다'));
    expect(s.flow.lastAcknowledged!.toJson()['risk_resolved'], isFalse);
  });

  test('okay confirms a visible fire without claiming the risk is resolved', () {
    final s = SituationService(settings: SituationSettings(enabled: false));
    addTearDown(s.dispose);
    s.receiveSign('괜찮다');
    expect(s.pendingSign, '괜찮다');
    s.observeBroadcast('화재가 발생했습니다.');
    final fire = s.flow.active;
    s.openHelp();
    s.receiveSign('괜찮아요');
    expect(s.helpOpen, isFalse);
    expect(s.flow.active, isNull);
    expect(fire!.acknowledged, isTrue);
    expect(fire.toJson()['risk_resolved'], isFalse);
  });

  test('a negated okay phrase does not dismiss assistance', () {
    final s = SituationService(settings: SituationSettings(enabled: false));
    addTearDown(s.dispose);
    s.receiveSign('구조');
    s.receiveSign('괜찮지 않다');
    expect(s.helpOpen, isTrue);
    expect(s.flow.active!.kind, HouseScenario.assistance);
  });

  test(
    'real fire captions preempt a test and an elevator prohibition is not a fire negation',
    () {
      final s = SituationService(settings: SituationSettings(enabled: false));
      addTearDown(s.dispose);
      s.startScenarioTest(HouseScenario.assistance, '시연 입력');
      s.addEvidence(
        '확정 음성자막',
        '화재가 발생했습니다. 엘리베이터를 이용하지 않고 안내를 확인하세요.',
        analyze: false,
      );
      expect(s.scenarioTestMode, isFalse);
      expect(s.liveFlow.active!.kind, HouseScenario.broadcast);
    },
  );
  test(
    'pain opens immediate help without LLM or a caregiver collapse claim',
    () {
      final s = SituationService(settings: SituationSettings(enabled: false));
      addTearDown(s.dispose);
      s.receiveSign('아프다');
      expect(s.helpOpen, isTrue);
      expect(s.helpSign, '아프다');
      expect(s.flow.active!.kind, HouseScenario.assistance);
      expect(s.flow.active!.evidence, isNot(contains('쓰러')));
      s.cancelHelp();
      s.receiveSign('아프다');
      expect(s.helpOpen, isFalse);
      s.receiveSign('감사');
      s.receiveSign('아프다');
      expect(s.helpOpen, isTrue);
    },
  );
  test(
    'help sign opens immediately and touch cancellation preserves its hazard',
    () {
      final s = SituationService(settings: SituationSettings(enabled: false));
      addTearDown(s.dispose);
      s.observeBroadcast('화재가 발생했습니다.');
      final hazard = s.flow.active;
      s.receiveSign('구조');
      expect(s.helpOpen, isTrue);
      expect(s.deferredHelp, isFalse);
      expect(s.flow.active, same(hazard));
      s.openHelp();
      s.cancelHelp();
      expect(s.flow.active, same(hazard));
      expect(hazard!.acknowledged, isFalse);
    },
  );
  test(
    'simulated inputs and stale sign state do not leak back to the real mode',
    () {
      final s = SituationService(settings: SituationSettings(enabled: false));
      addTearDown(s.dispose);
      s.startScenarioTest(HouseScenario.assistance, '가족 도움');
      s.receiveSign('구조');
      expect(s.helpSign, '구조');
      s.receiveSign('아프다', simulated: true);
      expect(s.helpSign, '아프다');
      s.endScenarioTest();
      expect(s.pendingSign, isEmpty);
      expect(s.helpSign, isEmpty);
      expect(s.liveFlow.active, isNull);
    },
  );

  test('real camera signs operate a test window without sending live alarms', () {
    final s = SituationService(settings: SituationSettings(enabled: false));
    addTearDown(s.dispose);
    var alarms = 0;
    s.onScenarioAlert = () => alarms++;
    s.startScenarioTest(HouseScenario.assistance, '테스트');
    final before = alarms;
    s.receiveSign('쓰러지다');
    expect(s.helpOpen, isTrue);
    expect(alarms, before);
    s.receiveSign('괜찮다');
    expect(s.helpOpen, isFalse);
    expect(s.flow.active, isNull);
    expect(s.liveFlow.active, isNull);
  });

  test('okay sign uses the same acknowledgement callback as touch', () {
    final s = SituationService(settings: SituationSettings(enabled: false));
    addTearDown(s.dispose);
    var acknowledgements = 0;
    s.onSignAcknowledge = () {
      acknowledgements++;
      s.acknowledge();
    };
    s.receiveSign('구조');
    s.receiveSign('괜찮다');
    expect(acknowledgements, 1);
    expect(s.helpOpen, isFalse);
    expect(s.flow.active, isNull);
  });
}
