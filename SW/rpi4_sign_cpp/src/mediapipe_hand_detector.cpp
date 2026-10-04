#include "mediapipe_hand_detector.hpp"

#include <cstdint>
#include <fstream>
#include <iterator>
#include <map>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>

#include "mediapipe/framework/calculator_framework.h"
#include "mediapipe/framework/formats/classification.pb.h"
#include "mediapipe/framework/formats/image_frame.h"
#include "mediapipe/framework/formats/image_frame_opencv.h"
#include "mediapipe/framework/formats/landmark.pb.h"


namespace sign_engine {


// ============================================================
// MediaPipeHandDetector::Impl
// ============================================================

class MediaPipeHandDetector::Impl {
public:
    explicit Impl(
        const std::string& graph_path
    ) {
        // ----------------------------------------------------
        // Load frozen canonical CalculatorGraphConfig.
        // ----------------------------------------------------

        std::ifstream file(
            graph_path,
            std::ios::binary
        );

        if (!file) {
            throw std::runtime_error(
                "Failed to open MediaPipe graph: " +
                graph_path
            );
        }

        const std::string graph_data(
            (std::istreambuf_iterator<char>(file)),
            std::istreambuf_iterator<char>()
        );

        mediapipe::CalculatorGraphConfig config;

        if (!config.ParseFromString(graph_data)) {
            throw std::runtime_error(
                "Failed to parse MediaPipe graph: " +
                graph_path
            );
        }


        // ----------------------------------------------------
        // Initialize graph.
        // ----------------------------------------------------

        absl::Status status =
            graph_.Initialize(config);

        if (!status.ok()) {
            throw std::runtime_error(
                "MediaPipe graph Initialize failed: " +
                std::string(status.message())
            );
        }


        // ----------------------------------------------------
        // Observe frozen Python output streams.
        //
        // We use observers rather than blocking pollers here
        // because a frame with no detected hand may produce
        // no landmark/handedness packet.
        // ----------------------------------------------------

        status =
            graph_.ObserveOutputStream(
                "multi_hand_landmarks",
                [this](
                    const mediapipe::Packet& packet
                ) -> absl::Status {

                    std::lock_guard<std::mutex> lock(
                        output_mutex_
                    );

                    latest_landmarks_packet_ =
                        packet;

                    have_landmarks_packet_ =
                        true;

                    return absl::OkStatus();
                }
            );

        if (!status.ok()) {
            throw std::runtime_error(
                "Failed to observe "
                "multi_hand_landmarks: " +
                std::string(status.message())
            );
        }


        status =
            graph_.ObserveOutputStream(
                "multi_handedness",
                [this](
                    const mediapipe::Packet& packet
                ) -> absl::Status {

                    std::lock_guard<std::mutex> lock(
                        output_mutex_
                    );

                    latest_handedness_packet_ =
                        packet;

                    have_handedness_packet_ =
                        true;

                    return absl::OkStatus();
                }
            );

        if (!status.ok()) {
            throw std::runtime_error(
                "Failed to observe "
                "multi_handedness: " +
                std::string(status.message())
            );
        }


        // ----------------------------------------------------
        // Frozen Python Hands constructor parity:
        //
        // max_num_hands=2
        // model_complexity=1
        // static_image_mode=False
        //
        // static_image_mode=False corresponds to:
        // use_prev_landmarks=true
        //
        // Detection / tracking threshold 0.5 are already
        // frozen inside the exported canonical graph.
        // ----------------------------------------------------

        std::map<
            std::string,
            mediapipe::Packet
        > side_packets;

        side_packets["num_hands"] =
            mediapipe::MakePacket<int>(2);

        side_packets["model_complexity"] =
            mediapipe::MakePacket<int>(1);

        side_packets["use_prev_landmarks"] =
            mediapipe::MakePacket<bool>(true);


        status =
            graph_.StartRun(side_packets);

        if (!status.ok()) {
            throw std::runtime_error(
                "MediaPipe graph StartRun failed: " +
                std::string(status.message())
            );
        }

        graph_started_ =
            true;
    }


    ~Impl() {
        if (!graph_started_) {
            return;
        }

        // Destructors must not throw.
        graph_.CloseInputStream(
            "image"
        );

        graph_.WaitUntilDone();
    }


