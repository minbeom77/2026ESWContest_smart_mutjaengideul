import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safehub_app/ui/home_page.dart';
import 'package:safehub_app/ui/theme/app_theme.dart';

void main() {
  for (final size in const [
    Size(800, 480),
    Size(900, 600),
    Size(1280, 720),
  ]) {
    testWidgets('home and sign navigation at $size', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const SafeHubHomePage(enableServices: false),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('생활 안전 현황'), findsOneWidget);
      expect(find.textContaining('센서 상태 미확인'), findsOneWidget);
      expect(find.textContaining('침실 · 정상'), findsNothing);
      expect(find.textContaining('화장실 · 정상'), findsNothing);

      final launch = find.text('번역 시작');
      await tester.ensureVisible(launch);
      await tester.pumpAndSettle();
      await tester.tap(launch);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('카메라 미리보기'), findsOneWidget);
      expect(find.text('수어 인식 대기 중'), findsOneWidget);

      final back = find.text('홈');
      await tester.ensureVisible(back);
      await tester.pumpAndSettle();
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(find.text('생활 안전 현황'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
