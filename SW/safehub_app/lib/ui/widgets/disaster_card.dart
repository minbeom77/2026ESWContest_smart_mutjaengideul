import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/disaster_display.dart';
import 'safehub_card.dart';

class DisasterCard extends StatelessWidget {
  final Map<String, dynamic>? disaster;

  const DisasterCard({
    super.key,
    required this.disaster,
  });

  @override
  Widget build(BuildContext context) {
    final currentDisaster = disaster;

    if (currentDisaster == null) {
      return const SafeHubCard(
        padding: EdgeInsets.symmetric(
          horizontal: 30,
          vertical: 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '재난 안전 정보',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 18),
            Text(
              '재난 안전 정보를 불러오는 중입니다.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      );
    }

    final severity = getDisasterSeverity(currentDisaster);

    final accentColor = getDisasterAccentColor(severity);

    final backgroundColor = getDisasterBackgroundColor(severity);

    final icon = getDisasterIcon(currentDisaster);

    final type = currentDisaster['DST_SE_NM']?.toString() ?? '재난';

    final step = currentDisaster['EMRG_STEP_NM']?.toString() ?? '';

    final region =
        currentDisaster['RCPTN_RGN_NM']?.toString().trim() ?? '지역 정보 없음';

    final message = currentDisaster['MSG_CN']?.toString() ?? '내용이 없습니다.';

    final date = currentDisaster['CRT_DT']?.toString() ?? '';

    return SafeHubCard(
      backgroundColor: backgroundColor,
      padding: const EdgeInsets.symmetric(
        horizontal: 30,
        vertical: 26,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 24,
                color: accentColor,
              ),
              const SizedBox(width: 10),
              const Text(
                '재난 안전 정보',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
              const Spacer(),
              Text(
                step,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: accentColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            type,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            region,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(
              fontSize: 14,
              height: 1.55,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            date,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
