#include <array>
#include <cstdint>
#include <cstdlib>
#include <exception>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

#include <opencv2/core.hpp>
#include <opencv2/highgui.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/videoio.hpp>

#include "hand_input.hpp"
#include "mediapipe_hand_detector.hpp"
#include "runtime_data.hpp"
#include "sign_runtime.hpp"


namespace {


// ============================================================
// Class labels
// ============================================================

constexpr std::array<const char*, 15> CLASS_NAMES = {
    "에어컨",       // 0  0128
    "문잠그다",     // 1  0527
    "꺼지다",       // 2  2353
    "덥다",         // 3  1382
    "춥다",         // 4  1248
    "구조",         // 5  1588
    "연기",         // 6  1570
    "아프다",       // 7  1152
    "괜찮다",       // 8  1381
    "감사",         // 9  1290
    "점등",         // 10 2403
    "소등",         // 11 2404
    "온도",         // 12 2563
    "배고프다",     // 13 0953
    "목마르다",     // 14 2036
};


std::string className(
    int final_id
) {
    if (
        final_id < 0 ||
        final_id >=
            static_cast<int>(
                CLASS_NAMES.size()
            )
    ) {
        return "NO-SIGN";
    }

    return CLASS_NAMES[
        static_cast<std::size_t>(
            final_id
        )
    ];
}


// ============================================================
// Result output
// ============================================================

void printResult(
    const sign_engine::SignRecognitionResult& result
) {
    std::cout
        << "\n========================================\n";

    std::cout
        << "SIGN RECOGNITION RESULT\n";

    std::cout
        << "========================================\n";


    std::cout
        << "valid           : "
        << (
            result.valid
                ? "true"
                : "false"
        )
        << '\n';


    std::cout
        << "final_id        : "
        << result.final_id
        << '\n';


    std::cout
        << "class           : "
        << className(
            result.final_id
        )
        << '\n';


    std::cout
        << "stage           : "
        << result.stage
        << '\n';


    std::cout
        << "is_nosign       : "
        << (
            result.is_nosign
                ? "true"
                : "false"
        )
        << '\n';


    std::cout
        << "source_mode     : "
        << result.source_mode
        << '\n';


    std::cout
        << "selected_frames : "
        << result.selected_frames
        << '\n';


    std::cout
        << "total_frames    : "
        << result.recording_stats.total_frames
        << '\n';


    std::cout
        << "left_frames     : "
        << result.recording_stats.left_count
        << '\n';


    std::cout
        << "right_frames    : "
        << result.recording_stats.right_count
        << '\n';


    std::cout
        << "both_frames     : "
        << result.recording_stats.both_count
        << '\n';


    std::cout
        << "both_ratio      : "
        << result.recording_stats.both_ratio
        << '\n';


    std::cout
        << "error           : "
        << result.error
        << '\n';


    std::cout
        << "========================================\n";


    if (
        result.valid &&
        !result.is_nosign &&
        result.final_id >= 0
    ) {
        std::cout
            << "\n>>> "
            << className(
                result.final_id
            )
            << "\n\n";
    }
    else if (
        result.valid &&
        result.is_nosign
    ) {
        std::cout
            << "\n>>> NO-SIGN\n\n";
    }
    else {
        std::cout
            << "\n>>> INVALID INPUT\n\n";
    }
}


// ============================================================
// Camera session
//
// Frozen Python capture_sequence() parity:
//
//   Hands() object is created once per sign session.
//   Camera is opened once per sign session.
//
//   Frames before S:
//       MediaPipe still processes them,
//       but they are NOT recorded.
//
//   S:
//       recording begins.
//
//   E:
//       recording stops and inference begins.
//
//   Q:
//       application exits.
//
// Only frames containing at least one valid hand are stored.
// ============================================================

enum class SessionResult {
    Classify,
    Quit,
};


SessionResult captureOneSign(
    const std::string& graph_path,
    int camera_index,
    sign_engine::RecordingFrames& recording_frames
) {
    // --------------------------------------------------------
    // Frozen Python creates a fresh Hands object for every
    // capture_sequence() call.
    //
    // Therefore the C++ graph is also recreated per sign.
    // --------------------------------------------------------

    sign_engine::MediaPipeHandDetector detector(
        graph_path
    );


    cv::VideoCapture capture(
        camera_index
    );


    if (!capture.isOpened()) {
        throw std::runtime_error(
            "카메라를 열 수 없습니다."
        );
    }


    bool recording =
        false;


    recording_frames.clear();


    std::cout
        << "\n========================================\n";

    std::cout
        << "READY FOR NEXT SIGN\n";

    std::cout
        << "========================================\n";

    std::cout
        << "S : 녹화 시작\n";

    std::cout
        << "E : 녹화 종료 + 추론\n";

    std::cout
        << "Q : 종료\n";


    cv::Mat frame;


    while (true) {
        const bool ok =
            capture.read(
                frame
            );


        if (!ok ||
            frame.empty()) {

            throw std::runtime_error(
                "카메라 frame read 실패"
            );
        }


        // ----------------------------------------------------
        // IMPORTANT:
        //
        // Do NOT flip before processBgrFrame().
        //
        // MediaPipeHandDetector internally performs exactly:
        //
        //     cv::flip(frame, 1)
        //     BGR -> RGB
        //
        // matching frozen Python.
        // ----------------------------------------------------

        const std::vector<
            sign_engine::NormalizedHandDetection
        > detections =
            detector.processBgrFrame(
                frame.data,
                frame.cols,
                frame.rows,
                static_cast<std::int32_t>(
                    frame.step
                )
            );


        // ----------------------------------------------------
        // Frozen Python:
        //
        // if recording:
        //     if left_xy is not None
        //        or right_xy is not None:
        //
        //         recording_frames.append(...)
        // ----------------------------------------------------

        if (recording) {
            sign_engine::appendDetectedFrame(
                recording_frames,
                detections,
                frame.cols,
                frame.rows
            );
        }


        // ----------------------------------------------------
        // Display only.
        //
        // Python displays the mirrored frame.
        //
        // The detector already mirrored its own private input,
        // so we mirror a separate display copy here.
        //
        // This does NOT affect classification coordinates.
        // ----------------------------------------------------

        cv::Mat display;

        cv::flip(
            frame,
            display,
            1
        );


        if (recording) {
            cv::putText(
                display,
                "RECORDING",
                cv::Point(
                    20,
                    40
                ),
                cv::FONT_HERSHEY_SIMPLEX,
                1.0,
                cv::Scalar(
                    0,
                    0,
                    255
                ),
                2
            );


            cv::putText(
                display,
                "Frames: " +
                    std::to_string(
                        recording_frames.size()
                    ),
                cv::Point(
                    20,
                    80
                ),
                cv::FONT_HERSHEY_SIMPLEX,
                0.8,
                cv::Scalar(
                    0,
                    0,
                    255
                ),
                2
            );
        }
        else {
            cv::putText(
                display,
                "S: Start  E: End  Q: Quit",
                cv::Point(
                    20,
                    40
                ),
                cv::FONT_HERSHEY_SIMPLEX,
                0.8,
                cv::Scalar(
                    0,
                    255,
                    0
                ),
                2
            );
        }


        cv::imshow(
            "C++ Sign Recognition",
            display
        );


        const int key =
            cv::waitKey(1)
            &
            0xFF;


        if (
            key == 's' ||
            key == 'S'
        ) {
            if (!recording) {
                recording_frames.clear();

                recording =
                    true;

                std::cout
                    << "\nRECORDING START\n";
            }

            continue;
        }


        if (
            key == 'e' ||
            key == 'E'
        ) {
            if (recording) {
                recording =
                    false;

                std::cout
                    << "RECORDING END\n";

                std::cout
                    << "Recorded hand frames: "
                    << recording_frames.size()
                    << '\n';

                capture.release();

                cv::destroyWindow(
                    "C++ Sign Recognition"
                );

                return SessionResult::Classify;
            }

            continue;
        }


        if (
            key == 'q' ||
            key == 'Q'
        ) {
            capture.release();

            cv::destroyWindow(
                "C++ Sign Recognition"
            );

            return SessionResult::Quit;
        }
    }
}


}  // namespace


