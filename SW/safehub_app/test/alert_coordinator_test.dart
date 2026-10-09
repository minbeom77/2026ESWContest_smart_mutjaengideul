import 'package:flutter_test/flutter_test.dart';
import 'package:safehub_app/core/alert_coordinator.dart';

void main() {
  SafeHubAlert createAlert({
    required AlertKind kind,
    required int priority,
    required String name,
  }) {
    return SafeHubAlert(
      kind: kind,
      priority: priority,
      data: {
        'name': name,
      },
    );
  }

  test('현재 알림이 없으면 바로 활성화된다', () {
    final coordinator = AlertCoordinator();

    final alert = createAlert(
      kind: AlertKind.disaster,
      priority: 6,
      name: '긴급재난',
    );

    final activated = coordinator.submit(alert);

    expect(activated, true);
    expect(
      coordinator.activeAlert?.data['name'],
      '긴급재난',
    );
  });

  test('더 높은 priority가 들어오면 기존 알림을 밀어낸다', () {
    final coordinator = AlertCoordinator();

    coordinator.submit(
      createAlert(
        kind: AlertKind.disaster,
        priority: 6,
        name: '긴급재난',
      ),
    );

    coordinator.submit(
      createAlert(
        kind: AlertKind.fall,
        priority: 9,
        name: '낙상감지',
      ),
    );

    expect(
      coordinator.activeAlert?.data['name'],
      '낙상감지',
    );

    expect(coordinator.pendingAlerts.length, 1);
  });

  test('낮은 priority는 현재 알림 뒤에서 대기한다', () {
    final coordinator = AlertCoordinator();

    coordinator.submit(
      createAlert(
        kind: AlertKind.fall,
        priority: 9,
        name: '낙상감지',
      ),
    );

    final activated = coordinator.submit(
      createAlert(
        kind: AlertKind.disaster,
        priority: 6,
        name: '긴급재난',
      ),
    );

    expect(activated, false);

    expect(
      coordinator.activeAlert?.data['name'],
      '낙상감지',
    );

    expect(coordinator.pendingAlerts.length, 1);
  });

  test('현재 알림 확인 후 가장 높은 priority가 활성화된다', () {
    final coordinator = AlertCoordinator();

    coordinator.submit(
      createAlert(
        kind: AlertKind.fall,
        priority: 9,
        name: '낙상감지',
      ),
    );

    coordinator.submit(
      createAlert(
        kind: AlertKind.disaster,
        priority: 3,
        name: '안전안내',
      ),
    );

    coordinator.submit(
      createAlert(
        kind: AlertKind.disaster,
        priority: 8,
        name: '위급재난',
      ),
    );

    coordinator.submit(
      createAlert(
        kind: AlertKind.disaster,
        priority: 6,
        name: '긴급재난',
      ),
    );

    coordinator.acknowledgeCurrent();

    expect(
      coordinator.activeAlert?.data['name'],
      '위급재난',
    );

    coordinator.acknowledgeCurrent();

    expect(
      coordinator.activeAlert?.data['name'],
      '긴급재난',
    );

    coordinator.acknowledgeCurrent();

    expect(
      coordinator.activeAlert?.data['name'],
      '안전안내',
    );
  });

  test('같은 priority면 먼저 들어온 알림이 먼저 처리된다', () {
    final coordinator = AlertCoordinator();

    coordinator.submit(
      createAlert(
        kind: AlertKind.fall,
        priority: 9,
        name: '낙상감지',
      ),
    );

    coordinator.submit(
      createAlert(
        kind: AlertKind.disaster,
        priority: 6,
        name: '긴급재난 A',
      ),
    );

    coordinator.submit(
      createAlert(
        kind: AlertKind.disaster,
        priority: 6,
        name: '긴급재난 B',
      ),
    );

    coordinator.acknowledgeCurrent();

    expect(
      coordinator.activeAlert?.data['name'],
      '긴급재난 A',
    );

    coordinator.acknowledgeCurrent();

    expect(
      coordinator.activeAlert?.data['name'],
      '긴급재난 B',
    );
  });

  test('priority가 1~10 범위를 벗어나면 오류가 발생한다', () {
    final coordinator = AlertCoordinator();

    expect(
      () => coordinator.submit(
        createAlert(
          kind: AlertKind.disaster,
          priority: 11,
          name: '잘못된 이벤트',
        ),
      ),
      throwsArgumentError,
    );
  });
}
