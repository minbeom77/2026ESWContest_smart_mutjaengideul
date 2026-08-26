import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../core/event_manager.dart';
import '../mqtt/mqtt_receiver.dart';
import 'theme/app_theme.dart';

class SafeHubHomePage extends StatefulWidget {
  const SafeHubHomePage({super.key});

  @override
  State<SafeHubHomePage> createState() => _SafeHubHomePageState();
}

class _SafeHubHomePageState extends State<SafeHubHomePage>
    with SingleTickerProviderStateMixin {
  final EventManager _eventManager = EventManager();

  late final MqttReceiver _mqttReceiver;
  late final AnimationController _alertPulseController;

  bool _mqttConnected = false;
  String _connectionStatus = '연결 중';

  String _signText = '수어 인식 대기 중';

  Map<String, dynamic>? _lastEvent;
  Map<String, dynamic>? _activeAlert;

  final List<Map<String, dynamic>> _recentEvents = [];

  @override
  void initState() {
    super.initState();
    _alertPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
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

    setState(() {
      _signText = text;
    });
  }

  void _handleEvent(Map<String, dynamic> event) {
    if (!mounted) {
      return;
    }

    setState(() {
      _lastEvent = event;

      _recentEvents.insert(
        0,
        Map<String, dynamic>.from(event),
      );

      if (_recentEvents.length > 5) {
        _recentEvents.removeLast();
      }

      if (_isEmergencyEvent(event)) {
        _activeAlert = event;
        _alertPulseController.repeat(reverse: true);
      }
    });
  }

  bool _isEmergencyEvent(Map<String, dynamic> event) {
    return event['event'] == 'fall_detected';
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

  @override
  void dispose() {
    _alertPulseController.dispose();
    _mqttReceiver.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F3F0),
      body: Stack(
        children: [
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 900;

                return SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: isCompact ? 24 : 54,
                    vertical: 32,
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
                          const SizedBox(height: 40),
                          _buildHero(),
                          const SizedBox(height: 28),
                          _buildMainCards(isCompact),
                          const SizedBox(height: 22),
                          _buildRecentEvents(),
                          const SizedBox(height: 26),
                          _buildFooter(),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_activeAlert != null) _buildEmergencyOverlay(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header
  // ---------------------------------------------------------------------------

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
              '배리어프리 스마트홈',
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

  // ---------------------------------------------------------------------------
  // Hero
  // ---------------------------------------------------------------------------

  Widget _buildHero() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '오늘도 안전한 소통을 함께합니다.',
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -1.1,
          ),
        ),
        SizedBox(height: 9),
        Text(
          '수어 번역과 생활 안전 상태를 한눈에 확인하세요.',
          style: TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Main cards
  // ---------------------------------------------------------------------------

  Widget _buildMainCards(bool isCompact) {
    if (isCompact) {
      return Column(
        children: [
          _buildSignCard(),
          const SizedBox(height: 18),
          _buildSafetyCard(),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 6,
          child: _buildSignCard(),
        ),
        const SizedBox(width: 18),
        Expanded(
          flex: 4,
          child: _buildSafetyCard(),
        ),
      ],
    );
  }

  Widget _buildSignCard() {
    final hasResult = _signText != '수어 인식 대기 중';

    return Container(
      height: 340,
      padding: const EdgeInsets.all(30),
      decoration: _softCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '수어 번역',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '인식된 수어를 실시간으로 텍스트로 표시합니다.',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const Spacer(),
          const Text(
            '인식 결과',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              _signText,
              key: ValueKey(_signText),
              style: TextStyle(
                fontSize: hasResult ? 38 : 29,
                fontWeight: FontWeight.w700,
                color:
                    hasResult ? AppColors.textPrimary : AppColors.textSecondary,
                letterSpacing: -0.9,
                height: 1.25,
              ),
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: hasResult ? AppColors.success : AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                hasResult ? '최근 수어 인식 결과' : '수어 입력을 기다리고 있습니다.',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyCard() {
    final hasEvent = _lastEvent != null;

    return Container(
      height: 340,
      padding: const EdgeInsets.all(30),
      decoration: _softCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '안전 상태',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '침실과 화장실의 이상 상황을 확인합니다.',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const Spacer(),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: hasEvent ? _buildEventState() : _buildSafeState(),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildSafeState() {
    return const Column(
      key: ValueKey('safe'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.shield_rounded,
          size: 45,
          color: AppColors.success,
        ),
        SizedBox(height: 18),
        Text(
          '이상 없음',
          style: TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.6,
          ),
        ),
        SizedBox(height: 9),
        Text(
          '현재 감지된 안전 이벤트가 없습니다.',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildEventState() {
    final event = _lastEvent!;

    final eventName = _getEventName(event);
    final locationName = _getLocationName(event);
    final priority = event['priority']?.toString() ?? '-';

    return Column(
      key: const ValueKey('event'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.warning_amber_rounded,
          size: 43,
          color: AppColors.danger,
        ),
        const SizedBox(height: 14),
        const Text(
          '안전 이벤트 감지',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.danger,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          eventName,
          style: const TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '$locationName · 위험도 $priority',
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  // Recent events

  Widget _buildRecentEvents() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 30,
        vertical: 24,
      ),
      decoration: _softCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '최근 이벤트',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            '최근 감지된 안전 이벤트를 확인할 수 있습니다.',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 18),
          if (_recentEvents.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(
                vertical: 10,
              ),
              child: Text(
                '아직 감지된 이벤트가 없습니다.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            )
          else
            Column(
              children: [
                for (int i = 0; i < _recentEvents.length; i++) ...[
                  _buildEventRow(
                    _recentEvents[i],
                  ),
                  if (i != _recentEvents.length - 1)
                    const Divider(
                      height: 1,
                      color: AppColors.border,
                    ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildEventRow(
    Map<String, dynamic> event,
  ) {
    final eventName = _getEventName(event);
    final locationName = _getLocationName(event);
    final priority = event['priority']?.toString() ?? '-';

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 14,
      ),
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eventName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  locationName,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '위험도 $priority',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // Emergency screen

  Widget _buildEmergencyOverlay() {
    final event = _activeAlert!;

    final eventName = _getEventName(event);
    final locationName = _getLocationName(event);
    final priority = event['priority']?.toString() ?? '-';

    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _alertPulseController,
        builder: (context, child) {
          final pulse = _alertPulseController.value;

          return Container(
            color: Color.lerp(
              const Color(0xFFFFF3F3),
              const Color(0xFFE54848),
              pulse,
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
                // 상단
                Row(
                  children: [
                    const Text(
                      'SafeHub',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                        color: AppColors.danger,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
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

                // 중앙 경고 영역
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

                const SizedBox(height: 26),

                AnimatedBuilder(
                  animation: _alertPulseController,
                  builder: (context, child) {
                    return Transform.scale(
                      alignment: Alignment.centerLeft,
                      scale: 1.0 + (_alertPulseController.value * 0.06),
                      child: child,
                    );
                  },
                  child: Text(
                    eventName,
                    style: const TextStyle(
                      fontSize: 60,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      letterSpacing: -1.4,
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                Text(
                  '$locationName에서 위험 상황이 감지되었습니다.',
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),

                const SizedBox(height: 8),

                const Text(
                  '주변 상황을 즉시 확인해 주세요.',
                  style: TextStyle(
                    fontSize: 15,
                    color: AppColors.textSecondary,
                  ),
                ),

                const SizedBox(height: 34),

                Row(
                  children: [
                    _buildEmergencyInfo(
                      title: '감지 위치',
                      value: locationName,
                    ),
                    const SizedBox(width: 56),
                    _buildEmergencyInfo(
                      title: '위험도',
                      value: priority,
                    ),
                  ],
                ),

                const Spacer(),

                Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: 220,
                    height: 54,
                    child: FilledButton(
                      onPressed: () {
                        _alertPulseController
                          ..stop()
                          ..reset();

                        setState(() {
                          _activeAlert = null;
                        });
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.danger,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        '확인했습니다',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
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

  Widget _buildEmergencyInfo({
    required String title,
    required String value,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  // Helpers

  BoxDecoration _softCardDecoration() {
    return BoxDecoration(
      color: const Color(0xF7FFFFFF),
      borderRadius: BorderRadius.circular(24),
      boxShadow: const [
        BoxShadow(
          color: Color(0x07000000),
          blurRadius: 22,
          offset: Offset(0, 7),
        ),
      ],
    );
  }

  String _getEventName(
    Map<String, dynamic> event,
  ) {
    switch (event['event']) {
      case 'fall_detected':
        return '낙상 감지';

      default:
        return event['event']?.toString() ?? '알 수 없는 이벤트';
    }
  }

  String _getLocationName(
    Map<String, dynamic> event,
  ) {
    switch (event['location']) {
      case 'bedroom':
        return '침실';

      case 'bathroom':
        return '화장실';

      default:
        return '실내';
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
