import 'package:flutter_test/flutter_test.dart';
import 'package:safehub_app/core/event_manager.dart';

void main() {
  test('priority가 높은 이벤트부터 반환된다', () {
    final manager = EventManager();

    manager.addEvent({
      'event': 'warning',
      'priority': 3,
    });

    manager.addEvent({
      'event': 'fall_detected',
      'priority': 9,
    });

    manager.addEvent({
      'event': 'disaster',
      'priority': 10,
    });

    expect(manager.getNextEvent()?['priority'], 10);
    expect(manager.getNextEvent()?['priority'], 9);
    expect(manager.getNextEvent()?['priority'], 3);
  });

  test('같은 priority면 먼저 들어온 이벤트가 먼저 반환된다', () {
    final manager = EventManager();

    manager.addEvent({
      'event': 'first',
      'priority': 9,
    });

    manager.addEvent({
      'event': 'second',
      'priority': 9,
    });

    expect(manager.getNextEvent()?['event'], 'first');
    expect(manager.getNextEvent()?['event'], 'second');
  });

  test('이벤트가 없으면 null을 반환한다', () {
    final manager = EventManager();

    expect(manager.getNextEvent(), null);
  });

  test('priority 범위를 벗어나면 오류가 발생한다', () {
    final manager = EventManager();

    expect(
      () => manager.addEvent({
        'event': 'invalid',
        'priority': 11,
      }),
      throwsArgumentError,
    );
  });
}