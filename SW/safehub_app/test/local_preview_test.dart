import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safehub_app/config/app_config.dart';
import 'package:safehub_app/main.dart';
import 'package:safehub_app/ui/connection_settings_page.dart';
import 'package:safehub_app/ui/home_page.dart';

void mockAudioPlugins(WidgetTester tester) {
  final messenger = tester.binding.defaultBinaryMessenger;
  final channels = <String>{};
  void mockChannel(String name, [Future<Object?> Function(MethodCall)? call]) {
    channels.add(name);
    messenger.setMockMethodCallHandler(
      MethodChannel(name),
      call ?? (_) async => null,
    );
  }

  mockChannel('xyz.luan/audioplayers.global');
  mockChannel('xyz.luan/audioplayers.global/events');
  mockChannel('xyz.luan/audioplayers', (call) async {
    if (call.method == 'create') {
      mockChannel('xyz.luan/audioplayers/events/${call.arguments['playerId']}');
    }
    return null;
  });
  mockChannel('com.llfbandit.record/messages', (call) async {
    if (call.method == 'create') {
      mockChannel(
        'com.llfbandit.record/events/${call.arguments['recorderId']}',
      );
    }
    return null;
  });
  addTearDown(() {
    for (final name in channels) {
      messenger.setMockMethodCallHandler(MethodChannel(name), null);
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('unconfigured services may wait in either mode', () {
    expect(AppConfig.validate, returnsNormally);
  });

  testWidgets(
    'opens without devices and disposes an unconnected MQTT receiver',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Native audio plugins are outside this device-free UI test.
      mockAudioPlugins(tester);

      await tester.pumpWidget(const SafeHubApp());
      await tester.pump();
      expect(
        find.textContaining(
          AppConfig.localPreview ? '장비 연결 전 체험 ·' : '실제 장비 연결 모드 ·',
        ),
        findsOneWidget,
      );
      expect(find.text('연결 설정'), findsOneWidget);
      expect(find.text('수어 인식 대기 중'), findsOneWidget);
      expect(find.text('신호 수집 · 모델 관리'), findsOneWidget);
      expect(find.text('연결 중'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('신호 수집 · 모델 관리'));
      await tester.pump();
      expect(find.text('1. 신호 수집'), findsOneWidget);
      expect(find.text('2. 기록 · 학습'), findsOneWidget);
      expect(find.text('3. 현재 행동'), findsOneWidget);
      expect(
        find.text('장비 없이 모의 신호'),
        AppConfig.localPreview ? findsOneWidget : findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saving connection settings recreates home and keeps missing devices waiting',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      mockAudioPlugins(tester);

      late Directory directory;
      late String configPath;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp(
          'safehub-home-settings-',
        );
        configPath =
            '${directory.path}${Platform.pathSeparator}connection-settings.json';
        await AppConfig.load(filePath: configPath);
      });
      addTearDown(() async {
        AppConfig.resetForTesting();
        await directory.delete(recursive: true);
      });

      await tester.pumpWidget(const SafeHubApp());
      await tester.pump();
      final previousHomeState = tester.state(find.byType(SafeHubHomePage));
      await tester.tap(find.text('연결 설정'));
      await tester.pumpAndSettle();
      expect(find.byType(ConnectionSettingsPage), findsOneWidget);
      for (final key in [
        'MQTT_BROKER',
        'CAMERA_HOST',
        'TTS_SERVER_URL',
        'STT_SERVER_URL',
        'DISASTER_API_URL',
        'DISASTER_API_KEY',
      ]) {
        expect(
          tester
              .widget<TextFormField>(find.byKey(ValueKey(key)))
              .controller!
              .text,
          isEmpty,
        );
      }
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('CSI_SERVICE_URL')),
            )
            .controller!
            .text,
        'http://127.0.0.1:8765',
      );

      final settingsRoute =
          ModalRoute.of(tester.element(find.byType(ConnectionSettingsPage)))!;
      await tester.ensureVisible(
        find.byKey(const ValueKey('save_connection_settings')),
      );
      await tester.runAsync(() async {
        await tester.tap(
          find.byKey(const ValueKey('save_connection_settings')),
        );
        for (var count = 0; count < 100 && settingsRoute.isCurrent; count++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();

      expect(find.byType(ConnectionSettingsPage), findsNothing);
      expect(
        identical(
          tester.state(find.byType(SafeHubHomePage)),
          previousHomeState,
        ),
        isFalse,
      );
      expect(previousHomeState.mounted, isFalse);
      expect(File(configPath).existsSync(), isTrue);
      expect(AppConfig.mqttConfigured, isFalse);
      expect(AppConfig.cameraConfigured, isFalse);
      expect(AppConfig.disasterConfigured, isFalse);
      expect(AppConfig.csiServiceUrl, 'http://127.0.0.1:8765');
      expect(find.text('수어 인식 대기 중'), findsOneWidget);
      expect(find.text('연결 중'), findsNothing);
      expect(
        find.textContaining(
          AppConfig.localPreview ? '장비 연결 전 체험 ·' : '실제 장비 연결 모드 ·',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
