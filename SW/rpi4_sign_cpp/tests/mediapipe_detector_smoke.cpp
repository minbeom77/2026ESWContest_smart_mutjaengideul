#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

#include <opencv2/imgcodecs.hpp>

#include "hand_input.hpp"
#include "mediapipe_hand_detector.hpp"


int main() {
    const std::string graph_path =
        "/mnt/c/2026ESWContest_smart_mutjaengideul/"
        "SW/rpi4_sign_cpp/mediapipe_assets/"
        "hands_0_10_21_canonical.binarypb";

    const std::string image_path =
        "/mnt/c/2026ESWContest_smart_mutjaengideul/"
        "SW/rpi4_sign_cpp/tests/fixtures/"
        "mediapipe_hand_smoke/hand_test.jpg";

    try {
        cv::Mat bgr =
            cv::imread(
                image_path,
                cv::IMREAD_COLOR
            );

        if (bgr.empty()) {
            std::cerr
                << "Failed to load image: "
                << image_path
                << '\n';

            return EXIT_FAILURE;
        }


        sign_engine::MediaPipeHandDetector detector(
            graph_path
        );


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


        std::cout
            << "detections: "
            << detections.size()
            << '\n';


        for (std::size_t i = 0;
             i < detections.size();
             ++i) {

            std::cout
                << "HAND "
                << i
                << " label="
                << detections[i].label
                << " score="
                << detections[i].confidence
                << '\n';
        }


        if (detections.size() != 1) {
            std::cerr
                << "EXPECTED exactly 1 hand\n";

            return EXIT_FAILURE;
        }


        if (detections[0].label != "Right") {
            std::cerr
                << "EXPECTED label Right\n";

            return EXIT_FAILURE;
        }


        const sign_engine::FrameHands frame =
            sign_engine::extractFrameHands(
                detections,
                bgr.cols,
                bgr.rows
            );


        std::cout
            << "has_left : "
            << (frame.has_left
                    ? "true"
                    : "false")
            << '\n';

        std::cout
            << "has_right: "
            << (frame.has_right
                    ? "true"
                    : "false")
            << '\n';


        if (frame.has_left ||
            !frame.has_right) {

            std::cerr
                << "EXPECTED RIGHT_ONLY frame\n";

            return EXIT_FAILURE;
        }


        std::cout
            << "RIGHT LM0: x="
            << frame.right.points[0].x
            << " y="
            << frame.right.points[0].y
            << '\n';


        std::cout
            << "\nPRODUCTION MEDIAPIPE DETECTOR PASS\n";

        return EXIT_SUCCESS;
    }
    catch (const std::exception& e) {
        std::cerr
            << "PRODUCTION DETECTOR FAIL: "
            << e.what()
            << '\n';

        return EXIT_FAILURE;
    }
}