import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../core/alert_coordinator.dart';
import '../core/appliance_controls.dart';
import '../core/event_manager.dart';
import '../mqtt/mqtt_receiver.dart';
import '../services/audio_service.dart';
import '../services/camera_stream_service.dart';
import '../services/disaster_service.dart';
import '../services/sign_speech_policy.dart';
import '../services/stt_service.dart';
import '../services/tts_service.dart';
import '../services/live_caption_service.dart';
import '../services/wifi_sensing_service.dart';
import 'connection_settings_page.dart';
import 'utils/disaster_display.dart';
import 'widgets/disaster_overlay.dart';
import 'widgets/appliance_panel.dart';
import 'widgets/wifi_sensing_panel.dart';
import 'widgets/wifi_action_status.dart';
import 'widgets/live_caption_panel.dart';

enum _SafeHubPage { home, signTranslation, appliances, wifiSensing }

typedef CameraFrameDecoder = void Function(
  Uint8List frame,
  int width,
  int height,
  ui.PixelFormat format,
  void Function(ui.Image image) onDecoded,
);

class SafeHubHomePage extends StatefulWidget {
  const SafeHubHomePage({
    super.key,
    this.onSettingsSaved,
    this.cameraStreamService,
    this.cameraDecoder,
  });
  final VoidCallback? onSettingsSaved;
  final CameraStreamService? cameraStreamService;
  final CameraFrameDecoder? cameraDecoder;

  @override
  State<SafeHubHomePage> createState() => _SafeHubHomePageState();
}

