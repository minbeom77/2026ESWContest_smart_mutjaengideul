#include "feature_v3.hpp"

#include <cmath>
#include <cstddef>
#include <fstream>
#include <iomanip>
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
        std::ios::binary | std::ios::ate
    );

    if (!file.is_open()) {
        throw std::runtime_error(
            "Failed to open file: " + path
        );
    }

    const std::streamsize file_size =
        file.tellg();

    const std::size_t expected_bytes =
        expected_count * sizeof(T);

    if (
        file_size < 0 ||
        static_cast<std::size_t>(file_size) != expected_bytes
    ) {
        throw std::runtime_error(
            "Invalid file size: " + path
        );
    }

    file.seekg(
        0,
        std::ios::beg
    );

    std::vector<T> data(
        expected_count
    );

    if (!file.read(
            reinterpret_cast<char*>(data.data()),
            static_cast<std::streamsize>(expected_bytes)
        )) {

        throw std::runtime_error(
            "Failed to read file: " + path
        );
    }

    return data;
}


double maxAbsoluteError(
    const std::vector<float>& actual,
    const std::vector<float>& expected
) {
    if (actual.size() != expected.size()) {
        throw std::runtime_error(
            "maxAbsoluteError: size mismatch"
        );
    }

    double max_error = 0.0;

    for (
        std::size_t i = 0;
        i < actual.size();
        ++i
    ) {
        const double error =
            std::abs(
                static_cast<double>(actual[i])
                -
                static_cast<double>(expected[i])
            );

        if (error > max_error) {
            max_error = error;
        }
    }

    return max_error;
}


double meanAbsoluteError(
    const std::vector<float>& actual,
    const std::vector<float>& expected
) {
    if (actual.size() != expected.size()) {
        throw std::runtime_error(
            "meanAbsoluteError: size mismatch"
        );
    }

    if (actual.empty()) {
        return 0.0;
    }

    double sum = 0.0;

    for (
        std::size_t i = 0;
        i < actual.size();
        ++i
    ) {
        sum += std::abs(
            static_cast<double>(actual[i])
            -
            static_cast<double>(expected[i])
        );
    }

    return (
        sum /
        static_cast<double>(actual.size())
    );
}


sign_engine::HandSequence buildSequence(
    const std::vector<float>& raw,
    std::size_t frame_count
) {
    sign_engine::HandSequence sequence(
        frame_count
    );

    for (
        std::size_t frame = 0;
        frame < frame_count;
        ++frame
    ) {
        for (
            std::size_t landmark = 0;
            landmark <
            sign_engine::HAND_LANDMARK_COUNT;
            ++landmark
        ) {
            const std::size_t offset =
                (
                    frame *
                    sign_engine::HAND_LANDMARK_COUNT *
                    2
                )
                +
                (
                    landmark *
                    2
                );

            sequence[
                frame
            ].points[
                landmark
            ].x =
                raw[
                    offset
                ];

            sequence[
                frame
            ].points[
                landmark
            ].y =
                raw[
                    offset + 1
                ];
        }
    }

    return sequence;
}

}  // namespace