// ============================================================
// main
//
// Usage:
//
//   sign_runtime_app <graph.binarypb> <runtime_data_dir>
//
// or
//
//   sign_runtime_app <graph.binarypb> <runtime_data_dir>
//                    <camera_index>
//
// No Windows / WSL path is hard-coded here.
// The same executable source can therefore be used on RPi4.
// ============================================================

int main(
    int argc,
    char* argv[]
) {
    if (
        argc != 3 &&
        argc != 4
    ) {
        std::cerr
            << "Usage:\n"
            << "  "
            << argv[0]
            << " <graph.binarypb>"
            << " <runtime_data_dir>"
            << " [camera_index]\n";

        return EXIT_FAILURE;
    }


    const std::string graph_path =
        argv[1];


    const std::string runtime_dir =
        argv[2];


    int camera_index =
        0;


    if (argc == 4) {
        try {
            camera_index =
                std::stoi(
                    argv[3]
                );
        }
        catch (const std::exception&) {
            std::cerr
                << "Invalid camera index: "
                << argv[3]
                << '\n';

            return EXIT_FAILURE;
        }
    }


    try {
        // ----------------------------------------------------
        // Runtime classifier data is immutable.
        // Load once for the entire application.
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

        std::cout
            << "Graph       : "
            << graph_path
            << '\n';

        std::cout
            << "Runtime data: "
            << runtime_dir
            << '\n';

        std::cout
            << "Camera index: "
            << camera_index
            << '\n';


        // ----------------------------------------------------
        // Each iteration corresponds to one frozen Python
        // capture_sequence() call.
        // ----------------------------------------------------

        while (true) {
            sign_engine::RecordingFrames
                recording_frames;


            const SessionResult session =
                captureOneSign(
                    graph_path,
                    camera_index,
                    recording_frames
                );


            if (
                session ==
                SessionResult::Quit
            ) {
                break;
            }


            // ------------------------------------------------
            // Same production classifier already verified
            // against frozen Python.
            // ------------------------------------------------

            const sign_engine::SignRecognitionResult result =
                sign_engine::classifyRecording(
                    recording_frames,
                    runtime
                );


            printResult(
                result
            );


            // Next iteration recreates the MediaPipe detector,
            // matching a new Python capture_sequence() call.
        }


        cv::destroyAllWindows();


        std::cout
            << "\nC++ SIGN RUNTIME EXIT\n";


        return EXIT_SUCCESS;
    }
    catch (const std::exception& e) {
        cv::destroyAllWindows();


        std::cerr
            << "\nSIGN RUNTIME FAIL: "
            << e.what()
            << '\n';


        return EXIT_FAILURE;
    }
}