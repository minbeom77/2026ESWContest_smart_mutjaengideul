enum CareHelpKind { familyVisit, familyCall }

extension CareHelpKindText on CareHelpKind {
  String get label => switch (this) {
    CareHelpKind.familyVisit => '가족이 와 주세요',
    CareHelpKind.familyCall => '가족과 통화하고 싶어요',
  };

  String message({String? sign, String? location}) {
    final context = location == null ? '' : '$location에서 낙상 의심 알림이 발생했습니다. ';
    final expression = sign == null ? '사용자가 ' : '사용자가 “$sign”라고 표현하고, ';
    final choice = this == CareHelpKind.familyVisit
        ? '가족에게 와 달라고 요청했습니다.'
        : '가족과 통화하기를 요청했습니다.';
    return '$context$expression$choice';
  }
}

/// Local response tracking only. No notification transport is implied.
class CareIncident {
  CareIncident({required this.id, required this.openedAt, required this.wait});
  final String id;
  final DateTime openedAt;
  final Duration wait;
  String? response;
  String? requestReason;
  bool _timeoutHandled = false;
  bool get awaitingResponse => response == null;
  bool get needsDelivery => requestReason != null;

  int secondsLeft(DateTime now) {
    final milliseconds = openedAt.add(wait).difference(now).inMilliseconds;
    return milliseconds <= 0 ? 0 : (milliseconds / 1000).ceil();
  }

  bool tick(DateTime now) {
    if (!awaitingResponse || _timeoutHandled || secondsLeft(now) > 0) return false;
    _timeoutHandled = true;
    requestReason = '낙상 의심 알림 후 사용자 응답이 없습니다.';
    return true;
  }

  void cancelUnsentRequest() {
    requestReason = null;
  }

  void reply({required bool needsHelp, String? helpMessage}) {
    response = needsHelp ? '도움이 필요해요' : '괜찮아요';
    // A late reply updates the unsent request; no false delivery/cancellation claim.
    requestReason = needsHelp ? helpMessage ?? '사용자가 도움을 요청했습니다.' : null;
  }
}
