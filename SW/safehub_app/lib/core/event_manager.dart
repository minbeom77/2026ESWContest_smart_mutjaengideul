class EventManager {
  final List<_QueuedEvent> _eventQueue = [];
  int _sequence = 0;

  void addEvent(Map<String, dynamic> event) {
    final priority = event['priority'];

    // priority는 정수만 허용
    if (priority is! int) {
      throw ArgumentError('priority는 정수여야 합니다.');
    }

    // priority는 1~10만 허용
    if (priority < 1 || priority > 10) {
      throw ArgumentError('priority는 1~10 범위여야 합니다.');
    }

    _eventQueue.add(
      _QueuedEvent(
        priority: priority,
        sequence: _sequence,
        event: event,
      ),
    );

    _sequence++;
  }

  Map<String, dynamic>? getNextEvent() {
    if (_eventQueue.isEmpty) {
      return null;
    }

    // priority가 가장 높은 이벤트 탐색
    // 같은 priority면 먼저 들어온 이벤트 유지
    var bestIndex = 0;

    for (var i = 1; i < _eventQueue.length; i++) {
      if (_eventQueue[i].priority > _eventQueue[bestIndex].priority) {
        bestIndex = i;
      }
    }

    return _eventQueue.removeAt(bestIndex).event;
  }
}

class _QueuedEvent {
  final int priority;
  final int sequence;
  final Map<String, dynamic> event;

  _QueuedEvent({
    required this.priority,
    required this.sequence,
    required this.event,
  });
}