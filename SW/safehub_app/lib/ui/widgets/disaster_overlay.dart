import 'package:flutter/material.dart';

import '../utils/disaster_display.dart';

/// Display API content faithfully. Acknowledgement is not a safety judgement.
class DisasterOverlay extends StatelessWidget {
  final Map<String, dynamic> disaster;
  // Kept for compatibility with the hub; no full-screen flashing animation.
  final Animation<double> pulseAnimation;
  final VoidCallback onAcknowledge;

  const DisasterOverlay({
    super.key,
    required this.disaster,
    required this.pulseAnimation,
    required this.onAcknowledge,
  });

  static const _ink = Color(0xFFF3F1EE);
  static const _muted = Color(0xFFC4C1BD);
  static const _coral = Color(0xFFFF8B7C);

  @override
  Widget build(BuildContext context) {
    final type = disaster['DST_SE_NM']?.toString().trim() ?? '재난';
    final step = disaster['EMRG_STEP_NM']?.toString().trim() ?? '재난 알림';
    final region = disaster['RCPTN_RGN_NM']?.toString().trim() ?? '지역 정보 없음';
    final message = disaster['MSG_CN']?.toString().trim() ?? '재난 정보를 확인해 주세요.';
    final date = disaster['CRT_DT']?.toString().trim() ?? '발표 시각 미확인';

    return Positioned.fill(child: ColoredBox(
      color: const Color(0xFF1C252D),
      child: SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.all(26),
        child: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Semantics(liveRegion: true, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SafeHub · $step${disaster['source'] == 'ui_test' ? ' · UI 테스트' : ''}', style: const TextStyle(color: _coral, fontSize: 18)),
              const SizedBox(height: 24),
              Wrap(spacing: 14, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Icon(getDisasterIcon(disaster), size: 34, color: _coral),
                Text('$type 알림을 확인해 주세요', style: const TextStyle(color: _ink, fontSize: 32, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 16),
              Text('대상 지역 · $region\n발표 · $date', style: const TextStyle(color: _muted, fontSize: 18, height: 1.6)),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: const Color(0xFF253038), borderRadius: BorderRadius.circular(16)),
                child: Text(message, style: const TextStyle(color: _ink, fontSize: 25, height: 1.7)),
              ),
              const SizedBox(height: 24),
              const Text('재난 문자에 안내된 행동을 확인해 주세요.', style: TextStyle(color: _muted, fontSize: 18)),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAcknowledge,
                style: FilledButton.styleFrom(
                  backgroundColor: _coral, foregroundColor: const Color(0xFF202D3E),
                  minimumSize: const Size(48, 56), padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('내용 확인했어요', style: TextStyle(fontSize: 21)),
              ),
              const SizedBox(height: 14),
              const Text('내용 확인은 안전이 확인되었다는 의미가 아닙니다.', style: TextStyle(color: _muted, fontSize: 15)),
            ],
          )),
        )),
      )),
    ));
  }
}
