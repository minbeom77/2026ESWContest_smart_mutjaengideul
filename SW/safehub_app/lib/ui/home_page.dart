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
import 'widgets/disaster_overlay.dart';

enum _SafeHubPage {
  home,
  signTranslation,
}

class SafeHubHomePage extends StatefulWidget {
  const SafeHubHomePage({super.key});

  @override
  State<SafeHubHomePage> createState() => _SafeHubHomePageState();
}

class _SafeHubHomePageState extends State<SafeHubHomePage>
    with SingleTickerProviderStateMixin {
  final EventManager _eventManager = EventManager();
  final DisasterService _disasterService = DisasterService();
  final AlertCoordinator _alertCoordinator = AlertCoordinator();
  final AudioService _audioService = AudioService();

  late final MqttReceiver _mqttReceiver;
  late final AnimationController _alertPulseController;
  late final TtsService _ttsService;

  Timer? _disasterTimer;

  _SafeHubPage _currentPage = _SafeHubPage.home;

  bool _mqttConnected = false;
  bool _signButtonPressed = false;
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
    unawaited(_audioService.dispose());
    _alertPulseController.dispose();
    _mqttReceiver.disconnect();
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
          final isCompact =
              constraints.maxWidth < 1050 || constraints.maxHeight < 650;
          final horizontalPadding = isCompact ? 20.0 : 36.0;
          final verticalPadding = isCompact ? 16.0 : 24.0;

          return Padding(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: verticalPadding,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1720),
                child: SizedBox(
                  height: constraints.maxHeight - (verticalPadding * 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(),
                      SizedBox(height: isCompact ? 14 : 20),
                      Expanded(
                        child: _buildHomeGrid(
                          activeAlert,
                          compact: isCompact,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHomeGrid(
    SafeHubAlert? activeAlert, {
    required bool compact,
  }) {
    if (compact) {
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 300,
              child: _dashboardCard(
                prominent: true,
                child: _buildSafetySection(activeAlert),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 280,
              child: _dashboardCard(
                color: AppColors.primaryLight,
                child: _buildSignLaunchSection(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 130,
              child: Row(
                children: [
                  Expanded(child: _buildDisasterSummary()),
                  const SizedBox(width: 12),
                  Expanded(child: _buildRecentSummary()),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          flex: 7,
          child: Row(
            children: [
              Expanded(
                flex: 13,
                child: _dashboardCard(
                  prominent: true,
                  child: _buildSafetySection(activeAlert),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                flex: 7,
                child: _dashboardCard(
                  color: AppColors.primaryLight,
                  child: _buildSignLaunchSection(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Expanded(
          flex: 3,
          child: Row(
            children: [
              Expanded(flex: 13, child: _buildDisasterSummary()),
              const SizedBox(width: 18),
              Expanded(flex: 7, child: _buildRecentSummary()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dashboardCard({
    required Widget child,
    Color color = AppColors.surface,
    bool prominent = false,
  }) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        boxShadow: prominent
            ? const [
                BoxShadow(
                  color: Color(0x12203850),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }

  Widget _buildDisasterSummary() {
    final disaster = _latestDisaster;
    final type = disaster?['DST_SE_NM']?.toString().trim();
    final region = disaster?['RCPTN_RGN_NM']?.toString().trim();
    final message = disaster?['MSG_CN']?.toString().trim();

    return _summaryPanel(
      icon: Icons.campaign_outlined,
      title: '최근 재난',
      primary: disaster == null
          ? '새로운 재난 정보 없음'
          : (type?.isNotEmpty == true ? type! : '재난 안내'),
      secondary: disaster == null
          ? '행정안전부 정보를 확인하고 있습니다.'
          : [region, message]
              .where((value) => value?.isNotEmpty == true)
              .join(' · '),
    );
  }

  Widget _buildRecentSummary() {
    final event = _recentEvents.isEmpty ? null : _recentEvents.first;

    return _summaryPanel(
      icon: Icons.monitor_heart_outlined,
      title: '최근 감지',
      primary: event == null ? '감지된 위험 없음' : _getEventName(event),
      secondary: event == null
          ? '침실과 화장실의 위험 이벤트를 확인합니다.'
          : '${_getLocationName(event)} · ${_formatEventDateTime(event)}',
    );
  }

  Widget _summaryPanel({
    required IconData icon,
    required String title,
    required String primary,
    required String secondary,
  }) {
    return Container(
      height: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 30, color: AppColors.primaryStrong),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  primary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  secondary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignTranslationPage() {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact =
              constraints.maxWidth < 1050 || constraints.maxHeight < 650;
          final horizontalPadding = isCompact ? 20.0 : 36.0;
          final verticalPadding = isCompact ? 16.0 : 24.0;

          return Padding(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: verticalPadding,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1720),
                child: SizedBox(
                  height: constraints.maxHeight - (verticalPadding * 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSignPageHeader(),
                      SizedBox(height: isCompact ? 14 : 20),
                      Expanded(
                        child: isCompact
                            ? SingleChildScrollView(
                                child: Column(
                                  children: [
                                    SizedBox(
                                      height: 280,
                                      child: _buildSignInputPanel(),
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      height: 320,
                                      child: _buildSignTranslationResult(),
                                    ),
                                  ],
                                ),
                              )
                            : Row(
                                children: [
                                  Expanded(
                                    flex: 9,
                                    child: _buildSignInputPanel(),
                                  ),
                                  const SizedBox(width: 20),
                                  Expanded(
                                    flex: 11,
                                    child: _buildSignTranslationResult(),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.only(bottom: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SafeHub',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.7,
                ),
              ),
              SizedBox(height: 3),
              Text(
                '배리어프리 스마트홈',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const Spacer(),
          _buildConnectionStatus(),
        ],
      ),
    );
  }

  Widget _buildSignPageHeader() {
    return Container(
      padding: const EdgeInsets.only(bottom: 18),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerUp: (_) => _returnHome(),
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primaryStrong,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.home_outlined, size: 20, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    '홈으로',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
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
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          _buildConnectionStatus(),
        ],
      ),
    );
  }

  Widget _buildConnectionStatus() {
    final statusColor = _mqttConnected ? AppColors.success : AppColors.warning;

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
          '시스템 $_connectionStatus',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildSignLaunchSection() {
    final hasResult = _signText != '수어 인식 대기 중';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(
              Icons.sign_language_outlined,
              size: 34,
              color: AppColors.primaryStrong,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                '수어 실시간 번역',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const Spacer(),
        Expanded(
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, animation) {
                final slide = Tween<Offset>(
                  begin: const Offset(0, 0.08),
                  end: Offset.zero,
                ).animate(animation);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: slide, child: child),
                );
              },
              child: Text(
                hasResult ? _signText : '인식 대기 중',
                key: ValueKey(_signText),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: hasResult ? 48 : 28,
                  fontWeight: FontWeight.w800,
                  color: hasResult
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  height: 1.1,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => setState(() => _signButtonPressed = true),
          onPointerCancel: (_) => setState(() => _signButtonPressed = false),
          onPointerUp: (_) {
            setState(() => _signButtonPressed = false);
            _openSignTranslation();
          },
          child: AnimatedScale(
            scale: _signButtonPressed ? 0.98 : 1,
            duration: const Duration(milliseconds: 100),
            child: Container(
              width: double.infinity,
              height: 62,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primaryStrong,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '번역 시작',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 9),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 21,
                    color: Colors.white,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSignInputPanel() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: const Color(0xFF24313D),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: _mqttConnected ? AppColors.success : AppColors.warning,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _mqttConnected ? '인식 장치 연결됨' : '인식 장치 연결 확인 중',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const Spacer(),
          Center(
            child: Column(
              children: [
                const Icon(
                  Icons.center_focus_strong_outlined,
                  size: 82,
                  color: Color(0xFF9FB1C2),
                ),
                const SizedBox(height: 22),
                Text(
                  _mqttConnected ? '수어 인식 대기 중' : '연결 확인 필요',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '카메라 앞에서 수어 동작을 보여주세요.',
                  style: TextStyle(
                    fontSize: 15,
                    color: Color(0xFFB9C5CF),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildSignTranslationResult() {
    final hasResult = _signText != '수어 인식 대기 중';

    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.all(34),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '번역 결과',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
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
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, animation) {
              final slide = Tween<Offset>(
                begin: const Offset(0, 0.08),
                end: Offset.zero,
              ).animate(animation);
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: slide, child: child),
              );
            },
            child: Text(
              _signText,
              key: ValueKey(_signText),
              style: TextStyle(
                fontSize: hasResult ? 72 : 42,
                fontWeight: FontWeight.w800,
                color:
                    hasResult ? AppColors.textPrimary : AppColors.textSecondary,
                height: 1.15,
                letterSpacing: -1.4,
              ),
            ),
          ),
          const Spacer(),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 18),
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

  // Legacy detail widgets retained until the new RPi5 layout is verified.
  // ignore: unused_element
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
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 76,
            color: AppColors.danger,
          ),
          const SizedBox(height: 20),
          Text(
            _getEventName(event),
            style: const TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -1.0,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${_getLocationName(event)} · ${_formatEventDateTime(event)} 감지',
            style: const TextStyle(
              fontSize: 18,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      );
    }

    final connected = _mqttConnected;
    final statusColor = connected ? AppColors.success : AppColors.warning;
    final statusBackground =
        connected ? AppColors.successLight : AppColors.warningLight;

    return Container(
      decoration: BoxDecoration(
        color: statusBackground,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '생활 안전',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                ),
              ),
              const Spacer(),
              Text(
                connected ? '실시간 감지 중' : '연결 확인 필요',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                connected
                    ? Icons.verified_user_rounded
                    : Icons.sensors_off_outlined,
                size: 74,
                color: statusColor,
              ),
              const SizedBox(width: 24),
              Flexible(
                child: Text(
                  connected ? '현재 감지된 위험 없음' : '안전 센서 연결 확인 필요',
                  maxLines: 2,
                  style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    height: 1.1,
                    letterSpacing: -1.0,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          const Divider(height: 1, color: Color(0x33248269)),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _RoomStatus(
                  label: '침실',
                  icon: Icons.bed_outlined,
                  connected: connected,
                ),
              ),
              Container(width: 1, height: 36, color: AppColors.border),
              Expanded(
                child: _RoomStatus(
                  label: '화장실',
                  icon: Icons.bathroom_outlined,
                  connected: connected,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
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

  // ignore: unused_element
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
    final priority = _getEventPriority(event);

    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _alertPulseController,
        builder: (context, child) {
          return Container(
            color: Color.lerp(
              const Color(0xFFFFF3F3),
              const Color(0xFFF3B2B2),
              _alertPulseController.value * 0.72,
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
                  eventName == '낙상 감지' ? '낙상이 감지되었습니다' : eventName,
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
                  '$detectedAt 감지  ·  긴급도 $priority',
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

  // ignore: unused_element
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

class _RoomStatus extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool connected;

  const _RoomStatus({
    required this.label,
    required this.icon,
    required this.connected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          icon,
          size: 30,
          color: connected ? AppColors.success : AppColors.warning,
        ),
        const SizedBox(width: 12),
        Text(
          '$label · ${connected ? '감지 대기' : '연결 확인'}',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: connected ? AppColors.textPrimary : AppColors.warning,
          ),
        ),
      ],
    );
  }
}
