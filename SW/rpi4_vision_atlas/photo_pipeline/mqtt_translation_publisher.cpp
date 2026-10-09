#include "mqtt_translation_publisher.hpp"

#include <chrono>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <utility>

MqttTranslationPublisher::MqttTranslationPublisher(
    std::string host,
    int port,
    std::string topic
)
    : address_(
          "tcp://" +
          std::move(host) +
          ":" +
          std::to_string(port)
      ),
      topic_(std::move(topic)),
      client_id_(
          "safehub_rpi4_sign_" +
          std::to_string(
              std::chrono::steady_clock::now()
                  .time_since_epoch()
                  .count()
          )
      ) {
    const int result = MQTTClient_create(
        &client_,
        address_.c_str(),
        client_id_.c_str(),
        MQTTCLIENT_PERSISTENCE_NONE,
        nullptr
    );

    if (result != MQTTCLIENT_SUCCESS) {
        client_ = nullptr;

        std::cerr
            << "[mqtt] client creation failed: "
            << result
            << '\n';
    }
}

MqttTranslationPublisher::~MqttTranslationPublisher() {
    disconnect();

    if (client_ != nullptr) {
        MQTTClient_destroy(
            &client_
        );
    }
}

bool MqttTranslationPublisher::connect() {
    if (client_ == nullptr) {
        return false;
    }

    if (MQTTClient_isConnected(client_)) {
        return true;
    }

    MQTTClient_connectOptions options =
        MQTTClient_connectOptions_initializer;

    options.keepAliveInterval = 30;
    options.cleansession = 1;
    options.connectTimeout = 3;

    const int result = MQTTClient_connect(
        client_,
        &options
    );

    if (result != MQTTCLIENT_SUCCESS) {
        std::cerr
            << "[mqtt] connection failed: "
            << address_
            << " rc="
            << result
            << '\n';

        return false;
    }

    std::cout
        << "[mqtt] connected: "
        << address_
        << '\n';

    return true;
}

void MqttTranslationPublisher::disconnect() {
    if (
        client_ != nullptr &&
        MQTTClient_isConnected(client_)
    ) {
        MQTTClient_disconnect(
            client_,
            1000
        );
    }
}

std::string MqttTranslationPublisher::escapeJson(
    const std::string& value
) {
    std::ostringstream output;

    for (const unsigned char byte : value) {
        switch (byte) {
        case '"':
            output << "\\\"";
            break;
        case '\\':
            output << "\\\\";
            break;
        case '\b':
            output << "\\b";
            break;
        case '\f':
            output << "\\f";
            break;
        case '\n':
            output << "\\n";
            break;
        case '\r':
            output << "\\r";
            break;
        case '\t':
            output << "\\t";
            break;
        default:
            if (byte < 0x20) {
                output
                    << "\\u"
                    << std::hex
                    << std::setw(4)
                    << std::setfill('0')
                    << static_cast<int>(byte)
                    << std::dec;
            } else {
                output
                    << static_cast<char>(byte);
            }
        }
    }

    return output.str();
}

bool MqttTranslationPublisher::publishText(
    const std::string& text
) {
    if (text.empty()) {
        return false;
    }

    const std::string payload =
        "{\"text\":\"" +
        escapeJson(text) +
        "\"}";

    for (int attempt = 0; attempt < 2; ++attempt) {
        if (!connect()) {
            continue;
        }

        MQTTClient_message message =
            MQTTClient_message_initializer;

        message.payload =
            const_cast<char*>(
                payload.data()
            );

        message.payloadlen =
            static_cast<int>(
                payload.size()
            );

        message.qos = 1;
        message.retained = 0;

        MQTTClient_deliveryToken token = 0;

        int result = MQTTClient_publishMessage(
            client_,
            topic_.c_str(),
            &message,
            &token
        );

        if (result == MQTTCLIENT_SUCCESS) {
            result = MQTTClient_waitForCompletion(
                client_,
                token,
                3000L
            );
        }

        if (result == MQTTCLIENT_SUCCESS) {
            std::cout
                << "[mqtt] published: "
                << payload
                << '\n';

            return true;
        }

        std::cerr
            << "[mqtt] publish failed: rc="
            << result
            << '\n';

        disconnect();
    }

    return false;
}
