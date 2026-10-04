import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safehub_app/services/wifi_sensing_service.dart';

http.Response utf8Response(
  String body,
  int status, {
  Map<String, String>? headers,
}) => http.Response(
  body,
  status,
  headers: {'content-type': 'application/json; charset=utf-8', ...?headers},
);

Map<String, dynamic> validState() => {
  'mode': 'live',
  'connected': false,
  'fresh': false,
  'error': '',
  'training_allowed': true,
  'dummy_allowed': false,
  'rate_hz': 0,
  'behaviors': ['정지', '낙상'],
  'records': [],
  'models': [],
  'model': null,
  'training': {'state': 'idle'},
  'capture': null,
  'recognition': {'running': false, 'result': null, 'reason': ''},
  'waveform': null,
};

void main() {
  test(
    'normalizes service URL and preserves stage query and waveform values',
    () async {
      final source =
          validState()
            ..['waveform'] = {
              'signal': [-2.5, 0, 9.3],
            };
      final service = WifiSensingService(
        baseUrl: 'http://127.0.0.1:9999///?obsolete=value#fragment',
        client: MockClient((request) async {
          expect(request.url.path, '/state');
          expect(request.url.queryParameters, {'denoise': 'false'});
          expect(request.url.fragment, isEmpty);
          return utf8Response(jsonEncode(source), 200);
        }),
      );
      expect(
        (await service.state({'denoise': 'false'}))['waveform'],
        source['waveform'],
      );
      service.close();
    },
  );

  final malformed = <String, void Function(Map<String, dynamic>)>{
    'nonnumeric rate': (state) => state['rate_hz'] = '60',
    'missing behavior': (state) => state['behaviors'] = ['걷기'],
    'duplicate behavior': (state) => state['behaviors'] = ['정지', '낙상', '정지'],
    'invalid record row': (state) => state['records'] = ['wrong'],
    'duplicate record ID':
        (state) =>
            state['records'] = [
              for (var i = 0; i < 2; i++) {'id': 'same'},
            ],
    'nonnumeric duration':
        (state) =>
            state['records'] = [
              {'id': 'r', 'label': '정지', 'experiment_id': 'a', 'duration': '8'},
            ],
    'invalid model labels':
        (state) =>
            state['models'] = [
              {'model_id': 'm', 'labels': 5},
            ],
    'missing selected model':
        (state) => state['model'] = {'model_id': 'missing'},
    'invalid capture countdown':
        (state) =>
            state['capture'] = {
              'state': 'recording',
              'error': '',
              'remaining': '4',
            },
    'invalid recognition map': (state) => state['recognition'] = false,
    'invalid score range':
        (state) =>
            state['recognition'] = {
              'running': true,
              'reason': '',
              'result': {
                'label': '걷기',
                'scores': {'걷기': 2},
              },
            },
    'invalid waveform point':
        (state) =>
            state['waveform'] = {
              'signal': [1, 'broken', 3],
            },
    'invalid warnings': (state) => state['storage_warnings'] = [99],
  };
  for (final entry in malformed.entries) {
    test('rejects malformed status before rendering: ${entry.key}', () async {
      final value = validState();
      entry.value(value);
      final service = WifiSensingService(
        baseUrl: 'http://127.0.0.1',
        client: MockClient((_) async => utf8Response(jsonEncode(value), 200)),
      );
      await expectLater(service.state({}), throwsFormatException);
      service.close();
    });
  }

  test(
    'accepts optional storage warnings without changing healthy data',
    () async {
      final value = validState()..['storage_warnings'] = ['읽지 못한 기록 1개'];
      final service = WifiSensingService(
        baseUrl: 'http://127.0.0.1',
        client: MockClient((_) async => utf8Response(jsonEncode(value), 200)),
      );
      expect(await service.state({}), value);
      service.close();
    },
  );

  test(
    'rejects duplicate port names instead of creating invalid dropdowns',
    () async {
      final service = WifiSensingService(
        baseUrl: 'http://127.0.0.1',
        client: MockClient(
          (_) async => utf8Response('[{"port":"COM5"},{"port":"COM5"}]', 200),
        ),
      );
      await expectLater(service.ports(), throwsFormatException);
      service.close();
    },
  );

  test(
    'command timeout reports uncertain outcome without retrying POST',
    () async {
      final pending = Completer<http.Response>();
      var calls = 0;
      final service = WifiSensingService(
        baseUrl: 'http://127.0.0.1',
        requestTimeout: const Duration(milliseconds: 1),
        client: MockClient((_) {
          calls++;
          return pending.future;
        }),
      );
      await expectLater(
        service.command('capture'),
        throwsA(
          isA<TimeoutException>().having(
            (error) => error.message,
            'outcome',
            contains('이미 적용됐을 수'),
          ),
        ),
      );
      expect(calls, 1);
      pending.complete(utf8Response('{"ok":true}', 200));
      service.close();
    },
  );

  test('rejects HTML and non-command success shapes', () async {
    for (final body in ['<html>wrong service</html>', '[]', '{}']) {
      final service = WifiSensingService(
        baseUrl: 'http://127.0.0.1',
        client: MockClient((_) async => utf8Response(body, 200)),
      );
      await expectLater(service.command('connect'), throwsFormatException);
      service.close();
    }
  });

  test('closing the service prevents future network commands', () async {
    var calls = 0;
    final service = WifiSensingService(
      baseUrl: 'http://127.0.0.1',
      client: MockClient((_) async {
        calls++;
        return utf8Response('{"ok":true}', 200);
      }),
    );
    service.close();
    await expectLater(service.command('train'), throwsStateError);
    expect(calls, 0);
  });
}
