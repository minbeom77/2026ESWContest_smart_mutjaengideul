from queue import PriorityQueue, Empty


class EventManager:
    def __init__(self):
        # 우선순위가 높은 이벤트부터 처리하기 위한 큐
        self.event_queue = PriorityQueue()

        # 같은 priority를 가진 이벤트가 들어왔을 때
        # 먼저 들어온 이벤트부터 처리하기 위한 순번
        self.sequence = 0

    def add_event(self, event):
        # 이벤트에서 priority 값 가져오기
        priority = event.get("priority")

        # priority는 정수만 허용
        if not isinstance(priority, int) or isinstance(priority, bool):
            raise ValueError("priority는 정수여야 합니다.")

        # 통신 규격에 따라 priority는 1~10만 허용
        if priority < 1 or priority > 10:
            raise ValueError("priority는 1~10 범위여야 합니다.")

        # PriorityQueue는 숫자가 작은 값을 먼저 꺼내므로
        # priority에 음수를 붙여 높은 priority가 먼저 처리되도록 함
        #
        # 예:
        # priority 10 -> -10
        # priority 9  -> -9
        # priority 3  -> -3
        #
        # 처리 순서: -10 -> -9 -> -3
        self.event_queue.put(
            (-priority, self.sequence, event)
        )
        self.sequence += 1

    def get_next_event(self):
        try:
            # 큐에서 가장 우선순위가 높은 이벤트 가져오기
            _, _, event = self.event_queue.get_nowait()

            return event

        except Empty:
            return None