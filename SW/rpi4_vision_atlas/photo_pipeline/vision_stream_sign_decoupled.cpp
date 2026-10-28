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
#include "classifier_frame_bridge.hpp"
#include "palm_retry_policy.hpp"
#include "tracking_roi_retry_policy.hpp"
#include "mqtt_translation_publisher.hpp"
#include "async_translation_queue.hpp"
#include <cstdio>
#include <sstream>
#include "vision_frame_hands.hpp"
#include "runtime_data.hpp"
#include "sign_runtime.hpp"
#include "active_targets.hpp"
#include "raw_tcp_streamer.hpp"
#include "recognition_light.hpp"
#include "landmark_preview.hpp"

namespace {

constexpr float kBorderMargin = 8.0f;
constexpr auto kStreamInterval =
    std::chrono::milliseconds(125);

constexpr std::array<const char*, 16>
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
        "쓰러지다",
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
    tracked.tracked_side = hand_result.handedness > 0.5 ? 1 : -1;
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

#include "tracking_roi_runner.inc"

void write_frame_json(std::ofstream& output,
                      size_t frame_index,
                      int width,
                      int height,
                      double processing_ms,
                      bool used_palm_detector,
                      bool tracking_fallback,
                      bool tracking_backoff,
                      bool second_hand_recovery,
                      const vision_runtime::TrackingRoiRetryDiagnostics& roi_retry,
                      bool any_candidate_failure,
                      bool force_palm_next_frame,
                      double capture_ms,
                      const vision_runtime::InferenceBudget& budget,
                      const PalmScanDiagnostics& palm_diagnostics,
                      const std::vector<Hand>& hands,
                      const vision_runtime::RecognitionLight* light = nullptr) {
    output << std::setprecision(12)
           << "{\"frame_index\":" << frame_index
           << ",\"image_size_wh\":[" << width << ',' << height << ']'
           << ",\"coordinate_system\":\"mirrored camera image pixels\""
           << ",\"mirror_input\":true"
           << ",\"processing_ms\":" << processing_ms
           << ",\"capture_monotonic_ms\":" << capture_ms
           << ",\"recognition_light_reference\":" << (light ? light->reference : 0)
           << ",\"recognition_light_measured\":" << (light ? light->measured : 0)
           << ",\"recognition_light_gain\":" << (light ? light->gain : 1)
           << ",\"recognition_light_gamma\":" << (light ? light->gamma : 1)
           << ",\"recognition_light_clipped_fraction\":" << (light ? light->clipped_fraction : 0)
           << ",\"hand_inferences\":" << budget.hand_calls
           << ",\"palm_inferences\":" << budget.palm_calls
           << ",\"palm_candidates\":" << palm_diagnostics.candidates
           << ",\"palm_nms_suppressed\":" << palm_diagnostics.suppressed
           << ",\"palm_nms_max_iou\":" << palm_diagnostics.max_suppressed_iou
           << ",\"palm_nms_max_keypoint_distance\":" << palm_diagnostics.max_suppressed_keypoint_distance
           << ",\"used_palm_detector\":"
           << (used_palm_detector ? "true" : "false")
           << ",\"tracking_fallback\":" << (tracking_fallback ? "true" : "false")
           << ",\"tracking_backoff\":" << (tracking_backoff ? "true" : "false")
           << ",\"second_hand_recovery\":" << (second_hand_recovery ? "true" : "false")
           << ",\"tracking_roi_retry_attempted\":" << roi_retry.attempted
           << ",\"tracking_roi_retry_accepted\":" << roi_retry.accepted
           << ",\"hand_candidate_failed\":" << (any_candidate_failure ? "true" : "false")
           << ",\"force_palm_next_frame\":" << (force_palm_next_frame ? "true" : "false")
           << ",\"palm_nms_pairs\":[";
    for (std::size_t i=0; i<palm_diagnostics.pairs.size(); ++i) {
        const auto& pair=palm_diagnostics.pairs[i];
        if (i) output << ',';
        output << "{\"discarded_anchor\":" << pair.candidate.id
               << ",\"kept_anchor\":" << pair.keeper.id
               << ",\"discarded_score\":" << pair.candidate.score
               << ",\"kept_score\":" << pair.keeper.score << ",\"iou\":" << pair.iou
               << ",\"discarded_box\":[" << pair.candidate.box[0] << ',' << pair.candidate.box[1]
               << ',' << pair.candidate.box[2] << ',' << pair.candidate.box[3] << "]}";
    }
    output << "],\"hand_candidates\":[";
    for (std::size_t i=0; i<roi_retry.candidates.size(); ++i) {
        const auto& c = roi_retry.candidates[i];
        if (i) output << ',';
        output << "{\"anchor\":" << c.anchor << ",\"confidence\":" << c.confidence
               << ",\"accepted\":" << (c.accepted?"true":"false")
               << ",\"square_retry\":" << (c.square_retry?"true":"false")
               << ",\"invalid_crop\":" << (c.invalid_crop?"true":"false")
               << ",\"angle\":" << c.angle << ",\"palm_points_outside_crop\":" << c.outside
               << ",\"crop\":[" << c.crop[0] << ',' << c.crop[1] << ',' << c.crop[2] << ',' << c.crop[3] << "]}";
    }
    output << "],\"hands\":[";

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
    std::setvbuf(stdout, nullptr, _IOLBF, 0);
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
        opts.SetIntraOpNumThreads(4);
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
        const auto active_targets = sign_engine::loadActiveTargetModel(
            environment_or_default("SIGN_ACTIVE_MODEL",
              (fs::path(runtime_data_dir).parent_path()/"active_targets_v4.bin").string().c_str()));

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

        // The synchronous Paho client is called by this worker only.
        // Inference only copies a short text into the bounded queue.
        auto mqtt_client = std::make_shared<MqttTranslationPublisher>(mqtt_host, mqtt_port, mqtt_topic);
        AsyncTranslationQueue mqtt_publisher([mqtt_client](const std::string& text) {
            return mqtt_client->publishText(text);
        });

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
        const bool show_landmarks=environment_or_default("SIGN_SHOW_LANDMARKS","0")=="1";
        vision_runtime::LandmarkPreview landmark_preview;

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
                        const auto overlay=show_landmarks ? landmark_preview.snapshot(stream_time) : nullptr;
                        camera_streamer.sendFrame(overlay ? *overlay : frame);
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
        std::vector<Palm> missing_palms;
        std::vector<Hand> latest_hands;

        cv::Mat latest_processed_frame;

        bool force_detection = true;
        vision_runtime::TwoHandTrackingBackoff tracking_backoff_policy;
        vision_runtime::LostSecondHandRecovery second_hand_recovery_policy;
        double last_palm_scan_ms = -1e9;
        const auto light_profile=environment_or_default("SIGN_LIGHT_PROFILE", "");
        vision_runtime::RecognitionLight recognition_light;
        if (!light_profile.empty()) {
            std::ifstream saved_light(light_profile);
            std::string version;double value=0;
            if (saved_light >> version >> value && version=="SAFEHUB_LIGHT_V1") {
                try { recognition_light.setReference(value); }
                catch (const std::exception& e) {
                    std::cerr << "[light] ignored invalid saved reference: " << e.what() << '\n';
                }
            }
        }

        size_t consumed_sequence = 0;
        size_t processed_frames = 0;
        size_t dropped_frames = 0;
        size_t detected_frames = 0;
        size_t palm_frames = 0;

        double processing_ms_sum = 0.0;
        double frame_age_ms_sum = 0.0;
        double frame_age_ms_max = 0.0;

        constexpr size_t kMinimumSignFrames = 10;
        constexpr size_t kMaximumSignFrames = 90;
        constexpr size_t kSignEndGapFrames = 5;

        LiveSignSession live_sign_session(
            kMinimumSignFrames,
            kMaximumSignFrames,
            kSignEndGapFrames
        );

        size_t completed_signs = 0;
        size_t queued_signs = 0;
        size_t mqtt_queue_rejections = 0;
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

                    const auto classify_begin = std::chrono::steady_clock::now();
                    std::ostringstream result_log;
                    sign_engine::ActiveTargetDiagnostics active_diag;
                    const auto sign_result = sign_engine::classifyWithActiveTargets(
                        direct_recording.frames, runtime, active_targets, active_diag);
                    result_log << "[active-target] paired=" << active_diag.paired_frames
                        << " evaluated=" << active_diag.evaluated << " accepted=" << active_diag.accepted
                        << " candidate=" << active_diag.candidate << " distance=" << active_diag.distance
                        << " runner_up=" << active_diag.runner_up << " motion_left=" << active_diag.left_motion
                        << " motion_right=" << active_diag.right_motion << " reason=" << std::quoted(active_diag.reason) << '\n';

                    result_log
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
                        << " source="
                        << sign_result.source_mode
                        << " c4_evaluated="
                        << sign_result.c4_evaluated
                        << " d_sign="
                        << sign_result.c4_gate.d_sign
                        << " d_nosign="
                        << sign_result.c4_gate.d_nosign
                        << " both=" << sign_result.recording_stats.both_count
                        << " classify_ms=" << std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-classify_begin).count()
                        << " error=" << std::quoted(sign_result.error)
                        << '\n';