    std::vector<NormalizedHandDetection>
    processBgrFrame(
        const std::uint8_t* bgr_data,
        std::int32_t width,
        std::int32_t height,
        std::int32_t stride_bytes
    ) {
        // ----------------------------------------------------
        // Validate input.
        // ----------------------------------------------------

        if (bgr_data == nullptr) {
            throw std::invalid_argument(
                "bgr_data is null"
            );
        }

        if (width <= 0 ||
            height <= 0) {

            throw std::invalid_argument(
                "Invalid frame width/height"
            );
        }

        const std::int32_t minimum_stride =
            width * 3;

        if (stride_bytes <
            minimum_stride) {

            throw std::invalid_argument(
                "Invalid BGR frame stride"
            );
        }


        // ----------------------------------------------------
        // Wrap input BGR memory.
        //
        // Clone because caller owns bgr_data and MediaPipe
        // processing must not depend on its lifetime.
        // ----------------------------------------------------

        cv::Mat input_bgr(
            height,
            width,
            CV_8UC3,
            const_cast<std::uint8_t*>(
                bgr_data
            ),
            static_cast<std::size_t>(
                stride_bytes
            )
        );

        cv::Mat mirrored_bgr;

        // Frozen Python:
        //
        // frame = cv2.flip(frame, 1)
        cv::flip(
            input_bgr,
            mirrored_bgr,
            1
        );


        // ----------------------------------------------------
        // Frozen Python:
        //
        // rgb = cv2.cvtColor(
        //     frame,
        //     cv2.COLOR_BGR2RGB
        // )
        // ----------------------------------------------------

        cv::Mat rgb;

        cv::cvtColor(
            mirrored_bgr,
            rgb,
            cv::COLOR_BGR2RGB
        );


        // ----------------------------------------------------
        // Clear per-frame output state.
        // ----------------------------------------------------

        {
            std::lock_guard<std::mutex> lock(
                output_mutex_
            );

            have_landmarks_packet_ =
                false;

            have_handedness_packet_ =
                false;

            latest_landmarks_packet_ =
                mediapipe::Packet();

            latest_handedness_packet_ =
                mediapipe::Packet();
        }


        // ----------------------------------------------------
        // Convert cv::Mat RGB -> MediaPipe ImageFrame.
        // ----------------------------------------------------

        auto input_frame =
            std::make_unique<
                mediapipe::ImageFrame
            >(
                mediapipe::ImageFormat::SRGB,
                width,
                height,
                mediapipe::ImageFrame::
                    kDefaultAlignmentBoundary
            );

        rgb.copyTo(
            mediapipe::formats::MatView(
                input_frame.get()
            )
        );


        // ----------------------------------------------------
        // Monotonic MediaPipe timestamp.
        //
        // Only ordering matters for this detector wrapper.
        // ----------------------------------------------------

        const mediapipe::Timestamp timestamp(
            next_timestamp_
        );

        ++next_timestamp_;


        // ----------------------------------------------------
        // Send frame to persistent graph.
        //
        // The graph is intentionally NOT restarted per frame.
        // This preserves use_prev_landmarks=true tracking
        // semantics from frozen Python.
        // ----------------------------------------------------

        absl::Status status =
            graph_.AddPacketToInputStream(
                "image",
                mediapipe::Adopt(
                    input_frame.release()
                ).At(timestamp)
            );

        if (!status.ok()) {
            throw std::runtime_error(
                "AddPacketToInputStream failed: " +
                std::string(status.message())
            );
        }


        // ----------------------------------------------------
        // Wait until this input has been processed.
        // ----------------------------------------------------

        status =
            graph_.WaitUntilIdle();

        if (!status.ok()) {
            throw std::runtime_error(
                "MediaPipe WaitUntilIdle failed: " +
                std::string(status.message())
            );
        }


        // ----------------------------------------------------
        // Copy observer results for this frame.
        // ----------------------------------------------------

        mediapipe::Packet landmarks_packet;
        mediapipe::Packet handedness_packet;

        bool have_landmarks =
            false;

        bool have_handedness =
            false;

        {
            std::lock_guard<std::mutex> lock(
                output_mutex_
            );

            have_landmarks =
                have_landmarks_packet_;

            have_handedness =
                have_handedness_packet_;

            if (have_landmarks) {
                landmarks_packet =
                    latest_landmarks_packet_;
            }

            if (have_handedness) {
                handedness_packet =
                    latest_handedness_packet_;
            }
        }


        // ----------------------------------------------------
        // Frozen Python behavior:
        //
        // No hand:
        // multi_hand_landmarks is None
        //
        // => return zero detections.
        // ----------------------------------------------------

        if (!have_landmarks &&
            !have_handedness) {

            return {};
        }


        if (have_landmarks !=
            have_handedness) {

            throw std::runtime_error(
                "MediaPipe landmark/handedness "
                "packet mismatch"
            );
        }


        // ----------------------------------------------------
        // Read graph output vectors.
        // ----------------------------------------------------

        const auto& multi_landmarks =
            landmarks_packet.Get<
                std::vector<
                    mediapipe::
                        NormalizedLandmarkList
                >
            >();

        const auto& multi_handedness =
            handedness_packet.Get<
                std::vector<
                    mediapipe::
                        ClassificationList
                >
            >();


        if (multi_landmarks.size() !=
            multi_handedness.size()) {

            throw std::runtime_error(
                "MediaPipe landmark/handedness "
                "vector size mismatch"
            );
        }


        // ----------------------------------------------------
        // Convert MediaPipe output into our neutral
        // NormalizedHandDetection representation.
        //
        // IMPORTANT:
        //
        // No pixel-coordinate transform here.
        // No label swapping here.
        // No additional confidence threshold here.
        //
        // hand_input.cpp owns the frozen Python
        // extract_hands() semantics.
        // ----------------------------------------------------

        std::vector<
            NormalizedHandDetection
        > detections;

        detections.reserve(
            multi_landmarks.size()
        );


        for (std::size_t i = 0;
             i < multi_landmarks.size();
             ++i) {

            const auto& landmarks =
                multi_landmarks[i];

            const auto& handedness =
                multi_handedness[i];


            // Frozen MediaPipe Hands should return 21.
            // Invalid output is ignored rather than creating
            // a malformed hand.
            if (landmarks.landmark_size() !=
                static_cast<int>(
                    HAND_LANDMARK_COUNT
                )) {

                continue;
            }


            if (handedness
                    .classification_size() <= 0) {

                continue;
            }


            const auto& classification =
                handedness.classification(0);


            NormalizedHandDetection detection;

            detection.label =
                classification.label();

            detection.confidence =
                static_cast<double>(
                    classification.score()
                );


            for (std::size_t landmark_index = 0;
                 landmark_index <
                     HAND_LANDMARK_COUNT;
                 ++landmark_index) {

                const auto& landmark =
                    landmarks.landmark(
                        static_cast<int>(
                            landmark_index
                        )
                    );


                detection
                    .landmarks[
                        landmark_index
                    ]
                    .x =
                    static_cast<float>(
                        landmark.x()
                    );


                detection
                    .landmarks[
                        landmark_index
                    ]
                    .y =
                    static_cast<float>(
                        landmark.y()
                    );
            }


            detections.push_back(
                std::move(detection)
            );
        }


        return detections;
    }


private:
    mediapipe::CalculatorGraph graph_;

