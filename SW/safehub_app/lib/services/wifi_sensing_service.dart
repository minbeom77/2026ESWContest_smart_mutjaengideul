import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Native UI control channel to the same-device CSI process.
/// Device-to-device MQTT topics are intentionally unchanged.
class WifiSensingService {
  WifiSensingService({
    required this.baseUrl,
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 5),
  }) : _client = client;

  final String baseUrl;
  final Duration requestTimeout;
  final http.Client? _client;
  final Set<http.Client> _activeClients = {};
  bool _closed = false;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(baseUrl.trim());
    return base.replace(
      path: '${base.path.replaceFirst(RegExp(r'/+$'), '')}/$path',
      queryParameters: query ?? const {},
      fragment: '',
    );
  }

  Future<dynamic> _request(
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? payload,
  }) async {
    if (_closed) throw StateError('센싱 서비스 연결이 종료되었습니다.');
    // An owned client per request lets a timeout actually release its socket.
    final client = _client ?? http.Client();
    _activeClients.add(client);
    try {
      final uri = _uri(path, query);
      final response = await (payload == null
              ? client.get(uri)
              : client.post(
                uri,
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode(payload),
              ))
          .timeout(requestTimeout);
      dynamic body;
      try {
        body = jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        throw const FormatException(
          'CSI 서비스가 올바른 JSON을 보내지 않았습니다. 주소와 서비스 버전을 확인하세요.',
        );
      }
      if (response.statusCode != 200) {
        throw StateError(
          body is Map && body['error'] is String
              ? body['error'] as String
              : 'CSI 서비스 요청 실패 (HTTP ${response.statusCode})',
        );
      }
      return body;
    } on TimeoutException {
      throw TimeoutException(
        payload == null
            ? '센싱 서비스 응답을 기다리는 중입니다. 연결 상태를 확인하세요.'
            : '응답 시간이 초과되었습니다. 명령이 이미 적용됐을 수 있으니 현재 상태를 확인한 뒤 다시 시도하세요.',
      );
    } finally {
      _activeClients.remove(client);
      if (_client == null) client.close();
    }
  }

  static Never _invalid() =>
      throw const FormatException('CSI 서비스 상태 형식이 맞지 않습니다. 서비스 버전을 확인하세요.');

  static Map<String, dynamic> _map(dynamic value) {
    if (value is! Map<String, dynamic>) _invalid();
    return value;
  }

  static bool _text(dynamic value) =>
      value is String && value.trim().isNotEmpty;
  static bool _number(dynamic value, {double max = double.infinity}) =>
      value is num && value.isFinite && value >= 0 && value <= max;

  static List<dynamic> _list(dynamic value) {
    if (value is! List) _invalid();
    return value;
  }

  static void _uniqueIds(List<dynamic> values, String key) {
    final ids = <String>{};
    for (final value in values) {
      final id = _map(value)[key];
      if (!_text(id) || !ids.add(id as String)) _invalid();
    }
  }

  Future<Map<String, dynamic>> state(Map<String, String> stages) async {
    final value = _map(await _request('state', query: stages));
    if (value['storage_warnings'] != null &&
        !_list(value['storage_warnings']).every((warning) => warning is String))
      _invalid();
    if (!['live', 'dummy'].contains(value['mode']) ||
        value['connected'] is! bool ||
        value['fresh'] is! bool ||
        value['training_allowed'] is! bool ||
        value['error'] is! String ||
        !_number(value['rate_hz']) ||
        (value.containsKey('dummy_allowed') &&
            value['dummy_allowed'] is! bool)) {
      _invalid();
    }
    final behaviors = _list(value['behaviors']);
    if (!behaviors.every(_text) ||
        behaviors.toSet().length != behaviors.length ||
        !behaviors.contains('정지') ||
        !behaviors.contains('낙상'))
      _invalid();
    final records = _list(value['records']);
    _uniqueIds(records, 'id');
    for (final record in records) {
      if (!_text(record['label']) ||
          !_number(record['duration']) ||
          !_text(record['experiment_id']) ||
          (record['collection'] != null && record['collection'] is! Map))
        _invalid();
    }
    final models = _list(value['models']);
    _uniqueIds(models, 'model_id');
    for (final model in models) {
      final labels = _list(model['labels']);
      if (labels.isEmpty ||
          !labels.every(_text) ||
          (model['name'] != null && model['name'] is! String) ||
          (model['balanced_accuracy'] != null &&
              !_number(model['balanced_accuracy'], max: 1)))
        _invalid();
    }
    final selected = value['model'];
    if (selected != null) {
      final model = _map(selected);
      if (!models.any((m) => m['model_id'] == model['model_id']) ||
          (model['balanced_accuracy'] != null &&
              !_number(model['balanced_accuracy'], max: 1)))
        _invalid();
    }
    final training = _map(value['training']);
    if (!['idle', 'running', 'complete', 'failed'].contains(training['state']))
      _invalid();
    final capture = value['capture'];
    if (capture != null) {
      final recording = _map(capture);
      if (![
            'preparing',
            'recording',
            'complete',
            'failed',
            'cancelled',
          ].contains(recording['state']) ||
          recording['error'] is! String ||
          !_number(recording['remaining']))
        _invalid();
    }
    final recognition = _map(value['recognition']);
    if (recognition['running'] is! bool || recognition['reason'] is! String)
      _invalid();
    if (recognition['result'] != null) {
      final result = _map(recognition['result']);
      final scores = _map(result['scores']);
      if (!_text(result['label']) ||
          scores.isEmpty ||
          !scores.entries.every(
            (entry) => _text(entry.key) && _number(entry.value, max: 1),
          ))
        _invalid();
    }
    if (value['waveform'] != null) {
      final signal = _list(_map(value['waveform'])['signal']);
      if (!signal.every((point) => point is num && point.isFinite)) _invalid();
    }
    return value;
  }

  Future<List<dynamic>> ports() async {
    final values = _list(await _request('ports'));
    _uniqueIds(values, 'port');
    return values;
  }

  Future<Map<String, dynamic>> command(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    final result = _map(await _request('command/$action', payload: payload));
    if (result['ok'] != true && !_text(result['path'])) _invalid();
    return result;
  }

  void close() {
    _closed = true;
    for (final client in _activeClients.toList()) {
      client.close();
    }
    _activeClients.clear();
    _client?.close();
  }
}
