class SignSpeechPolicy {
  SignSpeechPolicy({
    this.cooldown = const Duration(seconds: 4),
  });

  final Duration cooldown;

  String? _lastSign;
  DateTime? _lastSpokenAt;

  String phraseFor(String sign) {
    final cleanSign = sign.trim();

    return switch (cleanSign) {
      '아프다' => '아파요. 도움이 필요합니다.',
      '괜찮다' => '괜찮습니다.',
      '점등' => '조명을 켜 주세요.',
      '소등' => '조명을 꺼 주세요.',
      '온도' => '현재 온도를 확인해 주세요.',
      '배고프다' => '배가 고파요.',
      '목마르다' => '목이 말라요.',
      _ => cleanSign,
    };
  }

  bool isUrgent(String sign) {
    return sign.trim() == '아프다';
  }

  bool shouldSpeak(
    String sign, {
    DateTime? now,
  }) {
    final cleanSign = sign.trim();

    if (cleanSign.isEmpty) {
      return false;
    }

    final currentTime = now ?? DateTime.now();
    final lastSpokenAt = _lastSpokenAt;

    if (_lastSign == cleanSign &&
        lastSpokenAt != null &&
        currentTime.difference(lastSpokenAt) < cooldown) {
      return false;
    }

    _lastSign = cleanSign;
    _lastSpokenAt = currentTime;
    return true;
  }
}
