class AppConfig {
  static const String mqttBroker =
      String.fromEnvironment('MQTT_BROKER');

  static const int mqttPort =
      int.fromEnvironment('MQTT_PORT');

  static void validate() {
    if (mqttBroker.isEmpty) {
      throw StateError('MQTT_BROKER가 설정되지 않았습니다.');
    }

    if (mqttPort <= 0) {
      throw StateError('MQTT_PORT가 설정되지 않았습니다.');
    }
  }
}