                    writeSignLog(result_log.str());

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

                    const auto enqueue_begin = std::chrono::steady_clock::now();
                    const bool queued = mqtt_publisher.enqueueText(text);
                    const double enqueue_ms = std::chrono::duration<double,std::milli>(
                        std::chrono::steady_clock::now()-enqueue_begin).count();
                    std::ostringstream queue_log;
                    queue_log << "[mqtt] queued=" << (queued?1:0)
                              << " enqueue_ms=" << enqueue_ms
                              << " text=" << std::quoted(text) << '\n';
                    writeSignLog(queue_log.str());
                    if (queued) ++queued_signs; else ++mqtt_queue_rejections;

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

            const cv::Mat& raw_frame =
                *frame_ptr;

            const std::size_t previous_tracks = tracked_palms.size();
            const double capture_ms = std::chrono::duration<double, std::milli>(
                capture_time.time_since_epoch()).count();
            cv::Mat recognition_frame;
            if (!light_profile.empty()) {
                const fs::path request=light_profile+".recalibrate";
                if (fs::exists(request)) {
                    recognition_light.calibrate(capture_ms);
                    fs::remove(request);
                    std::cerr << "[light] calibrating current raw camera lighting; preview unchanged\n";
                }
                recognition_frame=recognition_light.apply(raw_frame,capture_ms);
                if (recognition_light.calibration_finished) {
                    try {
                        if (fs::exists(light_profile)) fs::copy_file(light_profile,
                            light_profile+".before-"+std::to_string(static_cast<long long>(capture_ms)));
                        const auto temporary=light_profile+".tmp";
                        { std::ofstream file(temporary);file << "SAFEHUB_LIGHT_V1\n" << std::setprecision(12)
                            << recognition_light.reference << '\n';
                          if (!file) throw std::runtime_error("Could not save light reference"); }
                        fs::rename(temporary,light_profile);
                        std::cerr << "[light] reference saved=" << recognition_light.reference
                                  << " clipped_fraction=" << recognition_light.clipped_fraction << '\n';
                    } catch (const std::exception& e) {
                        std::cerr << "[light] persistence failed; memory reference remains active: " << e.what() << '\n';
                    }
                }
            }
            const cv::Mat& frame=light_profile.empty() ? raw_frame : recognition_frame;
            vision_runtime::InferenceBudget inference_budget;
            PalmScanDiagnostics palm_diagnostics;
            const bool tracking_backoff = tracking_backoff_policy.beginFrame();
            const bool second_hand_recovery = second_hand_recovery_policy.beginFrame(capture_ms);
            if (!second_hand_recovery_policy.recovering(capture_ms)) missing_palms.clear();
            const auto inference_tracks = second_hand_recovery
                ? recovery_track_inputs(tracked_palms, missing_palms) : tracked_palms;
            const bool scan_requested =
                force_detection || tracking_backoff || second_hand_recovery ||
                capture_ms - last_palm_scan_ms >= 700;

