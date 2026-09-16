from core.event_manager import EventManager


# EventManager 객체 생성
manager = EventManager()


# 테스트용 이벤트
# 일부러 priority 순서와 상관없이 등록함
events = [
    {
        "event": "normal_warning",
        "priority": 3
    },
    {
        "event": "fall_detected",
        "priority": 9
    },
    {
        "event": "disaster_alert",
        "priority": 10
    }
]


# 이벤트를 EventManager에 등록
for event in events:
    manager.add_event(event)


# 우선순위가 높은 이벤트부터 하나씩 꺼내서 출력
while True:
    event = manager.get_next_event()

    # 더 이상 처리할 이벤트가 없으면 반복 종료
    if event is None:
        break

    print(event["priority"], event["event"])