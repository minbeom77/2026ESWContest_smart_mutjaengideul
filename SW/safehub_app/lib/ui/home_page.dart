import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../core/alert_coordinator.dart';
import '../core/care_incident.dart';
import '../core/appliance_controls.dart';
import '../core/event_manager.dart';
import '../mqtt/mqtt_receiver.dart';
import '../services/audio_service.dart';
import '../services/camera_stream_service.dart';
import '../services/disaster_service.dart';
import '../services/sign_speech_policy.dart';
import '../services/stt_service.dart';
import '../services/tts_service.dart';
import '../services/voice_recorder_service.dart';
import 'utils/disaster_display.dart';
import 'widgets/disaster_overlay.dart';
import 'widgets/appliance_panel.dart';

enum _SafeHubPage {
  home,
  signTranslation,
  appliances,
}

class SafeHubHomePage extends StatefulWidget {
  const SafeHubHomePage({
    super.key,
    this.demo = const bool.fromEnvironment('SAFEHUB_UI_DEMO'),
  });

  /// Offline UI review: no MQTT, camera, API, microphone or audio connections.
  final bool demo;

  @override
  State<SafeHubHomePage> createState() => _SafeHubHomePageState();
}

class _SafeHubHomePageState extends State<SafeHubHomePage>
    with SingleTickerProviderStateMixin {
  final EventManager _eventManager = EventManager();
  final ApplianceControls _appliances = ApplianceControls();
  final DisasterService _disasterService = DisasterService();
  final AlertCoordinator _alertCoordinator = AlertCoordinator();
  late final AudioService _audioService;
  final SignSpeechPolicy _signSpeechPolicy = SignSpeechPolicy();

  late final MqttReceiver _mqttReceiver;
  late final AnimationController _alertPulseController;
  late final TtsService _ttsService;
  late final SttService _sttService;
  late final VoiceRecorderService _voiceRecorderService;
  final CameraStreamService _cameraStreamService = CameraStreamService();

  Timer? _responseTicker;
  final Map<SafeHubAlert, CareIncident> _incidents = {};
  final List<({String speaker, String text, DateTime time})> _conversation = [];
  final SignSpeechPolicy _historyPolicy = SignSpeechPolicy();
  bool _autoSpeak = true;
  bool _helpChoice = false;
  bool _showTextComposer = false;
  final TextEditingController _messageController = TextEditingController();
  String? _helpContextSign;
  SafeHubAlert? _helpChoiceIncident;
  CareHelpKind _helpKind = CareHelpKind.familyVisit;
  DateTime? _lastHelpDismissedAt;
  String? _localHelpRequest;
  DateTime? _lastCsiReceived;
  DateTime? _lastCameraFrameAt;
  bool _cameraFresh = false;
  DateTime? _disasterCheckedAt;
  String _disasterStatus = '조회 중';
  int _responseSeconds = 30;
  int _sttGeneration = 0;
  bool get _demo => widget.demo;
  Timer? _disasterTimer;
  Timer? _signOverlayTimer;

  _SafeHubPage _currentPage = _SafeHubPage.home;

  bool _mqttConnected = false;
  String _connectionStatus = '연결 중';
  String _signText = '수어 인식 대기 중';
  String _ttsStatus = '음성 안내 대기';
  String _sttText = '음성 인식 대기 중';
  String _sttStatus = '마이크 대기';
  bool _sttRecording = false;
  bool _sttBusy = false;

  static const int _cameraWidth = 320;
  static const int _cameraHeight = 240;

  ui.Image? _cameraImage;
  bool _cameraConnected = false;
  bool _cameraDecodeInProgress = false;
  bool _showSignOverlay = false;

  Map<String, dynamic>? _latestDisaster;

  String? _lastDisasterId;
  int _speechGeneration = 0;

  final List<Map<String, dynamic>> _recentEvents = [];

  @override
  void initState() {
    super.initState();

    if (!_demo) {
      _audioService = AudioService();
      _voiceRecorderService = VoiceRecorderService();
    }

    _alertPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _ttsService = TtsService(
      baseUrl: AppConfig.ttsServerUrl,
    );

    _sttService = SttService(
      baseUrl: AppConfig.sttServerUrl,
    );

    _mqttReceiver = MqttReceiver(
      broker: AppConfig.mqttBroker,
      port: AppConfig.mqttPort,
      eventManager: _eventManager,
      onEventReceived: _handleEvent,
      onSignTextReceived: _handleSignText,
      onDeviceCommand: (topic, data) {
        if (mounted && _appliances.receiveCommand(topic, data)) setState(() {});
      },
      onConnectionChanged: _handleConnectionChanged,
    );

    _responseTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      var changed = false;
      for (final incident in _incidents.values) {
        changed = incident.tick(DateTime.now()) || changed;
      }
      final fresh = _lastCameraFrameAt != null && _cameraConnected &&
          DateTime.now().difference(_lastCameraFrameAt!) < const Duration(seconds: 5);
      if (_cameraFresh != fresh) {
        _cameraFresh = fresh;
        changed = true;
      }
      if (changed || _alertCoordinator.activeAlert?.kind == AlertKind.fall) {
        setState(() {});
      }
    });
    if (!_demo) {
      _connectMqtt();
      _connectCamera();
      _startDisasterPolling();
    } else {
      _connectionStatus = '미리보기 · 연결 안 함';
      _disasterStatus = '미리보기 · 조회 안 함';
    }
  }

  void _connectCamera() {
    unawaited(
      _cameraStreamService.connect(
        host: AppConfig.cameraHost,
        port: AppConfig.cameraPort,
        onFrame: _handleCameraFrame,
        onConnectionChanged: (connected) {
          if (!mounted) {
            return;
          }

          final previousImage = connected ? null : _cameraImage;

          setState(() {
            _cameraConnected = connected;

            if (!connected) {
              _cameraImage = null;
              _cameraFresh = false;
            }
          });

          previousImage?.dispose();
        },
      ),
    );
  }

  void _handleCameraFrame(Uint8List frame) {
    const expectedBytes = _cameraWidth * _cameraHeight * 4;

    if (frame.lengthInBytes != expectedBytes) {
      return;
    }

    if (_cameraDecodeInProgress) {
      return;
    }

    _cameraDecodeInProgress = true;

    ui.decodeImageFromPixels(
      frame,
      _cameraWidth,
      _cameraHeight,
      ui.PixelFormat.rgba8888,
      (image) {
        _cameraDecodeInProgress = false;

        if (!mounted) {
          image.dispose();
          return;
        }

        final previousImage = _cameraImage;

        setState(() {
          _cameraImage = image;
          _lastCameraFrameAt = DateTime.now();
          _cameraFresh = _cameraConnected;
        });

        previousImage?.dispose();
      },
    );
  }

  void _startDisasterPolling() {
    _fetchLatestDisaster();

    _disasterTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) {
        _fetchLatestDisaster();
      },
    );
  }

  Future<void> _fetchLatestDisaster() async {
    try {
      final disaster = await _disasterService.fetchLatest();
      if (mounted) setState(() {
        _disasterCheckedAt = DateTime.now();
        _disasterStatus = disaster == null ? '조회 결과 없음' : '조회 완료';
      });

      if (disaster == null || !mounted) {
        return;
      }

      final disasterId = DisasterService.identifierOf(disaster);

      if (disasterId == null || _lastDisasterId == disasterId) {
        return;
      }

      final disasterData = Map<String, dynamic>.from(disaster);
      final currentDisaster = _latestDisaster;

      if (currentDisaster != null &&
          !DisasterService.isNewerThan(
            disasterData,
            currentDisaster,
          )) {
        debugPrint(
          '[재난 API] 이전 데이터 무시: '
          'current=${currentDisaster['CRT_DT']} '
          'candidate=${disasterData['CRT_DT']}',
        );
        return;
      }

      final isInitialLoad = _lastDisasterId == null;
      final severity = getDisasterSeverity(disasterData);

      var activated = false;

      if (!isInitialLoad && severity != DisasterSeverity.notice) {
        activated = _alertCoordinator.submit(
          SafeHubAlert(
            kind: AlertKind.disaster,
            priority: _getDisasterPriority(severity),
            data: disasterData,
          ),
        );
      }

      setState(() {
        _lastDisasterId = disasterId;
        _latestDisaster = disasterData;
      });

      if (activated) {
        _interruptNormalSpeech();
        _restartAlertPulse();
      }
    } catch (e, st) {
      if (mounted) setState(() => _disasterStatus = '조회 실패 · 이전 정보 확인');
      debugPrint('[재난 API 실패] $e');
      debugPrint('$st');
      // 재난 API 실패 시 다른 SafeHub 기능은 계속 동작한다.
    }
  }

  int _getDisasterPriority(DisasterSeverity severity) {
    switch (severity) {
      case DisasterSeverity.notice:
        return 3;
      case DisasterSeverity.emergency:
        return 6;
      case DisasterSeverity.critical:
        return 8;
    }
  }

  Future<void> _connectMqtt() async {
    try {
      await _mqttReceiver.connect();

      if (!mounted) {
        return;
      }

      setState(() {
        _mqttConnected = true;
        _connectionStatus = '연결됨';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _mqttConnected = false;
        _connectionStatus = '연결 실패';
      });
    }
  }

  void _handleConnectionChanged(bool connected) {
    if (!mounted) {
      return;
    }

    setState(() {
      _mqttConnected = connected;
      _connectionStatus = connected ? '연결됨' : '재연결 중';
    });
  }

  void _handleSignText(String text) {
    if (!mounted) {
      return;
    }

    final cleanText = text.trim();

    if (cleanText.isEmpty) {
      return;
    }

    final ttsConfigured = AppConfig.ttsServerUrl.trim().isNotEmpty;
    final alertActive = _alertCoordinator.hasActiveAlert;
    final shouldSpeak = !_demo && _autoSpeak && !_sttRecording && !_sttBusy && ttsConfigured &&
        !alertActive &&
        _signSpeechPolicy.shouldSpeak(cleanText);

    final String nextTtsStatus;

    if (_demo) {
      nextTtsStatus = '미리보기 · 실제 음성 출력 없음';
    } else if (!_autoSpeak) {
      nextTtsStatus = '자동 읽기 꺼짐';
    } else if (_sttRecording || _sttBusy) {
      nextTtsStatus = '가족 음성 자막 입력 중';
    } else if (!ttsConfigured) {
      nextTtsStatus = '텍스트로 표시됨';
    } else if (alertActive) {
      nextTtsStatus = '안전 알림 화면 우선 표시 중';
    } else if (!shouldSpeak) {
      nextTtsStatus = '최근 음성 안내와 동일';
    } else {
      nextTtsStatus = '음성 변환 준비 중';
    }

    _signOverlayTimer?.cancel();

    setState(() {
      _signText = cleanText;
      if (_historyPolicy.shouldSpeak(cleanText)) {
        _addMessage('내 말 · 수어', cleanText);
        if (cleanText == '아프다' && !_helpChoice &&
            (_lastHelpDismissedAt == null ||
             DateTime.now().difference(_lastHelpDismissedAt!) >= const Duration(seconds: 15))) {
          _prepareHelpChoice(sign: cleanText);
        }
      }
      _showSignOverlay = true;
      _ttsStatus = nextTtsStatus;
    });

    _signOverlayTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) {
        return;
      }

      setState(() {
        _showSignOverlay = false;
      });
    });

    if (!shouldSpeak) {
      return;
    }

    final generation = ++_speechGeneration;
    final speechText = _signSpeechPolicy.phraseFor(cleanText);

    unawaited(
      _speakTranslation(
        speechText,
        generation,
      ),
    );
  }

  Future<void> _speakTranslation(
    String text,
    int generation,
  ) async {
    if (AppConfig.ttsServerUrl.trim().isEmpty) {
      return;
    }

    if (_alertCoordinator.hasActiveAlert || _sttRecording || _sttBusy) {
      return;
    }

    try {
      if (mounted) {
        setState(() {
          _ttsStatus = '음성 안내 준비 중';
        });
      }

      await _audioService.stop();

      if (generation != _speechGeneration || _alertCoordinator.hasActiveAlert) {
        return;
      }

      final bytes = await _ttsService.synthesize(text);

      if (!mounted ||
          generation != _speechGeneration ||
          _alertCoordinator.hasActiveAlert) {
        return;
      }

      setState(() {
        _ttsStatus = '음성 안내 중';
      });

      await _audioService.playBytes(bytes, shouldPlay: () => mounted &&
          generation == _speechGeneration && !_sttRecording && !_sttBusy &&
          !_alertCoordinator.hasActiveAlert);

      if (mounted &&
          generation == _speechGeneration &&
          !_alertCoordinator.hasActiveAlert) {
        setState(() {
          _ttsStatus = '음성 재생 시작됨';
        });
      }
    } catch (_) {
      if (mounted && generation == _speechGeneration) {
        setState(() {
          _ttsStatus = '음성 출력 실패 · 텍스트로 확인해 주세요';
        });
      }
    }
  }

  Future<void> _toggleSttRecording() async {
    if (_demo || _sttBusy || _alertCoordinator.hasActiveAlert) {
      return;
    }

    if (AppConfig.sttServerUrl.trim().isEmpty) {
      setState(() {
        _sttStatus = 'STT 서버 미설정';
      });
      return;
    }

    if (!_sttRecording) {
      setState(() => _sttBusy = true);
      _speechGeneration++;
      final startGeneration = ++_sttGeneration;
      try {
        await _audioService.stop();
        await _voiceRecorderService.start();
        if (!mounted || startGeneration != _sttGeneration || _alertCoordinator.hasActiveAlert) {
          await _voiceRecorderService.cancel();
          return;
        }

        if (!mounted) {
          return;
        }

        setState(() {
          _sttRecording = true;
          _sttStatus = '음성을 듣고 있습니다';
        });
      } catch (error, stackTrace) {
        debugPrint('[STT 녹음 시작 실패] $error');
        debugPrintStack(stackTrace: stackTrace);

        if (!mounted) {
          return;
        }

        setState(() {
          _sttRecording = false;
          _sttStatus = '마이크 시작 실패: $error';
        });
      } finally {
        if (mounted) setState(() => _sttBusy = false);
      }

      return;
    }

    setState(() {
      _sttRecording = false;
      _sttBusy = true;
      _sttStatus = '음성을 글자로 변환 중';
    });

    final sttGeneration = _sttGeneration;
    try {
      final audioBytes = await _voiceRecorderService.stopAndRead();
      final result = await _sttService.transcribe(audioBytes);

      if (!mounted || sttGeneration != _sttGeneration) {
        return;
      }

      setState(() {
        _sttText = result;
        if (result.trim().isNotEmpty) _addMessage('가족의 말 · 음성 자막', result);
        _sttStatus = '음성 인식 완료';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _sttStatus = '음성 인식 실패';
      });
    } finally {
      if (mounted) {
        setState(() {
          _sttBusy = false;
        });
      }
    }
  }

  Future<void> _cancelSttRecording() async {
    if (!_sttRecording) {
      return;
    }

    await _voiceRecorderService.cancel();

    if (!mounted) {
      return;
    }

    setState(() {
      _sttRecording = false;
      _sttBusy = false;
      _sttStatus = '안전 경보로 녹음 중단';
    });
  }

  void _handleEvent(Map<String, dynamic> event) {
    if (!mounted) {
      print('[UI] event ignored because widget is not mounted');
      return;
    }

    print(
      '[UI] event received event=${event['event']} '
      'location=${event['location']} priority=${event['priority']}',
    );

    // Transport deduplication remains in MqttReceiver (message_id, QoS 1).
    final incomingId = event['message_id']?.toString() ?? event['event_id']?.toString();
    _lastCsiReceived = DateTime.now();
    final eventData = Map<String, dynamic>.from(event);
    eventData['_receivedAt'] ??= DateTime.now().toIso8601String();

    var activated = false;

    if (_isEmergencyEvent(eventData)) {
      final priority = _getEventPriority(eventData);

      final alert = SafeHubAlert(kind: AlertKind.fall, priority: priority, data: eventData);
      _incidents[alert] = CareIncident(
        id: incomingId ?? DateTime.now().microsecondsSinceEpoch.toString(),
        openedAt: DateTime.now(), wait: Duration(seconds: _responseSeconds));
      activated = _alertCoordinator.submit(alert);

      print(
        '[ALERT] fall submitted activated=$activated priority=$priority',
      );
    } else {
      print('[ALERT] non-emergency event added to recent events only');
    }

    setState(() {
      _recentEvents.insert(
        0,
        eventData,
      );

      if (_recentEvents.length > 5) {
        _recentEvents.removeLast();
      }
    });

    if (activated) {
      // A choice opened before this event must never respond to this new event.
      _helpChoice = false;
      _helpChoiceIncident = null;
      FocusScope.of(context).unfocus();
      print('[UI] emergency overlay activated');
      _interruptNormalSpeech();
      _restartAlertPulse();
    } else {
      print('[UI] event stored without replacing active overlay');
    }
  }

  int _getEventPriority(Map<String, dynamic> event) {
    final priority = event['priority'];

    if (priority is int && priority >= 1 && priority <= 10) {
      return priority;
    }

    return 9;
  }

  bool _isEmergencyEvent(Map<String, dynamic> event) {
    return event['event'] == 'fall_detected';
  }

  void _interruptNormalSpeech() {
    _sttGeneration++;
    _speechGeneration++;
    if (!_demo) {
      unawaited(_audioService.stop());
      unawaited(_cancelSttRecording());
    }

    if (mounted) {
      setState(() {
        _ttsStatus = '안전 알림으로 음성 안내 중단';
      });
    }
  }

  void _acknowledgeActiveAlert() {
    _alertCoordinator.acknowledgeCurrent();
    setState(() {
      _helpChoice = false;
      _helpChoiceIncident = null;
    });

    _syncAlertPulse();
    _pruneResolvedIncidents();
  }

  void _pruneResolvedIncidents() {
    final waiting = {
      ..._alertCoordinator.pendingAlerts,
      if (_alertCoordinator.activeAlert != null) _alertCoordinator.activeAlert!,
    };
    _incidents.removeWhere((alert, incident) =>
        !waiting.contains(alert) && !incident.needsDelivery);
  }

  void _restartAlertPulse() {
    _alertPulseController
      ..stop()
      ..reset();
  }

  void _syncAlertPulse() {
    if (_alertCoordinator.hasActiveAlert) {
      _restartAlertPulse();
      return;
    }

    _alertPulseController
      ..stop()
      ..reset();
  }

  void _openSignTranslation() {
    if (_currentPage == _SafeHubPage.signTranslation) {
      return;
    }

    setState(() {
      _currentPage = _SafeHubPage.signTranslation;
    });
  }

  void _returnHome() {
    if (_currentPage == _SafeHubPage.home) {
      return;
    }

    setState(() {
      _currentPage = _SafeHubPage.home;
    });
  }

  @override
  void dispose() {
    _responseTicker?.cancel();
    _disasterTimer?.cancel();
    _signOverlayTimer?.cancel();
    _speechGeneration++;
    _messageController.dispose();
    _ttsService.dispose();
    _sttService.dispose();
    if (!_demo) {
      unawaited(_voiceRecorderService.dispose());
      unawaited(_audioService.dispose());
    }
    unawaited(_cameraStreamService.dispose());
    _cameraImage?.dispose();
    _cameraImage = null;
    _alertPulseController.dispose();
    if (!_demo) _mqttReceiver.disconnect();
    super.dispose();
  }

  static const _ink = Color(0xFFFFF6F1);
  static const _muted = Color(0xFFE0CEC5);
  static const _blue = Color(0xFFFFA49A);
  static const _coral = Color(0xFFFF8B7C);
  static const _surface = Color(0xB8201C1A);

  void _addMessage(String speaker, String text) {
    _conversation.add((speaker: speaker, text: text, time: DateTime.now()));
    if (_conversation.length > 100) _conversation.removeAt(0);
  }

  String _clock(DateTime? time) => time == null ? '기록 없음' :
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  String _room(Object? room) => switch (room) {
    'bedroom' => '침실', 'bathroom' => '화장실', 'livingroom' => '거실', _ => '공간 미확인',
  };

  void _reply(SafeHubAlert alert, bool help, {String? message}) {
    // This callback only resolves the exact visible incident.
    if (!identical(_alertCoordinator.activeAlert, alert)) return;
    final incident = _incidents[alert];
    if (incident == null) return;
    setState(() {
      incident.reply(needsHelp: help, helpMessage: message);
      _helpChoice = false;
      _lastHelpDismissedAt = DateTime.now();
      _addMessage('내 응답 · 직접 선택', help ? message ?? '도움이 필요해요' : '괜찮아요');
      _recentEvents.insert(0, {
        'event': help ? '사용자가 도움을 요청함 · 가족 전송 미연결' : '사용자가 괜찮다고 응답함',
        'location': alert.data['location'], '_receivedAt': DateTime.now().toIso8601String(),
      });
      if (_recentEvents.length > 5) _recentEvents.removeLast();
    });
    _acknowledgeActiveAlert();
  }

  void _prepareHelpChoice({String? sign}) {
    _helpChoice = true;
    _helpContextSign = sign;
    _helpKind = CareHelpKind.familyVisit;
    final active = _alertCoordinator.activeAlert;
    _helpChoiceIncident = active?.kind == AlertKind.fall ? active : null;
  }

  void _beginHelpChoice({String? sign}) {
    setState(() => _prepareHelpChoice(sign: sign));
  }

  void _dismissHelpChoice() {
    setState(() {
      _helpChoice = false;
      _helpChoiceIncident = null;
      _lastHelpDismissedAt = DateTime.now();
    });
  }

  String get _helpMessage => _helpKind.message(
    sign: _helpContextSign,
    location: _helpChoiceIncident == null ? null : _room(_helpChoiceIncident!.data['location']),
  );

  void _requestHelp() {
    final target = _helpChoiceIncident;
    final active = _alertCoordinator.activeAlert;
    if (!identical(target, active)) return;
    final message = _helpMessage;
    if (target != null) {
      _reply(target, true, message: message);
    } else {
      setState(() {
        _localHelpRequest = message;
        _helpChoice = false;
        _lastHelpDismissedAt = DateTime.now();
        _addMessage('내 응답 · 직접 선택', message);
      });
    }
  }

  void _typeMessage() {
    setState(() => _showTextComposer = true);
  }

  void _testDisaster() {
    final data = <String, dynamic>{
      'DST_SE_NM': '호우', 'EMRG_STEP_NM': '긴급재난',
      'RCPTN_RGN_NM': '시연 지역', 'CRT_DT': DateTime.now().toIso8601String(),
      'MSG_CN': '[UI 테스트] 재난 문자 내용과 확인 버튼을 점검하는 예시입니다.',
      'source': 'ui_test',
    };
    final activated = _alertCoordinator.submit(SafeHubAlert(kind: AlertKind.disaster, priority: 8, data: data));
    setState(() {});
    if (activated) {
      _helpChoice = false;
      _helpChoiceIncident = null;
      FocusScope.of(context).unfocus();
      _interruptNormalSpeech();
      _restartAlertPulse();
    }
  }

  void _submitTypedMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _addMessage('직접 입력', text);
      _messageController.clear();
      _showTextComposer = false;
    });
    FocusScope.of(context).unfocus();
  }

  Widget _textComposer() => _section('직접 입력해서 대화하기', [
    TextField(
      controller: _messageController, maxLines: 3, maxLength: 500,
      style: const TextStyle(color: _ink, fontSize: 22),
      decoration: const InputDecoration(
        hintText: '전하고 싶은 말을 입력해 주세요',
        hintStyle: TextStyle(color: _muted),
      ),
    ),
    Wrap(spacing: 12, runSpacing: 12, children: [
      _button('대화에 추가', Icons.send_outlined, _submitTypedMessage, primary: true),
      _button('취소', Icons.close, () {
        setState(() { _showTextComposer = false; _messageController.clear(); });
        FocusScope.of(context).unfocus();
      }),
    ]),
  ]);

  void _replaySign() {
    if (_signText == '수어 인식 대기 중' || _sttRecording || _sttBusy) return;
    if (_demo) {
      setState(() => _ttsStatus = '미리보기 · 실제 음성 출력 없음');
      return;
    }
    if (AppConfig.ttsServerUrl.trim().isEmpty) {
      setState(() => _ttsStatus = '음성 서비스 미설정 · 텍스트로 확인해 주세요');
      return;
    }
    unawaited(_speakTranslation(_signSpeechPolicy.phraseFor(_signText), ++_speechGeneration));
  }

  Text _text(String value, {double size = 20, Color color = _ink, FontWeight weight = FontWeight.w500}) =>
    Text(value, style: TextStyle(fontSize: size, color: color, fontWeight: weight, height: 1.45));

  Widget _button(String label, IconData icon, VoidCallback? action, {bool primary = false, bool urgent = false}) =>
    FilledButton.icon(
      onPressed: action,
      style: FilledButton.styleFrom(
        backgroundColor: urgent ? _coral : primary ? _blue : const Color(0x26FFF0E6),
        foregroundColor: primary || urgent ? const Color(0xFF3C211D) : _ink,
        disabledBackgroundColor: const Color(0x18201C1A),
        disabledForegroundColor: _muted,
        side: const BorderSide(color: Color(0x33FFFFFF)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ), icon: Icon(icon, size: 21), label: Text(label, style: const TextStyle(fontSize: 22)));

  Widget _panel(List<Widget> children, {Color color = _surface}) => ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color,
          gradient: const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xF0392F2A), Color(0xF024201E)],
          ),
          border: Border.all(color: const Color(0x2BFFFFFF)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      ),
    ),
  );

  Widget _section(String title, List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [_text(title, size: 22, weight: FontWeight.w600), const SizedBox(height: 12), ...children],
  );

  Widget _separator() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 18),
    child: Divider(height: 1, color: Color(0x26FFFFFF)),
  );

  Widget _columns(Widget left, Widget right) => LayoutBuilder(builder: (context, constraints) {
    if (constraints.maxWidth < 850) {
      return Column(children: [left, const SizedBox(height: 20), right]);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(flex: 6, child: left), const SizedBox(width: 26), Expanded(flex: 5, child: right),
    ]);
  });

  Widget _background() => Positioned.fill(child: Stack(fit: StackFit.expand, children: [
    Image.asset('assets/images/safehub_living_room.png', fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => const ColoredBox(color: Color(0xFF29231F))),
    const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [Color(0xB01D1715), Color(0x99241A18)],
    ))),
  ]));

  Widget _nav(String label, _SafeHubPage page, VoidCallback action) {
    final selected = _currentPage == page;
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(
        color: selected ? _blue : Colors.transparent, width: 2))),
      child: TextButton(
        onPressed: action,
        style: TextButton.styleFrom(
          foregroundColor: selected ? _blue : _ink,
          minimumSize: const Size(88, 56),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 22)),
      ),
    );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
    child: LayoutBuilder(builder: (context, constraints) {
      final brand = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _text('SafeHub.', size: 28, weight: FontWeight.w700, color: _blue),
        _text('배리어프리 스마트홈', size: 16, color: _muted),
      ]);
      final navigation = Wrap(spacing: 18, children: [
        _nav('홈', _SafeHubPage.home, _returnHome),
        _nav('대화', _SafeHubPage.signTranslation, _openSignTranslation),
        _nav('설정', _SafeHubPage.appliances, () => setState(() => _currentPage = _SafeHubPage.appliances)),
      ]);
      final status = _text(_demo ? 'UI 테스트 · 실제 장치 연결 없음' : '메시지 허브 · $_connectionStatus', size: 16, color: _muted);
      if (constraints.maxWidth < 950) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 24, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [brand, navigation]),
          const SizedBox(height: 10), status,
        ]);
      }
      return Row(children: [brand, const Spacer(), navigation, const Spacer(), status]);
    }),
  );

  void _testFall() => _handleEvent({
    'message_id': 'ui-test-${DateTime.now().microsecondsSinceEpoch}',
    'event': 'fall_detected', 'location': 'bathroom', 'priority': 9, 'source': 'ui_test',
  });

  Widget _footer() => ColoredBox(
    color: const Color(0xB0191614),
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12), child: Column(children: [
      if (_demo) ...[
        Wrap(spacing: 8, runSpacing: 8, children: [
          _button('낙상 테스트', Icons.warning_amber, _testFall),
          _button('재난 문자 테스트', Icons.campaign_outlined, _testDisaster),
          _button('수어 · 아프다', Icons.sign_language, () => _handleSignText('아프다')),
          _button('수어 · 괜찮다', Icons.sign_language, () => _handleSignText('괜찮다')),
          _button('가족 자막 예시', Icons.subtitles_outlined, () => setState(() {
            _sttText = '어디가 아프세요?';
            _addMessage('가족의 말 · 음성 자막', _sttText);
          })),
        ]), const SizedBox(height: 12),
      ],
      _text(_demo ? '화면 동작 미리보기 · 실제 감지나 가족 전송이 아닙니다' : 'SafeHub · 소통과 생활 안전을 한곳에서', size: 13, color: _muted),
    ])),
  );

  @override
  Widget build(BuildContext context) {
    final active = _alertCoordinator.activeAlert;
    return Scaffold(backgroundColor: const Color(0xFF29231F), body: Stack(children: [
      _background(),
      SafeArea(child: Column(children: [
        _header(),
        const Divider(height: 1, color: Color(0x26FFFFFF)),
        Expanded(child: LayoutBuilder(builder: (context, constraints) => SingleChildScrollView(
          padding: EdgeInsets.all(constraints.maxWidth < 700 ? 18 : 28),
          child: switch (_currentPage) {
            _SafeHubPage.home => _home(),
            _SafeHubPage.signTranslation => _conversationPage(constraints.maxHeight),
            _SafeHubPage.appliances => _settings(),
          },
        ))),
        _footer(),
      ])),
      if (_showSignOverlay && active == null && _currentPage != _SafeHubPage.signTranslation && !_helpChoice)
        Positioned(bottom: _demo ? 170 : 50, left: 26, right: 26, child: IgnorePointer(child: Semantics(liveRegion: true,
          child: _panel([_text('수어 인식 · $_signText', size: 22, color: _blue)])))),
      if (_helpChoice && active == null) _helpDialog(),
      if (active?.kind == AlertKind.fall) _fallDialog(active!),
      if (active?.kind == AlertKind.disaster) DisasterOverlay(disaster: active!.data, pulseAnimation: _alertPulseController, onAcknowledge: _acknowledgeActiveAlert),
    ]));
  }

  Widget _home() {
    final requests = _incidents.entries.where((i) => i.value.needsDelivery).toList();
    final pendingCount = requests.length + (_localHelpRequest == null ? 0 : 1);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _text('우리 집 상태', size: 16, color: _blue), const SizedBox(height: 8),
      _text(pendingCount > 0 ? '전달되지 않은 도움 요청이 있어요' : '새로운 위험 알림이 없어요', size: 28, weight: FontWeight.w600),
      const SizedBox(height: 10), _text('수신된 알림 기준 · 센서 상태는 연결 확인이 필요해요.', color: _muted),
      const SizedBox(height: 24),
      if (pendingCount > 0) ...[
        _panel([
          _text('가족 알림 $pendingCount건 · 전송되지 않음', size: 23, color: _coral),
          const SizedBox(height: 12),
          ...requests.map((i) => Padding(padding: const EdgeInsets.only(bottom: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _text('${_room(i.key.data['location'])} · ${i.value.requestReason!}'),
            _text('사건 수신 · ${_clock(i.value.openedAt)}', size: 16, color: _muted),
            const SizedBox(height: 8),
            _button('이 도움 요청 취소', Icons.close, () => setState(() {
              i.value.cancelUnsentRequest();
              _pruneResolvedIncidents();
            })),
          ]))),
          if (_localHelpRequest != null) _text(_localHelpRequest!),
          _text('가족 알림 서비스가 연결되지 않았어요. 지금은 휴대전화로 직접 연락해 주세요.', color: _muted),
          if (_localHelpRequest != null) ...[
            const SizedBox(height: 12), _button('내 도움 요청 취소', Icons.close, () => setState(() => _localHelpRequest = null)),
          ],
        ]), const SizedBox(height: 24),
      ],
      _columns(_panel([
        _section('가족과 대화', [
          _text('내 수어', size: 16, color: _muted), const SizedBox(height: 10),
          _text(_signText, size: 28, color: _blue),
          const SizedBox(height: 16), _text('수어와 음성 자막으로 대화하세요.', color: _muted),
          const SizedBox(height: 20), Wrap(spacing: 12, runSpacing: 12, children: [
            _button('대화 시작하기', Icons.forum_outlined, _openSignTranslation, primary: true),
            _button('도움 요청하기', Icons.front_hand_outlined, _beginHelpChoice),
          ]),
        ]),
        _separator(),
        _section('공간별 상태', [
          _roomStatus('bedroom'),
          _roomStatus('bathroom'),
        ]),
        _separator(),
        _section('최근 알림', [
          if (_recentEvents.isEmpty) _text('아직 수신한 안전 이벤트가 없어요.', color: _muted),
          ..._recentEvents.map((e) => Padding(padding: const EdgeInsets.only(bottom: 18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _text('${_room(e['location'])} · ${e['event'] == 'fall_detected' ? '낙상 의심' : e['event']}', size: 20),
            _text('${_clock(DateTime.tryParse(e['_receivedAt']?.toString() ?? ''))} · ${e['source'] == 'ui_test' ? 'UI 테스트 입력' : '수신 기록'}', size: 16, color: _muted),
          ]))),
        ]),
      ]), _panel([
        _section('장치 연결', [
          _status('수어 카메라', _cameraFresh ? '영상 수신 중' : _cameraConnected ? '영상 수신 대기 · 연결만 확인' : '연결 확인 필요'),
          _status('메시지 허브', _connectionStatus),
          _status('CSI 센서', '상태 확인 미연동'),
          _text('카메라 주소 · ${AppConfig.cameraHost.isEmpty ? '미설정' : AppConfig.cameraHost}:${AppConfig.cameraPort}', size: 16, color: _muted),
          _text('마지막 이벤트 수신 · ${_clock(_lastCsiReceived)}', size: 16, color: _muted),
          const SizedBox(height: 12), _text('허브 연결만으로 센서 작동 여부를 판단하지 않습니다.', size: 16, color: _muted),
        ]),
        _separator(),
        _section('재난 정보', [
          _text(_disasterStatus, color: _blue),
          _text('마지막 조회 · ${_clock(_disasterCheckedAt)}', size: 16, color: _muted),
          const SizedBox(height: 12),
          _text(_latestDisaster?['MSG_CN']?.toString() ?? '표시할 재난 정보가 없어요.', size: 19),
          if (_latestDisaster != null) _text('발표 · ${_latestDisaster!['CRT_DT'] ?? '시간 미확인'}', size: 16, color: _muted),
        ]),
      ])),
    ]);
  }

  Widget _status(String label, String value) => Padding(padding: const EdgeInsets.symmetric(vertical: 12),
    child: Wrap(spacing: 16, runSpacing: 6, children: [_text(label, size: 18), _text(value, size: 18, color: _muted)]));

  Widget _roomStatus(String room) {
    final events = _recentEvents.where((event) => event['location'] == room);
    final latest = events.isEmpty ? null : events.first;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(room == 'bedroom' ? Icons.bed_outlined : Icons.bathroom_outlined, color: _blue, size: 26),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _text(_room(room), size: 21),
          _text(latest == null ? '이벤트 수신 대기 · 센서 상태 미확인' :
            '최근 수신 · ${latest['event'] == 'fall_detected' ? '낙상 의심' : latest['event']}', size: 18, color: _muted),
        ])),
      ]),
    );
  }

  Widget _conversationPage(double availableHeight) {
    final cameraHeight = (availableHeight * 0.22).clamp(110.0, 220.0).toDouble();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _text('대화', size: 30, weight: FontWeight.w600),
      const SizedBox(height: 14),
      _columns(_panel([
        _section('수어로 말하기', [
          SizedBox(height: cameraHeight, width: double.infinity, child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: ColoredBox(color: const Color(0xFF171514), child:
              _cameraImage != null && _cameraFresh
                ? RawImage(image: _cameraImage, fit: BoxFit.contain)
                : Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.videocam_off_outlined, color: _muted, size: 32),
                  const SizedBox(height: 8),
                  _text(_cameraConnected ? '연결됨 · 영상 수신 대기' : '카메라 연결을 기다리고 있어요', size: 18, color: _muted),
                ])),
            ),
          )),
          const SizedBox(height: 12),
          Semantics(liveRegion: true, child: _text(_signText, size: 30, color: _blue)),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            _button('다시 읽기', Icons.volume_up_outlined,
              _sttRecording || _sttBusy || _signText == '수어 인식 대기 중' ? null : _replaySign),
            Row(mainAxisSize: MainAxisSize.min, children: [
              _text('자동 읽기', size: 18),
              Switch(value: _autoSpeak, activeColor: _blue, onChanged: (value) {
                setState(() => _autoSpeak = value);
                if (!value) {
                  _speechGeneration++;
                  if (!_demo) unawaited(_audioService.stop());
                }
              }),
            ]),
          ]),
          const SizedBox(height: 6), _text(_ttsStatus, size: 16, color: _muted),
        ]),
      ]), _panel([
        _section('가족의 말 · 음성 자막', [
          Semantics(liveRegion: true, child: _text(
            _sttText == '음성 인식 대기 중' ? '아직 가족의 음성 자막이 없어요.' : _sttText, size: 30)),
          const SizedBox(height: 14),
          _button(_sttBusy ? '자막 변환 중' : _sttRecording ? '말하기 종료 · 자막 보기' : '가족 말하기 시작',
            _sttRecording ? Icons.stop : Icons.mic_none,
            _sttBusy || _demo ? null : _toggleSttRecording, primary: true),
          const SizedBox(height: 10), _text(_sttStatus, size: 16, color: _muted),
          const SizedBox(height: 14),
          Wrap(spacing: 10, runSpacing: 10, children: [
            _button('직접 입력', Icons.keyboard_outlined, _typeMessage),
            _button('도움 요청하기', Icons.front_hand_outlined, _beginHelpChoice),
          ]),
          if (_showTextComposer) ...[const SizedBox(height: 16), _textComposer()],
        ]),
      ])),
      const SizedBox(height: 16),
      _panel([
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: _text('지난 대화', size: 22, weight: FontWeight.w600),
          subtitle: _text('최근 ${_conversation.length}개 · 눌러서 펼치기', size: 16, color: _muted),
          children: [
            _text('최신순 · 최대 100개 · 앱 종료 시 지워집니다', size: 16, color: _muted),
            if (_conversation.isEmpty) _text('아직 대화 기록이 없어요.', color: _muted),
            ..._conversation.reversed.map((message) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: _text(message.text, size: 22, color: message.speaker.startsWith('내') ? _blue : _ink),
              subtitle: _text('${message.speaker} · ${_clock(message.time)}', size: 16, color: _muted),
            )),
          ],
        ),
      ]),
    ]);
  }

  Widget _overlay(Widget child) => Positioned.fill(child: BlockSemantics(child: Material(
    color: const Color(0xF21D1715),
    child: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 860), child: child,
    )))),
  )));

  Widget _helpContents() => _panel([
    _text('도움 선택', color: _blue), const SizedBox(height: 12),
    _text(_helpContextSign != null ? '“$_helpContextSign”라고 표현했어요' : '도움이 필요하신가요?', size: 32, weight: FontWeight.w700),
    const SizedBox(height: 14), _text('어떤 도움이 필요한지 선택해 주세요.'),
    const SizedBox(height: 16),
    Wrap(spacing: 12, runSpacing: 12, children: CareHelpKind.values.map((kind) => _button(
      kind.label, kind == CareHelpKind.familyVisit ? Icons.person_outline : Icons.phone_outlined,
      () => setState(() => _helpKind = kind), primary: _helpKind == kind,
    )).toList()),
    const SizedBox(height: 20), _text('가족에게 전할 문장', size: 16, color: _muted),
    _text(_helpMessage, size: 23, color: _blue),
    const SizedBox(height: 12),
    _text('가족 알림 서비스 미연결 · 선택해도 실제 전송되지는 않습니다.', color: _muted),
    const SizedBox(height: 24), Wrap(spacing: 12, runSpacing: 12, children: [
      _button('이 문장으로 요청 만들기', Icons.front_hand_outlined, _requestHelp, urgent: true),
      _button('돌아가기', Icons.arrow_back, _dismissHelpChoice),
    ]),
  ]);

  Widget _helpDialog() => _overlay(_helpContents());

  Widget _fallDialog(SafeHubAlert alert) {
    final incident = _incidents[alert]!;
    final remaining = incident.secondsLeft(DateTime.now());
    if (_helpChoice && identical(_helpChoiceIncident, alert)) {
      return _overlay(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _text('${_room(alert.data['location'])} · 낙상 의심 알림 확인 중', color: _coral),
        const SizedBox(height: 12), _helpContents(),
        const SizedBox(height: 16),
        _text(incident.needsDelivery ? '사용자 미응답 요청 · 아직 전송되지 않음' : '응답 대기 · $remaining초', color: _muted),
      ]));
    }
    return _overlay(Semantics(liveRegion: true, child: _panel([
      _text(alert.data['source'] == 'ui_test' ? '안전 알림 · UI 테스트 입력' : '안전 알림 · 수신 이벤트', color: _coral),
      const SizedBox(height: 18), _text('${_room(alert.data['location'])}에서 낙상이 의심돼요', size: 34, weight: FontWeight.w700),
      const SizedBox(height: 12), _text('지금 상태를 알려주세요.', size: 24),
      const SizedBox(height: 24),
      if (_helpChoice) ...[_text('“아프다”라고 인식했어요. 도움이 필요하신가요?', color: _blue, size: 24), const SizedBox(height: 16)],
      Wrap(spacing: 14, runSpacing: 14, children: [
        _button('괜찮아요', Icons.check_circle_outline, () => _reply(alert, false), primary: true),
        _button('도움이 필요해요', Icons.front_hand_outlined, _beginHelpChoice, urgent: true),
      ]),
      const SizedBox(height: 24),
      _text(incident.needsDelivery ? '아직 응답이 없어 가족 알림 요청을 만들었어요.' : '응답 대기 · $remaining초', color: incident.needsDelivery ? _coral : _muted),
      if (incident.needsDelivery) _text('전송되지 않음 · 가족 알림 서비스 미연결', color: _coral),
      _text('대기 시간은 설정값입니다. 응답이 늦어도 위 버튼으로 상태를 알려주세요.', size: 16, color: _muted),
      const SizedBox(height: 16),
      _text('수어 인식 결과 · $_signText', color: _blue),
      _text('인식 결과를 확인한 뒤 버튼으로 응답해 주세요.', size: 16, color: _muted),
      if (_demo) ...[
        const SizedBox(height: 18),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _button('테스트 · 아프다', Icons.sign_language, () => _handleSignText('아프다')),
          _button('테스트 · 괜찮다', Icons.sign_language, () => _handleSignText('괜찮다')),
          _button('테스트 · 시간 종료', Icons.timer_outlined, () => setState(() => incident.tick(incident.openedAt.add(incident.wait)))),
          _button('테스트 · 다음 낙상', Icons.add_alert_outlined, _testFall),
        ]),
      ],
      if (_alertCoordinator.pendingAlerts.isNotEmpty) _text('다음 확인 알림 ${_alertCoordinator.pendingAlerts.length}건', color: _muted),
    ])));
  }

  Widget _settings() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _text('설정', size: 16, color: _blue),
    const SizedBox(height: 8), _text('필요한 기능만 편하게', size: 28, weight: FontWeight.w600),
    const SizedBox(height: 24),
    _panel([
      _text('안전 알림', size: 20, weight: FontWeight.w600),
      const SizedBox(height: 18),
      Wrap(spacing: 22, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
        _text('낙상 응답 대기 시간', size: 20),
        DropdownButton<int>(value: _responseSeconds, dropdownColor: const Color(0xFF332923), style: const TextStyle(color: _ink, fontSize: 20),
          items: [10, 30, 60].map((n) => DropdownMenuItem(value: n, child: Text('$n초'))).toList(),
          onChanged: (v) { if (v != null) setState(() => _responseSeconds = v); }),
      ]),
      _text('새 알림부터 적용 · 시연용 설정', size: 15, color: _muted),
      const SizedBox(height: 14), _text('가족 알림 · LED · 베드셰이커 연결 전', size: 15, color: _muted),
    ]),
    const SizedBox(height: 24),
    _panel([
      _text('보조 기능 · 가전 단축키', size: 20, weight: FontWeight.w600),
      const SizedBox(height: 12), _text('기존 단축키 저장과 MQTT 등록 기능을 유지합니다.', size: 15, color: _muted),
      const SizedBox(height: 20),
      SizedBox(height: 600, child: AppliancePanel(
        controls: _appliances, connected: _mqttConnected, latestSign: _signText,
        loadShortcuts: !_demo, publishShortcutCommand: _demo ? null : _mqttReceiver.publishShortcutCommand,
      )),
    ]),
  ]);
}
