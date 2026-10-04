import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safehub_app/config/app_config.dart';
import 'package:safehub_app/ui/connection_settings_page.dart';

void main() {
  late Directory directory;
  late String configPath;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('safehub-settings-test-');
    configPath =
        '${directory.path}${Platform.pathSeparator}connection-settings.json';
    await AppConfig.load(filePath: configPath);
  });

  tearDown(() async {
    AppConfig.resetForTesting();
    await directory.delete(recursive: true);
  });

  test(
    'unconfigured real services wait without requiring placeholder addresses',
    () {
      expect(AppConfig.validate, returnsNormally);
      expect(AppConfig.mqttConfigured, isFalse);
      expect(AppConfig.cameraConfigured, isFalse);
      expect(AppConfig.disasterConfigured, isFalse);
      expect(AppConfig.mqttPort, 1883);
      expect(AppConfig.cameraPort, 5000);
      expect(AppConfig.csiServiceUrl, 'http://127.0.0.1:8765');
      expect(AppConfig.setupError, isNull);
      expect(File(configPath).existsSync(), isFalse);
    },
  );

  test(
    'persists service settings separately from the API secret and reloads',
    () async {
      final values = {
        ...AppConfig.settings,
        'MQTT_BROKER': '192.168.0.10',
        'MQTT_PORT': '1884',
        'CAMERA_HOST': 'raspberrypi.local',
        'CAMERA_PORT': '5001',
        'TTS_SERVER_URL': 'http://192.168.0.10:8000',
        'DISASTER_API_URL': 'https://example.invalid/api',
        'DISASTER_API_KEY': '  sample-key="quoted"#value  ',
      };
      await AppConfig.save(values);
      final json = jsonDecode(await File(configPath).readAsString()) as Map;
      expect(json.containsKey('DISASTER_API_KEY'), isFalse);
      expect(
        (await File(configPath).readAsString()).contains('sample-key'),
        isFalse,
      );
      expect(File(AppConfig.secretFilePath).existsSync(), isTrue);
      await AppConfig.load(filePath: configPath);
      expect(AppConfig.mqttBroker, '192.168.0.10');
      expect(AppConfig.mqttPort, 1884);
      expect(AppConfig.cameraHost, 'raspberrypi.local');
      expect(AppConfig.cameraPort, 5001);
      expect(AppConfig.disasterApiKey, values['DISASTER_API_KEY']);
      expect(AppConfig.disasterConfigured, isTrue);
      expect(
        directory.listSync().where((file) => file.path.endsWith('.tmp')),
        isEmpty,
      );
    },
  );

  test('removing addresses is persisted and disables those services', () async {
    await AppConfig.save({...AppConfig.settings, 'MQTT_BROKER': 'host.local'});
    await AppConfig.save({...AppConfig.settings, 'MQTT_BROKER': ''});
    await AppConfig.load(filePath: configPath);
    expect(AppConfig.mqttConfigured, isFalse);
    expect(AppConfig.validate, returnsNormally);
  });

  test(
    'rejects malformed hosts, URL credentials, invalid ports and multiline keys',
    () async {
      final invalid = {
        ...AppConfig.settings,
        'MQTT_BROKER': 'mqtt://user:password@host',
        'MQTT_PORT': 'not-a-number',
        'CAMERA_HOST': 'host:5000',
        'CAMERA_PORT': '65536',
        'TTS_SERVER_URL': 'https://user:password@example.invalid',
        'STT_SERVER_URL': 'file:///tmp/file',
        'DISASTER_API_KEY': 'sample-secret\nSECOND_KEY=value',
      };
      final errors = AppConfig.validateValues(invalid);
      expect(
        errors.keys,
        containsAll([
          'MQTT_BROKER',
          'MQTT_PORT',
          'CAMERA_HOST',
          'CAMERA_PORT',
          'TTS_SERVER_URL',
          'STT_SERVER_URL',
          'DISASTER_API_KEY',
        ]),
      );
      expect(errors.values.join(), isNot(contains('sample-secret')));
      await expectLater(AppConfig.save(invalid), throwsFormatException);
      expect(File(configPath).existsSync(), isFalse);
      expect(File(AppConfig.secretFilePath).existsSync(), isFalse);
    },
  );

  test('URL validation safely rejects malformed ports and IPv6 addresses', () {
    for (final url in [
      'http://localhost:abc',
      'http://[broken',
      'http://localhost:0',
      'http://localhost:99999999999999999999999',
    ]) {
      expect(
        AppConfig.validateValues({
          ...AppConfig.settings,
          'CSI_SERVICE_URL': url,
        }),
        contains('CSI_SERVICE_URL'),
      );
    }
  });

  test(
    'bad settings leave a readable error without leaking file content',
    () async {
      await File(
        configPath,
      ).writeAsString('{"DISASTER_API_KEY":"sample-secret", broken');
      await AppConfig.load(filePath: configPath);
      expect(AppConfig.setupError, isNotNull);
      expect(AppConfig.setupError, isNot(contains('sample-secret')));
      expect(AppConfig.mqttConfigured, isFalse);
      expect(AppConfig.validate, returnsNormally);
    },
  );

  test(
    'legacy JSON secret is migrated and other env entries survive key deletion',
    () async {
      await File(
        configPath,
      ).writeAsString(jsonEncode({'DISASTER_API_KEY': 'legacy-key'}));
      await AppConfig.load(filePath: configPath);
      expect(AppConfig.disasterApiKey, 'legacy-key');
      await AppConfig.save(AppConfig.settings);
      expect(
        (jsonDecode(await File(configPath).readAsString()) as Map).containsKey(
          'DISASTER_API_KEY',
        ),
        isFalse,
      );
      final secretFile = File(AppConfig.secretFilePath);
      await secretFile.writeAsString(
        'OTHER_VALUE=keep\n',
        mode: FileMode.append,
      );
      await AppConfig.save({...AppConfig.settings, 'DISASTER_API_KEY': ''});
      expect(await secretFile.readAsString(), 'OTHER_VALUE=keep\n');
      await AppConfig.load(filePath: configPath);
      expect(AppConfig.disasterApiKey, isEmpty);
    },
  );

  test(
    'failed config replacement restores the old secret and in-memory state',
    () async {
      await File(
        AppConfig.secretFilePath,
      ).writeAsString('DISASTER_API_KEY="old-key"\n');
      await AppConfig.load(filePath: configPath);
      await Directory(configPath).create();
      await expectLater(
        AppConfig.save({...AppConfig.settings, 'DISASTER_API_KEY': 'new-key'}),
        throwsA(isA<FileSystemException>()),
      );
      expect(AppConfig.disasterApiKey, 'old-key');
      expect(
        await File(AppConfig.secretFilePath).readAsString(),
        'DISASTER_API_KEY="old-key"\n',
      );
    },
  );

  testWidgets('settings masks keys and prevents saving an invalid host', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ConnectionSettingsPage()));
    final keyField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('DISASTER_API_KEY')),
        matching: find.byType(TextField),
      ),
    );
    expect(keyField.obscureText, isTrue);
    await tester.enterText(
      find.byKey(const ValueKey('MQTT_BROKER')),
      'http://broker',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('save_connection_settings')),
    );
    await tester.tap(find.byKey(const ValueKey('save_connection_settings')));
    await tester.pumpAndSettle();
    expect(find.text('주소만 입력하세요. 프로토콜·포트·계정 정보는 제외하세요.'), findsOneWidget);
    expect(
      tester
          .getRect(find.byKey(const ValueKey('MQTT_BROKER')))
          .overlaps(
            Offset.zero &
                tester.view.physicalSize / tester.view.devicePixelRatio,
          ),
      isTrue,
      reason:
          'The invalid field must be visible after saving from the bottom of the form.',
    );
    expect(File(configPath).existsSync(), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'back navigation waits until an in-progress settings save completes',
    (tester) async {
      bool? saved;
      final writeComplete = Completer<void>();
      Map<String, Object?>? pendingValues;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: FilledButton(
                  onPressed: () async {
                    saved = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder:
                            (_) => ConnectionSettingsPage(
                              saveSettings: (values) {
                                pendingValues = values;
                                return writeComplete.future;
                              },
                            ),
                      ),
                    );
                  },
                  child: const Text('설정 열기'),
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('설정 열기'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('save_connection_settings')),
      );
      await tester.tap(find.byKey(const ValueKey('save_connection_settings')));
      await tester.pump();
      await tester.pageBack();
      await tester.pump();
      final route =
          ModalRoute.of(tester.element(find.byType(ConnectionSettingsPage)))!;
      expect(route.isCurrent, isTrue);
      expect(saved, isNull);
      await tester.runAsync(() async {
        await AppConfig.save(pendingValues!);
      });
      writeComplete.complete();
      await tester.pumpAndSettle();
      expect(saved, isTrue);
      expect(File(configPath).existsSync(), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saving optional empty services returns true to the home screen',
    (tester) async {
      bool? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: FilledButton(
                  onPressed: () async {
                    saved = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => const ConnectionSettingsPage(),
                      ),
                    );
                  },
                  child: const Text('설정 열기'),
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('설정 열기'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('save_connection_settings')),
      );
      await tester.runAsync(() async {
        await tester.tap(
          find.byKey(const ValueKey('save_connection_settings')),
        );
        for (var count = 0; count < 100 && saved == null; count++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(saved, isTrue);
      expect(File(configPath).existsSync(), isTrue);
      expect(AppConfig.mqttConfigured, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
