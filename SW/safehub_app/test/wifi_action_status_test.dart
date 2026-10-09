import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safehub_app/services/wifi_sensing_service.dart';
import 'package:safehub_app/ui/widgets/wifi_action_status.dart';
import 'package:safehub_app/ui/widgets/disaster_overlay.dart';
import 'wifi_sensing_panel_test.dart' show fixture, utf8Response;

Map<String, dynamic> liveState() {
  final state = fixture();
  state['mode'] = 'live';
  state['dummy_allowed'] = false;
  state['models'] = [
    {
      'model_id': 'model',
      'labels': ['정지', '걷기'],
      'window_seconds': 4,
    },
  ];
  state['model'] = (state['models'] as List).first;
  state['recognition'] = {
    'running': true,
    'reason': '실시간 인식 중',
    'result': {
      'label': '걷기',
      'scores': {'걷기': .8, '정지': .2},
    },
  };
  return state;
}

void main() {
  Future<void> mount(WidgetTester tester, MockClient client) async {
    final service = WifiSensingService(
      baseUrl: 'http://localhost',
      client: client,
    );
    addTearDown(service.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 310,
            child: WifiActionStatus(service: service),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('home polls lightweight state and clears action on disconnect', (
    tester,
  ) async {
    final state = liveState();
    await mount(
      tester,
      MockClient((request) async {
        expect(request.url.queryParameters['view'], 'summary');
        return utf8Response(jsonEncode(state), 200);
      }),
    );
    expect(find.text('걷기'), findsOneWidget);
    expect(find.text('모델 점수 80%'), findsOneWidget);
    state['fresh'] = false;
    state['connected'] = false;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('걷기'), findsNothing);
    expect(find.text('수신기 신호 대기'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a stalled connection removes an old result within three ticks', (
    tester,
  ) async {
    var requests = 0;
    final pending = Completer<http.Response>();
    await mount(
      tester,
      MockClient((_) async {
        return ++requests == 1
            ? utf8Response(jsonEncode(liveState()), 200)
            : pending.future;
      }),
    );
    expect(find.text('걷기'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text('걷기'), findsNothing);
    expect(find.text('서비스 연결 대기'), findsOneWidget);
    pending.complete(utf8Response(jsonEncode(liveState()), 200));
    await tester.pump();
    expect(find.text('걷기'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('home stop command clears scores and returns to start', (
    tester,
  ) async {
    final state = liveState();
    await mount(
      tester,
      MockClient((request) async {
        if (request.method == 'POST') {
          expect(request.url.path, '/command/stop_recognition');
          state['recognition'] = {
            'running': false,
            'result': null,
            'reason': '중지',
          };
          return utf8Response('{"ok":true}', 200);
        }
        return utf8Response(jsonEncode(state), 200);
      }),
    );
    await tester.tap(find.text('행동 인식 중지'));
    await tester.pump();
    expect(find.text('걷기'), findsNothing);
    expect(find.text('행동 인식 시작'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('real home rejects synthetic results', (tester) async {
    final state = liveState()..['mode'] = 'dummy';
    await mount(
      tester,
      MockClient((_) async => utf8Response(jsonEncode(state), 200)),
    );
    expect(find.text('걷기'), findsNothing);
    expect(find.text('실제 수신 전용 CSI 서비스를 연결하세요.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final size in [const Size(800, 480), const Size(1920, 1080)]) {
    testWidgets('disaster remains visible when CSI disconnects at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = liveState();
      final service = WifiSensingService(
        baseUrl: 'http://localhost',
        client: MockClient((_) async => utf8Response(jsonEncode(state), 200)),
      );
      addTearDown(service.close);
      var acknowledged = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                DisasterOverlay(
                  disaster: const {
                    'DST_SE_NM': '지진',
                    'EMRG_STEP_NM': '긴급재난',
                    'MSG_CN': '테스트용 재난 안내',
                  },
                  pulseAnimation: const AlwaysStoppedAnimation(0),
                  onAcknowledge: () => acknowledged = true,
                  activityStatus: WifiActionStatus(
                    service: service,
                    compact: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('현재 모델 예측: 걷기'), findsOneWidget);
      state['fresh'] = false;
      state['connected'] = false;
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text('현재 모델 예측: 걷기'), findsNothing);
      expect(find.text('현재 행동: 확인 불가'), findsOneWidget);
      expect(find.text('테스트용 재난 안내'), findsOneWidget);
      expect(find.textContaining('대피 여부는 확인할 수 없습니다'), findsOneWidget);
      await tester.tap(find.text('확인했습니다'));
      expect(acknowledged, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
