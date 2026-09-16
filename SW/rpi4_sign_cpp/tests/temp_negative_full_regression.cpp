#include "feature_v3.hpp"
#include "runtime_data.hpp"
#include "sign_classifier.hpp"
#include "twohand_classifier.hpp"

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>


namespace {

constexpr float FLOAT_TOLERANCE =
    1.0e-5f;

constexpr double DOUBLE_TOLERANCE =
    1.0e-12;

constexpr std::size_t RAW_FRAME_COUNT =
    80;

constexpr std::size_t BOTH_COUNT =
    20;

constexpr std::size_t TOTAL_FRAMES =
    100;


template <typename T>
std::vector<T> readBinary(
    const std::string& path
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

    if (
        byte_size < 0
        ||
        byte_size
            %
            static_cast<std::streamsize>(
                sizeof(T)
            )
            !=
            0
    ) {
        throw std::runtime_error(
            "Invalid binary size: " + path
        );
    }

    const std::size_t count =
        static_cast<std::size_t>(
            byte_size
        )
        /
        sizeof(T);

    std::vector<T> data(
        count
    );

    if (
        byte_size > 0
        &&
        !file.read(
            reinterpret_cast<char*>(
                data.data()
            ),
            byte_size
        )
    ) {
        throw std::runtime_error(
            "Failed to read: " + path
        );
    }

    return data;
}


std::string readText(
    const std::string& path
) {
    std::ifstream file(
        path
    );

    if (!file) {
        throw std::runtime_error(
            "Failed to open: " + path
        );
    }

    std::string value;

    std::getline(
        file,
        value
    );

    return value;
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
            raw[offset];

        hand.points[
            landmark
        ].y =
            raw[offset + 1];
    }

    return hand;
}


