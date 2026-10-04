import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safehub_app/config/app_config.dart';
import 'package:safehub_app/main.dart';
import 'package:safehub_app/services/live_caption_service.dart';
import 'package:safehub_app/ui/widgets/live_caption_panel.dart';

import 'local_preview_test.dart' show mockAudioPlugins;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fonts = FontLoader('Pretendard');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      fonts.addFont(rootBundle.load('assets/fonts/Pretendard-$weight.otf'));
    }
    await fonts.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  testWidgets('microphone start stays busy while permission is pending', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    mockAudioPlugins(tester);
    final permission = Completer<bool>();
    var permissionRequests = 0;
    final messenger = tester.binding.defaultBinaryMessenger;
    final recorderChannels = <String>{};
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      (call) async {
        if (call.method == 'create') {
          final channel =
              'com.llfbandit.record/events/${call.arguments['recorderId']}';
          recorderChannels.add(channel);
          messenger.setMockMethodCallHandler(
            MethodChannel(channel),
            (_) async => null,
          );
        }
        if (call.method == 'isRecording') return false;
        if (call.method == 'hasPermission') {
          permissionRequests++;
          return permission.future;
        }
        return null;
      },
    );
    addTearDown(() {
      for (final channel in recorderChannels) {
        messenger.setMockMethodCallHandler(MethodChannel(channel), null);
      }
    });
    late Directory directory;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp('safehub-mic-ui-');
      await AppConfig.load(filePath: '${directory.path}/settings.json');
      await AppConfig.save({
        ...AppConfig.settings,
        'STT_SERVER_URL': 'http://127.0.0.1:1',
      });
    });
    addTearDown(() async {
      AppConfig.resetForTesting();
      await directory.delete(recursive: true);
    });
    final captions = LiveCaptionService(transcribe: (_) async => '');
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: LiveCaptionPanel(service: captions, configured: true))));
    unawaited(captions.start());
    await tester.pump();
    expect(find.text('마이크 준비 중'), findsWidgets);
    expect(find.text('음성 녹음 시작'), findsNothing);
    expect(permissionRequests, 1);
    permission.complete(false);
    await tester.pump();
    await tester.pump();
    expect(find.text('자막 다시 시작'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await captions.close();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(1920, 1080),
    const Size(1024, 600),
    const Size(800, 480),
    const Size(600, 800),
  ]) {
    testWidgets('home and communication fit ${size.width} by ${size.height}', (
      tester,
    ) async {
      AppConfig.resetForTesting();
      addTearDown(AppConfig.resetForTesting);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      mockAudioPlugins(tester);
      final captureKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(key: captureKey, child: const SafeHubApp()),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('경보 · 재난 알림'), findsOneWidget);
      expect(find.text('실시간 음성 자막'), findsOneWidget);
      if (Platform.environment['SAFEHUB_CAPTURE_UI'] == '1') {
        await tester.pump(const Duration(milliseconds: 400));
        await tester.runAsync(() async {
          final boundary = captureKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            'home-${size.width.toInt()}x${size.height.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.ensureVisible(find.text('의사소통 화면 열기'));
      await tester.tap(find.text('의사소통 화면 열기'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('홈으로'));
      await tester.pump();
      expect(find.text('의사소통 화면 열기'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
