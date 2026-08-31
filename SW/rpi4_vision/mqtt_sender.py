import json
import time

import paho.mqtt.client as mqtt

try:
    from .config import MQTT_BROKER, MQTT_PORT, SIGN_QOS, SIGN_TOPIC
except ImportError:
    from config import MQTT_BROKER, MQTT_PORT, SIGN_QOS, SIGN_TOPIC


def build_translation_payload(text: str) -> str | None:
    clean_text = text.strip()

    if not clean_text:
        return None

    return json.dumps(
        {"text": clean_text},
        ensure_ascii=False,
    )


class MqttSender:
    def __init__(
        self,
        broker: str = MQTT_BROKER,
        port: int = MQTT_PORT,
    ):
        self._broker = broker
        self._port = port
        self._client = mqtt.Client(
            callback_api_version=mqtt.CallbackAPIVersion.VERSION2,
        )

    def connect(self) -> None:
        self._client.connect(
            self._broker,
            self._port,
            keepalive=60,
        )

        self._client.loop_start()

        deadline = time.time() + 3

        while not self._client.is_connected():
            if time.time() >= deadline:
                raise TimeoutError("MQTT 브로커 연결 시간 초과")

            time.sleep(0.05)

    def publish_translation(self, text: str) -> None:
        payload = build_translation_payload(text)

        if payload is None:
            return

        result = self._client.publish(
            SIGN_TOPIC,
            payload,
            qos=SIGN_QOS,
        )

        result.wait_for_publish(timeout=3)

        if not result.is_published():
            raise TimeoutError("MQTT 메시지 전송 시간 초과")

    def disconnect(self) -> None:
        self._client.disconnect()
        self._client.loop_stop()

def publish_translation_once(text: str) -> None:
    """번역 결과 하나를 MQTT로 전송한다."""
    sender = MqttSender()
    sender.connect()

    try:
        sender.publish_translation(text)
    finally:
        sender.disconnect()
