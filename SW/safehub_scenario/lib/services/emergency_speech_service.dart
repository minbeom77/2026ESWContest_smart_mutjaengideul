import 'dart:async';
import 'dart:typed_data';

import '../core/house_scenario.dart';

enum EmergencyVoice { broadcast, sound, disaster, assistance, fall }

/// Uses bundled Korean speech so an alert never waits for network synthesis.
class EmergencySpeechService {
  EmergencySpeechService({
    required this.load,
    required this.play,
    required this.stop,
    required this.onStatus,
    this.onError,
    this.timeout = const Duration(seconds: 5),
  });

  final Future<Uint8List> Function(EmergencyVoice voice) load;
  final Future<void> Function(Uint8List bytes) play;
  final Future<void> Function() stop;
  final void Function(String status) onStatus;
  final void Function(Object error)? onError;
  final Duration timeout;
  final Map<EmergencyVoice, Uint8List> _cache = {};
  final Set<String> _announced = {};
  String? _activeKey;
  int _generation = 0;
  bool _disposed = false;
  Future<void> _audioTail = Future<void>.value();

  static EmergencyVoice voiceFor(HouseIncident incident) =>
      switch (incident.kind) {
        HouseScenario.broadcast => incident.origin == 'sound'
            ? EmergencyVoice.sound
            : EmergencyVoice.broadcast,
        HouseScenario.disaster => EmergencyVoice.disaster,
        HouseScenario.assistance => const {'csi', 'csi_demo'}.contains(incident.origin) ? EmergencyVoice.fall : EmergencyVoice.assistance,
      };

  static String textFor(EmergencyVoice voice) => switch (voice) {
        EmergencyVoice.broadcast => '위험 관련 안내방송이 감지되었습니다. 화면과 방송 안내를 확인해 주세요.',
        EmergencyVoice.sound => '경보음이 감지되었습니다. 주변 상황과 화면 안내를 확인해 주세요.',
        EmergencyVoice.disaster =>
          '새로운 재난 알림이 도착했습니다. 화면에서 지역과 안내 내용을 확인해 주세요.',
        EmergencyVoice.assistance =>
          '도움이 필요한 상황이 감지되었습니다. 주변 사람의 상태와 화면을 확인해 주세요.',
        EmergencyVoice.fall => '낙상으로 의심되는 움직임이 감지되었습니다. 주변 사람의 상태를 확인해 주세요.',
      };

  static String assetFor(EmergencyVoice voice) =>
      'assets/audio/emergency_${voice.name}.mp3';

  // A repeated test has the same incident ID but a new start time.
  static String _key(HouseIncident incident) =>
      '${incident.kind.name}:${incident.origin}:${incident.id}:${incident.receivedAt.microsecondsSinceEpoch}';

  void update(HouseIncident? incident, {required bool enabled}) {
    if (_disposed) return;
    final key = enabled && incident != null ? _key(incident) : null;
    if (key == _activeKey) return;
    final wasActive = _activeKey != null;
    _activeKey = key;
    final generation = ++_generation;
    if (key == null) {
      if (wasActive) unawaited(_stop(generation));
      return;
    }
    if (!_announced.add(key)) {
      if (wasActive) unawaited(_stop(generation));
      return;
    }
    if (_announced.length > 128) _announced.remove(_announced.first);
    unawaited(_announce(voiceFor(incident!), generation));
  }

  void repeat(HouseIncident incident) {
    if (_disposed || _activeKey != _key(incident)) return;
    unawaited(_announce(voiceFor(incident), ++_generation));
  }

  bool _current(int generation) => !_disposed && generation == _generation;

  Future<void> _serialize(Future<void> Function() operation) {
    final next = _audioTail.then((_) => operation());
    _audioTail = next.catchError((Object _) {});
    return next;
  }

  Future<void> _stop(int generation) async {
    try {
      await _serialize(() async {
        if (_current(generation)) await stop().timeout(timeout);
      });
    } catch (error) {
      onError?.call(error);
      if (_current(generation)) onStatus('위험 음성 중단 실패 · 화면 안내 확인');
    }
  }

  Future<void> _announce(EmergencyVoice voice, int generation) async {
    onStatus('위험 음성 안내 준비 중');
    try {
      // Stop ordinary sign speech before loading the alert; do not block UI/MQTT.
      await _serialize(() async {
        if (_current(generation)) await stop().timeout(timeout);
      });
      if (!_current(generation)) return;
      final bytes = _cache[voice] ?? await load(voice).timeout(timeout);
      if (bytes.isEmpty) throw StateError('Empty emergency audio');
      _cache[voice] = bytes;
      if (!_current(generation)) return;
      await _serialize(() async {
        if (!_current(generation)) return;
        await play(bytes).timeout(timeout);
        if (_current(generation)) onStatus('위험 음성 재생 요청 완료');
      });
    } catch (error) {
      onError?.call(error);
      if (_current(generation)) onStatus('위험 음성 재생 실패 · 화면·LED·진동 안내 확인');
    }
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _cache.clear();
  }
}
