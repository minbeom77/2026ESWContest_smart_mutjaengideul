import json
import time
import uuid

from paho.mqtt import publish


BROKER_HOST = "raspberrypi5.local"
BROKER_PORT = 1883
TOPIC = "safehub/csi/bedroom/event"


# ESP32 침실에서 낙상을 감지했다고 가정
event = {
    "message_id": str(uuid.uuid4()),
    "device": "esp32_bedroom",
    "event": "fall_detected",
    "confidence": 0.92,
    "priority": 9,
    "timestamp": int(time.time())
}


# MQTT QoS 1으로 테스트 이벤트 전송
publish.single(
    TOPIC,
    payload=json.dumps(event),
    hostname=BROKER_HOST,
    port=BROKER_PORT,
    qos=1
)

print("테스트 MQTT 메시지 전송 완료")