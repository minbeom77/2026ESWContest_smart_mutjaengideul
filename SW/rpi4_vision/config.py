import os

MQTT_BROKER = os.getenv("MQTT_BROKER", "127.0.0.1")
MQTT_PORT = int(os.getenv("MQTT_PORT", "1883"))

SIGN_TOPIC = "safehub/vision/livingroom/translation"
SIGN_QOS = 0
