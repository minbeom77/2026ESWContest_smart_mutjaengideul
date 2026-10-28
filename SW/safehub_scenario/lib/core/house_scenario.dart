import 'package:flutter/foundation.dart';

enum HouseScenario { broadcast, disaster, assistance }

class HouseIncident {
  HouseIncident(
    this.id,
    this.kind,
    this.evidence,
    this.receivedAt, {
    this.relevance = '상황 확인 필요',
    this.origin = 'text',
  });
  final String id, relevance, origin;
  String evidence;
  final HouseScenario kind;
  final DateTime receivedAt;
  String response = '';
  String delivery = '화면 안내 중 · LED·진동 전송 전';
  bool acknowledged = false;
  int get priority => kind == HouseScenario.assistance
      ? 3
      : kind == HouseScenario.broadcast
          ? 2
          : 1;
  String get title => switch (kind) {
        HouseScenario.broadcast => origin == 'sound' ? '경보음 감지 · 위급상황인지 확인해 주세요.' : '위험을 알리는 말이 들렸어요. 방송을 확인해 주세요.',
        HouseScenario.disaster => '새 재난 알림이 도착했어요. 적용 지역을 확인해 주세요.',
        HouseScenario.assistance => const {'csi', 'csi_demo'}.contains(origin) ? '낙상 의심 신호가 감지됐어요. 상태를 확인해 주세요.' : '도움이 필요한 상황인지 확인해 주세요.',
      };
  String get nextAction => response.isEmpty
      ? '수어 또는 터치로 확인 여부를 알려주세요.'
      : response.contains('도움') ||
              response.contains('쓰러') ||
              response.contains('아프')
          ? '확인된 내용으로 도움 요청 문안을 준비하세요.'
          : '응답을 기록했어요. 추가 도움이 필요한지 확인하세요.';
  Map<String, dynamic> toJson() => {
        'scenario': kind.name,
        'origin': origin,
        'evidence': evidence.substring(0, evidence.length.clamp(0, 500)),
        'relevance': relevance,
        'received_at': receivedAt.toIso8601String(),
        'user_response': response,
        'delivery': delivery,
        'acknowledged': acknowledged,
        'risk_resolved': false,
      };
}

/// Alert/acknowledgement flow runs without an LLM or an inference score.
class HouseScenarioFlow extends ChangeNotifier {
  HouseScenarioFlow({this.simulated = false});
  final bool simulated;
  final List<HouseIncident> _pending = [];
  final Set<String> _seen = {};
  HouseIncident? active, lastAcknowledged;
  String observation = '방송·재난·센서에서 새 정보를 기다리고 있어요.';
  int get pendingCount => _pending.length;
  static final _hazard = RegExp(r'화재가?\s*(발생|났)|불이\s*났|대피(하|해|\s*바랍)|가스\s*누출');
  static final _nonEmergency = RegExp(
    r'훈련|연습|테스트|시나리오|예시|가정|실험|예방|오보|취소|해제|화재[^.!?\n]{0,16}(발생하지\s*않|아닙|아니|없습|없음)|불이\s*나지\s*않|대피(하지\s*않|[^.!?\n]{0,8}필요[가\s]*없)',
  );

  bool broadcast(String text, {DateTime? now}) {
    final explicit = text
        .replaceAll(RegExp(r'\r\n?'), '\n')
        .split(RegExp(r'[.!?\n]+'))
        .any((clause) =>
            _hazard.hasMatch(clause) && !_nonEmergency.hasMatch(clause));
    if (!explicit) {
      observation = '방송·대화 원문 확인 · 긴급 상황으로 확정하지 않았어요.';
      notifyListeners();
      return false;
    }
    final stamp = now ?? DateTime.now();
    // Repeated ASR delivery of the same phrase is one incident for 5 minutes.
    return _submit(
      HouseIncident(
        'broadcast:${stamp.millisecondsSinceEpoch ~/ 300000}:${text.replaceAll(RegExp(r'\s+'), '')}',
        HouseScenario.broadcast,
        text,
        stamp,
        relevance: '음성 인식 결과 · 실제 방송·위험 여부 미확인',
      ),
    );
  }

