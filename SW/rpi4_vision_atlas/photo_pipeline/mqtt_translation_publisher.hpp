#pragma once

#include <MQTTClient.h>

#include <string>

class MqttTranslationPublisher {
public:
    MqttTranslationPublisher(
        std::string host,
        int port,
        std::string topic
    );

    ~MqttTranslationPublisher();

    MqttTranslationPublisher(
        const MqttTranslationPublisher&
    ) = delete;

    MqttTranslationPublisher& operator=(
        const MqttTranslationPublisher&
    ) = delete;

    bool publishText(
        const std::string& text
    );

private:
    bool connect();
    void disconnect();

    static std::string escapeJson(
        const std::string& value
    );

    std::string address_;
    std::string topic_;
    std::string client_id_;

    MQTTClient client_ = nullptr;
};
