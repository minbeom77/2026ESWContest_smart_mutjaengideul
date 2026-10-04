import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safehub_app/services/wifi_sensing_service.dart';
import 'package:safehub_app/ui/widgets/wifi_sensing_panel.dart';

http.Response utf8Response(
  String body,
  int status, {
  Map<String, String>? headers,
}) => http.Response(
  body,
  status,
  headers: {'content-type': 'application/json; charset=utf-8', ...?headers},
);

Map<String, dynamic> fixture() => {
  'mode': 'dummy',
  'fresh': true,
  'connected': true,
  'error': '모의 신호',
  'rate_hz': 60.0,
  'behaviors': ['정지', '낙상', '걷기'],
  'records': [
    for (var i = 0; i < 3; i++)
      {
        'id': 'record-$i',
        'label': i == 0 ? '정지' : '걷기',
        'duration': 8.0,
        'experiment_id': '회차 ${i + 1}',
        'collection': {'mode': 'dummy'},
      },
  ],
  'models': [],
  'model': null,
  'training': {'state': 'idle'},
  'training_allowed': true,
  'capture': null,
  'recognition': {'running': false, 'result': null, 'reason': '모델을 선택하세요.'},
  'waveform': {
    'signal': List.generate(
      240,
      (i) => math.sin(i / 14) * .6 + math.sin(i / 35) * .2,
    ),
  },
};