  bool soundAlarm(String id, String label, {DateTime? now}) {
    const sirens = {'Siren', 'Civil defense siren', 'Police car (siren)',
      'Ambulance (siren)', 'Fire engine, fire truck (siren)'};
    if (!{'Fire alarm', 'Smoke detector, smoke alarm', ...sirens}.contains(label)) return false;
    final kind = sirens.contains(label) ? '사이렌' : '화재경보음';
    return _submit(HouseIncident('sound:$id', HouseScenario.broadcast,
        '$kind 소리가 의심됩니다. 주변 상황과 안내를 확인해 주세요.\nYAMNet 음향 분류 결과 · 실제 화재·재난이나 발생 장소를 확정하지 않습니다.',
        now ?? DateTime.now(), origin: 'sound', relevance: '음성자막 없이 경보음에서 감지 · 주변 확인 필요'));
  }

  bool disaster({
    required String id,
    required String text,
    required String region,
    required DateTime? issuedAt,
    String homeRegion = '',
    DateTime? now,
  }) {
    final stamp = now ?? DateTime.now();
    if (issuedAt == null ||
        stamp.difference(issuedAt) > const Duration(minutes: 30) ||
        issuedAt.difference(stamp) > const Duration(minutes: 5)) {
      observation = '기존 재난 기록 또는 발행 시각 미확인 · 새 경보로 처리하지 않아요.';
      notifyListeners();
      return false;
    }
    final selected = homeRegion.trim();
    if (selected.isNotEmpty &&
        region.isNotEmpty &&
        !region.contains(selected) &&
        !region.contains('전국')) {
      observation = '$region 참고 알림 · 설정한 지역($selected)과 다릅니다.';
      notifyListeners();
      return false;
    }
    return _submit(
      HouseIncident(
        'disaster:$id',
        HouseScenario.disaster,
        '$text\n지역: ${region.isEmpty ? '미확인' : region} · 발행: $issuedAt',
        stamp,
        relevance: selected.isEmpty || region.isEmpty
            ? '집 지역 미확인 · 적용 여부를 확인해 주세요.'
            : '설정한 지역 관련 알림',
      ),
    );
  }

  bool assistance(String id, String text, {DateTime? now, String origin = 'text'}) => _submit(
        HouseIncident(
          'assistance:$id',
          HouseScenario.assistance,
          text,
          now ?? DateTime.now(),
          origin: origin,
          relevance: '센서 의심 신호 또는 사용자 요청 · 낙상·의식불명 확정 아님',
        ),
      );

  bool _submit(HouseIncident incident) {
    if (!_seen.add(incident.id)) return false;
    if (_seen.length > 128) _seen.remove(_seen.first);
    // Sound and text are independent triggers, but near-simultaneous evidence
    // belongs to one alert rather than opening duplicate popups.
    if (incident.kind == HouseScenario.broadcast) {
      for (final previous in [if (active != null) active!, ..._pending]) {
        if (previous.kind == HouseScenario.broadcast &&
            (previous.origin != incident.origin || incident.origin == 'sound') &&
            incident.receivedAt.difference(previous.receivedAt).abs() <= const Duration(seconds: 30)) {
          if (!previous.evidence.contains(incident.evidence)) {
            previous.evidence = '${previous.evidence}\n\n추가 감지 근거:\n${incident.evidence}';
          }
          notifyListeners();
          return false;
        }
      }
    }
    if (simulated) incident.delivery = '테스트: 화면 알림 · LED·진동 모의 표시 (실제 명령 없음)';
    if (active == null) {
      active = incident;
    } else if (incident.priority > active!.priority) {
      _pending.add(active!);
      active = incident;
    } else {
      _pending.add(incident);
    }
    if (_pending.length > 8) _pending.removeAt(0);
    notifyListeners();
    return true;
  }

  void respond(String text) {
    active?.response = text;
    notifyListeners();
  }

  void setDelivery(String text) {
    active?.delivery = text;
    notifyListeners();
  }

  void acknowledge() {
    if (active == null) return;
    active!.acknowledged = true;
    if (active!.response.isEmpty) active!.response = '사용자가 화면을 확인했어요.';
    lastAcknowledged = active;
    _pending.sort((a, b) => b.priority.compareTo(a.priority));
    active = _pending.isEmpty ? null : _pending.removeAt(0);
    notifyListeners();
  }

  void reset() {
    active = lastAcknowledged = null;
    _pending.clear();
    _seen.clear();
    observation = '테스트 시나리오를 선택해 주세요.';
    notifyListeners();
  }
}
