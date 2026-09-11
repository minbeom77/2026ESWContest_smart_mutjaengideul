import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class CameraFeedPanel extends StatelessWidget {
  final String streamUrl;

  const CameraFeedPanel({
    super.key,
    required this.streamUrl,
  });

  @override
  Widget build(BuildContext context) {
    final configured = streamUrl.trim().isNotEmpty;

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.cameraBackground,
          border: Border.all(color: AppColors.borderStrong),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'RPi4 CAMERA · 영상 미연결',
              style: TextStyle(
                color: Color(0xFFB7C0C9),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.videocam_outlined,
                        size: 40,
                        color: Color(0xFFB7C0C9),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '카메라 미리보기',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        configured
                            ? '영상 주소 설정됨 · 수신 기능 연결 예정'
                            : '영상 주소가 설정되지 않았습니다.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFB7C0C9),
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
