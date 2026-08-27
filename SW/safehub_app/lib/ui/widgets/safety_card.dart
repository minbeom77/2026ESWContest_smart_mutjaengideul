import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/event_display.dart';
import 'safehub_card.dart';

class SafetyCard extends StatelessWidget {
  final Map<String, dynamic>? event;

  const SafetyCard({
    super.key,
    required this.event,
  });

  @override
  Widget build(BuildContext context) {
    return SafeHubCard(
      height: 340,
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
            child: event == null ? _buildSafeState() : _buildEventState(event!),
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

  Widget _buildEventState(Map<String, dynamic> event) {
    final eventName = getEventName(event);
    final locationName = getLocationName(event);
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
}
