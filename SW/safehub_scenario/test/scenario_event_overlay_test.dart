import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safehub_app/core/house_scenario.dart';
import 'package:safehub_app/services/situation_service.dart';
import 'package:safehub_app/ui/widgets/scenario_event_overlay.dart';

Widget host(SituationService service) => MaterialApp(
  home: Scaffold(
    body: Stack(
      children: [
        const Center(child: Text('SafeHub 홈')),
        AnimatedBuilder(
          animation: service,
          builder: (_, __) => service.flow.active == null
              ? const SizedBox.shrink()
              : ScenarioEventOverlay(
                  key: ValueKey(service.flow.active),
                  service: service,
                  camera: const ColoredBox(
                    color: Colors.black,
                    child: Center(child: Text('연결된 수어 카메라')),
                  ),
                  onAcknowledge: service.acknowledge,
                  onSignal: () => service.flow.setDelivery('테스트 · 실제 명령 없음'),
                ),
        ),
      ],
    ),
  ),
);

SituationService createService() => SituationService(
  settings: SituationSettings(enabled: false, address: '테스트시 안심로 10, 101호'),
);

Future<void> mount(WidgetTester t, SituationService s) async {
  t.view.physicalSize = const Size(1304, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  addTearDown(s.dispose);
  await t.pumpWidget(host(s));
  await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, String label) async {
  await t.ensureVisible(find.text(label));
  await t.tap(find.text(label));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('unsent 119 report opens a sign-video demonstration with address and live signs', (t) async {
    final s = createService();
    s.settings.address = '영남대학교 멋쟁이들 집';
    s.receiveSign('쓰러지다');
    await mount(t, s);
    await t.pump(const Duration(seconds: 7));
    await t.pumpAndSettle();
    expect(find.text('119 수어·영상 신고'), findsOneWidget);
    expect(find.text('연결된 수어 카메라'), findsOneWidget);
    expect(find.text('영남대학교 멋쟁이들 집'), findsOneWidget);
    expect(find.text('시연 · 119 및 수어통역사 미연결'), findsOneWidget);
    s.receiveSign('구조');
    await t.pumpAndSettle();
    expect(find.text('구조'), findsOneWidget);
    s.receiveSign('괜찮다');
    await t.pumpAndSettle();
    expect(find.byType(ScenarioEventOverlay), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('collapse selects another person and opens unsent report after seven seconds', (t) async {
    final s = createService();
    s.receiveSign('쓰러지다');
    await mount(t, s);
    final selection = t.widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>));
    expect(selection.selected, {'다른 사람'});
    expect(find.text('불러도 반응이 있나요?'), findsOneWidget);
    await t.pump(const Duration(seconds: 6));
    expect(find.text('내용 복사'), findsNothing);
    // A repeated observation of the same sign must not reset the deadline.
    s.receiveSign('쓰러짐');
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    expect(find.text('119 수어·영상 신고'), findsOneWidget);
    await tap(t, '신고 내용으로 돌아가기');
    expect(find.text('내용 복사'), findsOneWidget);
    expect(find.textContaining('119 신고 내용 · 미전송'), findsOneWidget);
    expect(find.textContaining('의식 상태는 미확인'), findsOneWidget);
    expect(find.textContaining('불러도 반응이 있는지: 미확인'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('okay sign cancels the report deadline and closes help', (t) async {
    final s = createService();
    s.receiveSign('쓰러졌어요');
    await mount(t, s);
    await t.pump(const Duration(seconds: 6));
    s.receiveSign('괜찮다');
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 8));
    expect(find.byType(ScenarioEventOverlay), findsNothing);
    expect(s.flow.active, isNull);
  });

  testWidgets('explicit reaction selection cancels automatic report', (t) async {
    final s = createService();
    s.receiveSign('쓰러지다');
    await mount(t, s);
    await tap(t, '반응 있어요');
    await t.pump(const Duration(seconds: 8));
    expect(find.text('내용 복사'), findsNothing);
    expect(find.text('자동 전환 취소'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('collapse arriving in an already open help window starts its deadline', (t) async {
    final s = createService();
    s.receiveSign('아프다');
    await mount(t, s);
    await t.pump(const Duration(seconds: 8));
    expect(find.text('내용 복사'), findsNothing);
    s.receiveSign('쓰러지다');
    await t.pump();
    await t.pump(const Duration(seconds: 7));
    await t.pumpAndSettle();
    expect(find.text('119 수어·영상 신고'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('okay sign dismisses the help screen without a tap', (t) async {
    final s = createService();
    s.receiveSign('쓰러지다');
    await mount(t, s);
    expect(find.byType(ScenarioEventOverlay), findsOneWidget);
    s.receiveSign('괜찮다');
    await t.pumpAndSettle();
    expect(find.byType(ScenarioEventOverlay), findsNothing);
    expect(find.text('SafeHub 홈'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'broadcast keeps source, simulated delivery and acknowledgement semantics',
    (t) async {
      final s = createService();
      s.startScenarioTest(HouseScenario.broadcast, '화재가 발생했습니다. 대피하세요.');
      await mount(t, s);
      expect(find.text('SafeHub 홈'), findsOneWidget);
      expect(find.text('화재 관련 안내방송'), findsOneWidget);
      expect(find.text('화재가 발생했습니다. 대피하세요.'), findsOneWidget);
      expect(find.text('화면 테스트 · 실제 장치와 신고는 작동하지 않아요.'), findsOneWidget);
      await tap(t, '시간·알림 전달 상태 보기');
      expect(find.textContaining('실제 명령 없음'), findsOneWidget);
      await tap(t, '방송 확인했어요');
      expect(find.byType(ScenarioEventOverlay), findsNothing);
      expect(s.flow.lastAcknowledged!.toJson()['risk_resolved'], isFalse);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('disaster retains the actual source and region', (t) async {
    final s = createService();
    s.startScenarioTest(HouseScenario.disaster, '시연지역에 지진이 발생했습니다.');
    await mount(t, s);
    expect(find.text('지진 알림이 도착했어요'), findsOneWidget);
    expect(find.textContaining('지역: 시연지역'), findsOneWidget);
    expect(find.text('119 신고 내용 확인'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'unknown response and address remain explicit in an unsent report',
    (t) async {
      final s = createService();
      s.startScenarioTest(HouseScenario.assistance, '보호자 쓰러짐 의심');
      await mount(t, s);
      await tap(t, '119 신고 내용 확인');
      expect(find.textContaining('불러도 반응이 있는지: 미확인'), findsOneWidget);
      expect(find.textContaining('주소: 테스트시 안심로 10, 101호'), findsOneWidget);
      expect(
        find.textContaining('미전송 · 실제 신고·연락 기능은 연결되어 있지 않아요.'),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('new incident clears the old report and response', (t) async {
    final s = createService();
    s.startScenarioTest(HouseScenario.assistance, '보호자 첫 사건');
    await mount(t, s);
    await tap(t, '반응 없어요');
    s.receiveSign('구조', simulated: true);
    await t.pumpAndSettle();
    await tap(t, '119 신고 내용 확인');
    expect(find.text('도움 요청 내용을 확인해 주세요'), findsOneWidget);
    s.acknowledge();
    s.startScenarioTest(HouseScenario.assistance, '다음 사건');
    await t.pumpAndSettle();
    expect(find.text('도움 요청 내용을 확인해 주세요'), findsNothing);
    expect(s.flow.active!.response, isEmpty);
    expect(find.text('119 신고 내용 확인'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'camera and touch are visible together without starting sign capture',
    (t) async {
      final s = createService();
      s.startScenarioTest(HouseScenario.assistance, '보호자 쓰러짐 의심');
      await mount(t, s);
      final camera = t.getRect(find.text('연결된 수어 카메라'));
      final touch = t.getRect(find.text('119 신고 내용 확인'));
      expect(camera.bottom, lessThan(900));
      expect(touch.bottom, lessThan(900));
      expect(camera.left, lessThan(touch.left));
      expect(find.byTooltip('구조 수어 입력 시연'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'repeated help signs stay on one surface and cancellation suppresses repeats',
    (t) async {
      final s = createService();
      s.startScenarioTest(HouseScenario.assistance, '보호자 쓰러짐 의심');
      await mount(t, s);
      s.receiveSign('쓰러짐', simulated: true);
      s.receiveSign('쓰러짐', simulated: true);
      await t.pumpAndSettle();
      expect(find.text('“쓰러짐” 수어를 인식했어요.'), findsOneWidget);
      expect(find.byType(ScenarioEventOverlay), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      await tap(t, '괜찮아요');
      s.receiveSign('쓰러짐', simulated: true);
      await t.pumpAndSettle();
      expect(find.byType(ScenarioEventOverlay), findsNothing);
      s.receiveSign('감사', simulated: true);
      s.receiveSign('도움', simulated: true);
      await t.pumpAndSettle();
      expect(find.text('“도움” 수어를 인식했어요.'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('ending an incident removes its help surface', (t) async {
    final s = createService();
    s.startScenarioTest(HouseScenario.assistance, '첫 사건');
    await mount(t, s);
    s.receiveSign('구조', simulated: true);
    await t.pumpAndSettle();
    expect(find.text('“구조” 수어를 인식했어요.'), findsOneWidget);
    s.acknowledge();
    await t.pumpAndSettle();
    expect(find.byType(ScenarioEventOverlay), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('every event surface has an accessible close control', (t) async {
    final s = createService();
    await mount(t, s);
    for (final kind in HouseScenario.values) {
      s.startScenarioTest(kind, '화재가 발생했습니다.');
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('알림 창 닫기').hitTestable());
      await t.pumpAndSettle();
      expect(find.byType(ScenarioEventOverlay), findsNothing);
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('cancelling help preserves a simultaneous fire hazard', (
    t,
  ) async {
    final s = createService();
    s.startScenarioTest(HouseScenario.broadcast, '화재가 발생했습니다.');
    final hazard = s.flow.active;
    await mount(t, s);
    await tap(t, '도움이 필요해요');
    await tap(t, '괜찮아요');
    expect(s.flow.active, same(hazard));
    expect(hazard!.acknowledged, isFalse);
    expect(find.text('화재 관련 안내방송'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'report returns to choice and close without claiming transmission',
    (t) async {
      final s = createService();
      s.startScenarioTest(HouseScenario.assistance, '보호자 쓰러짐 의심');
      await mount(t, s);
      await tap(t, '119 신고 내용 확인');
      expect(find.text('내용 복사'), findsOneWidget);
      expect(find.text('신고하기'), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      await tap(t, '다시 선택하기');
      expect(find.text('119 신고 내용 확인'), findsOneWidget);
      await tap(t, '가족에게 전할 내용 확인');
      expect(find.textContaining('가족에게 전할 내용 · 미전송'), findsOneWidget);
      await tap(t, '확인하고 돌아가기');
      expect(find.byType(ScenarioEventOverlay), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
}
