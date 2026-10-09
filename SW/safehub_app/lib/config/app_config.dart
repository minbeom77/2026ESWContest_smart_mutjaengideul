import 'dart:convert';
import 'dart:io';

class AppConfig {
  static const bool localPreview = bool.fromEnvironment(
    'APP_LOCAL_PREVIEW',
    defaultValue: false,
  );

  static const _defaults = <String, Object?>{
    'MQTT_BROKER': String.fromEnvironment('MQTT_BROKER'),
    'MQTT_PORT': int.fromEnvironment('MQTT_PORT', defaultValue: 1883),
    'CAMERA_HOST': String.fromEnvironment('CAMERA_HOST'),
    'CAMERA_PORT': int.fromEnvironment('CAMERA_PORT', defaultValue: 5000),
    'TTS_SERVER_URL': String.fromEnvironment('TTS_SERVER_URL'),
    'STT_SERVER_URL': String.fromEnvironment('STT_SERVER_URL'),
    'DISASTER_API_URL': String.fromEnvironment('DISASTER_API_URL'),
    'DISASTER_API_KEY': String.fromEnvironment('DISASTER_API_KEY'),
    'CSI_SERVICE_URL': String.fromEnvironment(
      'CSI_SERVICE_URL',
      defaultValue: 'http://127.0.0.1:8765',
    ),
  };
  static const _portDefaults = {'MQTT_PORT': 1883, 'CAMERA_PORT': 5000};
  static const _hostKeys = {'MQTT_BROKER', 'CAMERA_HOST'};
  static const _urlKeys = {
    'TTS_SERVER_URL',
    'STT_SERVER_URL',
    'DISASTER_API_URL',
    'CSI_SERVICE_URL',
  };
  static Map<String, Object?> _values = {};
  static String? _filePath;
  static String? setupError;

  static Map<String, Object?> get settings => {
    ..._defaults,
    ..._values,
    if (Platform.environment.containsKey('DISASTER_API_KEY'))
      'DISASTER_API_KEY': Platform.environment['DISASTER_API_KEY'],
  };
  static String _text(String key) => settings[key].toString();
  static String get mqttBroker => _text('MQTT_BROKER');
  static int get mqttPort => settings['MQTT_PORT'] as int;
  static String get cameraHost => _text('CAMERA_HOST');
  static int get cameraPort => settings['CAMERA_PORT'] as int;
  static String get ttsServerUrl => _text('TTS_SERVER_URL');
  static String get sttServerUrl => _text('STT_SERVER_URL');
  static String get disasterApiUrl => _text('DISASTER_API_URL');
  static String get disasterApiKey => _text('DISASTER_API_KEY');
  static String get csiServiceUrl => _text('CSI_SERVICE_URL');
  static bool get mqttConfigured => mqttBroker.isNotEmpty;
  static bool get cameraConfigured => cameraHost.isNotEmpty;
  static bool get disasterConfigured =>
      disasterApiUrl.isNotEmpty && disasterApiKey.isNotEmpty;

