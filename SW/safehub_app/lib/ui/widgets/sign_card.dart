import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'safehub_card.dart';

class SignCard extends StatelessWidget {
  final String signText;

  const SignCard({
    super.key,
    required this.signText,
  });

  @override
  Widget build(BuildContext context) {
    final hasResult = signText != '수어 인식 대기 중';

    return SafeHubCard(
      height: 340,
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
              signText,
              key: ValueKey(signText),
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
}
