import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safehub_app/ui/home_page.dart';
import 'package:safehub_app/ui/theme/app_theme.dart';

void main() {
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
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
    expect(find.text('화면 동작 미리보기 · 실제 감지나 가족 전송이 아닙니다'), findsOneWidget);
    expect(find.text('공간별 상태'), findsOneWidget);
    expect(find.text('경보 시스템'), findsOneWidget);
    await press(tester, '의사소통 화면 열기');
    expect(find.text('수어 카메라'), findsWidgets);
    expect(find.text('대화 기록'), findsOneWidget);
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

  testWidgets('기존 의사소통 화면에서 직접 입력과 대화 기록을 사용한다', (tester) async {
    await open(tester);
    await press(tester, '의사소통 화면 열기');
    final recording = tester.getRect(find.text('음성 녹음 시작'));
    expect(recording.bottom, lessThan(940));
    await press(tester, '직접 입력');
    await tester.enterText(find.byType(TextField), '잠깐 쉬고 싶어요');
    await press(tester, '대화에 추가');
    expect(find.byType(TextField), findsNothing);
    await press(tester, '대화 기록');
    expect(find.textContaining('잠깐 쉬고 싶어요'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('시간 초과 뒤 늦은 정상 응답은 미전송 요청을 해제한다', (tester) async {
    await open(tester);
    await press(tester, '낙상 테스트');
    await press(tester, '테스트 · 시간 종료');
    expect(find.text('전송되지 않음 · 가족 알림 서비스 미연결'), findsOneWidget);
    await press(tester, '괜찮아요');
    expect(find.text('화장실에서 낙상이 의심돼요'), findsNothing);
    await tester.tap(find.byTooltip('안전 알림 설정'));
    await tester.pump();
    expect(find.text('도움 요청 0건 · 실제 전송되지 않음'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await close(tester);
  });
}