class _SafeHubHomePageState extends State<SafeHubHomePage>
    with SingleTickerProviderStateMixin {
  final EventManager _eventManager = EventManager();
  final ApplianceControls _appliances = ApplianceControls();
  final DisasterService _disasterService = DisasterService();
  final AlertCoordinator _alertCoordinator = AlertCoordinator();
  final AudioService _audioService = AudioService();
  final SignSpeechPolicy _signSpeechPolicy = SignSpeechPolicy();

  late final MqttReceiver _mqttReceiver;
  late final AnimationController _alertPulseController;
  late final TtsService _ttsService;
  late final SttService _sttService;
  late final LiveCaptionService _captions;
  bool _resumeCaptionsAfterAlert = false;
  late final CameraStreamService _cameraStreamService;
  final WifiSensingService _wifiSensingService = WifiSensingService(
    baseUrl: AppConfig.csiServiceUrl,
  );

  Timer? _disasterTimer;
  Timer? _signOverlayTimer;
  Timer? _clockTimer;
  final _clock = ValueNotifier<DateTime>(DateTime.now());

  _SafeHubPage _currentPage = _SafeHubPage.home;

  bool _mqttConnected = false;
  bool _mqttStarted = false;
  String _connectionStatus = '연결 중';
  String _signText = '수어 인식 대기 중';
  String _ttsStatus = '음성 안내 대기';
  static const int _cameraWidth = 320;
  static const int _cameraHeight = 240;

  ui.Image? _cameraImage;
  bool _cameraConnected = false;
  bool _cameraDecodeInProgress = false;
  int _cameraGeneration = 0;
  bool _showSignOverlay = false;

  Map<String, dynamic>? _latestDisaster;

  String? _lastDisasterId;
  int _speechGeneration = 0;

  final List<Map<String, dynamic>> _recentEvents = [];

  @override
  void initState() {
    super.initState();
    _cameraStreamService = widget.cameraStreamService ?? CameraStreamService();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _clock.value = DateTime.now();
    });

    _alertPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _ttsService = TtsService(baseUrl: AppConfig.ttsServerUrl);

    _sttService = SttService(baseUrl: AppConfig.sttServerUrl);
    _captions = LiveCaptionService(
        transcribe: _sttService.transcribe,
        connectStream: _sttService.connectCaptions);
    if (!AppConfig.localPreview && AppConfig.sttServerUrl.trim().isNotEmpty) {
      unawaited(_captions.start());
    }

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

    if (AppConfig.localPreview) {
      _connectionStatus = '체험 모드';
    } else {
      if (AppConfig.mqttConfigured) {
        _mqttStarted = true;
        _connectMqtt();
      } else {
        _connectionStatus = '주소 미설정';
      }
      if (AppConfig.disasterConfigured) _startDisasterPolling();
    }
    if ((!AppConfig.localPreview && AppConfig.cameraConfigured) ||
        widget.cameraStreamService != null) {
      _connectCamera();
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
            _cameraGeneration++;
            _cameraConnected = connected;

            if (!connected) {
              _cameraImage = null;
            }
          });

          previousImage?.dispose();
        },
      ),
    );
  }

  void _handleCameraFrame(Uint8List frame) {
    const expectedBytes = _cameraWidth * _cameraHeight * 4;

    if (!_cameraConnected || frame.lengthInBytes != expectedBytes) {
      return;
    }

    if (_cameraDecodeInProgress) {
      return;
    }

    _cameraDecodeInProgress = true;
    final generation = _cameraGeneration;

    (widget.cameraDecoder ?? ui.decodeImageFromPixels)(
      frame,
      _cameraWidth,
      _cameraHeight,
      ui.PixelFormat.rgba8888,
      (image) {
        _cameraDecodeInProgress = false;

        if (!mounted ||
            !_cameraConnected ||
            generation != _cameraGeneration) {
          image.dispose();
          return;
        }

        final previousImage = _cameraImage;

        setState(() {
          _cameraImage = image;
        });

        previousImage?.dispose();
      },
    );
  }

  void _startDisasterPolling() {
    _fetchLatestDisaster();

    _disasterTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      _fetchLatestDisaster();
    });
  }

  Future<void> _fetchLatestDisaster() async {
    try {
      final disaster = await _disasterService.fetchLatest();

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
          !DisasterService.isNewerThan(disasterData, currentDisaster)) {
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
    final shouldSpeak =
        ttsConfigured &&
        !alertActive &&
        _signSpeechPolicy.shouldSpeak(cleanText);

    final String nextTtsStatus;

    if (!ttsConfigured) {
      nextTtsStatus = '텍스트로 표시됨';
    } else if (alertActive) {
      nextTtsStatus = '긴급 경보 우선 안내 중';
    } else if (!shouldSpeak) {
      nextTtsStatus = '최근 음성 안내와 동일';
    } else {
      nextTtsStatus = '음성 변환 준비 중';
    }

    _signOverlayTimer?.cancel();

    setState(() {
      _signText = cleanText;
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

    unawaited(_speakTranslation(speechText, generation));
  }

  Future<void> _speakTranslation(String text, int generation) async {
    if (AppConfig.ttsServerUrl.trim().isEmpty) {
      return;
    }

    if (_alertCoordinator.hasActiveAlert) {
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

      await _audioService.playBytes(bytes);

      if (mounted &&
          generation == _speechGeneration &&
          !_alertCoordinator.hasActiveAlert) {
        setState(() {
          _ttsStatus = '음성으로 전달됨';
        });
      }
    } catch (_) {
      if (mounted && generation == _speechGeneration) {
        setState(() {
          _ttsStatus = '텍스트 번역은 정상 표시 중';
        });
      }
    }
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

    final eventData = Map<String, dynamic>.from(event);
    eventData['_receivedAt'] ??= DateTime.now().toIso8601String();

    var activated = false;

    if (_isEmergencyEvent(eventData)) {
      final priority = _getEventPriority(eventData);

      activated = _alertCoordinator.submit(
        SafeHubAlert(kind: AlertKind.fall, priority: priority, data: eventData),
      );

      print('[ALERT] fall submitted activated=$activated priority=$priority');
    } else {
      print('[ALERT] non-emergency event added to recent events only');
    }

    setState(() {
      _recentEvents.insert(0, eventData);

      if (_recentEvents.length > 5) {
        _recentEvents.removeLast();
      }
    });

    if (activated) {
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
    _speechGeneration++;
    unawaited(
      _audioService.stop().catchError((Object error, StackTrace stack) {
        debugPrint('[음성 안내 중단 실패] $error');
      }),
    );
    _resumeCaptionsAfterAlert = _resumeCaptionsAfterAlert || _captions.enabled;
    unawaited(_captions.pause(reason: '안전 경보 확인 후 자막을 재개합니다'));

    if (mounted) {
      setState(() {
        _ttsStatus = '안전 알림으로 음성 안내 중단';
      });
    }
  }

  void _acknowledgeActiveAlert() {
    _alertCoordinator.acknowledgeCurrent();

    setState(() {});

    _syncAlertPulse();
    if (!_alertCoordinator.hasActiveAlert && _resumeCaptionsAfterAlert) {
      _resumeCaptionsAfterAlert = false;
      unawaited(_captions.start());
    }
  }

  void _restartAlertPulse() {
    _alertPulseController
      ..stop()
      ..reset()
      ..repeat(reverse: true);
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

  Future<void> _openConnectionSettings() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ConnectionSettingsPage()),
    );
    if (saved == true && mounted) widget.onSettingsSaved?.call();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _clock.dispose();
    _wifiSensingService.close();
    _disasterTimer?.cancel();
    _signOverlayTimer?.cancel();
    _speechGeneration++;
    _ttsService.dispose();
    _sttService.dispose();
    _captions.dispose();
    unawaited(
      _audioService.dispose().catchError((Object error, StackTrace stack) {
        debugPrint('[음성 안내 종료 실패] $error');
      }),
    );
    unawaited(_cameraStreamService.dispose());
    _cameraImage?.dispose();
    _cameraImage = null;
    _alertPulseController.dispose();
    if (_mqttStarted) _mqttReceiver.disconnect();
    super.dispose();
  }

  // SafeHub glass layout v4 — presentation only.
  static const _ink = Color(0xFFF3F1EE);
  static const _muted = Color(0xFFC4C1BD);
  static const _blue = Color(0xFFB9D2FA);
  static const _green = Color(0xFFA5DDAA);
  static const _amber = Color(0xFFF3D49B);
  String _selectedRoom = 'all';
  String? _detailTitle;
  String _detailBody = '';

  Text _text(
    String value, {
    double size = 18,
    Color color = _ink,
    FontWeight weight = FontWeight.w500,
    int lines = 1,
  }) => Text(
    value,
    maxLines: lines,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontSize: size,
      color: color,
      fontWeight: weight,
      height: 1.3,
      letterSpacing: -0.3,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final activeAlert = _alertCoordinator.activeAlert;
    return Scaffold(
      backgroundColor: const Color(0xFF24221F),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/safehub_living_room.png',
              fit: BoxFit.cover,
              errorBuilder:
                  (context, error, stackTrace) =>
                      const ColoredBox(color: Color(0xFF393731)),
            ),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x66201D19),
                    Color(0x33201D19),
                    Color(0x88201D19),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(34, 22, 34, 30),
              child: Column(
                children: [
                  _glassHeader(),
                  ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xEE273744),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0x778CABD0)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              AppConfig.setupError ??
                                  (AppConfig.localPreview
                                      ? '장비 연결 전 체험 · 실제 수어·안전 감지는 동작하지 않습니다. '
                                          '와이파이 센싱에서 모의 신호를 시작해 수집·학습을 체험하세요.'
                                      : '실제 장비 연결 모드 · 장비에서 새 데이터가 들어오면 표시합니다.'),
                              style: const TextStyle(
                                color: _ink,
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          FilledButton.icon(
                            onPressed: _openConnectionSettings,
                            icon: const Icon(Icons.settings_input_component),
                            label: const Text('연결 설정'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(132, 48),
                              backgroundColor: _blue,
                              foregroundColor: const Color(0xFF202B3D),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Expanded(
                    child:
                        _currentPage == _SafeHubPage.home
                            ? LayoutBuilder(
                              builder: (context, constraints) {
                                if (constraints.maxWidth < 1100) {
                                  return _compactDashboard(
                                    activeAlert,
                                    constraints.maxWidth,
                                  );
                                }
                                return SingleChildScrollView(
                                  child: SizedBox(
                                    height: math.max(
                                      840,
                                      constraints.maxHeight,
                                    ),
                                    child: _glassDashboard(activeAlert),
                                  ),
                                );
                              },
                            )
                            : _currentPage == _SafeHubPage.wifiSensing
                            ? WifiSensingPanel(
                              service: _wifiSensingService,
                              allowDummy: AppConfig.localPreview,
                            )
                            : _currentPage == _SafeHubPage.appliances
                            ? AppliancePanel(
                              controls: _appliances,
                              allowPreview: AppConfig.localPreview,
                              connected: _mqttConnected,
                              latestSign: _signText,
                              publishShortcutCommand:
                                  _mqttReceiver.publishShortcutCommand,
                            )
                            : _glassTranslation(),
                  ),
                ],
              ),
            ),
          ),
          if (_detailTitle != null)
            Positioned.fill(
              child: ColoredBox(
                color: const Color(0x99000000),
                child: Center(
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: math.min(
                        680,
                        MediaQuery.sizeOf(context).width - 32,
                      ),
                      maxHeight: MediaQuery.sizeOf(context).height * 0.8,
                    ),
                    child: _glass(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _text(
                            _detailTitle!,
                            size: 24,
                            weight: FontWeight.w600,
                          ),
                          const SizedBox(height: 20),
                          Flexible(
                            child: SingleChildScrollView(
                              child: Text(
                                _detailBody,
                                style: const TextStyle(
                                  color: _ink,
                                  fontSize: 20,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          _action(
                            '닫기',
                            Icons.close,
                            () => setState(() => _detailTitle = null),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          _buildSignOverlay(
            visible:
                _showSignOverlay && activeAlert == null && _detailTitle == null,
          ),
          if (activeAlert != null && activeAlert.kind == AlertKind.fall)
            _buildFallOverlay(activeAlert.data),
          if (activeAlert != null && activeAlert.kind == AlertKind.disaster)
            DisasterOverlay(
              disaster: activeAlert.data,
              pulseAnimation: _alertPulseController,
              onAcknowledge: _acknowledgeActiveAlert,
              activityStatus: WifiActionStatus(
                service: _wifiSensingService,
                allowDummy: AppConfig.localPreview,
                compact: true,
              ),
            ),
        ],
      ),
    );
  }

  Widget _glass({
    required Widget child,
    bool inset = false,
    EdgeInsets padding = const EdgeInsets.all(24),
  }) => Container(
    padding: padding,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors:
            inset
                ? const [Color(0xFF303C44), Color(0xFF2B353D)]
                : const [Color(0xF2253038), Color(0xF21C252D)],
      ),
      borderRadius: BorderRadius.circular(inset ? 15 : 20),
      border: Border.all(
        color: inset ? const Color(0x24FFFFFF) : const Color(0x40FFFFFF),
      ),
      boxShadow:
          inset
              ? null
              : const [
                BoxShadow(
                  color: Color(0x26000000),
                  blurRadius: 20,
                  offset: Offset(0, 8),
                ),
              ],
    ),
    child: child,
  );

  Widget _heading(IconData icon, String title, {Widget? trailing}) => Row(
    children: [
      Icon(icon, color: _ink, size: 25),
      const SizedBox(width: 12),
      Expanded(child: _text(title, size: 22, weight: FontWeight.w600)),
      if (trailing != null) trailing,
    ],
  );

  Widget _dot(String label, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [BoxShadow(color: color.withAlpha(55), blurRadius: 8)],
        ),
      ),
      const SizedBox(width: 8),
      _text(label, color: color, size: 16),
    ],
  );

  Widget _glassHeader() => LayoutBuilder(
    builder: (context, bounds) {
      if (bounds.maxWidth >= 1100) return _wideHeader();
      return Column(
        children: [
          Row(
            children: [
              const Icon(Icons.home_rounded, color: _blue, size: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _text(
                      'SafeHub',
                      size: 28,
                      color: _blue,
                      weight: FontWeight.w700,
                    ),
                    _text('배리어프리 스마트홈', size: 14, color: _muted),
                  ],
                ),
              ),
              if (bounds.maxWidth >= 500) ...[
                _headerClock(),
                const SizedBox(width: 20),
              ],
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _text('MQTT', size: 14, color: _muted),
                  const SizedBox(height: 4),
                  _dot(_connectionStatus, _mqttConnected ? _green : _amber),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_currentPage == _SafeHubPage.home)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _glass(
                padding: const EdgeInsets.all(5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _roomTab('all', '전체', Icons.grid_view_rounded),
                    _roomTab('livingroom', '거실', Icons.weekend_outlined),
                    _roomTab('bedroom', '침실', Icons.bed_outlined),
                    _roomTab('bathroom', '화장실', Icons.bathroom_outlined),
                  ],
                ),
              ),
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: _action('홈으로', Icons.home_outlined, _returnHome),
            ),
        ],
      );
    },
  );

  Widget _wideHeader() => SizedBox(
    height: 70,
    child: Row(
      children: [
        const Icon(Icons.home_rounded, color: _blue, size: 48),
        const SizedBox(width: 12),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _text('SafeHub', size: 31, color: _blue, weight: FontWeight.w700),
            _text('배리어프리 스마트홈', size: 15, color: _muted),
          ],
        ),
        const Spacer(),
        if (_currentPage == _SafeHubPage.home)
          _glass(
            padding: const EdgeInsets.all(5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _roomTab('all', '전체', Icons.grid_view_rounded),
                _roomTab('livingroom', '거실', Icons.weekend_outlined),
                _roomTab('bedroom', '침실', Icons.bed_outlined),
                _roomTab('bathroom', '화장실', Icons.bathroom_outlined),
              ],
            ),
          )
        else
          _action('홈으로', Icons.home_outlined, _returnHome),
        const Spacer(),
        _headerClock(),
        const SizedBox(width: 30),
        Icon(
          _mqttConnected ? Icons.wifi : Icons.wifi_off,
          color: _mqttConnected ? _blue : _amber,
          size: 30,
        ),
        const SizedBox(width: 12),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _text('MQTT', size: 14, color: _muted),
            const SizedBox(height: 4),
            _dot(_connectionStatus, _mqttConnected ? _green : _amber),
          ],
        ),
      ],
    ),
  );

  Widget _headerClock() => ValueListenableBuilder<DateTime>(
    valueListenable: _clock,
    builder: (context, now, child) {
      final hh = now.hour.toString().padLeft(2, '0');
      final mm = now.minute.toString().padLeft(2, '0');
      final date =
          '${now.year}.${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')}';
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _text(date, size: 14, color: _muted),
          _text('$hh:$mm', size: 30, weight: FontWeight.w600),
        ],
      );
    },
  );

  Widget _roomTab(String id, String label, IconData icon) {
    final selected = _selectedRoom == id;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: () => setState(() => _selectedRoom = id),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          decoration: BoxDecoration(
            color: selected ? const Color(0x556F8FAE) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? const Color(0xFF9EBDE7) : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 19, color: selected ? _blue : _muted),
              const SizedBox(width: 8),
              _text(label, size: 16, color: selected ? _ink : _muted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _compactDashboard(SafeHubAlert? alert, double width) {
    final sign = SizedBox(height: 660, child: _signPanel());
    final space = SizedBox(height: 490, child: _spacePanel(alert));
    final alarm = SizedBox(height: 490, child: _alarmPanel(alert));
    final captions = SizedBox(height: 340, child: _sttPanel());
    final events = SizedBox(height: 320, child: _eventsPanel());
    const gap = SizedBox(height: 20);
    return SingleChildScrollView(
      child:
          width >= 680
              ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Column(children: [sign, gap, events])),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(children: [space, gap, captions, gap, alarm]),
                  ),
                ],
              )
              : Column(
                children: [
                  sign,
                  gap,
                  space,
                  gap,
                  alarm,
                  gap,
                  captions,
                  gap,
                  events,
                ],
              ),
    );
  }

  Widget _glassDashboard(SafeHubAlert? alert) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(flex: 34, child: _signPanel()),
      const SizedBox(width: 20),
      Expanded(
        flex: 35,
        child: Column(
          children: [
            Expanded(flex: 6, child: _spacePanel(alert)),
            const SizedBox(height: 20),
            Expanded(flex: 4, child: _sttPanel()),
          ],
        ),
      ),
      const SizedBox(width: 20),
      Expanded(
        flex: 31,
        child: Column(
          children: [
            Expanded(flex: 6, child: _alarmPanel(alert)),
            const SizedBox(height: 20),
            Expanded(flex: 4, child: _eventsPanel()),
          ],
        ),
      ),
    ],
  );

  Widget _signPanel() => _glass(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(Icons.sign_language_outlined, '수어 · 의사소통'),
        const SizedBox(height: 16),
        Expanded(flex: 4, child: _cameraPlaceholder()),
        const SizedBox(height: 16),
        Expanded(flex: 4, child: _signResultCard()),
        const SizedBox(height: 16),
        _action(
          '의사소통 화면 열기',
          Icons.arrow_forward_rounded,
          _openSignTranslation,
          primary: true,
        ),
      ],
    ),
  );

  Widget _cameraPlaceholder() => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: const Color(0x88202020),
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: const Color(0x24FFFFFF)),
    ),
    clipBehavior: Clip.antiAlias,
    child:
        _cameraImage == null
            ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.videocam_outlined, size: 66, color: _blue),
                const SizedBox(height: 14),
                _text('수어 카메라', size: 23, weight: FontWeight.w600),
                const SizedBox(height: 8),
                _text(
                  AppConfig.localPreview
                      ? '장비 연결 후 수어 인식을 사용할 수 있어요'
                      : !AppConfig.cameraConfigured
                      ? '연결 설정에서 카메라 서버 주소를 입력하세요'
                      : _cameraConnected
                      ? '카메라 영상 수신 대기 중'
                      : 'RPi4 카메라 연결 대기 중',
                  size: 15,
                  color: _muted,
                ),
              ],
            )
            : Stack(
              fit: StackFit.expand,
              children: [
                RawImage(
                  key: const ValueKey('camera_preview'),
                  image: _cameraImage,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.low,
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xAA111111),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.circle,
                          size: 9,
                          color: _cameraConnected ? _green : _amber,
                        ),
                        const SizedBox(width: 7),
                        _text(
                          _cameraConnected ? 'LIVE' : '연결 확인',
                          size: 13,
                          color: _ink,
                          weight: FontWeight.w600,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
  );

  Widget _action(
    String label,
    IconData icon,
    VoidCallback onTap, {
    bool primary = false,
  }) => SizedBox(
    height: 55,
    child: TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: primary ? const Color(0xFF202D3E) : _ink,
        backgroundColor: primary ? _blue : const Color(0x22FFFFFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 20),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 12),
          Icon(icon, size: 22),
        ],
      ),
    ),
  );

  Widget _spacePanel(SafeHubAlert? alert) {
    return _glass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(Icons.sensors_outlined, '재실 · 활동 상태'),
          const SizedBox(height: 10),
          Expanded(
            child: WifiActionStatus(
              service: _wifiSensingService,
              allowDummy: AppConfig.localPreview,
            ),
          ),
          const SizedBox(height: 10),
          _action(
            '신호 수집 · 모델 관리',
            Icons.sensors_rounded,
            () => setState(() => _currentPage = _SafeHubPage.wifiSensing),
          ),
          if (_selectedRoom == 'all' || _selectedRoom == 'livingroom') ...[
            const SizedBox(height: 10),
            _action(
              '가전 · 수어 단축키',
              Icons.tune_rounded,
              () => setState(() => _currentPage = _SafeHubPage.appliances),
              primary: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _alarmPanel(SafeHubAlert? alert) => _glass(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(Icons.shield_outlined, '경보 · 재난 알림'),
        const SizedBox(height: 16),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _systemRow(
                  Icons.warning_amber_rounded,
                  '화면 경보',
                  alert != null
                      ? '알림 발생'
                      : _mqttConnected
                      ? '수신 대기'
                      : '연결 확인 필요',
                  alert != null ? _amber : _muted,
                ),
                const SizedBox(height: 18),
                _disasterSummary(),
                const SizedBox(height: 18),
                _systemRow(
                  Icons.sensors_outlined,
                  '초인종 · 세탁기',
                  '이벤트 연결 필요',
                  _muted,
                ),
              ],
            ),
          ),
        ),
        const Divider(color: Color(0x33FFFFFF), height: 24),
        _systemRow(
          Icons.wifi,
          '알림 연결',
          AppConfig.localPreview
              ? '체험 모드'
              : _mqttConnected
              ? '연결됨'
              : _connectionStatus,
          _mqttConnected ? _green : _amber,
        ),
      ],
    ),
  );

  Widget _systemRow(IconData icon, String label, String value, Color color) =>
      Row(
        children: [
          Icon(icon, size: 24, color: color),
          const SizedBox(width: 12),
          Expanded(child: _text(label, size: 17)),
          const SizedBox(width: 8),
          Flexible(child: _text(value, color: color, size: 15, lines: 2)),
        ],
      );

  Widget _disasterSummary() {
    final disaster = _latestDisaster;
    final color =
        disaster == null
            ? _muted
            : _disasterAccent(getDisasterSeverity(disaster));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x33202020),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                _disasterIcon(disaster?['DST_SE_NM']?.toString()),
                color: color,
                size: 24,
              ),
              const SizedBox(width: 10),
              Expanded(child: _text('재난경보', size: 18, weight: FontWeight.w600)),
              if (disaster != null) _more(() => _showDisasterDetails(disaster)),
            ],
          ),
          const SizedBox(height: 12),
          _text(
            disaster == null
                ? '수신된 재난 정보가 없습니다'
                : disaster['DST_SE_NM']?.toString() ?? '재난 안내',
            size: 17,
            weight: FontWeight.w600,
            lines: 2,
          ),
          const SizedBox(height: 8),
          _text(
            disaster == null
                ? AppConfig.localPreview
                    ? '체험 모드에서는 재난 정보를 수신하지 않습니다'
                    : AppConfig.disasterConfigured
                    ? '새 재난 정보 수신 대기'
                    : '재난 API 연결 설정 필요'
                : disaster['MSG_CN']?.toString() ?? '상세 정보를 확인해 주세요',
            size: 15,
            color: _muted,
            lines: 4,
          ),
          if (disaster?['CRT_DT'] != null) ...[
            const SizedBox(height: 8),
            _text(disaster!['CRT_DT'].toString(), size: 12, color: _muted),
          ],
        ],
      ),
    );
  }

  Widget _more(VoidCallback onTap) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(
      foregroundColor: _muted,
      minimumSize: const Size(60, 44),
    ),
    child: const Text('더보기 ›', style: TextStyle(fontSize: 15)),
  );

  List<Map<String, dynamic>> get _visibleEvents =>
      _recentEvents
          .where(
            (event) =>
                _selectedRoom == 'all' || event['location'] == _selectedRoom,
          )
          .toList();

  Widget _eventsPanel() {
    final events = _visibleEvents;
    return _glass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(
            Icons.receipt_long_outlined,
            '최근 이벤트',
            trailing: events.isEmpty ? null : _more(_showEventDetails),
          ),
          const SizedBox(height: 12),
          Expanded(
            child:
                events.isEmpty
                    ? Center(
                      child: _text(
                        '아직 수신된 이벤트가 없습니다',
                        size: 17,
                        color: _muted,
                        lines: 2,
                      ),
                    )
                    : Column(
                      children: [
                        for (final event in events.take(3))
                          Expanded(child: _eventLine(event)),
                      ],
                    ),
          ),
        ],
      ),
    );
  }

  Widget _eventLine(Map<String, dynamic> event) => Row(
    children: [
      Icon(
        Icons.circle,
        size: 8,
        color: _isEmergencyEvent(event) ? const Color(0xFFFF9A93) : _blue,
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _text(
              _getLocationName(event) + ' · ' + _getEventName(event),
              size: 17,
            ),
            const SizedBox(height: 3),
            _text(_formatEventDateTime(event), size: 14, color: _muted),
          ],
        ),
      ),
    ],
  );

  void _showDisasterDetails(Map<String, dynamic> disaster) => _showDetails(
    '재난 정보',
    [
      disaster['DST_SE_NM']?.toString() ?? '재난 안내',
      disaster['RCPTN_RGN_NM']?.toString() ?? '',
      disaster['CRT_DT']?.toString() ?? '',
      disaster['MSG_CN']?.toString() ?? '내용 없음',
    ].where((s) => s.isNotEmpty).join('\n\n'),
  );

  void _showEventDetails() => _showDetails(
    '최근 이벤트',
    _visibleEvents
        .map(
          (e) =>
              _getLocationName(e) +
              ' · ' +
              _getEventName(e) +
              '\n' +
              _formatEventDateTime(e),
        )
        .join('\n\n'),
  );

  void _showDetails(String title, String body) {
    setState(() {
      _detailTitle = title;
      _detailBody = body;
    });
  }

  Widget _buildSignOverlay({required bool visible}) {
    final isUrgent = _signText == '아프다';
    final accent = isUrgent ? const Color(0xFFFF9B91) : const Color(0xFF9ED7FF);

    return Positioned.fill(
      child: IgnorePointer(
        child: Align(
          alignment: const Alignment(0, -0.10),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            reverseDuration: const Duration(milliseconds: 180),
            transitionBuilder:
                (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.94, end: 1).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                    child: child,
                  ),
                ),
            child:
                visible
                    ? Container(
                      key: ValueKey(_signText),
                      constraints: const BoxConstraints(maxWidth: 440),
                      margin: const EdgeInsets.symmetric(horizontal: 28),
                      padding: const EdgeInsets.fromLTRB(26, 20, 30, 22),
                      decoration: BoxDecoration(
                        color: const Color(0xF523272E),
                        border: Border.all(color: accent.withOpacity(0.72)),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x66000000),
                            blurRadius: 24,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Semantics(
                        liveRegion: true,
                        label: '수어 인식 결과 $_signText',
                        child: Row(
                          children: [
                            Container(
                              width: 54,
                              height: 54,
                              decoration: BoxDecoration(
                                color: accent.withOpacity(0.14),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                Icons.sign_language_rounded,
                                color: accent,
                                size: 29,
                              ),
                            ),
                            const SizedBox(width: 18),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '수어가 인식되었습니다',
                                    style: TextStyle(
                                      color: accent,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    _signText,
                                    style: const TextStyle(
                                      color: Color(0xFFFFFFFF),
                                      fontSize: 34,
                                      height: 1.1,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.6,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    : const SizedBox.shrink(
                      key: ValueKey('sign-overlay-hidden'),
                    ),
          ),
        ),
      ),
    );
  }

  Widget _signResultCard() {
    final isWaiting = _signText == '수어 인식 대기 중';
    final isUrgent = _signText == '아프다';

    final accent = isUrgent ? const Color(0xFFFF9B91) : const Color(0xFF9ED7FF);

    final resultColor =
        isUrgent ? const Color(0xFFFFA59D) : const Color(0xFFF7F9FC);

    return Container(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xEB30343B), Color(0xF224282E)],
        ),
        border: Border.all(
          color: isUrgent ? const Color(0x80FF9B91) : const Color(0x42FFFFFF),
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sign_language_outlined, color: accent, size: 25),
              const SizedBox(width: 10),
              const Text(
                '수어 인식 결과',
                style: TextStyle(
                  fontSize: 19,
                  color: Color(0xFFF3F5F7),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Semantics(
                  liveRegion: true,
                  label: '수어 인식 결과 $_signText',
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _signText,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: isWaiting ? 29 : 58,
                          color: resultColor,
                          height: 1.15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: isWaiting ? -0.5 : -1.2,
                        ),
                      ),
                      if (!isWaiting) ...[
                        const SizedBox(height: 12),
                        Text(
                          isUrgent ? '도움이 필요한 수어입니다' : '수어가 정상적으로 인식되었습니다',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: accent,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.center,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.11),
                border: Border.all(color: accent.withOpacity(0.28)),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                _ttsStatus,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color:
                      isUrgent
                          ? const Color(0xFFFFC0BA)
                          : const Color(0xFFD7E8F7),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glassTranslation() => LayoutBuilder(
    builder: (context, bounds) {
      final camera = _glass(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _heading(Icons.videocam_outlined, '수어 카메라'),
            const SizedBox(height: 16),
            Expanded(child: _cameraPlaceholder()),
            const SizedBox(height: 16),
            _text('카메라를 보며 수어를 표현하세요', size: 16, color: _muted),
          ],
        ),
      );
      if (bounds.maxWidth < 1000 || bounds.maxHeight < 480) {
        return ListView(
          children: [
            SizedBox(height: 280, child: camera),
            const SizedBox(height: 16),
            SizedBox(height: 260, child: _signResultCard()),
            const SizedBox(height: 16),
            SizedBox(height: 320, child: _sttPanel()),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 4, child: camera),
          const SizedBox(width: 20),
          Expanded(
            flex: 6,
            child: Column(
              children: [
                Expanded(flex: 5, child: _signResultCard()),
                const SizedBox(height: 20),
                Expanded(flex: 5, child: _sttPanel()),
              ],
            ),
          ),
        ],
      );
    },
  );

  Widget _sttPanel() => _glass(
    child: LiveCaptionPanel(
      service: _captions,
      configured: AppConfig.sttServerUrl.trim().isNotEmpty,
      preview: AppConfig.localPreview,
    ),
  );

  Widget _buildFallOverlay(Map<String, dynamic> event) {
    final eventName = _getEventName(event);
    final locationName = _getLocationName(event);
    final detectedAt = _formatEventDateTime(event);
    final priority = _getEventPriority(event);
    const accent = Color(0xFFFFA49A);

    // Presentation only: preserve the existing alert acknowledgement lifecycle.
    return Positioned.fill(
      child: BlockSemantics(
        child: Material(
          color: const Color(0xFF24221F),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                'assets/images/safehub_living_room.png',
                fit: BoxFit.cover,
                errorBuilder:
                    (context, error, stackTrace) =>
                        const ColoredBox(color: Color(0xFF393731)),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xD923201E), Color(0xC43A2220)],
                  ),
                ),
              ),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact =
                        constraints.maxWidth < 700 ||
                        constraints.maxHeight < 650;
                    final padding = compact ? 20.0 : 40.0;
                    return SingleChildScrollView(
                      padding: EdgeInsets.all(padding),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: math.max(
                            0.0,
                            constraints.maxHeight - padding * 2,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              spacing: 20,
                              runSpacing: 12,
                              children: [
                                _text(
                                  'SafeHub',
                                  size: 26,
                                  weight: FontWeight.w600,
                                ),
                                _dot('긴급 안전 알림', accent),
                              ],
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(
                                vertical: compact ? 24 : 40,
                              ),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 1040,
                                  ),
                                  child: AnimatedBuilder(
                                    animation: _alertPulseController,
                                    builder: (context, child) {
                                      final pulse =
                                          MediaQuery.of(
                                                context,
                                              ).disableAnimations
                                              ? 0.0
                                              : _alertPulseController.value;
                                      return Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            22,
                                          ),
                                          border: Border.all(
                                            width: 2,
                                            color:
                                                Color.lerp(
                                                  const Color(0x667F514A),
                                                  const Color(0xD9E58A7D),
                                                  pulse,
                                                )!,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Color.fromARGB(
                                                (18 + 20 * pulse).round(),
                                                220,
                                                82,
                                                64,
                                              ),
                                              blurRadius: 30,
                                              spreadRadius: 2,
                                            ),
                                          ],
                                        ),
                                        child: child,
                                      );
                                    },
                                    child: _glass(
                                      padding: EdgeInsets.all(
                                        compact ? 24 : 48,
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          const Icon(
                                            Icons.warning_amber_rounded,
                                            size: 72,
                                            color: accent,
                                          ),
                                          const SizedBox(height: 24),
                                          Semantics(
                                            liveRegion: true,
                                            child: Text(
                                              eventName == '낙상 감지'
                                                  ? '낙상이 감지되었습니다'
                                                  : eventName,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontFamily: 'Pretendard',
                                                fontSize: compact ? 32 : 50,
                                                height: 1.25,
                                                fontWeight: FontWeight.w600,
                                                color: _ink,
                                                letterSpacing: -1,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          const Text(
                                            '즉시 주변 상황을 확인해 주세요.',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: _muted,
                                              fontSize: 22,
                                              height: 1.4,
                                            ),
                                          ),
                                          const SizedBox(height: 30),
                                          _glass(
                                            inset: true,
                                            child: Column(
                                              children: [
                                                Text(
                                                  locationName,
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                    color: _ink,
                                                    fontSize: 32,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                const SizedBox(height: 10),
                                                Text(
                                                  '$detectedAt 감지',
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                    color: _muted,
                                                    fontSize: 18,
                                                  ),
                                                ),
                                                const SizedBox(height: 10),
                                                Text(
                                                  '긴급도 $priority / 10',
                                                  style: const TextStyle(
                                                    color: accent,
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 30),
                                          Center(
                                            child: ConstrainedBox(
                                              constraints: const BoxConstraints(
                                                maxWidth: 400,
                                              ),
                                              child: SizedBox(
                                                width: double.infinity,
                                                child: FilledButton.icon(
                                                  onPressed:
                                                      _acknowledgeActiveAlert,
                                                  icon: const Icon(
                                                    Icons.check_rounded,
                                                  ),
                                                  label: const Text('경보 확인'),
                                                  style: FilledButton.styleFrom(
                                                    backgroundColor:
                                                        const Color(0xFFAD443B),
                                                    foregroundColor:
                                                        Colors.white,
                                                    minimumSize: const Size(
                                                      0,
                                                      64,
                                                    ),
                                                    padding:
                                                        const EdgeInsets.all(
                                                          18,
                                                        ),
                                                    textStyle: const TextStyle(
                                                      fontFamily: 'Pretendard',
                                                      fontSize: 22,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            14,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 14),
                                          const Text(
                                            '경보 확인은 안전 확인 완료를 의미하지 않습니다.',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: _muted,
                                              fontSize: 15,
                                              height: 1.4,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const Text(
                              'SafeHub · 공간 안전 모니터링',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: _muted, fontSize: 15),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getEventName(Map<String, dynamic> event) {
    switch (event['event']) {
      case 'fall_detected':
        return '낙상 감지';
      default:
        return event['event']?.toString() ?? '안전 이벤트';
    }
  }

  String _getLocationName(Map<String, dynamic> event) {
    switch (event['location']) {
      case 'bedroom':
        return '침실';
      case 'bathroom':
        return '화장실';
      default:
        return '실내';
    }
  }

  String _formatEventDateTime(Map<String, dynamic> event) {
    final raw = event['_receivedAt']?.toString();

    if (raw == null || raw.isEmpty) {
      return '감지 시각 확인 불가';
    }

    final parsed = DateTime.tryParse(raw);

    if (parsed == null) {
      return '감지 시각 확인 불가';
    }

    final local = parsed.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');

    return '$year/$month/$day $hour:$minute';
  }

  Color _disasterAccent(DisasterSeverity severity) {
    switch (severity) {
      case DisasterSeverity.notice:
        return const Color(0xFFF59E0B);
      case DisasterSeverity.emergency:
        return const Color(0xFFEA580C);
      case DisasterSeverity.critical:
        return const Color(0xFFDC2626);
    }
  }

  IconData _disasterIcon(String? type) {
    switch (type) {
      case '폭염':
        return Icons.sunny;
      case '호우':
        return Icons.water_drop_outlined;
      case '태풍':
        return Icons.cyclone;
      case '대설':
        return Icons.ac_unit;
      case '산불':
        return Icons.local_fire_department_outlined;
      case '지진':
        return Icons.vibration;
      case '미세먼지':
        return Icons.air;
      default:
        return Icons.campaign_outlined;
    }
  }
}