int main() {
    try {
        constexpr std::size_t FRAME_COUNT = 80;

        constexpr double FEATURE_TOLERANCE =
            1e-5;

        constexpr double VALUE_TOLERANCE =
            1e-5;


        constexpr double EXPECTED_LEFT_SCORE =
            3.482832056505203;

        constexpr double EXPECTED_RIGHT_SCORE =
            3.316777979090397;

        constexpr double EXPECTED_RATIO =
            0.9523221090641242;

        constexpr double EXPECTED_TRAJECTORY_SCALE =
            51.686421037967264;


        const std::string fixture_dir =
            "SW/rpi4_sign_cpp/tests/fixtures/"
            "feature_v3_twohand/";


        // ====================================================
        // 1. Python input landmarks
        //
        // float32 [80, 21, 2]
        // ====================================================

        const std::vector<float> raw_left =
            readBinary<float>(
                fixture_dir +
                "input_left_landmarks_80x21x2.bin",

                FRAME_COUNT *
                sign_engine::HAND_LANDMARK_COUNT *
                2
            );


        const std::vector<float> raw_right =
            readBinary<float>(
                fixture_dir +
                "input_right_landmarks_80x21x2.bin",

                FRAME_COUNT *
                sign_engine::HAND_LANDMARK_COUNT *
                2
            );


        // ====================================================
        // 2. Convert to C++ HandSequence
        // ====================================================

        const sign_engine::HandSequence left_sequence =
            buildSequence(
                raw_left,
                FRAME_COUNT
            );


        const sign_engine::HandSequence right_sequence =
            buildSequence(
                raw_right,
                FRAME_COUNT
            );


        // ====================================================
        // 3. Final 07g webcam Feature V3 options
        // ====================================================

        sign_engine::FeatureV3Options options;

        options.one_hand_ratio_threshold =
            0.20;

        options.no_motion_threshold =
            0.0;

        options.anchor_frame_count =
            5;

        options.canonical_hand =
            sign_engine::CanonicalHand::Right;


        // ====================================================
        // 4. C++ Feature V3
        // ====================================================

        const sign_engine::FeatureV3Result result =
            sign_engine::buildHandFeaturesV3(
                &left_sequence,
                &right_sequence,
                options
            );


        // ====================================================
        // 5. Python expected [80,172]
        // ====================================================

        const std::vector<float> expected_feature =
            readBinary<float>(
                fixture_dir +
                "expected_feature_80x172.bin",

                FRAME_COUNT *
                sign_engine::FEATURE_V3_DIM
            );


        // ====================================================
        // 6. Numerical comparison
        // ====================================================

        const double max_error =
            maxAbsoluteError(
                result.features,
                expected_feature
            );


        const double mean_error =
            meanAbsoluteError(
                result.features,
                expected_feature
            );


        // ====================================================
        // Output
        // ====================================================

        std::cout
            << std::fixed
            << std::setprecision(12);


        std::cout
            << "========================================\n";

        std::cout
            << "FEATURE V3 TWOHAND REGRESSION\n";

        std::cout
            << "========================================\n\n";


        std::cout
            << "valid                    : "
            << (
                result.valid
                ? "true"
                : "false"
            )
            << '\n';


        std::cout
            << "usage type               : "
            << sign_engine::usageTypeToString(
                result.usage.type
            )
            << '\n';


        std::cout
            << "active hand              : "
            << sign_engine::activeHandToString(
                result.usage.active_hand
            )
            << '\n';


        std::cout
            << "usage mask               : ["
            << result.usage.usage_mask[0]
            << ", "
            << result.usage.usage_mask[1]
            << "]\n";


        std::cout
            << "detected mask            : ["
            << result.usage.detected_mask[0]
            << ", "
            << result.usage.detected_mask[1]
            << "]\n";


        std::cout
            << "canonicalized            : "
            << (
                result.canonicalized
                ? "true"
                : "false"
            )
            << '\n';


        std::cout
            << "left motion score        : "
            << result.usage.left_score
            << '\n';


        std::cout
            << "expected left score      : "
            << EXPECTED_LEFT_SCORE
            << '\n';


        std::cout
            << "right motion score       : "
            << result.usage.right_score
            << '\n';


        std::cout
            << "expected right score     : "
            << EXPECTED_RIGHT_SCORE
            << '\n';


        std::cout
            << "usage ratio              : "
            << result.usage.ratio
            << '\n';


        std::cout
            << "expected usage ratio     : "
            << EXPECTED_RATIO
            << '\n';


        std::cout
            << "trajectory scale         : "
            << result.trajectory_scale
            << '\n';


        std::cout
            << "expected trajectory scale: "
            << EXPECTED_TRAJECTORY_SCALE
            << '\n';


        std::cout
            << "feature max abs error    : "
            << max_error
            << '\n';


        std::cout
            << "feature mean abs error   : "
            << mean_error
            << '\n';


        // ====================================================
        // Validation
        // ====================================================

        bool pass = true;


        if (!result.valid) {
            std::cerr
                << "Feature V3 result invalid\n";

            pass = false;
        }


        if (
            result.usage.type !=
            sign_engine::UsageType::TwoHand
        ) {
            std::cerr
                << "Usage type mismatch\n";

            pass = false;
        }


        if (
            result.usage.active_hand !=
            sign_engine::ActiveHand::Both
        ) {
            std::cerr
                << "Active hand mismatch\n";

            pass = false;
        }


        if (
            result.usage.usage_mask[0] != 1.0f
            ||
            result.usage.usage_mask[1] != 1.0f
        ) {
            std::cerr
                << "Usage mask mismatch\n";

            pass = false;
        }


        if (
            result.usage.detected_mask[0] != 1.0f
            ||
            result.usage.detected_mask[1] != 1.0f
        ) {
            std::cerr
                << "Detected mask mismatch\n";

            pass = false;
        }


        if (result.canonicalized) {
            std::cerr
                << "Canonicalization mismatch\n";

            pass = false;
        }


        if (
            std::abs(
                result.usage.left_score
                -
                EXPECTED_LEFT_SCORE
            )
            >
            VALUE_TOLERANCE
        ) {
            std::cerr
                << "Left motion score mismatch\n";

            pass = false;
        }


        if (
            std::abs(
                result.usage.right_score
                -
                EXPECTED_RIGHT_SCORE
            )
            >
            VALUE_TOLERANCE
        ) {
            std::cerr
                << "Right motion score mismatch\n";

            pass = false;
        }


        if (
            std::abs(
                result.usage.ratio
                -
                EXPECTED_RATIO
            )
            >
            VALUE_TOLERANCE
        ) {
            std::cerr
                << "Usage ratio mismatch\n";

            pass = false;
        }


        if (
            std::abs(
                result.trajectory_scale
                -
                EXPECTED_TRAJECTORY_SCALE
            )
            >
            VALUE_TOLERANCE
        ) {
            std::cerr
                << "Trajectory scale mismatch\n";

            pass = false;
        }


        if (
            max_error >
            FEATURE_TOLERANCE
        ) {
            std::cerr
                << "Feature V3 numerical mismatch\n";

            pass = false;
        }


        // ====================================================
        // Final
        // ====================================================

        if (!pass) {

            std::cout
                << "\nFEATURE V3 TWOHAND REGRESSION FAIL\n";

            return 1;
        }


        std::cout
            << "\nFEATURE V3 TWOHAND REGRESSION PASS\n";

        return 0;
    }
    catch (const std::exception& e) {

        std::cerr
            << "FEATURE V3 TWOHAND REGRESSION ERROR\n";

        std::cerr
            << e.what()
            << '\n';

        return 1;
    }
}