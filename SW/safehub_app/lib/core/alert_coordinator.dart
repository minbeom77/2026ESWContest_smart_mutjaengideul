enum AlertKind {
  fall,
  disaster,
}

class SafeHubAlert {
  final AlertKind kind;
  final int priority;
  final Map<String, dynamic> data;

  const SafeHubAlert({
    required this.kind,
    required this.priority,
    required this.data,
  });
}

class AlertCoordinator {
  SafeHubAlert? _activeAlert;
  final List<SafeHubAlert> _pendingAlerts = [];

  SafeHubAlert? get activeAlert => _activeAlert;

  List<SafeHubAlert> get pendingAlerts => List.unmodifiable(_pendingAlerts);

  bool get hasActiveAlert => _activeAlert != null;

  /// 새 알림을 등록한다.
  ///
  /// 반환값:
  /// true  -> 새 알림이 즉시 현재 알림이 됨
  /// false -> 대기열에 들어감
  bool submit(SafeHubAlert alert) {
    _validatePriority(alert.priority);

    if (_activeAlert == null) {
      _activeAlert = alert;
      return true;
    }

    if (alert.priority > _activeAlert!.priority) {
      _pendingAlerts.add(_activeAlert!);
      _activeAlert = alert;
      return true;
    }

    _pendingAlerts.add(alert);
    return false;
  }

  /// 현재 알림을 확인 처리하고,
  /// 대기 중인 알림 중 priority가 가장 높은 것을 활성화한다.
  SafeHubAlert? acknowledgeCurrent() {
    _activeAlert = _takeNextAlert();
    return _activeAlert;
  }

  void clear() {
    _activeAlert = null;
    _pendingAlerts.clear();
  }

  SafeHubAlert? _takeNextAlert() {
    if (_pendingAlerts.isEmpty) {
      return null;
    }

    var highestIndex = 0;

    for (var i = 1; i < _pendingAlerts.length; i++) {
      if (_pendingAlerts[i].priority > _pendingAlerts[highestIndex].priority) {
        highestIndex = i;
      }
    }

    return _pendingAlerts.removeAt(highestIndex);
  }

  void _validatePriority(int priority) {
    if (priority < 1 || priority > 10) {
      throw ArgumentError.value(
        priority,
        'priority',
        'priority는 1~10 사이여야 합니다.',
      );
    }
  }
}
