import 'dart:io';

import 'package:safehub_app/services/disaster_service.dart';

Future<void> main() async {
  final service = DisasterService();

  try {
    final disaster = await service.fetchLatest();

    if (disaster == null) {
      stdout.writeln('재난문자가 없습니다.');
      return;
    }

    stdout.writeln('===== 최신 재난문자 =====');
    stdout.writeln('SN: ${disaster['SN']}');
    stdout.writeln('종류: ${disaster['DST_SE_NM']}');
    stdout.writeln('단계: ${disaster['EMRG_STEP_NM']}');
    stdout.writeln('지역: ${disaster['RCPTN_RGN_NM']}');
    stdout.writeln('시간: ${disaster['CRT_DT']}');
    stdout.writeln('내용: ${disaster['MSG_CN']}');
  } catch (e) {
    stderr.writeln('재난 API 호출 실패: $e');
    exitCode = 1;
  }
}
