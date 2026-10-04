#define main vision_photo_original_main
#include "vision_photo.cpp"
#undef main

#include <chrono>

int main(int argc, char** argv) {
    try {
        if (argc != 3) {
            throw std::runtime_error(
                "Usage: vision_benchmark RAW_FIXTURE MODEL_DIR"
            );
        }

        const fs::path fixture = argv[1];
        const fs::path models = argv[2];

        auto wh = read<int32_t>(fixture / "image_wh_i32.bin", 2);
        if (wh[0] <= 0 || wh[1] <= 0) {
            throw std::runtime_error("Invalid raw size");
        }

        auto bytes = read<uint8_t>(
            fixture / "image_bgr_u8.bin",
            size_t(wh[0]) * wh[1] * 3
        );
        cv::Mat image(wh[1], wh[0], CV_8UC3, bytes.data());

        Ort::Env env(ORT_LOGGING_LEVEL_WARNING, "vision_benchmark");
        Ort::SessionOptions opts;
        opts.SetIntraOpNumThreads(1);
        opts.SetInterOpNumThreads(1);
        opts.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);

        Model palm_model(
            env,
            models / "palm_detection_mediapipe_2023feb.onnx",
            opts,
            192
        );
        Model hand_model(
            env,
            models / "handpose_estimation_mediapipe_2023feb.onnx",
            opts,
            224
        );

        size_t total_palms = 0;
        size_t total_hands = 0;

        auto run_once = [&]() {
            auto selected = palms(image, palm_model);
            size_t accepted = 0;
            for (const auto& palm : selected) {
                Hand result{};
                if (hand(image, palm, hand_model, result)) {
                    ++accepted;
                }
            }
            total_palms += selected.size();
            total_hands += accepted;
        };

        constexpr int warmup_iterations = 3;
        constexpr int measured_iterations = 30;

        for (int i = 0; i < warmup_iterations; ++i) {
            run_once();
        }

        total_palms = 0;
        total_hands = 0;
        const auto start = std::chrono::steady_clock::now();
        for (int i = 0; i < measured_iterations; ++i) {
            run_once();
        }
        const auto end = std::chrono::steady_clock::now();

        const double total_ms =
            std::chrono::duration<double, std::milli>(end - start).count();
        const double average_ms = total_ms / measured_iterations;
        const double fps = 1000.0 / average_ms;

        std::cout << std::fixed << std::setprecision(3)
                  << "Warmup iterations: " << warmup_iterations << '\n'
                  << "Measured iterations: " << measured_iterations << '\n'
                  << "Total measured ms: " << total_ms << '\n'
                  << "Average pipeline ms: " << average_ms << '\n'
                  << "Pipeline FPS: " << fps << '\n'
                  << "Average kept palms: "
                  << double(total_palms) / measured_iterations << '\n'
                  << "Average accepted hands: "
                  << double(total_hands) / measured_iterations << '\n';
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "ERROR: " << error.what() << '\n';
        return 1;
    }
}
