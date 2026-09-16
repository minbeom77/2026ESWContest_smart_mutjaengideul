#include "feature_v3.hpp"
#include "runtime_data.hpp"
#include "sign_classifier.hpp"

#include <cmath>
#include <cstddef>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>


namespace {

template <typename T>
std::vector<T> readBinary(
    const std::string& path,
    std::size_t expected_count
) {
    std::ifstream file(
        path,
        std::ios::binary
    );

    if (!file) {
        throw std::runtime_error(
            "Failed to open: " + path
        );
    }

    file.seekg(
        0,
        std::ios::end
    );

    const std::streamsize actual_bytes =
        file.tellg();

    file.seekg(
        0,
        std::ios::beg
    );

    const std::streamsize expected_bytes =
        static_cast<std::streamsize>(
            expected_count * sizeof(T)
        );

    if (
        actual_bytes
        !=
        expected_bytes
    ) {
        throw std::runtime_error(
            "Unexpected file size: " + path
        );
    }

    std::vector<T> data(
        expected_count
    );

    if (
        !file.read(
            reinterpret_cast<char*>(
                data.data()
            ),
            expected_bytes
        )
    ) {
        throw std::runtime_error(
            "Failed to read: " + path
        );
    }

    return data;
}


sign_engine::HandLandmarks buildHand(
    const std::vector<float>& raw,
    std::size_t frame_index
) {
    sign_engine::HandLandmarks hand;

    for (
        std::size_t landmark = 0;
        landmark <
        sign_engine::HAND_LANDMARK_COUNT;
        ++landmark
    ) {
        const std::size_t offset =
            (
                frame_index
                *
                sign_engine::HAND_LANDMARK_COUNT
                +
                landmark
            )
            *
            2;

        hand.points[landmark].x =
            raw[offset];

        hand.points[landmark].y =
            raw[offset + 1];
    }

    return hand;
}


sign_engine::RecordingFrames buildRecording(
    std::size_t both_count,
    const std::vector<float>& raw_left,
    const std::vector<float>& raw_right
) {
    // Keep BOTH ratio exactly 0.20.
    //
    // Example:
    // both=15 -> total=75
    // both=19 -> total=95
    // both=20 -> total=100
    //
    // Remaining frames are RIGHT_ONLY.
    //
    // Therefore the original normal routing is consistent
    // with one-hand routing:
    //
    // both_ratio = 0.20 < 0.35
    // right_count >= left_count
    // -> RIGHT_ONLY.

    const std::size_t total_frames =
        both_count * 5;

    sign_engine::RecordingFrames recording;

    recording.reserve(
        total_frames
    );

    for (
        std::size_t i = 0;
        i < total_frames;
        ++i
    ) {
        const std::size_t source_index =
            i % 80;

        sign_engine::FrameHands frame;

        if (
            i < both_count
        ) {
            frame.has_left =
                true;

            frame.has_right =
                true;

            frame.left =
                buildHand(
                    raw_left,
                    source_index
                );

            frame.right =
                buildHand(
                    raw_right,
                    source_index
                );
        }
        else {
            frame.has_left =
                false;

            frame.has_right =
                true;

            frame.right =
                buildHand(
                    raw_right,
                    source_index
                );
        }

        recording.push_back(
            frame
        );
    }

    return recording;
}


bool near(
    double a,
    double b,
    double tolerance = 1e-12
) {
    return std::fabs(
        a - b
    ) <= tolerance;
}


void printBoolCheck(
    const std::string& name,
    bool actual,
    bool expected,
    bool& all_pass
) {
    const bool pass =
        actual == expected;

    std::cout
        << "  "
        << name
        << " : "
        << actual
        << " / expected "
        << expected
        << " -> "
        << (
            pass
            ?
            "PASS"
            :
            "FAIL"
        )
        << '\n';

    if (!pass) {
        all_pass =
            false;
    }
}


bool testCase(
    std::size_t both_count,
    const std::vector<float>& raw_left,
    const std::vector<float>& raw_right,
    const sign_engine::RuntimeData& runtime_data
) {
    const sign_engine::RecordingFrames recording =
        buildRecording(
            both_count,
            raw_left,
            raw_right
        );

    const sign_engine::RecordingStats stats =
        sign_engine::analyzeRecordingFrames(
            recording
        );

    const bool expected_eligible =
        both_count >= 15;

    const bool expected_classifier_ran =
        both_count >= 20;

    bool all_pass =
        true;

    std::cout
        << "\n----------------------------------------\n";

    std::cout
        << "BOTH COUNT = "
        << both_count
        << '\n';

    std::cout
        << "----------------------------------------\n";

    std::cout
        << "  total frames      : "
        << stats.total_frames
        << '\n';

    std::cout
        << "  left count        : "
        << stats.left_count
        << '\n';

    std::cout
        << "  right count       : "
        << stats.right_count
        << '\n';

    std::cout
        << "  both count        : "
        << stats.both_count
        << '\n';

    std::cout
        << "  both ratio        : "
        << stats.both_ratio
        << '\n';


    if (
        stats.total_frames
        !=
        both_count * 5
    ) {
        all_pass =
            false;
    }

    if (
        stats.both_count
        !=
        both_count
    ) {
        all_pass =
            false;
    }

    if (
        !near(
            stats.both_ratio,
            0.20
        )
    ) {
        all_pass =
            false;
    }


    const bool eligible =
        sign_engine::isTempOverlapRescueEligible(
            true,
            true,
            stats
        );

    printBoolCheck(
        "eligible",
        eligible,
        expected_eligible,
        all_pass
    );


    const sign_engine::TempOverlapRescueResult result =
        sign_engine::attemptTempOverlapRescue(
            true,
            true,
            recording,
            runtime_data
        );


    printBoolCheck(
        "result.eligible",
        result.eligible,
        expected_eligible,
        all_pass
    );


    printBoolCheck(
        "classifier_ran",
        result.classifier_ran,
        expected_classifier_ran,
        all_pass
    );


    if (
        both_count < 15
    ) {
        printBoolCheck(
            "feature_valid",
            result.feature_valid,
            false,
            all_pass
        );
    }
    else if (
        both_count < 20
    ) {
        // Python TEMP trigger passes at >=15,
        // but build_webcam_feature() rejects
        // BOTH_ALIGNED selected frames <20.
        printBoolCheck(
            "feature_valid",
            result.feature_valid,
            false,
            all_pass
        );
    }
    else {
        printBoolCheck(
            "feature_valid",
            result.feature_valid,
            true,
            all_pass
        );

        if (
            result.feature_result.selected_both_frames
            !=
            both_count
        ) {
            std::cout
                << "  selected BOTH     : "
                << result
                       .feature_result
                       .selected_both_frames
                << " / expected "
                << both_count
                << " -> FAIL\n";

            all_pass =
                false;
        }
        else {
            std::cout
                << "  selected BOTH     : "
                << result
                       .feature_result
                       .selected_both_frames
                << " / expected "
                << both_count
                << " -> PASS\n";
        }

        std::cout
            << "  candidate final id: "
            << result.candidate_final_id
            << '\n';

        std::cout
            << "  candidate stage   : "
            << result.twohand_result.stage
            << '\n';
    }


    std::cout
        << "  CASE RESULT       : "
        << (
            all_pass
            ?
            "PASS"
            :
            "FAIL"
        )
        << '\n';

    return all_pass;
}

}  // namespace