            auto scan_palms = [&](const std::vector<Hand>& retained_hands) {
                if (!inference_budget.takePalm()) return std::vector<Palm>{};
                last_palm_scan_ms = capture_ms;
                auto inputs = palms(frame, palm_model, &palm_diagnostics);
                // Prefer candidates associated with the failed track. Do not
                // blindly prefer distant false candidates during close overlap.
                std::stable_sort(inputs.begin(), inputs.end(), [&](const Palm& a, const Palm& b) {
                    auto distance = [&](const Palm& p) {
                        double nearest = 1e9;
                        for (const auto& old : tracked_palms) {
                            const bool retained = std::any_of(retained_hands.begin(), retained_hands.end(), [&](const Hand& h) {
                                return h.palm.tracked_side == old.tracked_side;
                            });
                            if (!retained) nearest = std::min(nearest, cv::norm(p.points[0]-old.points[0]));
                        }
                        return nearest;
                    };
                    return distance(a) < distance(b);
                });
                return inputs;
            };
            vision_runtime::TrackingRoiRetryDiagnostics roi_retry;
            auto observation = observe_frame_hands(
                frame, inference_tracks, hand_model, scan_requested,
                !tracking_backoff && (!force_detection ||
                    (second_hand_recovery && !missing_palms.empty())), scan_palms,
                roi_retry, inference_budget);
            auto hands = std::move(observation.hands);
            const bool used_palm_detector = observation.used_palm_detector;
            const bool attempted_tracking = observation.attempted_tracking;
            const bool tracking_fallback = observation.tracking_fallback;
            const bool failure = observation.any_failure;
            if (used_palm_detector) ++palm_frames;
            // Match classifier side selection. Two detections labelled as the
            // same hand are not evidence that the missing opposite hand returned.
            const auto current_tracking_hands=strongest_hand_per_side(hands);
            const auto accepted_tracks=current_tracking_hands.size();

