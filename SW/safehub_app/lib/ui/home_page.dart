import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../core/alert_coordinator.dart';
import '../core/event_manager.dart';
import '../mqtt/mqtt_receiver.dart';
import '../services/audio_service.dart';
import '../services/disaster_service.dart';
import '../services/tts_service.dart';
import 'theme/app_theme.dart';
import 'utils/disaster_display.dart';
import 'widgets/camera_feed_panel.dart';
import 'widgets/disaster_overlay.dart';

enum _SafeHubPage {
  home,
  signTranslation,
}

class SafeHubHomePage extends StatefulWidget {
  final bool enableServices;

  const SafeHubHomePage({
    super.key,
    this.enableServices = true,
  });

  @override
  State<SafeHubHomePage> createState() => _SafeHubHomePageState();
}

class _SafeHubHomePageState extends State<SafeHubHomePage>
    with SingleTickerProviderStateMixin {
  final EventManager _eventManager = EventManager();
  late final DisasterService _disasterService;
  final AlertCoordinator _alertCoordinator = AlertCoordinator();
  late final AudioService _audioService;

  late final MqttReceiver _mqttReceiver;
  late final AnimationController _alertPulseController;
  late final TtsService _ttsService;

  Timer? _disasterTimer;

  _SafeHubPage _currentPage = _SafeHubPage.home;

  bool _mqttConnected = false;
  String _connectionStatus = '연결 중';
  String _signText = '수어 인식 대기 중';
  String _ttsStatus = '음성 안내 대기';

  Map<String, dynamic>? _latestDisaster;

  int? _lastDisasterSn;
  int _speechGeneration = 0;

  final List<Map<String, dynamic>> _recentEvents = [];

  @override
  void initState() {
    super.initState();

    _alertPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    if (!widget.enableServices) {
      _connectionStatus = '미리보기 · 연결 안 함';
      return;
    }

    _disasterService = DisasterService();
    _audioService = AudioService();

    _ttsService = TtsService(
      baseUrl: AppConfig.ttsServerUrl,
    );

    _mqttReceiver = MqttReceiver(
      broker: AppConfig.mqttBroker,
      port: AppConfig.mqttPort,
      eventManager: _eventManager,
      onEventReceived: _handleEvent,
      onSignTextReceived: _handleSignText,
      onConnectionChanged: _handleConnectionChanged,
    );

    _connectMqtt();
    _startDisasterPolling();
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

      if (disaster == null || !mounted) {
        return;
      }

      final sn = disaster['SN'];

      if (sn is! int || _lastDisasterSn == sn) {
        return;
      }

      final isInitialLoad = _lastDisasterSn == null;
      final disasterData = Map<String, dynamic>.from(disaster);
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
        _lastDisasterSn = sn;
        _latestDisaster = disasterData;
      });

      if (activated) {
        _interruptNormalSpeech();
        _restartAlertPulse();
      }
    } catch (_) {
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

    setState(() {
      _signText = cleanText;
      _ttsStatus =
          AppConfig.ttsServerUrl.trim().isEmpty ? '텍스트로 표시됨' : '음성 변환 준비 중';
    });

    final generation = ++_speechGeneration;

    unawaited(
      _speakTranslation(
        cleanText,
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
      return;
    }

    final eventData = Map<String, dynamic>.from(event);
    eventData['_receivedAt'] ??= DateTime.now().toIso8601String();

    var activated = false;

    if (_isEmergencyEvent(eventData)) {
      activated = _alertCoordinator.submit(
        SafeHubAlert(
          kind: AlertKind.fall,
          priority: _getEventPriority(eventData),
          data: eventData,
        ),
      );
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
      _interruptNormalSpeech();
      _restartAlertPulse();
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
    unawaited(_audioService.stop());

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

  @override
  void dispose() {
    _disasterTimer?.cancel();
    _speechGeneration++;
    if (widget.enableServices) {
      unawaited(_audioService.dispose());
      _mqttReceiver.disconnect();
    }
    _alertPulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeAlert = _alertCoordinator.activeAlert;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          if (_currentPage == _SafeHubPage.home)
            _buildHomePage(activeAlert)
          else
            _buildSignTranslationPage(),
          if (activeAlert != null && activeAlert.kind == AlertKind.fall)
            _buildFallOverlay(activeAlert.data),
          if (activeAlert != null && activeAlert.kind == AlertKind.disaster)
            DisasterOverlay(
              disaster: activeAlert.data,
              pulseAnimation: _alertPulseController,
              onAcknowledge: _acknowledgeActiveAlert,
            ),
        ],
      ),
    );
  }

  Widget _buildHomePage(SafeHubAlert? activeAlert) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 900;

          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 24 : 58,
              vertical: 30,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 1180,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 24),
                    _buildHero(activeAlert),
                    const SizedBox(height: 20),
                    _buildOverview(activeAlert, compact: isCompact),
                    const SizedBox(height: 30),
                    const Divider(
                      height: 1,
                      color: Color(0xFFE1E4E0),
                    ),
                    const SizedBox(height: 26),
                    _buildDisasterSection(),
                    const SizedBox(height: 30),
                    const Divider(
                      height: 1,
                      color: Color(0xFFE1E4E0),
                    ),
                    const SizedBox(height: 26),
                    _buildRecentEventsSection(),
                    const SizedBox(height: 30),
                    const Divider(
                      height: 1,
                      color: Color(0xFFE1E4E0),
                    ),
                    const SizedBox(height: 16),
                    _buildFooter(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildOverview(
    SafeHubAlert? activeAlert, {
    required bool compact,
  }) {
    Widget panel(Widget child) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: child,
      );
    }

    final safety = panel(_buildSafetySection(activeAlert));
    final translation = panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSignLaunchSection(),
          const SizedBox(height: 18),
          const Divider(),
          const SizedBox(height: 16),
          const Text(
            '카메라 화면과 수어 번역 결과를 확인합니다.\n'
            '영상 수신 및 음성 자막 기능은 연결 준비 중입니다.',
            style: TextStyle(
              fontSize: 13,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          safety,
          const SizedBox(height: 16),
          translation,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: safety),
        const SizedBox(width: 20),
        Expanded(child: translation),
      ],
    );
  }

  Widget _buildSignTranslationPage() {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 900;
          final horizontalPadding = isCompact ? 24.0 : 58.0;

          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: 30,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 1180,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSignPageHeader(),
                    const SizedBox(height: 48),
                    const Text(
                      '수어 번역',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: -1.0,
                      ),
                    ),
                    const SizedBox(height: 9),
                    const Text(
                      '인식된 수어를 텍스트로 표시하고 음성으로 전달합니다.',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 30),
                    const Divider(
                      height: 1,
                      color: Color(0xFFE1E4E0),
                    ),
                    const SizedBox(height: 42),
                    _buildSignWorkspace(
                      compact: isCompact,
                    ),
                    const SizedBox(height: 42),
                    const Divider(
                      height: 1,
                      color: Color(0xFFE1E4E0),
                    ),
                    const SizedBox(height: 20),
                    _buildSignStatusBar(),
                    const SizedBox(height: 22),
                    _buildFooter(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SafeHub',
              style: TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -0.7,
              ),
            ),
            SizedBox(height: 3),
            Text(
              '배리어프리 스마트홈 안전 정보',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const Spacer(),
        _buildConnectionStatus(),
      ],
    );
  }

  Widget _buildSignPageHeader() {
    return Row(
      children: [
        Listener(
          behavior: HitTestBehavior.opaque,
          onPointerUp: (_) => _returnHome(),
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFEDEFEA),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.arrow_back_rounded,
                  size: 18,
                  color: AppColors.textPrimary,
                ),
                SizedBox(width: 7),
                Text(
                  '홈',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 20),
        const Text(
          'SafeHub',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        const Spacer(),
        _buildConnectionStatus(),
      ],
    );
  }

  Widget _buildConnectionStatus() {
    final statusColor = _mqttConnected ? AppColors.success : AppColors.danger;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: statusColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'MQTT $_connectionStatus',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildHero(SafeHubAlert? activeAlert) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '생활 안전 현황',
          style: TextStyle(
            fontSize: 35,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -1.1,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          '실내 안전 이벤트 · 재난 안내 · 수어 통역',
          style: TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildSignLaunchSection() {
    final hasResult = _signText != '수어 인식 대기 중';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Icon(
          Icons.sign_language_outlined,
          size: 34,
          color: AppColors.textPrimary,
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '수어 번역',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                hasResult ? '최근 번역 · $_signText' : '수어를 인식해 텍스트와 음성으로 전달합니다.',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 18),
        Listener(
          behavior: HitTestBehavior.opaque,
          onPointerUp: (_) => _openSignTranslation(),
          child: Container(
            width: 132,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.textPrimary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '번역 시작',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 7),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: Colors.white,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSignWorkspace({required bool compact}) {
    const camera = CameraFeedPanel(
      streamUrl: AppConfig.cameraStreamUrl,
    );
    final result = Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: _buildSignTranslationResult(availableHeight: 600),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (compact) ...[
          camera,
          const SizedBox(height: 16),
          result,
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(flex: 3, child: camera),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: result),
            ],
          ),
        const SizedBox(height: 16),
        const DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.fromBorderSide(
              BorderSide(color: AppColors.border),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Text(
              '상대방 음성 자막 · 준비 중\n'
              'STT는 아직 연결되지 않았으며 마이크를 사용하지 않습니다.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.6,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSignTranslationResult({
    required double availableHeight,
  }) {
    final hasResult = _signText != '수어 인식 대기 중';
    final resultHeight = availableHeight > 700 ? 330.0 : 260.0;

    return SizedBox(
      width: double.infinity,
      height: resultHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _mqttConnected ? AppColors.success : AppColors.danger,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 9),
              Text(
                _mqttConnected ? '실시간 인식 대기 중' : '연결 확인 필요',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const Spacer(),
          const Text(
            '번역 결과',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              _signText,
              key: ValueKey(_signText),
              style: TextStyle(
                fontSize: hasResult ? 58 : 38,
                fontWeight: FontWeight.w800,
                color:
                    hasResult ? AppColors.textPrimary : AppColors.textSecondary,
                height: 1.2,
                letterSpacing: -1.4,
              ),
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Icon(
                _ttsStatus == '음성으로 전달됨'
                    ? Icons.check_rounded
                    : Icons.volume_up_outlined,
                size: 19,
                color: _ttsStatus == '음성으로 전달됨'
                    ? AppColors.success
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 9),
              Text(
                _ttsStatus,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSignStatusBar() {
    return Wrap(
      spacing: 24,
      runSpacing: 12,
      children: [
        _statusItem(
          icon: Icons.sensors_outlined,
          label: _mqttConnected ? '수어 결과 수신 가능' : 'MQTT 연결 확인 필요',
          active: _mqttConnected,
        ),
        _statusItem(
          icon: Icons.volume_up_outlined,
          label:
              AppConfig.ttsServerUrl.trim().isEmpty ? 'TTS 미설정' : 'TTS 연결 설정됨',
          active: AppConfig.ttsServerUrl.trim().isNotEmpty,
        ),
      ],
    );
  }

  Widget _statusItem({
    required IconData icon,
    required String label,
    required bool active,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 16,
          color: active ? AppColors.success : AppColors.textMuted,
        ),
        const SizedBox(width: 7),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildSafetySection(SafeHubAlert? activeAlert) {
    final activeFall =
        activeAlert != null && activeAlert.kind == AlertKind.fall;

    if (activeFall) {
      final event = activeAlert.data;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(
            title: '생활 안전',
            subtitle: '',
          ),
          const SizedBox(height: 24),
          const Icon(
            Icons.warning_amber_rounded,
            size: 36,
            color: AppColors.danger,
          ),
          const SizedBox(height: 12),
          Text(
            _getEventName(event),
            style: const TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            '${_getLocationName(event)} · ${_formatEventDateTime(event)} 감지',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(
          title: '생활 안전',
          subtitle: '',
        ),
        const SizedBox(height: 24),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 34,
              color: AppColors.textSecondary,
            ),
            SizedBox(width: 14),
            Expanded(
              child: Text(
                '표시 중인 낙상 경보 없음',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const Text(
          '침실 · 화장실 센서 상태 미확인\n'
          '센서 연결 상태는 아직 수신하지 않습니다.',
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildDisasterSection() {
    final disaster = _latestDisaster;

    if (disaster == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(
            title: '재난 안전 정보',
            subtitle: '행정안전부 재난문자를 표시합니다.',
          ),
          const SizedBox(height: 18),
          const Text(
            '재난 안전 정보를 불러오는 중입니다.',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textMuted,
            ),
          ),
        ],
      );
    }

    final severity = getDisasterSeverity(disaster);
    final accent = _disasterAccent(severity);
    final background = _disasterBackground(severity);
    final type = disaster['DST_SE_NM']?.toString().trim();
    final step = disaster['EMRG_STEP_NM']?.toString().trim();
    final region = disaster['RCPTN_RGN_NM']?.toString().trim();
    final message = disaster['MSG_CN']?.toString().trim();
    final date = disaster['CRT_DT']?.toString().trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(
          title: '재난 안전 정보',
          subtitle: '행정안전부 재난문자를 표시합니다.',
        ),
        const SizedBox(height: 17),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 17,
          ),
          color: background,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _disasterIcon(type),
                size: 26,
                color: accent,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          type?.isNotEmpty == true ? type! : '재난',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          step ?? '',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      region?.isNotEmpty == true ? region! : '지역 정보 없음',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      message?.isNotEmpty == true ? message! : '내용이 없습니다.',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      date ?? '',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRecentEventsSection() {
    final visibleEvents = _recentEvents.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(
          title: '최근 감지',
          subtitle: '',
        ),
        const SizedBox(height: 12),
        if (visibleEvents.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '감지 이력이 없습니다.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textMuted,
              ),
            ),
          )
        else
          for (var i = 0; i < visibleEvents.length; i++) ...[
            _buildEventRow(visibleEvents[i]),
            if (i != visibleEvents.length - 1)
              const Divider(
                height: 1,
                color: Color(0xFFE1E4E0),
              ),
          ],
      ],
    );
  }

  Widget _buildEventRow(Map<String, dynamic> event) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: AppColors.danger,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 13),
          SizedBox(
            width: 150,
            child: Text(
              _formatEventDateTime(event),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          SizedBox(
            width: 70,
            child: Text(
              _getLocationName(event),
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              _getEventName(event),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFallOverlay(Map<String, dynamic> event) {
    final eventName = _getEventName(event);
    final locationName = _getLocationName(event);
    final detectedAt = _formatEventDateTime(event);

    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _alertPulseController,
        builder: (context, child) {
          return Container(
            color: Color.lerp(
              const Color(0xFFFFF3F3),
              const Color(0xFFE54848),
              _alertPulseController.value,
            ),
            child: child,
          );
        },
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 64,
              vertical: 42,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Text(
                      'SafeHub',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Spacer(),
                    Text(
                      '긴급 안전 알림',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.danger,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                AnimatedBuilder(
                  animation: _alertPulseController,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: 1.0 + (_alertPulseController.value * 0.14),
                      child: child,
                    );
                  },
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    size: 82,
                    color: AppColors.danger,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  eventName,
                  style: const TextStyle(
                    fontSize: 60,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -1.4,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  locationName,
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  '$detectedAt 감지',
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  '즉시 주변 상황을 확인해 주세요.',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _acknowledgeActiveAlert,
                    child: Container(
                      width: 220,
                      height: 54,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '확인했습니다',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel({
    required String title,
    required String subtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.3,
          ),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
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

  Color _disasterBackground(DisasterSeverity severity) {
    switch (severity) {
      case DisasterSeverity.notice:
        return const Color(0xFFFFF7D6);
      case DisasterSeverity.emergency:
        return const Color(0xFFFFE8CC);
      case DisasterSeverity.critical:
        return const Color(0xFFFFE2E2);
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

  Widget _buildFooter() {
    return const Row(
      children: [
        Text(
          'SafeHub',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
          ),
        ),
        Spacer(),
        Text(
          '모두를 위한 안전한 스마트홈',
          style: TextStyle(
            fontSize: 10,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}