sign_engine::RecordingFrames buildRecording(
    const std::vector<float>& raw_left,
    const std::vector<float>& raw_right
) {
    sign_engine::RecordingFrames recording;

    recording.reserve(
        TOTAL_FRAMES
    );

    for (
        std::size_t frame_index = 0;
        frame_index < TOTAL_FRAMES;
        ++frame_index
    ) {
        sign_engine::FrameHands frame;

        if (
            frame_index
            <
            BOTH_COUNT
        ) {
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
        }
        else {
            const std::size_t source_index =
                frame_index
                %
                RAW_FRAME_COUNT;

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


bool nearFloat(
    float actual,
    float expected
) {
    return std::fabs(
        actual - expected
    )
    <=
    FLOAT_TOLERANCE;
}


bool nearDouble(
    double actual,
    double expected
) {
    return std::fabs(
        actual - expected
    )
    <=
    DOUBLE_TOLERANCE;
}


struct ErrorStats {
    float max_abs_error =
        0.0f;

    double mean_abs_error =
        0.0;
};


ErrorStats compareFloatVectors(
    const std::vector<float>& actual,
    const std::vector<float>& expected,
    bool& all_pass
) {
    if (
        actual.size()
        !=
        expected.size()
    ) {
        all_pass =
            false;

        return {};
    }

    float max_error =
        0.0f;

    double error_sum =
        0.0;

    for (
        std::size_t i = 0;
        i < actual.size();
        ++i
    ) {
        const float error =
            std::fabs(
                actual[i]
                -
                expected[i]
            );

        if (
            error > max_error
        ) {
            max_error =
                error;
        }

        error_sum +=
            static_cast<double>(
                error
            );

        if (
            error
            >
            FLOAT_TOLERANCE
        ) {
            all_pass =
                false;
        }
    }

    ErrorStats stats;

    stats.max_abs_error =
        max_error;

    stats.mean_abs_error =
        actual.empty()
        ?
        0.0
        :
        error_sum
        /
        static_cast<double>(
            actual.size()
        );

    return stats;
}


}  // namespace


int main() {
    try {
        const std::string raw_fixture_dir =
            "SW/rpi4_sign_cpp/tests/fixtures/"
            "feature_v3_twohand/";

        const std::string expected_fixture_dir =
            "SW/rpi4_sign_cpp/tests/fixtures/"
            "temp_negative_synthetic/";

        const std::string runtime_dir =
            "SW/rpi4_sign_cpp/runtime_data";


        // ====================================================
        // Raw Python-validated landmarks
        // ====================================================

        const std::vector<float> raw_left =
            readBinary<float>(
                raw_fixture_dir
                +
                "input_left_landmarks_80x21x2.bin"
            );

        const std::vector<float> raw_right =
            readBinary<float>(
                raw_fixture_dir
                +
                "input_right_landmarks_80x21x2.bin"
            );


        const std::size_t expected_raw_count =
            RAW_FRAME_COUNT
            *
            sign_engine::HAND_LANDMARK_COUNT
            *
            2;

        if (
            raw_left.size()
            !=
            expected_raw_count
            ||
            raw_right.size()
            !=
            expected_raw_count
        ) {
            throw std::runtime_error(
                "Raw landmark fixture size mismatch"
            );
        }


        // ====================================================
        // Frozen Python expected data
        // ====================================================

        const std::vector<float> expected_feature =
            readBinary<float>(
                expected_fixture_dir
                +
                "expected_rescue_feature_80x172.bin"
            );

        const std::vector<float> expected_local84 =
            readBinary<float>(
                expected_fixture_dir
                +
                "expected_rescue_local84_80x84.bin"
            );

        const std::vector<std::int32_t>
            expected_ranking_ids =
                readBinary<std::int32_t>(
                    expected_fixture_dir
                    +
                    "expected_base_ranking_class_ids.bin"
                );

        const std::vector<float>
            expected_ranking_scores =
                readBinary<float>(
                    expected_fixture_dir
                    +
                    "expected_base_ranking_scores.bin"
                );

        const std::vector<std::int32_t>
            expected_base_id_data =
                readBinary<std::int32_t>(
                    expected_fixture_dir
                    +
                    "expected_base_id.bin"
                );

        const std::vector<std::int32_t>
            expected_final_id_data =
                readBinary<std::int32_t>(
                    expected_fixture_dir
                    +
                    "expected_final_id.bin"
                );

        const std::vector<float>
            expected_base_margin_data =
                readBinary<float>(
                    expected_fixture_dir
                    +
                    "expected_base_margin.bin"
                );

        const std::vector<std::int32_t>
            expected_counts =
                readBinary<std::int32_t>(
                    expected_fixture_dir
                    +
                    "expected_recording_counts.bin"
                );

        const std::vector<double>
            expected_both_ratio_data =
                readBinary<double>(
                    expected_fixture_dir
                    +
                    "expected_both_ratio.bin"
                );

        const std::vector<std::int32_t>
            expected_rescued_data =
                readBinary<std::int32_t>(
                    expected_fixture_dir
                    +
                    "expected_rescued.bin"
                );

        const std::string expected_stage =
            readText(
                expected_fixture_dir
                +
                "expected_stage.txt"
            );


        if (
            expected_base_id_data.size()
            !=
            1
            ||
            expected_final_id_data.size()
            !=
            1
            ||
            expected_base_margin_data.size()
            !=
            1
            ||
            expected_both_ratio_data.size()
            !=
            1
            ||
            expected_rescued_data.size()
            !=
            1
            ||
            expected_counts.size()
            !=
            4
        ) {
            throw std::runtime_error(
                "Expected fixture scalar size mismatch"
            );
        }


        // ====================================================
        // Build exact same TEST-ONLY synthetic recording
        // ====================================================

        const sign_engine::RecordingFrames recording =
            buildRecording(
                raw_left,
                raw_right
            );


        // ====================================================
        // C++ complete TEMP rescue helper
        //
        // original_one_hand = true
        // c4_is_nosign     = true
        //
        // These two preceding states are already independently
        // validated elsewhere.
        // ====================================================

        const sign_engine::RuntimeData runtime_data =
            sign_engine::loadRuntimeData(
                runtime_dir
            );

        const sign_engine::TempOverlapRescueResult result =
            sign_engine::attemptTempOverlapRescue(
                true,
                true,
                recording,
                runtime_data
            );


        bool all_pass =
            true;


        // ====================================================
        // Recording stats
        // ====================================================

        const bool total_pass =
            result.stats.total_frames
            ==
            static_cast<std::size_t>(
                expected_counts[0]
            );

        const bool left_pass =
            result.stats.left_count
            ==
            static_cast<std::size_t>(
                expected_counts[1]
            );

        const bool right_pass =
            result.stats.right_count
            ==
            static_cast<std::size_t>(
                expected_counts[2]
            );

        const bool both_pass =
            result.stats.both_count
            ==
            static_cast<std::size_t>(
                expected_counts[3]
            );

        const bool ratio_pass =
            nearDouble(
                result.stats.both_ratio,
                expected_both_ratio_data[0]
            );


        all_pass =
            all_pass
            &&
            total_pass
            &&
            left_pass
            &&
            right_pass
            &&
            both_pass
            &&
            ratio_pass;


        // ====================================================
        // Branch state
        // ====================================================

        const bool eligible_pass =
            result.eligible;

        const bool feature_valid_pass =
            result.feature_valid;

        const bool classifier_ran_pass =
            result.classifier_ran;

        const bool selected_both_pass =
            result
                .feature_result
                .selected_both_frames
            ==
            BOTH_COUNT;


        all_pass =
            all_pass
            &&
            eligible_pass
            &&
            feature_valid_pass
            &&
            classifier_ran_pass
            &&
            selected_both_pass;


        // ====================================================
        // Feature V3 [80,172]
        // ====================================================

        const ErrorStats feature_error =
            compareFloatVectors(
                result
                    .feature_result
                    .resampled_features,
                expected_feature,
                all_pass
            );


        // ====================================================
        // Local84 [80,84]
        // ====================================================

        const ErrorStats local_error =
            compareFloatVectors(
                result.local84,
                expected_local84,
                all_pass
            );


        // ====================================================
        // Classifier result
        // ====================================================

        const std::int32_t expected_base_id =
            expected_base_id_data[0];

        const std::int32_t expected_final_id =
            expected_final_id_data[0];

        const float expected_base_margin =
            expected_base_margin_data[0];

        const bool expected_rescued =
            expected_rescued_data[0]
            !=
            0;


        const bool base_id_pass =
            result.twohand_result.base_id
            ==
            expected_base_id;

        const bool final_id_pass =
            result.twohand_result.final_id
            ==
            expected_final_id;

        const bool candidate_id_pass =
            result.candidate_final_id
            ==
            expected_final_id;

        const bool stage_pass =
            result.twohand_result.stage
            ==
            expected_stage;

        const bool margin_pass =
            nearFloat(
                result.twohand_result.base_margin,
                expected_base_margin
            );

        const bool rescued_pass =
            result.rescued
            ==
            expected_rescued;


        all_pass =
            all_pass
            &&
            base_id_pass
            &&
            final_id_pass
            &&
            candidate_id_pass
            &&
            stage_pass
            &&
            margin_pass
            &&
            rescued_pass;


        // ====================================================
        // Base ranking
        // ====================================================

        const bool ranking_count_pass =
            result
                .twohand_result
                .base_ranking
                .size()
            ==
            expected_ranking_ids.size();


        if (
            !ranking_count_pass
            ||
            expected_ranking_ids.size()
            !=
            expected_ranking_scores.size()
        ) {
            all_pass =
                false;
        }


        float ranking_max_error =
            0.0f;

        double ranking_error_sum =
            0.0;

        std::size_t ranking_compared =
            0;


        if (
            ranking_count_pass
            &&
            expected_ranking_ids.size()
            ==
            expected_ranking_scores.size()
        ) {
            for (
                std::size_t i = 0;
                i
                <
                expected_ranking_ids.size();
                ++i
            ) {
                const auto& actual =
                    result
                        .twohand_result
                        .base_ranking[i];

                if (
                    actual.class_id
                    !=
                    expected_ranking_ids[i]
                ) {
                    all_pass =
                        false;
                }

                const float error =
                    std::fabs(
                        actual.score
                        -
                        expected_ranking_scores[i]
                    );

                if (
                    error
                    >
                    ranking_max_error
                ) {
                    ranking_max_error =
                        error;
                }

                ranking_error_sum +=
                    static_cast<double>(
                        error
                    );

                ++ranking_compared;

                if (
                    error
                    >
                    FLOAT_TOLERANCE
                ) {
                    all_pass =
                        false;
                }
            }
        }


        const double ranking_mean_error =
            ranking_compared == 0
            ?
            0.0
            :
            ranking_error_sum
            /
            static_cast<double>(
                ranking_compared
            );


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
            << "TEMP NEGATIVE FULL REGRESSION\n";

        std::cout
            << "========================================\n\n";


        std::cout
            << "TEST-ONLY synthetic recording\n";

        std::cout
            << "20 BOTH + 80 RIGHT_ONLY\n\n";


        std::cout
            << "RECORDING STATS\n";

        std::cout
            << "total frames          : "
            << result.stats.total_frames
            << " / expected "
            << expected_counts[0]
            << " -> "
            << (
                total_pass
                ?
                "PASS"
                :
                "FAIL"
            )
            << '\n';

        std::cout
            << "left count            : "
            << result.stats.left_count
            << " / expected "
            << expected_counts[1]
            << " -> "
            << (
                left_pass
                ?
                "PASS"
                :
                "FAIL"
            )
            << '\n';

        std::cout
            << "right count           : "
            << result.stats.right_count
            << " / expected "
            << expected_counts[2]
            << " -> "
            << (
                right_pass
                ?
                "PASS"
                :
                "FAIL"
            )
            << '\n';

        std::cout
            << "both count            : "
            << result.stats.both_count
            << " / expected "
            << expected_counts[3]
            << " -> "
            << (
                both_pass
                ?
                "PASS"
                :
                "FAIL"
            )
            << '\n';

        std::cout
            << "both ratio            : "
            << result.stats.both_ratio
            << " / expected "
            << expected_both_ratio_data[0]
            << " -> "
            << (
                ratio_pass
                ?
                "PASS"
                :
                "FAIL"
            )
            << '\n';


        std::cout
            << "\nTEMP BRANCH\n";

        std::cout
            << "eligible              : "
            << result.eligible
            << " / expected 1\n";

        std::cout
            << "feature_valid         : "
            << result.feature_valid
            << " / expected 1\n";

        std::cout
            << "classifier_ran        : "
            << result.classifier_ran
            << " / expected 1\n";

        std::cout
            << "selected BOTH         : "
            << result
                   .feature_result
                   .selected_both_frames
            << " / expected "
            << BOTH_COUNT
            << '\n';


        std::cout
            << "\nFEATURE V3 [80,172]\n";

        std::cout
            << "actual count          : "
            << result
                   .feature_result
                   .resampled_features
                   .size()
            << " / expected "
            << expected_feature.size()
            << '\n';

        std::cout
            << "max abs error         : "
            << feature_error.max_abs_error
            << '\n';

        std::cout
            << "mean abs error        : "
            << feature_error.mean_abs_error
            << '\n';


        std::cout
            << "\nLOCAL84 [80,84]\n";

        std::cout
            << "actual count          : "
            << result.local84.size()
            << " / expected "
            << expected_local84.size()
            << '\n';

        std::cout
            << "max abs error         : "
            << local_error.max_abs_error
            << '\n';

        std::cout
            << "mean abs error        : "
            << local_error.mean_abs_error
            << '\n';


        std::cout
            << "\nCLASSIFIER\n";

        std::cout
            << "base_id               : "
            << result.twohand_result.base_id
            << " / expected "
            << expected_base_id
            << " -> "
            << (
                base_id_pass
                ?
                "PASS"
                :
                "FAIL"
            )
            << '\n';

        std::cout
            << "final_id              : "
            << result.twohand_result.final_id
            << " / expected "
            << expected_final_id
            << " -> "
            << (
                final_id_pass
                ?
                "PASS"
                :
                "FAIL"
            )
            << '\n';

        std::cout
            << "candidate_final_id    : "
            << result.candidate_final_id
            << " / expected "
            << expected_final_id
            << " -> "
            << (
                candidate_id_pass
                ?
                "PASS"
                :
                "FAIL"
            )
            << '\n';

        std::cout
            << "stage                  : "
            << result.twohand_result.stage
            << " / expected "
            << expected_stage
            << " -> "
            << (
                stage_pass
                ?
                "PASS"
                :
                "FAIL"
            )
            << '\n';

        std::cout
            << "base_margin            : "
            << result.twohand_result.base_margin
            << " / expected "
            << expected_base_margin
            << " -> "
            << (
                margin_pass
                ?
                "PASS"
                :
                "FAIL"
            )
            << '\n';

        std::cout
            << "rescued                : "
            << result.rescued
            << " / expected "
            << expected_rescued
            << " -> "
            << (
                rescued_pass
                ?
                "PASS"
                :
                "FAIL"
            )
            << '\n';


        std::cout
            << "\nBASE RANKING\n";


        if (
            ranking_count_pass
        ) {
            for (
                std::size_t i = 0;
                i
                <
                expected_ranking_ids.size();
                ++i
            ) {
                const auto& actual =
                    result
                        .twohand_result
                        .base_ranking[i];

                const float expected_score =
                    expected_ranking_scores[i];

                const float error =
                    std::fabs(
                        actual.score
                        -
                        expected_score
                    );

                std::cout
                    << "  "
                    << (
                        i + 1
                    )
                    << ". class "
                    << actual.class_id
                    << " / expected "
                    << expected_ranking_ids[i]
                    << " | score "
                    << actual.score
                    << " / expected "
                    << expected_score
                    << " | error "
                    << error
                    << '\n';
            }
        }


        std::cout
            << "\nRANKING ERROR\n";

        std::cout
            << "max abs error         : "
            << ranking_max_error
            << '\n';

        std::cout
            << "mean abs error        : "
            << ranking_mean_error
            << '\n';

        std::cout
            << "tolerance             : "
            << FLOAT_TOLERANCE
            << '\n';


        std::cout
            << "\n========================================\n";


        if (
            all_pass
        ) {
            std::cout
                << "TEMP NEGATIVE FULL REGRESSION PASS\n";

            std::cout
                << "========================================\n";

            return 0;
        }


        std::cout
            << "TEMP NEGATIVE FULL REGRESSION FAIL\n";

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