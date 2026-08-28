from mqtt_sender import MqttSender
from predictor import MockPredictor


def create_dummy_sequence():
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
    translation = predictor.predict(sequence)

    if translation is None:
        return

    sender.connect()

    try:
        sender.publish_translation(translation)
        print(f"수어 번역 결과 전송: {translation}")
    finally:
        sender.disconnect()


if __name__ == "__main__":
    main()
