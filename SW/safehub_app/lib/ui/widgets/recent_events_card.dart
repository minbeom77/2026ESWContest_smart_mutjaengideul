import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/event_display.dart';
import 'safehub_card.dart';

class RecentEventsCard extends StatelessWidget {
  final List<Map<String, dynamic>> events;

  const RecentEventsCard({
    super.key,
    required this.events,
  });

  @override
  Widget build(BuildContext context) {
    return SafeHubCard(
      padding: const EdgeInsets.symmetric(
        horizontal: 30,
        vertical: 24,
      ),
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
          if (events.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
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
                for (int i = 0; i < events.length; i++) ...[
                  _buildEventRow(events[i]),
                  if (i != events.length - 1)
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
    final eventName = getEventName(event);
    final locationName = getLocationName(event);
    final priority = event['priority']?.toString() ?? '-';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
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
}
