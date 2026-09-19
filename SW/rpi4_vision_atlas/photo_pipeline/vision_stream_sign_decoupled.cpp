#define VISION_PHOTO_NO_MAIN
#include "vision_photo.cpp"
#undef VISION_PHOTO_NO_MAIN

#include <array>
#include <chrono>
#include <condition_variable>
#include <cstdlib>
#include <memory>
#include <mutex>
#include <thread>
#include <utility>

#include "live_sign_session.hpp"
#include "mqtt_translation_publisher.hpp"
#include "vision_frame_hands.hpp"
#include "runtime_data.hpp"
#include "sign_runtime.hpp"
#include "raw_tcp_streamer.hpp"

namespace {

constexpr int kPalmInterval = 10;
constexpr float kBorderMargin = 8.0f;
constexpr auto kStreamInterval =
    std::chrono::milliseconds(125);

constexpr std::array<const char*, 15>
    kClassNames{{
        "에어컨",
        "문잠그다",
        "꺼지다",
        "덥다",
        "춥다",
        "구조",
        "연기",
        "아프다",
        "괜찮다",
        "감사",
        "점등",
        "소등",
        "온도",
        "배고프다",
        "목마르다",
    }};

std::string class_name(
    int final_id
) {
    if (
        final_id < 0 ||
        final_id >=
            static_cast<int>(
                kClassNames.size()
            )
    ) {
        return {};
    }

    return kClassNames[
        static_cast<std::size_t>(
            final_id
        )
    ];
}

std::string environment_or_default(
    const char* name,
    const char* fallback
) {
    const char* value =
        std::getenv(name);

    return value != nullptr &&
           value[0] != '\0'
        ? value
        : fallback;
}

int mqtt_port_from_environment() {
    const char* value =
        std::getenv("MQTT_PORT");

    if (value == nullptr || value[0] == '\0') {
        return 1883;
    }

    const int port =
        std::stoi(value);

    if (port <= 0 || port > 65535) {
        throw std::runtime_error(
            "MQTT_PORT must be in 1..65535"
        );
    }

    return port;
}


sign_engine::VisionFrameDetections to_vision_detections(
    const std::vector<Hand>& hands
) {
    sign_engine::VisionFrameDetections detections;

    detections.reserve(
        hands.size()
    );

    for (const Hand& hand : hands) {
        sign_engine::VisionHandDetection detection{};

        detection.handedness_raw =
            hand.handedness;

        detection.confidence =
            hand.confidence;

        for (std::size_t i = 0; i < 21; ++i) {
            detection.landmarks.points[i].x =
                hand.xy[i].x;

            detection.landmarks.points[i].y =
                hand.xy[i].y;
        }

        detections.push_back(
            detection
        );
    }

    return detections;
}


Palm tracked_palm_from_hand(const Hand& hand_result) {
    Palm tracked{};
    tracked.id = -1;
    tracked.score = hand_result.confidence;
    tracked.points[0] = hand_result.xy[0];
    tracked.points[1] = hand_result.xy[5];
    tracked.points[2] = hand_result.xy[9];
    tracked.points[3] = hand_result.xy[13];
    tracked.points[4] = hand_result.xy[17];
    tracked.points[5] = hand_result.xy[1];

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

bool near_border(const Hand& hand_result, int width, int height) {
    // Fingertips may legitimately touch the frame edge. Re-detect only when
    // the stable palm core approaches an edge.
    constexpr std::array<int, 5> kPalmCore{0, 5, 9, 13, 17};
    for (const int index : kPalmCore) {
        const auto& point = hand_result.xy[index];
        if (point.x < kBorderMargin || point.y < kBorderMargin ||
            point.x >= width - kBorderMargin ||
            point.y >= height - kBorderMargin) {
            return true;
        }
    }
    return false;
}

std::vector<Hand> run_hands(const cv::Mat& image,
                            const std::vector<Palm>& palms_to_run,
                            Model& hand_model,
                            bool& any_failure) {
    std::vector<Hand> results;
    any_failure = false;
    for (const auto& palm : palms_to_run) {
        Hand result{};
        if (hand(image, palm, hand_model, result)) {
            results.push_back(result);
        } else {
            any_failure = true;
        }
    }
    return results;
}

void write_frame_json(std::ofstream& output,
                      size_t frame_index,
                      int width,
                      int height,
                      double processing_ms,
                      bool used_palm_detector,
                      const std::vector<Hand>& hands) {
    output << std::setprecision(12)
           << "{\"frame_index\":" << frame_index
           << ",\"image_size_wh\":[" << width << ',' << height << ']'
           << ",\"coordinate_system\":\"mirrored camera image pixels\""
           << ",\"mirror_input\":true"
           << ",\"processing_ms\":" << processing_ms
           << ",\"used_palm_detector\":"
           << (used_palm_detector ? "true" : "false")
           << ",\"hands\":[";

    for (size_t index = 0; index < hands.size(); ++index) {
        if (index != 0) {
            output << ',';
        }
        const auto& result = hands[index];
        const char* model_hand = result.handedness > 0.5 ? "RIGHT" : "LEFT";
        const char* physical_hand = result.handedness > 0.5 ? "LEFT" : "RIGHT";
        output << "{\"anchor_index\":" << result.palm.id
               << ",\"palm_score\":" << result.palm.score
               << ",\"hand_confidence\":" << result.confidence
               << ",\"handedness_raw\":" << result.handedness
               << ",\"model_hand\":\"" << model_hand << "\""
               << ",\"physical_hand\":\"" << physical_hand << "\""
               << ",\"landmarks_xy\":[";
        for (int point = 0; point < 21; ++point) {
            if (point != 0) {
                output << ',';
            }
            output << '[' << result.xy[point].x
                   << ',' << result.xy[point].y << ']';
        }
        const auto world_a = result.world_xyz[5] - result.world_xyz[0];
        const auto world_b = result.world_xyz[17] - result.world_xyz[0];
        const auto world_c = result.world_xyz[4] - result.world_xyz[0];
        const float world_chirality = world_a.cross(world_b).dot(world_c);
        output << "],\"world_chirality\":" << world_chirality << '}';
    }
    output << "]}\n";
    output.flush();
}

void write_overlay_ppm(const fs::path& path,
                       const cv::Mat& image,
                       const std::vector<Hand>& hands) {
    cv::Mat canvas = image.clone();
    const std::array<std::array<int, 2>, 21> edges{{
        {{0,1}},{{1,2}},{{2,3}},{{3,4}},{{0,5}},{{5,6}},{{6,7}},
        {{7,8}},{{5,9}},{{9,10}},{{10,11}},{{11,12}},{{9,13}},
        {{13,14}},{{14,15}},{{15,16}},{{13,17}},{{17,18}},
        {{18,19}},{{19,20}},{{0,17}}
    }};
    for (const auto& hand_result : hands) {
        for (const auto& edge : edges) {
            const cv::Point from(
                cvRound(hand_result.xy[edge[0]].x),
                cvRound(hand_result.xy[edge[0]].y)
            );
            const cv::Point to(
                cvRound(hand_result.xy[edge[1]].x),
                cvRound(hand_result.xy[edge[1]].y)
            );
            cv::line(canvas, from, to, cv::Scalar(0, 255, 0), 1);
        }
        for (int i = 0; i < 21; ++i) {
            const cv::Point point(
                cvRound(hand_result.xy[i].x),
                cvRound(hand_result.xy[i].y)
            );
            cv::circle(canvas, point, 2, cv::Scalar(0, 0, 255), -1);
        }
    }
    cv::Mat rgb;
    cv::cvtColor(canvas, rgb, cv::COLOR_BGR2RGB);
    std::ofstream ppm(path, std::ios::binary);
    ppm << "P6\n" << rgb.cols << ' ' << rgb.rows << "\n255\n";
    ppm.write(reinterpret_cast<const char*>(rgb.data),
              static_cast<std::streamsize>(rgb.total() * rgb.elemSize()));
    if (!ppm) {
        throw std::runtime_error("Could not write overlay PPM");
    }
}

}  // namespace

int main(int argc, char** argv) {
    try {
        if (argc != 7) {
            throw std::runtime_error(
                "Usage: vision_stream_sign_decoupled "
                "WIDTH HEIGHT MODEL_DIR OUTPUT_JSONL "
                "MAX_FRAMES RUNTIME_DATA_DIR"
            );
        }

        const int width = std::stoi(argv[1]);
        const int height = std::stoi(argv[2]);
        const fs::path models = argv[3];
        const fs::path output_path = argv[4];
        const size_t max_frames =
            static_cast<size_t>(std::stoul(argv[5]));
        const std::string runtime_data_dir = argv[6];

        if (width <= 0 || height <= 0 || max_frames == 0) {
            throw std::runtime_error("Invalid stream arguments");
        }

        if (fs::exists(output_path)) {
            throw std::runtime_error(
                "Output JSONL already exists"
            );
        }

        Ort::Env env(
            ORT_LOGGING_LEVEL_WARNING,
            "vision_stream_decoupled"
        );

        Ort::SessionOptions opts;
        opts.SetIntraOpNumThreads(2);
        opts.SetInterOpNumThreads(1);
        opts.SetGraphOptimizationLevel(
            GraphOptimizationLevel::ORT_ENABLE_ALL
        );

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

        const sign_engine::RuntimeData runtime =
            sign_engine::loadRuntimeData(
                runtime_data_dir
            );

        sign_engine::validateRuntimeData(runtime);

        std::cout
            << "Runtime data validated: "
            << runtime_data_dir
            << '\n';

        const std::string mqtt_host =
            environment_or_default(
                "MQTT_BROKER",
                "192.168.0.38"
            );

        const int mqtt_port =
            mqtt_port_from_environment();

        const std::string mqtt_topic =
            environment_or_default(
                "SIGN_TOPIC",
                "safehub/vision/livingroom/translation"
            );

        MqttTranslationPublisher
            mqtt_publisher(
                mqtt_host,
                mqtt_port,
                mqtt_topic
            );

        std::cout
            << "[mqtt] configured: tcp://"
            << mqtt_host
            << ':'
            << mqtt_port
            << " topic="
            << mqtt_topic
            << '\n';

        std::ofstream jsonl(output_path);

        if (!jsonl) {
            throw std::runtime_error(
                "Could not create output JSONL"
            );
        }

        RawTcpStreamer camera_streamer(5000);

        if (!camera_streamer.start()) {
            std::cerr
                << "[camera stream] disabled; "
                << "sign recognition continues\n";
        }

        // Latest-frame mailbox shared by camera producer and inference.
        std::mutex frame_mutex;
        std::condition_variable frame_cv;

        std::shared_ptr<cv::Mat> latest_frame;

        std::chrono::steady_clock::time_point
            latest_capture_time{};

        size_t latest_sequence = 0;
        size_t captured_frames = 0;

        bool capture_done = false;
        std::string capture_error;

        const auto pipeline_begin =
            std::chrono::steady_clock::now();

        // Camera/raw-input producer.
        // UI streaming occurs here and therefore does not wait for inference.
        std::thread capture_thread([&]() {
            try {
                cv::Mat frame(
                    height,
                    width,
                    CV_8UC3
                );

                size_t local_captured = 0;
                auto last_stream_time =
                    std::chrono::steady_clock::time_point{};

                while (local_captured < max_frames) {
                    const size_t bytes =
                        frame.total() *
                        frame.elemSize();

                    std::cin.read(
                        reinterpret_cast<char*>(
                            frame.data
                        ),
                        static_cast<std::streamsize>(
                            bytes
                        )
                    );

                    if (std::cin.gcount() == 0) {
                        break;
                    }

                    if (
                        static_cast<size_t>(
                            std::cin.gcount()
                        ) != bytes
                    ) {
                        throw std::runtime_error(
                            "Partial raw frame received"
                        );
                    }

                    // Preserve existing mirrored-camera contract.
                    cv::flip(frame, frame, 1);

                    // RPi5 UI path is intentionally independent
                    // from ONNX inference. Limit preview traffic
                    // so TCP buffering cannot build visible lag.
                    const auto stream_time =
                        std::chrono::steady_clock::now();

                    if (
                        stream_time - last_stream_time >=
                        kStreamInterval
                    ) {
                        camera_streamer.sendFrame(frame);
                        last_stream_time = stream_time;
                    }

                    auto published =
                        std::make_shared<cv::Mat>(
                            frame.clone()
                        );

                    const auto capture_time =
                        std::chrono::steady_clock::now();

                    {
                        std::lock_guard<std::mutex>
                            lock(frame_mutex);

                        latest_frame =
                            std::move(published);

                        latest_capture_time =
                            capture_time;

                        ++latest_sequence;
                        ++local_captured;

                        captured_frames =
                            local_captured;
                    }

                    frame_cv.notify_one();
                }
            }
            catch (const std::exception& e) {
                capture_error = e.what();
            }

            {
                std::lock_guard<std::mutex>
                    lock(frame_mutex);

                capture_done = true;
            }

            frame_cv.notify_all();
        });

        std::vector<Palm> tracked_palms;
        std::vector<Hand> latest_hands;

        cv::Mat latest_processed_frame;

        bool force_detection = true;

        size_t consumed_sequence = 0;
        size_t processed_frames = 0;
        size_t dropped_frames = 0;
        size_t detected_frames = 0;
        size_t palm_frames = 0;

        double processing_ms_sum = 0.0;
        double frame_age_ms_sum = 0.0;
        double frame_age_ms_max = 0.0;

        constexpr size_t kMinimumSignFrames = 20;
        constexpr size_t kMaximumSignFrames = 90;
        constexpr size_t kSignEndGapFrames = 5;

        LiveSignSession live_sign_session(
            kMinimumSignFrames,
            kMaximumSignFrames,
            kSignEndGapFrames
        );

        size_t completed_signs = 0;
        size_t published_signs = 0;
        size_t rejected_signs = 0;

        auto process_sign_recording =
            [&](sign_engine::VisionRecordingDetections recording) {
                ++completed_signs;

                try {
                    const auto direct_recording =
                        sign_engine::
                            buildRecordingFramesFromVision(
                                recording
                            );

                    const auto sign_result =
                        sign_engine::classifyRecording(
                            direct_recording.frames,
                            runtime
                        );

                    std::cout
                        << "[sign] completed"
                        << " input="
                        << direct_recording.input_frame_count
                        << " selected="
                        << sign_result.selected_frames
                        << " valid="
                        << (
                            sign_result.valid
                                ? "true"
                                : "false"
                        )
                        << " nosign="
                        << (
                            sign_result.is_nosign
                                ? "true"
                                : "false"
                        )
                        << " id="
                        << sign_result.final_id
                        << " stage="
                        << sign_result.stage
                        << '\n';

                    if (
                        !sign_result.valid ||
                        sign_result.is_nosign
                    ) {
                        ++rejected_signs;
                        return;
                    }

                    const std::string text =
                        class_name(
                            sign_result.final_id
                        );

                    if (text.empty()) {
                        ++rejected_signs;

                        std::cerr
                            << "[sign] unknown final_id: "
                            << sign_result.final_id
                            << '\n';

                        return;
                    }

                    if (
                        mqtt_publisher.publishText(
                            text
                        )
                    ) {
                        ++published_signs;
                    } else {
                        ++rejected_signs;
                    }
                }
                catch (const std::exception& error) {
                    ++rejected_signs;

                    std::cerr
                        << "[sign] session failed: "
                        << error.what()
                        << '\n';
                }
            };

        while (true) {
            std::shared_ptr<cv::Mat> frame_ptr;

            std::chrono::steady_clock::time_point
                capture_time{};

            size_t sequence = 0;

            {
                std::unique_lock<std::mutex>
                    lock(frame_mutex);

                frame_cv.wait(
                    lock,
                    [&]() {
                        return
                            capture_done ||
                            latest_sequence >
                                consumed_sequence;
                    }
                );

                if (
                    latest_sequence ==
                        consumed_sequence &&
                    capture_done
                ) {
                    break;
                }

                if (
                    latest_sequence ==
                    consumed_sequence
                ) {
                    continue;
                }

                sequence = latest_sequence;
                frame_ptr = latest_frame;
                capture_time =
                    latest_capture_time;
            }

            if (
                sequence >
                consumed_sequence + 1
            ) {
                dropped_frames +=
                    sequence -
                    consumed_sequence -
                    1;
            }

            consumed_sequence = sequence;

            const auto start =
                std::chrono::steady_clock::now();

            const double frame_age_ms =
                std::chrono::duration<
                    double,
                    std::milli
                >(
                    start - capture_time
                ).count();

            frame_age_ms_sum +=
                frame_age_ms;

            frame_age_ms_max =
                std::max(
                    frame_age_ms_max,
                    frame_age_ms
                );

            const cv::Mat& frame =
                *frame_ptr;

            bool used_palm_detector =
                force_detection ||
                processed_frames %
                    kPalmInterval == 0;

            std::vector<Palm> inputs =
                used_palm_detector
                    ? palms(
                          frame,
                          palm_model
                      )
                    : tracked_palms;

            if (used_palm_detector) {
                ++palm_frames;
            }

            bool failure = false;

            auto hands = run_hands(
                frame,
                inputs,
                hand_model,
                failure
            );

            // Same-frame fallback if tracking failed.
            if (
                !used_palm_detector &&
                (failure || hands.empty())
            ) {
                used_palm_detector = true;
                ++palm_frames;

                inputs = palms(
                    frame,
                    palm_model
                );

                hands = run_hands(
                    frame,
                    inputs,
                    hand_model,
                    failure
                );
            }

            tracked_palms.clear();

            bool border = false;

            for (
                const auto& hand_result :
                hands
            ) {
                tracked_palms.push_back(
                    tracked_palm_from_hand(
                        hand_result
                    )
                );

                border =
                    border ||
                    near_border(
                        hand_result,
                        width,
                        height
                    );
            }

            force_detection =
                failure ||
                hands.empty() ||
                border;

            latest_hands = hands;

            latest_processed_frame =
                frame.clone();

            if (!hands.empty()) {
                ++detected_frames;
            }

            auto completed_sign =
                live_sign_session.push(
                    to_vision_detections(
                        hands
                    )
                );

            if (completed_sign.has_value()) {
                process_sign_recording(
                    std::move(
                        *completed_sign
                    )
                );
            }

            const auto end =
                std::chrono::steady_clock::now();

            const double processing_ms =
                std::chrono::duration<
                    double,
                    std::milli
                >(
                    end - start
                ).count();

            processing_ms_sum +=
                processing_ms;

            write_frame_json(
                jsonl,
                sequence - 1,
                width,
                height,
                processing_ms,
                used_palm_detector,
                hands
            );

            ++processed_frames;
        }

        if (
            auto pending_sign =
                live_sign_session.flush();
            pending_sign.has_value()
        ) {
            process_sign_recording(
                std::move(
                    *pending_sign
                )
            );
        }

        capture_thread.join();

        if (!capture_error.empty()) {
            throw std::runtime_error(
                "Capture thread: " +
                capture_error
            );
        }

        const auto pipeline_end =
            std::chrono::steady_clock::now();

        const double pipeline_ms =
            std::chrono::duration<
                double,
                std::milli
            >(
                pipeline_end -
                pipeline_begin
            ).count();

        if (processed_frames == 0) {
            throw std::runtime_error(
                "No frames reached inference"
            );
        }

        const double average_ms =
            processing_ms_sum /
            processed_frames;

        const double average_frame_age_ms =
            frame_age_ms_sum /
            processed_frames;

        const double inference_fps =
            average_ms > 0.0
                ? 1000.0 / average_ms
                : 0.0;

        const double pipeline_fps =
            pipeline_ms > 0.0
                ? processed_frames *
                    1000.0 /
                    pipeline_ms
                : 0.0;

        const double drop_ratio =
            captured_frames > 0
                ? static_cast<double>(
                      dropped_frames
                  ) /
                  static_cast<double>(
                      captured_frames
                  )
                : 0.0;

        std::cout
            << "\n========================================\n"
            << "DECOUPLED STREAM + LIVE SIGN RESULT\n"
            << "========================================\n"
            << "Captured frames     : "
            << captured_frames << '\n'
            << "Processed frames    : "
            << processed_frames << '\n'
            << "Dropped inference   : "
            << dropped_frames << '\n'
            << "Drop ratio          : "
            << drop_ratio << '\n'
            << "Frames with hands   : "
            << detected_frames << '\n'
            << "Palm detector frames: "
            << palm_frames << '\n'
            << "Minimum sign frames : "
            << kMinimumSignFrames << '\n'
            << "Maximum sign frames : "
            << kMaximumSignFrames << '\n'
            << "Sign end gap frames : "
            << kSignEndGapFrames << '\n'
            << "Completed signs     : "
            << completed_signs << '\n'
            << "Published signs     : "
            << published_signs << '\n'
            << "Rejected signs      : "
            << rejected_signs << '\n'
            << "Average processing ms: "
            << average_ms << '\n'
            << "Inference FPS       : "
            << inference_fps << '\n'
            << "Pipeline FPS        : "
            << pipeline_fps << '\n'
            << "Average frame age ms: "
            << average_frame_age_ms << '\n'
            << "Maximum frame age ms: "
            << frame_age_ms_max << '\n'
            << "========================================\n";

        write_overlay_ppm(
            output_path.string() +
                ".last.ppm",
            latest_processed_frame,
            latest_hands
        );

        return 0;
    }
    catch (const std::exception& error) {
        std::cerr
            << "ERROR: "
            << error.what()
            << '\n';

        return 1;
    }
}