  static String get configFilePath {
    if (_filePath != null) return _filePath!;
    final override = Platform.environment['SAFEHUB_CONFIG_FILE']?.trim();
    if (override != null && override.isNotEmpty) return override;
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      throw StateError('사용자 폴더를 찾을 수 없습니다. SAFEHUB_CONFIG_FILE을 지정하세요.');
    }
    return '$home${Platform.pathSeparator}SafeHubData'
        '${Platform.pathSeparator}connection-settings.json';
  }

  static String get secretFilePath =>
      '${File(configFilePath).parent.path}${Platform.pathSeparator}connection-settings.env';

  // Empty addresses leave services waiting. Local values override build values;
  // process environment remains the highest-priority source for the API key.
  static Future<void> load({String? filePath}) async {
    _filePath = filePath;
    _values = {};
    setupError = null;
    try {
      final file = File(configFilePath);
      final decoded =
          await file.exists()
              ? jsonDecode(await file.readAsString())
              : <String, dynamic>{};
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('설정 파일은 JSON 객체여야 합니다.');
      }
      final candidate = _normalize({..._defaults, ...decoded});
      final secretFile = File(secretFilePath);
      if (await secretFile.exists()) {
        candidate['DISASTER_API_KEY'] = _readSecret(
          await secretFile.readAsString(),
        );
      }
      if (validateValues(candidate).isNotEmpty) {
        throw const FormatException('설정값이 올바르지 않습니다.');
      }
      _values = candidate;
    } on FileSystemException {
      setupError = '연결 설정 파일을 읽지 못했습니다. 연결 설정에서 다시 저장하세요.';
    } on FormatException {
      setupError = '연결 설정 파일 형식이 올바르지 않습니다. 연결 설정에서 확인하세요.';
    } on StateError {
      setupError = '연결 설정 저장 위치를 찾지 못했습니다.';
    }
  }

  static String _readSecret(String content) {
    String result = '';
    for (final line in const LineSplitter().convert(content)) {
      final match = RegExp(r'^\s*DISASTER_API_KEY\s*=(.*)$').firstMatch(line);
      if (match == null) continue;
      final raw = match.group(1)!.trim();
      if (raw.startsWith('"')) {
        final decoded = jsonDecode(raw);
        if (decoded is! String) throw const FormatException();
        result = decoded;
      } else if (raw.startsWith("'")) {
        if (raw.length < 2 || !raw.endsWith("'")) throw const FormatException();
        result = raw.substring(1, raw.length - 1);
      } else {
        result = raw;
      }
    }
    return result;
  }

  static Map<String, Object?> _normalize(Map<String, Object?> values) {
    final result = <String, Object?>{};
    for (final key in _defaults.keys) {
      final raw = values[key];
      if (_portDefaults.containsKey(key)) {
        final value = raw?.toString().trim() ?? '';
        result[key] =
            value.isEmpty ? _portDefaults[key] : int.tryParse(value) ?? value;
      } else if (raw == null || raw is String) {
        final value = raw as String? ?? '';
        final normalized = key == 'DISASTER_API_KEY' ? value : value.trim();
        result[key] =
            key == 'CSI_SERVICE_URL' && normalized.isEmpty
                ? _defaults[key]
                : normalized;
      } else {
        result[key] = raw;
      }
    }
    return result;
  }

  static Map<String, String> validateValues(Map<String, Object?> values) {
    final errors = <String, String>{};
    for (final entry in _normalize(values).entries) {
      final key = entry.key;
      final value = entry.value;
      if (_portDefaults.containsKey(key)) {
        if (value is! int || value < 1 || value > 65535) {
          errors[key] = '포트는 1~65535 사이의 정수를 입력하세요.';
        }
        continue;
      }
      if (value is! String) {
        errors[key] = '문자열을 입력하세요.';
        continue;
      }
      if (key == 'DISASTER_API_KEY' && RegExp(r'[\r\n]').hasMatch(value)) {
        errors[key] = 'API 키는 한 줄로 입력하세요.';
      }
      if (value.isEmpty) continue;
      if (_hostKeys.contains(key) && !_validHost(value)) {
        errors[key] = '주소만 입력하세요. 프로토콜·포트·계정 정보는 제외하세요.';
      }
      if (_urlKeys.contains(key) && !_validUrl(value)) {
        errors[key] = 'http:// 또는 https://로 시작하는 서버 주소를 입력하세요.';
      }
    }
    return errors;
  }

  static bool _validUrl(String value) {
    try {
      final uri = Uri.parse(value);
      return {'http', 'https'}.contains(uri.scheme) &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty &&
          !RegExp(r'\s').hasMatch(value) &&
          uri.port >= 1 &&
          uri.port <= 65535;
    } on FormatException {
      return false;
    }
  }

  static bool _validHost(String value) {
    if (RegExp(r'[\s/@?#]').hasMatch(value)) return false;
    if (InternetAddress.tryParse(value) != null) return true;
    if (value.length > 253) return false;
    return value
        .split('.')
        .every(
          (label) =>
              label.isNotEmpty &&
              label.length <= 63 &&
              RegExp(
                r'^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$',
              ).hasMatch(label),
        );
  }

  static void validate() {
    if (localPreview) return;
    if (validateValues(settings).isNotEmpty) {
      throw StateError('연결 설정의 주소 또는 포트를 확인하세요.');
    }
  }

  static Future<void> _atomicWrite(File target, String? content) async {
    if (content == null) {
      if (await target.exists()) await target.delete();
      return;
    }
    final temporary = File(
      '${target.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await temporary.writeAsString(content, flush: true);
      await temporary.rename(target.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  static Future<void> save(Map<String, Object?> values) async {
    final candidate = _normalize({..._defaults, ...values});
    if (validateValues(candidate).isNotEmpty) {
      throw const FormatException('연결 설정의 주소 또는 포트를 확인하세요.');
    }
    final target = File(configFilePath);
    final secretFile = File(secretFilePath);
    await target.parent.create(recursive: true);
    final oldJson = await target.exists() ? await target.readAsString() : null;
    final oldSecret =
        await secretFile.exists() ? await secretFile.readAsString() : null;
    final secret = candidate['DISASTER_API_KEY'] as String;
    final secretLines =
        const LineSplitter()
            .convert(oldSecret ?? '')
            .where(
              (line) => !RegExp(r'^\s*DISASTER_API_KEY\s*=').hasMatch(line),
            )
            .toList();
    if (secret.isNotEmpty)
      secretLines.add('DISASTER_API_KEY=${jsonEncode(secret)}');
    final publicSettings = {...candidate}..remove('DISASTER_API_KEY');
    try {
      await _atomicWrite(
        secretFile,
        secretLines.isEmpty ? null : '${secretLines.join('\n')}\n',
      );
      await _atomicWrite(
        target,
        '${const JsonEncoder.withIndent('  ').convert(publicSettings)}\n',
      );
    } catch (_) {
      // Retain the previous pair when either file cannot be replaced.
      try {
        await _atomicWrite(secretFile, oldSecret);
        await _atomicWrite(target, oldJson);
      } catch (_) {
        throw const FileSystemException('설정 저장 및 이전 파일 복원에 실패했습니다.');
      }
      rethrow;
    }
    _values = candidate;
    setupError = null;
  }

  static void resetForTesting() {
    _values = {};
    _filePath = null;
    setupError = null;
  }
}
