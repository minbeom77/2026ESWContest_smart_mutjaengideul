import 'package:flutter_test/flutter_test.dart';
import 'package:safehub_app/services/disaster_service.dart';

void main() {
  group('DisasterService.identifierOf', () {
    test('숫자 SN을 문자열 식별자로 변환한다', () {
      expect(
        DisasterService.identifierOf({'SN': 301}),
        '301',
      );
    });

    test('문자열 SN 앞뒤 공백을 제거한다', () {
      expect(
        DisasterService.identifierOf({'SN': ' 302 '}),
        '302',
      );
    });

    test('SN이 없거나 비어 있으면 null을 반환한다', () {
      expect(DisasterService.identifierOf({}), isNull);
      expect(DisasterService.identifierOf({'SN': '  '}), isNull);
    });
  });

  group('DisasterService.selectLatest', () {
    test('응답이 오래된 순서여도 가장 최신 CRT_DT를 선택한다', () {
      final latest = DisasterService.selectLatest([
        {
          'SN': 100,
          'CRT_DT': '2026/09/12 10:00:00',
          'MSG_CN': '오래된 재난',
        },
        {
          'SN': 102,
          'CRT_DT': '2026/09/14 15:30:00',
          'MSG_CN': '최신 재난',
        },
        {
          'SN': 101,
          'CRT_DT': '2026/09/13 12:00:00',
          'MSG_CN': '중간 재난',
        },
      ]);

      expect(latest?['SN'], 102);
      expect(latest?['MSG_CN'], '최신 재난');
    });

    test('응답이 최신 순서여도 가장 최신 CRT_DT를 선택한다', () {
      final latest = DisasterService.selectLatest([
        {
          'SN': '202',
          'CRT_DT': '2026-09-14 18:00:00',
        },
        {
          'SN': '201',
          'CRT_DT': '2026-09-13 18:00:00',
        },
      ]);

      expect(latest?['SN'], '202');
    });

    test('CRT_DT가 같으면 더 큰 SN을 선택한다', () {
      final latest = DisasterService.selectLatest([
        {
          'SN': '300',
          'CRT_DT': '2026/09/14 18:00:00',
        },
        {
          'SN': 301,
          'CRT_DT': '2026/09/14 18:00:00',
        },
      ]);

      expect(latest?['SN'], 301);
    });

    test('현재 항목보다 오래된 재난은 최신으로 판단하지 않는다', () {
      final current = {
        'SN': 500,
        'CRT_DT': '2026/09/20 10:00:00',
      };

      final older = {
        'SN': 499,
        'CRT_DT': '2026/09/17 13:50:40',
      };

      final newer = {
        'SN': 501,
        'CRT_DT': '2026/09/21 09:00:00',
      };

      expect(
        DisasterService.isNewerThan(older, current),
        isFalse,
      );

      expect(
        DisasterService.isNewerThan(newer, current),
        isTrue,
      );
    });

    test('잘못된 항목과 빈 목록을 안전하게 처리한다', () {
      final latest = DisasterService.selectLatest([
        null,
        'invalid',
        {
          'SN': 400,
          'CRT_DT': '2026/09/14 19:00:00',
        },
      ]);

      expect(latest?['SN'], 400);
      expect(DisasterService.selectLatest([]), isNull);
    });
  });
}
