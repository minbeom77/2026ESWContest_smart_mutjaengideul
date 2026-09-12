#include "feature_v3.hpp"
#include "sign_classifier.hpp"

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

    const std::streamsize byte_size =
        file.tellg();

    file.seekg(
        0,
        std::ios::beg
    );


    const std::streamsize expected_bytes =
        static_cast<std::streamsize>(
            expected_count
            *
            sizeof(T)
        );


    if (
        byte_size
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
        landmark
        <
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


        hand.points[
            landmark
        ].x =
            raw[
                offset
            ];

        hand.points[
            landmark
        ].y =
            raw[
                offset + 1
            ];
    }


    return hand;
}


}  // namespace


int main() {
    try {
        constexpr std::size_t FRAME_COUNT =
            80;

        constexpr double TOLERANCE =
            1e-5;


        const std::string fixture_dir =
            "SW/rpi4_sign_cpp/tests/fixtures/"
            "feature_v3_twohand/";


        // ====================================================
        // Python fixture inputs
        // ====================================================

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


        const std::vector<float> expected =
            readBinary<float>(
                fixture_dir
                +
                "expected_feature_80x172.bin",

                FRAME_COUNT
                *
                sign_engine::FEATURE_V3_DIM
            );


        // ====================================================
        // Build original RecordingFrames.
        //
        // Every fixture frame contains BOTH hands.
        // ====================================================

        sign_engine::RecordingFrames recording;

        recording.reserve(
            FRAME_COUNT
        );


        for (
            std::size_t frame_index = 0;
            frame_index < FRAME_COUNT;
            ++frame_index
        ) {
            sign_engine::FrameHands frame;


            frame.has_left =
                true;

            frame.has_right =
                true;


            frame.left =
                buildHand(
                    raw_left,
                    frame_index
                );

            frame.right =
                buildHand(
                    raw_right,
                    frame_index
                );


            recording.push_back(
                frame
            );
        }


        // ====================================================
        // TEMP overlap integration
        // ====================================================

        const sign_engine::TempOverlapFeatureResult result =
            sign_engine::buildTempOverlapFeature80(
                recording
            );


        bool pass =
            true;


        if (
            !result.valid
        ) {
            pass =
                false;
        }


        if (
            result.selected_both_frames
            !=
            FRAME_COUNT
        ) {
            pass =
                false;
        }


        if (
            result.raw_feature.usage.type
            !=
            sign_engine::UsageType::TwoHand
        ) {
            pass =
                false;
        }


        if (
            result.raw_feature.frame_count
            !=
            FRAME_COUNT
        ) {
            pass =
                false;
        }


        if (
            result.resampled_features.size()
            !=
            expected.size()
        ) {
            pass =
                false;
        }


        // ====================================================
        // Numerical comparison
        // ====================================================

        double max_abs_error =
            0.0;

        double sum_abs_error =
            0.0;


        if (
            result.resampled_features.size()
            ==
            expected.size()
        ) {
            for (
                std::size_t i = 0;
                i < expected.size();
                ++i
            ) {
                const double error =
                    std::abs(
                        static_cast<double>(
                            result.resampled_features[
                                i
                            ]
                        )
                        -
                        static_cast<double>(
                            expected[
                                i
                            ]
                        )
                    );


                if (
                    error
                    >
                    max_abs_error
                ) {
                    max_abs_error =
                        error;
                }


                sum_abs_error +=
                    error;
            }
        }


        const double mean_abs_error =
            expected.empty()
            ?
            0.0
            :
            (
                sum_abs_error
                /
                static_cast<double>(
                    expected.size()
                )
            );


        if (
            max_abs_error
            >
            TOLERANCE
        ) {
            pass =
                false;
        }


        // ====================================================
        // Output
        // ====================================================

        std::cout
            << std::fixed
            << std::setprecision(
                12
            );


        std::cout
            << "========================================\n";

        std::cout
            << "TEMP FEATURE INTEGRATION REGRESSION\n";

        std::cout
            << "========================================\n\n";


        std::cout
            << "valid                 : "
            << result.valid
            << " / expected 1\n";

        std::cout
            << "selected BOTH frames  : "
            << result.selected_both_frames
            << " / expected 80\n";

        std::cout
            << "usage TwoHand         : "
            << (
                result.raw_feature.usage.type
                ==
                sign_engine::UsageType::TwoHand
            )
            << " / expected 1\n";

        std::cout
            << "raw frames            : "
            << result.raw_feature.frame_count
            << " / expected 80\n";

        std::cout
            << "output count          : "
            << result.resampled_features.size()
            << " / expected "
            << expected.size()
            << '\n';

        std::cout
            << "max abs error         : "
            << max_abs_error
            << '\n';

        std::cout
            << "mean abs error        : "
            << mean_abs_error
            << '\n';

        std::cout
            << "tolerance             : "
            << TOLERANCE
            << '\n';


        std::cout
            << '\n'
            << "========================================\n";


        if (
            pass
        ) {
            std::cout
                << "TEMP FEATURE INTEGRATION REGRESSION PASS\n";

            std::cout
                << "========================================\n";

            return 0;
        }


        std::cout
            << "TEMP FEATURE INTEGRATION REGRESSION FAIL\n";

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

        return 2;
    }
}