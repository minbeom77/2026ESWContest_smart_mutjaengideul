import 'dart:io';

import 'package:flutter/material.dart';

import '../config/app_config.dart';

class ConnectionSettingsPage extends StatefulWidget {
  const ConnectionSettingsPage({super.key, this.saveSettings});

  final Future<void> Function(Map<String, Object?>)? saveSettings;

  @override
  State<ConnectionSettingsPage> createState() => _ConnectionSettingsPageState();
}

class _ConnectionSettingsPageState extends State<ConnectionSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    for (final entry in AppConfig.settings.entries) {
      _controllers[entry.key] = TextEditingController(
        text: entry.value?.toString() ?? '',
      );
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Map<String, Object?> get _values => {
    for (final entry in _controllers.entries) entry.key: entry.value.text,
  };

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await (widget.saveSettings ?? AppConfig.save)(_values);
      if (mounted) Navigator.of(context).pop(true);
    } on FileSystemException {
      if (mounted)
        setState(() => _saveError = '저장하지 못했습니다. 저장 폴더의 접근 권한과 여유 공간을 확인하세요.');
    } on FormatException {
      if (mounted) setState(() => _saveError = '입력한 주소와 포트를 다시 확인하세요.');
    } on StateError {
      if (mounted) setState(() => _saveError = '설정 파일의 저장 위치를 확인하세요.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(
    String key,
    String label, {
    String? helper,
    bool secret = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: TextFormField(
        key: ValueKey(key),
        controller: _controllers[key],
        enabled: !_saving,
        obscureText: secret,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType:
            key.endsWith('_PORT') ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          hintText: '미설정',
          helperText: helper,
          helperMaxLines: 3,
          errorMaxLines: 3,
          border: const OutlineInputBorder(),
        ),
        validator: (_) => AppConfig.validateValues(_values)[key],
      ),
    );
  }

  Widget _section(String title, String detail, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(detail),
            const SizedBox(height: 18),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      PopScope(canPop: !_saving, child: _buildForm(context));

  Widget _buildForm(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('장비 · 서버 연결 설정')),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '실제 장비를 연결할 때 사용하는 주소를 입력하세요. 아직 정해지지 않은 항목은 비워 두면 해당 기능이 미설정 상태로 대기합니다.',
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '터치디스플레이·스피커는 운영체제에서 연결합니다. 카메라 호스트는 영상을 제공하는 서버 주소이며, 카메라를 USB로 꽂는 것만으로 수어 인식 서버가 실행되지는 않습니다.',
                  ),
                  const SizedBox(height: 20),
                  if (AppConfig.setupError != null) ...[
                    Text(
                      AppConfig.setupError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  _section(
                    '수어 인식 결과 · MQTT',
                    '팀에서 사용하는 브로커 주소를 입력하세요. Topic과 데이터 형식은 변경하지 않습니다.',
                    [
                      _field(
                        'MQTT_BROKER',
                        'MQTT 브로커 주소',
                        helper: '예: 192.168.0.10 · http:// 없이 입력',
                      ),
                      _field('MQTT_PORT', 'MQTT 포트', helper: '기본 1883'),
                    ],
                  ),
                  _section('카메라 영상', '카메라 스트림 서버가 실행되는 장치의 주소와 포트입니다.', [
                    _field(
                      'CAMERA_HOST',
                      '카메라 서버 주소',
                      helper: '예: 192.168.0.10 · http:// 없이 입력',
                    ),
                    _field('CAMERA_PORT', '카메라 서버 포트', helper: '기본 5000'),
                  ]),
                  _section(
                    '와이파이 센싱',
                    '이 앱과 함께 실행하는 CSI 수집 서비스의 주소입니다. ESP32의 USB 포트는 신호 수집 화면에서 선택합니다.',
                    [
                      _field(
                        'CSI_SERVICE_URL',
                        'CSI 서비스 URL',
                        helper: '같은 컴퓨터에서는 http://127.0.0.1:8765',
                      ),
                    ],
                  ),
                  _section('음성', '음성 합성과 음성 인식 서버는 선택 기능입니다.', [
                    _field('TTS_SERVER_URL', '음성 합성 서버 URL'),
                    _field('STT_SERVER_URL', '음성 인식 서버 URL'),
                  ]),
                  _section('재난 정보', 'API 주소와 인증키를 모두 설정한 경우에만 정보를 조회합니다.', [
                    _field('DISASTER_API_URL', '재난 정보 API URL'),
                    _field(
                      'DISASTER_API_KEY',
                      '재난 정보 API 키',
                      secret: true,
                      helper:
                          Platform.environment.containsKey('DISASTER_API_KEY')
                              ? '현재 프로세스 환경변수의 키가 우선 적용됩니다.'
                              : '이 기기의 별도 .env 파일에 저장됩니다. 설정 파일은 공유하지 마세요.',
                    ),
                  ]),
                  const Text('설정 저장 위치'),
                  const SizedBox(height: 6),
                  SelectableText(AppConfig.configFilePath),
                  const SizedBox(height: 6),
                  SelectableText(AppConfig.secretFilePath),
                  const SizedBox(height: 18),
                  if (_saveError != null) ...[
                    Text(
                      _saveError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  FilledButton.icon(
                    key: const ValueKey('save_connection_settings'),
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(_saving ? '저장 중…' : '저장하고 연결 적용'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '저장 후 설정한 서비스에 연결을 시도합니다. 실제 장비가 꺼져 있으면 연결 대기 상태가 표시됩니다.',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
