#include <cstdint>
#include <cstdlib>
#include <exception>
#include <iostream>
#include <string>
#include <vector>

#include <opencv2/core.hpp>
#include <opencv2/videoio.hpp>

#include "hand_input.hpp"
#include "mediapipe_hand_detector.hpp"
#include "runtime_data.hpp"
#include "sign_runtime.hpp"


int main(
    int argc,
    char* argv[]
) {
    // --------------------------------------------------------
    // Usage
    // --------------------------------------------------------

    if (argc != 2) {
        std::cerr
            << "Usage:\n"
            << "  video_pipeline_smoke <video_path>\n";

        return EXIT_FAILURE;
    }


    const std::string video_path =
        argv[1];


    // --------------------------------------------------------
    // Temporary WSL validation paths.
    //
    // These are NOT final Raspberry Pi production paths.
    // --------------------------------------------------------

    const std::string graph_path =
        "/mnt/c/2026ESWContest_smart_mutjaengideul/"
        "SW/rpi4_sign_cpp/mediapipe_assets/"
        "hands_0_10_21_canonical.binarypb";


    const std::string runtime_dir =
        "/mnt/c/2026ESWContest_smart_mutjaengideul/"
        "SW/rpi4_sign_cpp/runtime_data";


    try {
        // ----------------------------------------------------
        // Load classifier runtime data.
        // ----------------------------------------------------

        const sign_engine::RuntimeData runtime =
            sign_engine::loadRuntimeData(
                runtime_dir
            );

        sign_engine::validateRuntimeData(
            runtime
        );

        std::cout
            << "RuntimeData load: PASS\n";


        // ----------------------------------------------------
        // Open input video.
        // ----------------------------------------------------

        cv::VideoCapture capture(
            video_path
        );

        if (!capture.isOpened()) {
            std::cerr
                << "Failed to open video: "
                << video_path
                << '\n';

            return EXIT_FAILURE;
        }


        const double fps =
            capture.get(
                cv::CAP_PROP_FPS
            );

        const double reported_frame_count =
            capture.get(
                cv::CAP_PROP_FRAME_COUNT
            );


        std::cout
            << "video      : "
            << video_path
            << '\n';

        std::cout
            << "fps        : "
            << fps
            << '\n';

        std::cout
            << "frame count: "
            << reported_frame_count
            << '\n';


        // ----------------------------------------------------
        // One persistent detector for the ENTIRE video.
        //
        // This is required for frozen Python parity because:
        //
        // static_image_mode=False
        // -> use_prev_landmarks=true
        //
        // MediaPipe tracking state therefore persists between
        // consecutive frames.
        // ----------------------------------------------------

        sign_engine::MediaPipeHandDetector detector(
            graph_path
        );


        sign_engine::RecordingFrames recording_frames;


        std::size_t decoded_frames =
            0;

        std::size_t detected_frames =
            0;

        std::size_t left_frames =
            0;

        std::size_t right_frames =
            0;

        std::size_t both_frames =
            0;


        // ----------------------------------------------------
        // Video -> MediaPipe -> RecordingFrames
        // ----------------------------------------------------

        cv::Mat bgr;


        while (capture.read(bgr)) {
            ++decoded_frames;


            if (bgr.empty()) {
                continue;
            }


            if (bgr.type() != CV_8UC3) {
                std::cerr
                    << "Unexpected frame type at frame "
                    << decoded_frames
                    << '\n';

                return EXIT_FAILURE;
            }


            const std::vector<
                sign_engine::NormalizedHandDetection
            > detections =
                detector.processBgrFrame(
                    bgr.data,
                    bgr.cols,
                    bgr.rows,
                    static_cast<std::int32_t>(
                        bgr.step
                    )
                );


            // --------------------------------------------
            // Frozen Python capture semantics:
            //
            // No hand:
            //   do NOT append this frame.
            //
            // One or more valid hands:
            //   append FrameHands.
            // --------------------------------------------

            const bool appended =
                sign_engine::appendDetectedFrame(
                    recording_frames,
                    detections,
                    bgr.cols,
                    bgr.rows
                );


            if (!appended) {
                continue;
            }


            ++detected_frames;


            const sign_engine::FrameHands& frame =
                recording_frames.back();


            if (frame.has_left) {
                ++left_frames;
            }


            if (frame.has_right) {
                ++right_frames;
            }


            if (frame.has_left &&
                frame.has_right) {

                ++both_frames;
            }
        }


        capture.release();


        // ----------------------------------------------------
        // Capture diagnostics.
        // ----------------------------------------------------

        std::cout
            << "\n===== VIDEO CAPTURE =====\n";

        std::cout
            << "decoded frames : "
            << decoded_frames
            << '\n';

        std::cout
            << "detected frames: "
            << detected_frames
            << '\n';

        std::cout
            << "recorded frames: "
            << recording_frames.size()
            << '\n';

        std::cout
            << "left frames    : "
            << left_frames
            << '\n';

        std::cout
            << "right frames   : "
            << right_frames
            << '\n';

        std::cout
            << "both frames    : "
            << both_frames
            << '\n';


        if (decoded_frames == 0) {
            std::cerr
                << "No video frames decoded\n";

            return EXIT_FAILURE;
        }


        // ----------------------------------------------------
        // Production classifier.
        //
        // IMPORTANT:
        // We call the same classifyRecording() already
        // regression-tested against frozen Python.
        // ----------------------------------------------------

        const sign_engine::SignRecognitionResult result =
            sign_engine::classifyRecording(
                recording_frames,
                runtime
            );


        // ----------------------------------------------------
        // Classification diagnostics.
        // ----------------------------------------------------

        std::cout
            << "\n===== CLASSIFICATION =====\n";

        std::cout
            << "valid          : "
            << (
                result.valid
                    ? "true"
                    : "false"
            )
            << '\n';

        std::cout
            << "final_id       : "
            << result.final_id
            << '\n';

        std::cout
            << "stage          : "
            << result.stage
            << '\n';

        std::cout
            << "is_nosign      : "
            << (
                result.is_nosign
                    ? "true"
                    : "false"
            )
            << '\n';

        std::cout
            << "selected frames: "
            << result.selected_frames
            << '\n';

        std::cout
            << "stats total    : "
            << result.recording_stats.total_frames
            << '\n';

        std::cout
            << "stats left     : "
            << result.recording_stats.left_count
            << '\n';

        std::cout
            << "stats right    : "
            << result.recording_stats.right_count
            << '\n';

        std::cout
            << "stats both     : "
            << result.recording_stats.both_count
            << '\n';

        std::cout
            << "stats bothRatio: "
            << result.recording_stats.both_ratio
            << '\n';

        std::cout
            << "error          : "
            << result.error
            << '\n';


        // ----------------------------------------------------
        // This smoke test validates the PIPELINE itself.
        //
        // A valid sign classification is NOT required yet,
        // because the input video may intentionally be a
        // non-sign / insufficient-frame fixture.
        // ----------------------------------------------------

        std::cout
            << "\nVIDEO PIPELINE EXECUTION PASS\n";

        return EXIT_SUCCESS;
    }
    catch (const std::exception& e) {
        std::cerr
            << "VIDEO PIPELINE FAIL: "
            << e.what()
            << '\n';

        return EXIT_FAILURE;
    }
}