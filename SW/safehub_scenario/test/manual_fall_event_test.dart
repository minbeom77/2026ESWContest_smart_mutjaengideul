import 'package:flutter_test/flutter_test.dart';
import 'package:safehub_app/core/manual_fall_event.dart';
import 'package:safehub_app/services/situation_service.dart';

void main() {
  final now = DateTime(2026, 10, 28);
  Map<String, dynamic> event(String action) => {
    'device': 'safehub_manual_demo', 'message_id': 'operator-1',
    'timestamp': now.millisecondsSinceEpoch ~/ 1000, 'event': action,
  };
  test('manual control accepts fresh operator events only', () {
    expect(manualFallAction(event('fall_detected'), now: now), ManualFallAction.fall);
    expect(manualFallAction(event('normal'), now: now), ManualFallAction.normal);
    expect(manualFallAction({...event('normal'), 'device': 'esp32'}, now: now), isNull);
    expect(manualFallAction(event('off'), now: now), isNull);
    expect(manualFallAction(event('normal'), now: now.add(const Duration(seconds: 31))), isNull);
    expect(manualFallAction({...event('normal'), 'timestamp': double.nan}, now: now), isNull);
  });
  test('repeated operator fall does not queue extra help windows', () {
    final service = SituationService(settings: SituationSettings(enabled: false));
    addTearDown(service.dispose);
    var alarms = 0;
    service.onScenarioAlert = () => alarms++;
    service.observeFall('manual-1', 'operator input', origin: 'csi_demo');
    service.observeFall('manual-2', 'operator input', origin: 'csi_demo');
    expect(service.flow.active!.origin, 'csi_demo');
    expect(alarms, 1);
    service.acknowledge();
    expect(service.flow.active, isNull);
  });
}
