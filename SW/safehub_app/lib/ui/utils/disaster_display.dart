import 'package:flutter/material.dart';

enum DisasterSeverity {
  notice,
  emergency,
  critical,
}

DisasterSeverity getDisasterSeverity(
  Map<String, dynamic> disaster,
) {
  final step = disaster['EMRG_STEP_NM']?.toString().trim() ?? '';

  switch (step) {
    case '위급재난':
      return DisasterSeverity.critical;

    case '긴급재난':
      return DisasterSeverity.emergency;

    case '안전안내':
    default:
      return DisasterSeverity.notice;
  }
}

Color getDisasterBackgroundColor(
  DisasterSeverity severity,
) {
  switch (severity) {
    case DisasterSeverity.notice:
      return const Color(0xFFFFF7D6);

    case DisasterSeverity.emergency:
      return const Color(0xFFFFE8CC);

    case DisasterSeverity.critical:
      return const Color(0xFFFFE2E2);
  }
}

Color getDisasterAccentColor(
  DisasterSeverity severity,
) {
  switch (severity) {
    case DisasterSeverity.notice:
      return const Color(0xFFF59E0B);

    case DisasterSeverity.emergency:
      return const Color(0xFFEA580C);

    case DisasterSeverity.critical:
      return const Color(0xFFDC2626);
  }
}

IconData getDisasterIcon(
  Map<String, dynamic> disaster,
) {
  final type = disaster['DST_SE_NM']?.toString().trim() ?? '';

  switch (type) {
    case '폭염':
      return Icons.wb_sunny_rounded;

    case '호우':
      return Icons.water_drop_rounded;

    case '태풍':
      return Icons.cyclone_rounded;

    case '대설':
      return Icons.ac_unit_rounded;

    case '산불':
      return Icons.local_fire_department_rounded;

    case '지진':
      return Icons.vibration_rounded;

    case '미세먼지':
      return Icons.air_rounded;

    default:
      return Icons.campaign_rounded;
  }
}
