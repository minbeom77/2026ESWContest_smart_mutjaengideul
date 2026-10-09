import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/event_display.dart';

class EmergencyOverlay extends StatelessWidget {
  final Map<String, dynamic> event;
  final Animation<double> pulseAnimation;
  final VoidCallback onAcknowledge;

  const EmergencyOverlay({
    super.key,
    required this.event,
    required this.pulseAnimation,
    required this.onAcknowledge,
  });

  @override
  Widget build(BuildContext context) {
    final eventName = getEventName(event);
    final locationName = getLocationName(event);
    final priority = event['priority']?.toString() ?? '-';

    return Positioned.fill(
      child: AnimatedBuilder(
        animation: pulseAnimation,
        builder: (context, child) {
          final pulse = pulseAnimation.value;

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
                _buildHeader(),
                const Spacer(),
                _buildWarningIcon(),
                const SizedBox(height: 26),
                _buildEventTitle(eventName),
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
                      onPressed: onAcknowledge,
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

  Widget _buildHeader() {
    return Row(
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
    );
  }

  Widget _buildWarningIcon() {
    return AnimatedBuilder(
      animation: pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: 1.0 + (pulseAnimation.value * 0.14),
          child: child,
        );
      },
      child: const Icon(
        Icons.warning_amber_rounded,
        size: 82,
        color: AppColors.danger,
      ),
    );
  }

  Widget _buildEventTitle(String eventName) {
    return AnimatedBuilder(
      animation: pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          alignment: Alignment.centerLeft,
          scale: 1.0 + (pulseAnimation.value * 0.06),
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
}
