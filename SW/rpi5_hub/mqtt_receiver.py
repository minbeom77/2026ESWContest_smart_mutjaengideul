import json
import paho.mqtt.client as mqtt

from core.event_manager import EventManager


BROKER_HOST = "raspberrypi5.local"
BROKER_PORT = 1883

BEDROOM_TOPIC = "safehub/csi/bedroom/event"
BATHROOM_TOPIC = "safehub/csi/bathroom/event"


# 긴급 이벤트를 관리할 EventManager
event_manager = EventManager()


# MQTT Broker 연결 성공 시 호출
def on_connect(client, userdata, flags, reason_code, properties):
    if reason_code.is_failure:
        print(f"MQTT 연결 실패: {reason_code}")
        return

    print("MQTT Broker 연결 성공")

    # ESP32 침실 / 화장실 이벤트 구독
    client.subscribe(BEDROOM_TOPIC, qos=1)
    client.subscribe(BATHROOM_TOPIC, qos=1)


# MQTT 메시지 수신 시 호출
def on_message(client, userdata, msg):
    try:
        # MQTT payload(bytes)를 문자열로 변환 후 JSON 파싱
        event = json.loads(msg.payload.decode("utf-8"))

        # EventManager에 이벤트 등록
        event_manager.add_event(event)

        print(
            f"수신: {event['event']} "
            f"(priority={event['priority']})"
        )

    except (json.JSONDecodeError, KeyError, ValueError) as error:
        print(f"잘못된 MQTT 메시지: {error}")


# Paho MQTT Client 생성
client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)

client.on_connect = on_connect
client.on_message = on_message


# RPi5 Mosquitto Broker에 연결
client.connect(BROKER_HOST, BROKER_PORT, 60)

# MQTT 메시지를 계속 수신
client.loop_forever()