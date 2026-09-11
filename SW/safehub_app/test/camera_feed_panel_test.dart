import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safehub_app/ui/widgets/camera_feed_panel.dart';

void main() {
  for (final width in <double>[320, 800, 900, 1280]) {
    testWidgets('camera placeholder fits width $width', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CameraFeedPanel(streamUrl: ''),
              ),
            ),
          ),
        ),
      );

      expect(find.text('카메라 미리보기'), findsOneWidget);
      expect(find.text('영상 주소가 설정되지 않았습니다.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('configured URL does not imply a live connection', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CameraFeedPanel(
            streamUrl: 'http://127.0.0.1:8080/stream',
          ),
        ),
      ),
    );

    expect(find.text('RPi4 CAMERA · 영상 미연결'), findsOneWidget);
    expect(find.text('영상 주소 설정됨 · 수신 기능 연결 예정'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
