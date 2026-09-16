#define main vision_photo_original_main
#include "vision_photo.cpp"
#undef main

#include <chrono>

Palm tracked_palm_from_hand(const Hand& hand_result) {
    Palm tracked{};
    tracked.id = -1;
    tracked.score = hand_result.confidence;

    // BlazePalm-compatible orientation: wrist -> middle-finger MCP.
    tracked.points[0] = hand_result.xy[0];
    tracked.points[1] = hand_result.xy[5];
    tracked.points[2] = hand_result.xy[9];
    tracked.points[3] = hand_result.xy[13];
    tracked.points[4] = hand_result.xy[17];
    tracked.points[5] = hand_result.xy[2];

    cv::Point2d center(0.0, 0.0);
    for (int i = 0; i < 6; ++i) {
        center += tracked.points[i];
    }
    tracked.points[6] = center * (1.0 / 6.0);

    cv::Point2d lo(1e100, 1e100);
    cv::Point2d hi(-1e100, -1e100);
    for (const auto& point : tracked.points) {
        lo.x = std::min(lo.x, point.x);
        lo.y = std::min(lo.y, point.y);
        hi.x = std::max(hi.x, point.x);
        hi.y = std::max(hi.y, point.y);
    }
    if (hi.x - lo.x < 2.0 || hi.y - lo.y < 2.0) {
        throw std::runtime_error("Tracked palm is too small");
    }
    tracked.box = {lo.x, lo.y, hi.x, hi.y};
    return tracked;
}

int main(int argc, char** argv) {
    try {
        if (argc != 3) {
            throw std::runtime_error(
                "Usage: vision_tracking_benchmark RAW_FIXTURE MODEL_DIR"
            );
        }

        const fs::path fixture = argv[1];
        const fs::path models = argv[2];
        auto wh = read<int32_t>(fixture / "image_wh_i32.bin", 2);
        auto bytes = read<uint8_t>(
            fixture / "image_bgr_u8.bin",
            size_t(wh[0]) * wh[1] * 3
        );
        cv::Mat image(wh[1], wh[0], CV_8UC3, bytes.data());

        Ort::Env env(ORT_LOGGING_LEVEL_WARNING, "vision_tracking_benchmark");
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

        auto initial_palms = palms(image, palm_model);
        if (initial_palms.empty()) {
            throw std::runtime_error("Initial palm detection failed");
        }
        Hand reference{};
        if (!hand(image, initial_palms.front(), hand_model, reference)) {
            throw std::runtime_error("Initial HandPose failed");
        }

        constexpr int palm_interval = 5;
        constexpr int warmup_iterations = 3;
        constexpr int measured_iterations = 30;
        Palm tracked = tracked_palm_from_hand(reference);
        Hand latest = reference;
        int failures = 0;
        double minimum_confidence = 1.0;
        double maximum_point_error = 0.0;
        double point_error_sum = 0.0;
        size_t point_error_count = 0;

        auto run_frame = [&](int frame_index, bool measure) {
            Palm input_palm = tracked;
            if (frame_index % palm_interval == 0) {
                auto detected = palms(image, palm_model);
                if (!detected.empty()) {
                    input_palm = detected.front();
                } else {
                    ++failures;
                }
            }

            Hand current{};
            if (!hand(image, input_palm, hand_model, current)) {
                ++failures;
                auto detected = palms(image, palm_model);
                if (detected.empty() ||
                    !hand(image, detected.front(), hand_model, current)) {
                    return;
                }
            }

            tracked = tracked_palm_from_hand(current);
            latest = current;
            if (!measure) {
                return;
            }
            minimum_confidence = std::min(
                minimum_confidence,
                current.confidence
            );
            for (int i = 0; i < 21; ++i) {
                const double error = cv::norm(
                    current.xy[i] - reference.xy[i]
                );
                maximum_point_error = std::max(maximum_point_error, error);
                point_error_sum += error;
                ++point_error_count;
            }
        };

        for (int i = 0; i < warmup_iterations; ++i) {
            run_frame(i, false);
        }

        const auto start = std::chrono::steady_clock::now();
        for (int i = 0; i < measured_iterations; ++i) {
            run_frame(i, true);
        }
        const auto end = std::chrono::steady_clock::now();

        const double total_ms =
            std::chrono::duration<double, std::milli>(end - start).count();
        const double average_ms = total_ms / measured_iterations;
        const double mean_point_error = point_error_count == 0
            ? 0.0
            : point_error_sum / point_error_count;

        std::cout << std::fixed << std::setprecision(3)
                  << "Threads: 2\n"
                  << "Palm interval: " << palm_interval << '\n'
                  << "Measured frames: " << measured_iterations << '\n'
                  << "Average scheduled ms: " << average_ms << '\n'
                  << "Scheduled FPS: " << 1000.0 / average_ms << '\n'
                  << "Tracking failures: " << failures << '\n'
                  << "Minimum hand confidence: " << minimum_confidence << '\n'
                  << "Mean landmark drift px: " << mean_point_error << '\n'
                  << "Maximum landmark drift px: " << maximum_point_error << '\n'
                  << "Final hand confidence: " << latest.confidence << '\n';
        return failures == 0 ? 0 : 2;
    } catch (const std::exception& error) {
        std::cerr << "ERROR: " << error.what() << '\n';
        return 1;
    }
}