void main() {
  Future<void> mount(
    WidgetTester tester,
    WifiSensingService service, {
    bool allowDummy = true,
  }) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(service.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WifiSensingPanel(service: service, allowDummy: allowDummy),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'real mode cannot send record or behavior commands to a rejected service',
    (tester) async {
      final requests = <http.Request>[];
      final service = WifiSensingService(
        baseUrl: 'http://127.0.0.1',
        client: MockClient((request) async {
          requests.add(request);
          return utf8Response(
            jsonEncode(request.url.path == '/ports' ? [] : fixture()),
            200,
          );
        }),
      );
      await mount(tester, service, allowDummy: false);
      await tester.ensureVisible(find.text('행동 추가'));
      await tester.tap(find.text('행동 추가'));
      await tester.pump();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.text('2. 기록 · 학습'));
      await tester.pump();
      await tester.tap(find.text('기록 가져오기'));
      await tester.pump();
      expect(find.byType(AlertDialog), findsNothing);
      expect(requests.every((request) => request.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'malformed state removes an old result without crashing the panel',
    (tester) async {
      final state = fixture();
      final service = WifiSensingService(
        baseUrl: 'http://127.0.0.1',
        client: MockClient(
          (request) async => utf8Response(
            jsonEncode(request.url.path == '/ports' ? [] : state),
            200,
          ),
        ),
      );
      await mount(tester, service);
      state['rate_hz'] = 'broken';
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(find.textContaining('상태 형식이 맞지 않습니다'), findsOneWidget);
      expect(find.text('서비스 대기'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'ports recover automatically after startup failure and hot plug',
    (tester) async {
      var portRequests = 0;
      final state =
          fixture()..addAll({
            'mode': 'live',
            'connected': false,
            'fresh': false,
            'waveform': null,
          });
      final service = WifiSensingService(
        baseUrl: 'http://127.0.0.1',
        client: MockClient((request) async {
          if (request.url.path == '/ports') {
            if (++portRequests == 1) throw const SocketException('starting');
            return utf8Response(
              '[{"port":"COM7","name":"ESP32 receiver"}]',
              200,
            );
          }
          return utf8Response(jsonEncode(state), 200);
        }),
      );
      await mount(tester, service);
      expect(find.textContaining('USB 포트 목록을 확인하지 못했습니다'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(portRequests, 2);
      expect(find.text('COM7'), findsOneWidget);
      expect(find.textContaining('USB 포트 목록을 확인하지 못했습니다'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a stage toggle queues the latest request behind an older poll', (
    tester,
  ) async {
    final first = Completer<http.Response>();
    final queries = <Map<String, String>>[];
    final service = WifiSensingService(
      baseUrl: 'http://127.0.0.1',
      client: MockClient((request) async {
        if (request.url.path == '/ports') return utf8Response('[]', 200);
        queries.add(request.url.queryParameters);
        if (queries.length == 1) return first.future;
        return utf8Response(jsonEncode(fixture()), 200);
      }),
    );
    await mount(tester, service);
    await tester.tap(find.text('원본 보기'));
    await tester.pump();
    expect(queries.length, 1);
    first.complete(utf8Response(jsonEncode(fixture()), 200));
    await tester.pump();
    await tester.pump();
    expect(queries.length, 2);
    expect(queries.last['denoise'], 'false');
    expect(queries.last['pca'], 'false');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an old poll cannot restore connected state after disconnect', (
    tester,
  ) async {
    final stale = Completer<http.Response>();
    var polls = 0;
    var disconnected = false;
    final service = WifiSensingService(
      baseUrl: 'http://127.0.0.1',
      client: MockClient((request) async {
        if (request.url.path == '/ports') return utf8Response('[]', 200);
        if (request.method == 'POST') {
          disconnected = true;
          return utf8Response('{"ok":true}', 200);
        }
        if (++polls == 2) return stale.future;
        final value = fixture();
        if (disconnected)
          value.addAll({'connected': false, 'fresh': false, 'waveform': null});
        return utf8Response(jsonEncode(value), 200);
      }),
    );
    await mount(tester, service);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('연결 해제'));
    await tester.pump();
    stale.complete(utf8Response(jsonEncode(fixture()), 200));
    await tester.pump();
    await tester.pump();
    expect(polls, 3);
    expect(find.text('연결 해제'), findsNothing);
    expect(find.text('실제 신호 연결'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'a command timeout polls its outcome and never retries the command',
    (tester) async {
      final pending = Completer<http.Response>();
      var posted = 0;
      final service = WifiSensingService(
        baseUrl: 'http://127.0.0.1',
        requestTimeout: const Duration(milliseconds: 100),
        client: MockClient((request) async {
          if (request.url.path == '/ports') return utf8Response('[]', 200);
          if (request.method == 'POST') {
            posted++;
            return pending.future;
          }
          final state = fixture();
          if (posted > 0)
            state.addAll({
              'connected': false,
              'fresh': false,
              'waveform': null,
            });
          return utf8Response(jsonEncode(state), 200);
        }),
      );
      await mount(tester, service);
      await tester.tap(find.text('연결 해제'));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();
      expect(find.textContaining('명령이 이미 적용됐을 수'), findsOneWidget);
      expect(find.text('연결 해제'), findsNothing);
      await tester.pump(const Duration(milliseconds: 600));
      expect(posted, 1);
      pending.complete(utf8Response('{"ok":true}', 200));
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('delete completion after leaving the panel does not setState', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final service = WifiSensingService(
      baseUrl: 'http://127.0.0.1',
      client: MockClient((request) async {
        if (request.method == 'POST') return pending.future;
        return utf8Response(
          jsonEncode(request.url.path == '/ports' ? [] : fixture()),
          200,
        );
      }),
    );
    await mount(tester, service);
    await tester.tap(find.text('2. 기록 · 학습'));
    await tester.pump();
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    await tester.tap(find.text('선택 1개 삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    pending.complete(utf8Response('{"ok":true}', 200));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('storage warnings leave healthy records and sensing usable', (
    tester,
  ) async {
    final state =
        fixture()
          ..['storage_warnings'] = List.generate(
            5,
            (i) => '손상된 저장 파일 ${i + 1}',
          );
    final service = WifiSensingService(
      baseUrl: 'http://127.0.0.1',
      client: MockClient(
        (request) async => utf8Response(
          jsonEncode(request.url.path == '/ports' ? [] : state),
          200,
        ),
      ),
    );
    await mount(tester, service);
    expect(find.textContaining('추가 알림 2개'), findsOneWidget);
    expect(find.textContaining('손상된 저장 파일 5'), findsNothing);
    await tester.tap(find.text('2. 기록 · 학습'));
    await tester.pump();
    expect(find.byType(CheckboxListTile), findsNWidgets(3));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final realService in [false, true]) {
    testWidgets('real mode requires a real-only service: $realService', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = fixture();
      if (realService) {
        state.addAll({
          'mode': 'live',
          'dummy_allowed': false,
          'connected': false,
          'fresh': false,
          'waveform': null,
          'records': [],
          'rate_hz': 0.0,
          'error': 'ESP32 연결 대기',
        });
      }
      final requests = <http.Request>[];
      final service = WifiSensingService(
        baseUrl: 'http://127.0.0.1:8766',
        client: MockClient((request) async {
          requests.add(request);
          return utf8Response(
            request.url.path == '/ports' ? '[]' : jsonEncode(state),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WifiSensingPanel(service: service, allowDummy: false),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('장비 없이 모의 신호'), findsNothing);
      expect(
        find.textContaining('실제 수신 전용 CSI 서비스를 연결하세요.'),
        realService ? findsNothing : findsOneWidget,
      );
      if (realService)
        expect(find.textContaining('ESP32 연결 대기'), findsOneWidget);
      expect(requests.every((r) => r.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      service.close();
    });
  }

  testWidgets('stage changes and selected IDs reach the existing engine API', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requests = <http.Request>[];
    final state = fixture();
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/ports') return utf8Response('[]', 200);
      if (request.method == 'POST') {
        return utf8Response('{"ok":true}', 200);
      }
      return utf8Response(
        jsonEncode(state),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final service = WifiSensingService(
      baseUrl: 'http://127.0.0.1:8765',
      client: client,
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: WifiSensingPanel(service: service))),
    );
    await tester.pump();
    await tester.tap(find.text('원본 보기'));
    await tester.pump(const Duration(milliseconds: 600));
    final query =
        requests.lastWhere((r) => r.url.path == '/state').url.queryParameters;
    expect(query['denoise'], 'false');
    expect(query['normalize'], 'false');
    expect(query['pca'], 'false');
    expect(query['lowpass'], 'false');
    await tester.tap(find.text('2. 기록 · 학습'));
    await tester.pump();
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    await tester.ensureVisible(find.text('선택 기록 학습 시작'));
    await tester.tap(find.text('선택 기록 학습 시작'));
    await tester.pump();
    final command = requests.lastWhere((r) => r.url.path == '/command/train');
    expect(jsonDecode(command.body)['ids'], ['record-0']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    service.close();
  });

  for (final size in [const Size(1280, 720), const Size(600, 800)]) {
    testWidgets('Pi-sized panel scrolls without overflow $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = WifiSensingService(
        baseUrl: 'http://127.0.0.1',
        client: MockClient(
          (r) async => utf8Response(
            jsonEncode(r.url.path == '/ports' ? [] : fixture()),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: WifiSensingPanel(service: service),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('모의 신호 사용 중'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('3. 현재 행동'));
      await tester.pump();
      expect(find.text('판단 대기'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      service.close();
    });
  }

  testWidgets('connection failure removes displayed old prediction', (
    tester,
  ) async {
    var fail = false;
    final state = fixture();
    state['recognition'] = {
      'running': true,
      'reason': '인식 중',
      'result': {
        'label': '걷기',
        'scores': {'걷기': .8, '정지': .2},
      },
    };
    final service = WifiSensingService(
      baseUrl: 'http://127.0.0.1',
      client: MockClient((r) async {
        if (fail) throw const SocketException('disconnected');
        return utf8Response(
          jsonEncode(r.url.path == '/ports' ? [] : state),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: WifiSensingPanel(service: service))),
    );
    await tester.pump();
    await tester.tap(find.text('3. 현재 행동'));
    await tester.pump();
    expect(find.text('걷기'), findsNWidgets(2));
    fail = true;
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.text('걷기'), findsNothing);
    expect(find.text('판단 대기'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    service.close();
  });

  testWidgets(
    'monitoring continues while a slow command disables repeat clicks',
    (tester) async {
      final pending = Completer<http.Response>();
      var commands = 0;
      final service = WifiSensingService(
        baseUrl: 'http://127.0.0.1',
        client: MockClient((request) async {
          if (request.url.path == '/ports') return utf8Response('[]', 200);
          if (request.method == 'POST') {
            commands++;
            return pending.future;
          }
          final state = fixture();
          if (commands > 0) state['rate_hz'] = 55;
          return utf8Response(jsonEncode(state), 200);
        }),
      );
      await mount(tester, service);
      await tester.tap(find.text('연결 해제'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(find.textContaining('55.0 Hz'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('연결 해제'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.onPressed, isNull);
      expect(commands, 1);
      pending.complete(utf8Response('{"ok":true}', 200));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('capture page visual evidence', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final loader = FontLoader('Pretendard')
      ..addFont(rootBundle.load('assets/fonts/Pretendard-Regular.otf'));
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final service = WifiSensingService(
      baseUrl: 'http://127.0.0.1',
      client: MockClient(
        (r) async => utf8Response(
          jsonEncode(r.url.path == '/ports' ? [] : fixture()),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: key,
          child: Scaffold(
            backgroundColor: const Color(0xFF393731),
            body: Padding(
              padding: const EdgeInsets.all(28),
              child: WifiSensingPanel(service: service),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('wifi-panel.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await tester.pumpWidget(const SizedBox());
    service.close();
  });
}
