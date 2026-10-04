from main import process_sequence
from mqtt_sender import MqttSender
from predictor import MockPredictor


def create_dummy_sequence():
    """실제 MediaPipe 연결 전 파이프라인 검증용 더미 관절 데이터."""
    return [
        [
            [0.1, 0.2, 0.3]
            for _ in range(21)
        ]
    ]


def main():
    predictor = MockPredictor()
    sender = MqttSender()

    sequence = create_dummy_sequence()
    translation = process_sequence(sequence, predictor, sender)

    if translation is not None:
        print(f"수어 번역 결과 전송: {translation}")


if __name__ == "__main__":
    main()