            tracking_backoff_policy.observe(
                attempted_tracking, tracking_fallback, previous_tracks, accepted_tracks
            );

            second_hand_recovery_policy.observe(previous_tracks, accepted_tracks, capture_ms);
            if (previous_tracks==2 && accepted_tracks<2)
                missing_palms=missing_track_regions(tracked_palms,hands);
            if (accepted_tracks>=2) missing_palms.clear();

            tracked_palms.clear();

            bool border = false;

            for (
                const auto& hand_result :
                current_tracking_hands
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

            // A rejected detector candidate is not a failed tracked hand.
            // Keep accepted ROIs instead of forcing full detection next frame.
            // Same-frame tracking fallback above and scheduled scans stay intact.
            force_detection = vision_runtime::forcePalmAfterInference(
                used_palm_detector, failure, hands.size(), border
            );

            latest_hands = hands;

            latest_processed_frame =
                frame.clone();
            if (show_landmarks) {
                std::vector<vision_runtime::PreviewHand> preview_hands;
                for(const auto& hand_result:hands)
                    preview_hands.push_back({hand_geometry(hand_result),hand_result.handedness>.5});
                landmark_preview.publish(raw_frame,preview_hands,capture_time);
            }

            if (!hands.empty()) {
                ++detected_frames;
            }

            auto completed_sign =
                live_sign_session.push(
                    restoreClassifierCoordinates(
                        to_vision_detections(hands),
                        width
                    ),
                    capture_ms,
                    second_hand_recovery_policy.recovering(capture_ms)
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
                tracking_fallback,
                tracking_backoff,
                second_hand_recovery,
                roi_retry,
                failure,
                force_detection,
                capture_ms,
                inference_budget,
                palm_diagnostics,
                hands,
                light_profile.empty() ? nullptr : &recognition_light
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

        // All camera input has ended. Waiting here cannot drop a future camera frame.
        mqtt_publisher.stop();
        const auto mqtt_stats = mqtt_publisher.stats();

        std::cout
            << "\n"
            << "DECOUPLED STREAM + LIVE SIGN RESULT\n"
            << "\n"
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
            << "Queued translations : "
            << queued_signs << '\n'
            << "MQTT queue rejected : " << mqtt_queue_rejections << '\n'
            << "MQTT delivered      : " << mqtt_stats.delivered << '\n'
            << "MQTT failed         : " << mqtt_stats.failed << '\n'
            << "MQTT cancelled      : " << mqtt_stats.cancelled << '\n'
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
            << "\n";

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