    bool graph_started_ =
        false;


    // Monotonic timestamps for video-mode graph.
    std::int64_t next_timestamp_ =
        0;


    // Observer callbacks may run on MediaPipe worker threads.
    std::mutex output_mutex_;

    bool have_landmarks_packet_ =
        false;

    bool have_handedness_packet_ =
        false;

    mediapipe::Packet
        latest_landmarks_packet_;

    mediapipe::Packet
        latest_handedness_packet_;
};


// ============================================================
// Public wrapper
// ============================================================

MediaPipeHandDetector::
MediaPipeHandDetector(
    const std::string& graph_path
)
    : impl_(
          std::make_unique<Impl>(
              graph_path
          )
      ) {
}


MediaPipeHandDetector::
MediaPipeHandDetector(
    MediaPipeHandDetector&&
) noexcept = default;


MediaPipeHandDetector&
MediaPipeHandDetector::operator=(
    MediaPipeHandDetector&&
) noexcept = default;


MediaPipeHandDetector::
~MediaPipeHandDetector() = default;


std::vector<NormalizedHandDetection>
MediaPipeHandDetector::processBgrFrame(
    const std::uint8_t* bgr_data,
    std::int32_t width,
    std::int32_t height,
    std::int32_t stride_bytes
) {
    return impl_->processBgrFrame(
        bgr_data,
        width,
        height,
        stride_bytes
    );
}


}  // namespace sign_engine