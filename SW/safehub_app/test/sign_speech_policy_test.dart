import 'package:flutter_test/flutter_test.dart';
import 'package:safehub_app/services/sign_speech_policy.dart';

void main() {
  group('수어 음성 문장 변환', () {
    final policy = SignSpeechPolicy();

    test('아프다를 도움 요청 문장으로 변환한다', () {
      expect(
        policy.phraseFor('아프다'),
        '아파요. 도움이 필요합니다.',
      );
    });

    test('가전 수어를 자연스러운 문장으로 변환한다', () {
      expect(policy.phraseFor('점등'), '조명을 켜 주세요.');
      expect(policy.phraseFor('소등'), '조명을 꺼 주세요.');
    });

    test('기타 수어는 원문을 사용한다', () {
      expect(policy.phraseFor('감사합니다'), '감사합니다');
    });

    test('아프다만 긴급 수어로 구분한다', () {
      expect(policy.isUrgent('아프다'), isTrue);
      expect(policy.isUrgent('괜찮다'), isFalse);
    });
  });

  group('수어 음성 중복 방지', () {
    test('같은 수어는 4초 안에 다시 재생하지 않는다', () {
      final policy = SignSpeechPolicy();
      final start = DateTime(2026, 9, 22, 12);

      expect(
        policy.shouldSpeak('아프다', now: start),
        isTrue,
      );

      expect(
        policy.shouldSpeak(
          '아프다',
          now: start.add(const Duration(seconds: 2)),
        ),
        isFalse,
      );

      expect(
        policy.shouldSpeak(
          '아프다',
          now: start.add(const Duration(seconds: 4)),
        ),
        isTrue,
      );
    });

    test('다른 수어는 바로 재생할 수 있다', () {
      final policy = SignSpeechPolicy();
      final start = DateTime(2026, 9, 22, 12);

      expect(
        policy.shouldSpeak('아프다', now: start),
        isTrue,
      );

      expect(
        policy.shouldSpeak(
          '괜찮다',
          now: start.add(const Duration(seconds: 1)),
        ),
        isTrue,
      );
    });

    test('빈 수어는 재생하지 않는다', () {
      final policy = SignSpeechPolicy();

      expect(policy.shouldSpeak('   '), isFalse);
    });
  });
}