int main() {
    try {
        constexpr std::size_t FRAME_COUNT =
            80;

        const std::string fixture_dir =
            "SW/rpi4_sign_cpp/tests/fixtures/"
            "feature_v3_twohand/";

        const std::string runtime_dir =
            "SW/rpi4_sign_cpp/runtime_data";


        const std::size_t landmark_value_count =
            FRAME_COUNT
            *
            sign_engine::HAND_LANDMARK_COUNT
            *
            2;


        const std::vector<float> raw_left =
            readBinary<float>(
                fixture_dir
                +
                "input_left_landmarks_80x21x2.bin",

                landmark_value_count
            );


        const std::vector<float> raw_right =
            readBinary<float>(
                fixture_dir
                +
                "input_right_landmarks_80x21x2.bin",

                landmark_value_count
            );


        const sign_engine::RuntimeData runtime_data =
            sign_engine::loadRuntimeData(
                runtime_dir
            );


        std::cout
            << "========================================\n";

        std::cout
            << "TEMP MIN-FRAMES REGRESSION\n";

        std::cout
            << "========================================\n";

        std::cout
            << "\nTEST-ONLY boundary fixture:\n";

        std::cout
            << "BOTH ratio is fixed to exactly 0.20.\n";

        std::cout
            << "C4 NO-SIGN is supplied as true.\n";


        bool all_pass =
            true;


        all_pass =
            testCase(
                14,
                raw_left,
                raw_right,
                runtime_data
            )
            &&
            all_pass;


        all_pass =
            testCase(
                15,
                raw_left,
                raw_right,
                runtime_data
            )
            &&
            all_pass;


        all_pass =
            testCase(
                19,
                raw_left,
                raw_right,
                runtime_data
            )
            &&
            all_pass;


        all_pass =
            testCase(
                20,
                raw_left,
                raw_right,
                runtime_data
            )
            &&
            all_pass;


        std::cout
            << "\n========================================\n";


        if (
            all_pass
        ) {
            std::cout
                << "TEMP MIN-FRAMES REGRESSION PASS\n";

            std::cout
                << "========================================\n";

            return 0;
        }


        std::cout
            << "TEMP MIN-FRAMES REGRESSION FAIL\n";

        std::cout
            << "========================================\n";

        return 1;
    }
    catch (
        const std::exception& e
    ) {
        std::cerr
            << "ERROR: "
            << e.what()
            << '\n';

        return 1;
    }
}