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

class _SafeHubHomePageState extends State<SafeHubHomePage> {
  final EventManager _eventManager = EventManager();

  late final MqttReceiver _mqttReceiver;

  bool _mqttConnected = false;
  String _connectionStatus = '연결 중';

  String _signText = '수어 인식 대기 중';

  Map<String, dynamic>? _lastEvent;
  Map<String, dynamic>? _activeAlert;

  final List<Map<String, dynamic>> _recentEvents = [];

  @override
  void initState() {
    super.initState();

    _mqttReceiver = MqttReceiver(
      broker: AppConfig.mqttBroker,
      port: AppConfig.mqttPort,
      eventManager: _eventManager,
      onEventReceived: _handleEvent,
    );

    _connectMqtt();
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
    _mqttReceiver.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 950;

                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 42,
                    vertical: 30,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 1320,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(),
                          const SizedBox(height: 56),
                          _buildIntro(),
                          const SizedBox(height: 34),
                          if (isCompact)
                            Column(
                              children: [
                                _buildSignCard(),
                                const SizedBox(height: 22),
                                _buildSafetyCard(),
                              ],
                            )
                          else
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 6,
                                  child: _buildSignCard(),
                                ),
                                const SizedBox(width: 24),
                                Expanded(
                                  flex: 4,
                                  child: _buildSafetyCard(),
                                ),
                              ],
                            ),
                          const SizedBox(height: 24),
                          _buildRecentEvents(),
                          const SizedBox(height: 30),
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

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(
            Icons.home_rounded,
            color: Colors.white,
            size: 27,
          ),
        ),
        const SizedBox(width: 14),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SafeHub',
              style: TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -0.6,
              ),
            ),
            SizedBox(height: 2),
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
        _buildConnectionBadge(),
      ],
    );
  }

  Widget _buildConnectionBadge() {
    final color = _mqttConnected ? AppColors.success : AppColors.danger;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 11,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: AppColors.border,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D101828),
            blurRadius: 18,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 9),
          Text(
            '시스템 $_connectionStatus',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntro() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '안전한 소통이 머무는 공간',
          style: TextStyle(
            fontSize: 35,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            letterSpacing: -1.1,
          ),
        ),
        SizedBox(height: 10),
        Text(
          '수어 번역과 생활 안전 이벤트를 하나의 화면에서 확인하세요.',
          style: TextStyle(
            fontSize: 16,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildSignCard() {
    return Container(
      height: 410,
      padding: const EdgeInsets.all(30),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            icon: Icons.sign_language_rounded,
            title: '실시간 수어 번역',
            description: '수어 동작을 텍스트로 번역합니다',
            color: AppColors.primary,
          ),
          const Spacer(),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: 36,
              vertical: 42,
            ),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFF7FAFF),
                  Color(0xFFEEF4FF),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                Container(
                  width: 82,
                  height: 82,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.sign_language_rounded,
                    color: AppColors.primary,
                    size: 40,
                  ),
                ),
                const SizedBox(width: 28),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '인식 결과',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      AnimatedSwitcher(
                        duration: const Duration(
                          milliseconds: 250,
                        ),
                        child: Text(
                          _signText,
                          key: ValueKey(_signText),
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.7,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          const Row(
            children: [
              Icon(
                Icons.circle,
                size: 8,
                color: AppColors.primary,
              ),
              SizedBox(width: 8),
              Text(
                '수어 입력을 기다리고 있습니다.',
                style: TextStyle(
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

  Widget _buildSafetyCard() {
    final hasEvent = _lastEvent != null;

    return Container(
      height: 410,
      padding: const EdgeInsets.all(30),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            icon: Icons.shield_outlined,
            title: '안전 모니터링',
            description: '침실 및 화장실의 이상 상황을 감지합니다',
            color: hasEvent ? AppColors.danger : AppColors.success,
          ),
          const SizedBox(height: 32),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(
                milliseconds: 250,
              ),
              child: hasEvent ? _buildEventState() : _buildSafeState(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSafeState() {
    return Container(
      key: const ValueKey('safe'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.successLight,
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.verified_user_rounded,
            size: 65,
            color: AppColors.success,
          ),
          SizedBox(height: 22),
          Text(
            '현재 안전합니다',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 25,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          SizedBox(height: 9),
          Text(
            '감지된 안전 이벤트가 없습니다.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventState() {
    final eventName = _lastEvent?['event']?.toString() ?? '알 수 없는 이벤트';

    final priority = _lastEvent?['priority']?.toString() ?? '-';

    return Container(
      key: const ValueKey('event'),
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.dangerLight,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 65,
            color: AppColors.danger,
          ),
          const SizedBox(height: 18),
          const Text(
            '안전 이벤트가 감지되었습니다',
            style: TextStyle(
              color: AppColors.danger,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            eventName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 25,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '위험도 $priority',
              style: const TextStyle(
                color: AppColors.danger,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentEvents() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(30),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            icon: Icons.history_rounded,
            title: '최근 이벤트',
            description: '최근 감지된 안전 이벤트',
            color: AppColors.primary,
          ),
          const SizedBox(height: 24),
          if (_recentEvents.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                vertical: 32,
              ),
              child: const Center(
                child: Text(
                  '아직 수신된 이벤트가 없습니다.',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 14,
                  ),
                ),
              ),
            )
          else
            Column(
              children: [
                for (int i = 0; i < _recentEvents.length; i++) ...[
                  _buildEventRow(_recentEvents[i]),
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

  Widget _buildEventRow(Map<String, dynamic> event) {
    final eventName = event['event']?.toString() ?? '알 수 없는 이벤트';

    final priority = event['priority']?.toString() ?? '-';

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 17,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: AppColors.dangerLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              size: 20,
              color: AppColors.danger,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Text(
              eventName,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '위험도 $priority',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          width: 43,
          height: 43,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(
            icon,
            color: color,
            size: 22,
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(26),
      border: Border.all(
        color: AppColors.border,
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0A101828),
          blurRadius: 24,
          offset: Offset(0, 8),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return const Row(
      children: [
        Text(
          'SafeHub',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        Spacer(),
        Text(
          '모두를 위한 안전한 스마트홈',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  String _getEventName(Map<String, dynamic> event) {
    switch (event['event']) {
      case 'fall_detected':
        return '낙상 감지';
      default:
        return event['event']?.toString() ?? '알 수 없는 이벤트';
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

  Widget _buildEmergencyOverlay() {
    final event = _activeAlert!;

    final eventName = _getEventName(event);
    final locationName = _getLocationName(event);

    return Positioned.fill(
      child: Container(
        color: const Color(0xFFFDF2F2),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(42),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Icon(
                        Icons.warning_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SafeHub',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          '긴급 안전 알림',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.danger,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  width: 110,
                  height: 110,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    size: 62,
                    color: AppColors.danger,
                  ),
                ),
                const SizedBox(height: 30),
                Text(
                  eventName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 46,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                    letterSpacing: -1.4,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '$locationName에서 위험 상황이 감지되었습니다.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 21,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '주변 상황을 확인해 주세요.',
                  style: TextStyle(
                    fontSize: 16,
                    color: AppColors.textSecondary,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 320,
                  height: 58,
                  child: FilledButton(
                    onPressed: () {
                      setState(() {
                        _activeAlert = null;
                      });
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.danger,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      '확인했습니다',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
