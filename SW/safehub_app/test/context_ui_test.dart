import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safehub_app/ui/home_page.dart';
import 'package:safehub_app/ui/theme/app_theme.dart';

void main() {
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: const SafeHubHomePage(demo: true),
    ));
    await tester.pump();
  }

  Future<void> press(WidgetTester tester, String label) async {
    final target = find.text(label).last;
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pump();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('홈에서 대화로 이동하고 실제 장치 연결을 주장하지 않는다', (tester) async {
    await open(tester);
    expect(find.text('UI 테스트 · 실제 장치 연결 없음'), findsOneWidget);
    expect(find.text('상태 확인 미연동'), findsOneWidget);
    await press(tester, '대화 시작하기');
    expect(find.text('지난 대화'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('한 낙상에 대한 응답이 다음 낙상을 종료하지 않는다', (tester) async {
    await open(tester);
    await press(tester, '낙상 테스트');
    await press(tester, '테스트 · 다음 낙상');
    expect(find.text('다음 확인 알림 1건'), findsOneWidget);
    await press(tester, '괜찮아요');
    expect(find.text('화장실에서 낙상이 의심돼요'), findsOneWidget);
    expect(find.text('다음 확인 알림 1건'), findsNothing);
    await press(tester, '괜찮아요');
    expect(find.text('화장실에서 낙상이 의심돼요'), findsNothing);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('대화에서 자막과 녹음 버튼을 스크롤 없이 확인한다', (tester) async {
    await open(tester);
    await press(tester, '대화 시작하기');
    for (final label in ['수어 인식 대기 중', '아직 가족의 음성 자막이 없어요.', '가족 말하기 시작']) {
      final rect = tester.getRect(find.text(label));
      expect(rect.top, greaterThanOrEqualTo(0), reason: label);
      expect(rect.bottom, lessThan(620), reason: label);
    }
    expect(find.text('아직 대화 기록이 없어요.'), findsNothing);
    await press(tester, '지난 대화');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('아직 대화 기록이 없어요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('시간 초과 뒤 늦은 정상 응답은 미전송 요청을 해제한다', (tester) async {
    await open(tester);
    await press(tester, '낙상 테스트');
    await press(tester, '테스트 · 시간 종료');
    expect(find.text('전송되지 않음 · 가족 알림 서비스 미연결'), findsOneWidget);
    await press(tester, '괜찮아요');
    expect(find.text('전달되지 않은 도움 요청이 있어요'), findsNothing);
    expect(tester.takeException(), isNull);
    await close(tester);
  });
}
