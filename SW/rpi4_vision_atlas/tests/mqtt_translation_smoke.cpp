#include "mqtt_translation_publisher.hpp"

#include <exception>
#include <iostream>
#include <string>

int main(
    int argc,
    char** argv
) {
    if (argc != 4) {
        std::cerr
            << "Usage: mqtt_translation_smoke "
            << "HOST PORT TEXT\n";

        return 2;
    }

    try {
        const std::string host = argv[1];

        const int port =
            std::stoi(
                argv[2]
            );

        const std::string text = argv[3];

        MqttTranslationPublisher publisher(
            host,
            port,
            "safehub/vision/livingroom/translation"
        );

        if (!publisher.publishText(text)) {
            std::cerr
                << "MQTT_SMOKE_FAIL\n";

            return 1;
        }

        std::cout
            << "MQTT_SMOKE_PASS\n";

        return 0;
    }
    catch (const std::exception& error) {
        std::cerr
            << "MQTT_SMOKE_ERROR: "
            << error.what()
            << '\n';

        return 1;
    }
}
