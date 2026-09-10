#define main vision_photo_original_main
#include "vision_photo.cpp"
#undef main

#include <chrono>

int main(int argc, char** argv) {
    try {
        if (argc != 3) {
            throw std::runtime_error(
                "Usage: vision_stage_benchmark RAW_FIXTURE MODEL_DIR"
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

        Ort::Env env(ORT_LOGGING_LEVEL_WARNING, "vision_stage_benchmark");
        Ort::SessionOptions opts;
        opts.SetIntraOpNumThreads(2);
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

        constexpr int warmup_iterations = 3;
        constexpr int measured_iterations = 30;
        double palm_ms = 0.0;
        double hand_ms = 0.0;
        size_t kept_palms = 0;
        size_t accepted_hands = 0;

        auto run_once = [&](bool measure) {
            const auto palm_start = std::chrono::steady_clock::now();
            auto selected = palms(image, palm_model);
            const auto palm_end = std::chrono::steady_clock::now();

            size_t accepted = 0;
            const auto hand_start = std::chrono::steady_clock::now();
            for (const auto& palm : selected) {
                Hand result{};
                if (hand(image, palm, hand_model, result)) {
                    ++accepted;
                }
            }
            const auto hand_end = std::chrono::steady_clock::now();

            if (measure) {
                palm_ms += std::chrono::duration<double, std::milli>(
                    palm_end - palm_start
                ).count();
                hand_ms += std::chrono::duration<double, std::milli>(
                    hand_end - hand_start
                ).count();
                kept_palms += selected.size();
                accepted_hands += accepted;
            }
        };

        for (int i = 0; i < warmup_iterations; ++i) {
            run_once(false);
        }
        for (int i = 0; i < measured_iterations; ++i) {
            run_once(true);
        }

        const double avg_palm_ms = palm_ms / measured_iterations;
        const double avg_hand_ms = hand_ms / measured_iterations;
        const double avg_full_ms = avg_palm_ms + avg_hand_ms;
        const double full_fps = 1000.0 / avg_full_ms;
        const double hand_only_fps = 1000.0 / avg_hand_ms;

        std::cout << std::fixed << std::setprecision(3)
                  << "Threads: 2\n"
                  << "Warmup iterations: " << warmup_iterations << '\n'
                  << "Measured iterations: " << measured_iterations << '\n'
                  << "Average Palm ms: " << avg_palm_ms << '\n'
                  << "Average HandPose ms: " << avg_hand_ms << '\n'
                  << "Average full pipeline ms: " << avg_full_ms << '\n'
                  << "Full pipeline FPS: " << full_fps << '\n'
                  << "HandPose-only upper FPS: " << hand_only_fps << '\n'
                  << "Average kept palms: "
                  << double(kept_palms) / measured_iterations << '\n'
                  << "Average accepted hands: "
                  << double(accepted_hands) / measured_iterations << '\n';
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "ERROR: " << error.what() << '\n';
        return 1;
    }
}
