import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/disaster_display.dart';

class DisasterOverlay extends StatelessWidget {
  final Map<String, dynamic> disaster;
  final Animation<double> pulseAnimation;
  final VoidCallback onAcknowledge;

  const DisasterOverlay({
    super.key,
    required this.disaster,
    required this.pulseAnimation,
    required this.onAcknowledge,
  });

  @override
  Widget build(BuildContext context) {
    final severity = getDisasterSeverity(disaster);
    final isCritical = severity == DisasterSeverity.critical;

    final type = disaster['DST_SE_NM']?.toString().trim() ?? '재난';

    final step = disaster['EMRG_STEP_NM']?.toString().trim() ?? '재난알림';

    final region = disaster['RCPTN_RGN_NM']?.toString().trim() ?? '지역 정보 없음';

    final message = disaster['MSG_CN']?.toString().trim() ?? '재난 정보를 확인해 주세요.';

    final date = disaster['CRT_DT']?.toString().trim() ?? '';

    final icon = getDisasterIcon(disaster);

    final accentColor =
        isCritical ? const Color(0xFFDC2626) : const Color(0xFFEA580C);

    final startColor =
        isCritical ? const Color(0xFFFFF3F3) : const Color(0xFFFFF7E8);

    final endColor =
        isCritical ? const Color(0xFFE54848) : const Color(0xFFF59E0B);

    return Positioned.fill(
      child: AnimatedBuilder(
        animation: pulseAnimation,
        builder: (context, child) {
          return Container(
            color: Color.lerp(
              startColor,
              endColor,
              pulseAnimation.value,
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
                      decoration: BoxDecoration(
                        color: accentColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$step 알림',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: accentColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 34),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AnimatedBuilder(
                          animation: pulseAnimation,
                          builder: (context, child) {
                            final amount = isCritical ? 0.14 : 0.07;

                            return Transform.scale(
                              alignment: Alignment.centerLeft,
                              scale: 1 + pulseAnimation.value * amount,
                              child: child,
                            );
                          },
                          child: Icon(
                            icon,
                            size: 78,
                            color: accentColor,
                          ),
                        ),
                        const SizedBox(height: 26),
                        Text(
                          step,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: accentColor,
                          ),
                        ),
                        const SizedBox(height: 8),
                        AnimatedBuilder(
                          animation: pulseAnimation,
                          builder: (context, child) {
                            final amount = isCritical ? 0.05 : 0.025;

                            return Transform.scale(
                              alignment: Alignment.centerLeft,
                              scale: 1 + pulseAnimation.value * amount,
                              child: child,
                            );
                          },
                          child: Text(
                            type,
                            style: const TextStyle(
                              fontSize: 58,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                              letterSpacing: -1.4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          region,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 26),
                        Text(
                          message,
                          style: const TextStyle(
                            fontSize: 20,
                            height: 1.55,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          date,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          isCritical
                              ? '즉시 안전한 장소로 이동하고 재난 안내에 따라 행동해 주세요.'
                              : '재난문자 내용을 확인하고 안전에 유의해 주세요.',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: accentColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: 220,
                    height: 54,
                    child: FilledButton(
                      onPressed: onAcknowledge,
                      style: FilledButton.styleFrom(
                        backgroundColor: accentColor,
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
}
