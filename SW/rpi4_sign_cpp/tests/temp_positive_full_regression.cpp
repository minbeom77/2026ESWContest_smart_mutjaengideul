#include "c4_gate.hpp"
#include "feature_v3.hpp"
#include "runtime_data.hpp"
#include "sign_classifier.hpp"
#include "temporal_resample.hpp"
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
    1.0e-5;

constexpr double NORMAL_BOTH_RATIO_THRESHOLD =
    0.35;

constexpr std::size_t MIN_ACCEPTED_FRAMES =
    20;

constexpr std::size_t REAL_BOTH_FRAMES =
    87;

constexpr std::size_t EXTRA_RIGHT_ONLY =
    247;

constexpr std::size_t TOTAL_FRAMES =
    334;


struct ErrorStats {
    double max_abs_error =
        0.0;

    double mean_abs_error =
        0.0;
};


struct OriginalFeatureResult {
    bool valid =
        false;

    bool original_one_hand =
        false;

    std::string source_mode;

    std::size_t selected_frames =
        0;

    sign_engine::FeatureV3Result raw_feature;

    std::vector<float> feature80;
};


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

    if (
        !value.empty()
        &&
        value.back() == '\r'
    ) {
        value.pop_back();
    }

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


sign_engine::RecordingFrames buildRecording(
    const std::vector<float>& raw_left,
    const std::vector<float>& raw_right
) {
    sign_engine::RecordingFrames recording;

    recording.reserve(
        TOTAL_FRAMES
    );

    // ========================================================
    // REAL01 BOTH 87 frames
    // ========================================================

    for (
        std::size_t frame = 0;
        frame < REAL_BOTH_FRAMES;
        ++frame
    ) {
        sign_engine::FrameHands item;

        item.has_left =
            true;

        item.has_right =
            true;

        item.left =
            buildHand(
                raw_left,
                frame
            );

        item.right =
            buildHand(
                raw_right,
                frame
            );

        recording.push_back(
            item
        );
    }

    // ========================================================
    // TEST-ONLY RIGHT_ONLY padding
    //
    // Exact same synthetic construction as Python fixture:
    // cycle REAL01 right-hand 87-frame sequence.
    // ========================================================

    for (
        std::size_t i = 0;
        i < EXTRA_RIGHT_ONLY;
        ++i
    ) {
        const std::size_t source_index =
            i
            %
            REAL_BOTH_FRAMES;

        sign_engine::FrameHands item;

        item.has_left =
            false;

        item.has_right =
            true;

        item.right =
            buildHand(
                raw_right,
                source_index
            );

        recording.push_back(
            item
        );
    }

    return recording;
}


sign_engine::FeatureV3Options makeFeatureOptions() {
    sign_engine::FeatureV3Options options;

    options.one_hand_ratio_threshold =
        0.20;

    options.no_motion_threshold =
        0.0;

    options.anchor_frame_count =
        5;

    options.canonical_hand =
        sign_engine::CanonicalHand::Right;

    return options;
}


// ============================================================
// Exact 06u build_webcam_feature routing semantics used by
// this regression.
//
// This test helper intentionally mirrors frozen Python:
//
// both_ratio >= 0.35:
//     BOTH_ALIGNED
//
// else:
//     right_count >= left_count -> RIGHT_ONLY
//     otherwise                 -> LEFT_ONLY
//
// selected frames must be >=20.
// ============================================================

OriginalFeatureResult buildOriginalFeature80(
    const sign_engine::RecordingFrames& recording
) {
    if (recording.empty()) {
        throw std::runtime_error(
            "buildOriginalFeature80: empty recording"
        );
    }

    const sign_engine::RecordingStats stats =
        sign_engine::analyzeRecordingFrames(
            recording
        );

    const sign_engine::FeatureV3Options options =
        makeFeatureOptions();

    OriginalFeatureResult result;

    if (
        stats.both_ratio
        >=
        NORMAL_BOTH_RATIO_THRESHOLD
    ) {
        result.source_mode =
            "BOTH_ALIGNED";

        result.original_one_hand =
            false;

        sign_engine::HandSequence left;
        sign_engine::HandSequence right;

        left.reserve(
            stats.both_count
        );

        right.reserve(
            stats.both_count
        );

        for (
            const sign_engine::FrameHands& frame :
            recording
        ) {
            if (
                !frame.has_left
                ||
                !frame.has_right
            ) {
                continue;
            }

            left.push_back(
                frame.left
            );

            right.push_back(
                frame.right
            );
        }

        result.selected_frames =
            left.size();

        if (
            result.selected_frames
            <
            MIN_ACCEPTED_FRAMES
        ) {
            throw std::runtime_error(
                "BOTH_ALIGNED frame 부족"
            );
        }

        result.raw_feature =
            sign_engine::buildHandFeaturesV3(
                &left,
                &right,
                options
            );
    }
    else {
        result.original_one_hand =
            true;

        if (
            stats.right_count
            >=
            stats.left_count
        ) {
            result.source_mode =
                "RIGHT_ONLY";

            sign_engine::HandSequence right;

            right.reserve(
                stats.right_count
            );

            for (
                const sign_engine::FrameHands& frame :
                recording
            ) {
                if (!frame.has_right) {
                    continue;
                }

                right.push_back(
                    frame.right
                );
            }

            result.selected_frames =
                right.size();

            if (
                result.selected_frames
                <
                MIN_ACCEPTED_FRAMES
            ) {
                throw std::runtime_error(
                    "RIGHT_ONLY frame 부족"
                );
            }

            result.raw_feature =
                sign_engine::buildHandFeaturesV3(
                    nullptr,
                    &right,
                    options
                );
        }
        else {
            result.source_mode =
                "LEFT_ONLY";

            sign_engine::HandSequence left;

            left.reserve(
                stats.left_count
            );

            for (
                const sign_engine::FrameHands& frame :
                recording
            ) {
                if (!frame.has_left) {
                    continue;
                }

                left.push_back(
                    frame.left
                );
            }

            result.selected_frames =
                left.size();

            if (
                result.selected_frames
                <
                MIN_ACCEPTED_FRAMES
            ) {
                throw std::runtime_error(
                    "LEFT_ONLY frame 부족"
                );
            }

            result.raw_feature =
                sign_engine::buildHandFeaturesV3(
                    &left,
                    nullptr,
                    options
                );
        }
    }

    if (
        !result.raw_feature.valid
    ) {
        throw std::runtime_error(
            "Original Feature V3 invalid"
        );
    }

    const std::size_t expected_raw_size =
        result.raw_feature.frame_count
        *
        sign_engine::FEATURE_V3_DIM;

    if (
        result.raw_feature.features.size()
        !=
        expected_raw_size
    ) {
        throw std::runtime_error(
            "Original raw feature size mismatch"
        );
    }

    result.feature80 =
        sign_engine::temporalResample(
            result.raw_feature.features,
            result.raw_feature.frame_count,
            sign_engine::FEATURE_V3_DIM,
            sign_engine::TARGET_FRAMES
        );

    const std::size_t expected_feature_size =
        sign_engine::TARGET_FRAMES
        *
        sign_engine::FEATURE_V3_DIM;

    if (
        result.feature80.size()
        !=
        expected_feature_size
    ) {
        throw std::runtime_error(
            "Original Feature80 size mismatch"
        );
    }

    result.valid =
        true;

    return result;
}


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

    ErrorStats result;

    double sum =
        0.0;

    for (
        std::size_t i = 0;
        i < actual.size();
        ++i
    ) {
        const double error =
            std::fabs(
                static_cast<double>(
                    actual[i]
                )
                -
                static_cast<double>(
                    expected[i]
                )
            );

        if (
            error
            >
            result.max_abs_error
        ) {
            result.max_abs_error =
                error;
        }

        sum +=
            error;

        if (
            error
            >
            FLOAT_TOLERANCE
        ) {
            all_pass =
                false;
        }
    }

    if (!actual.empty()) {
        result.mean_abs_error =
            sum
            /
            static_cast<double>(
                actual.size()
            );
    }

    return result;
}


ErrorStats compareDoubleToFloat(
    const std::vector<double>& actual,
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

    ErrorStats result;

    double sum =
        0.0;

    for (
        std::size_t i = 0;
        i < actual.size();
        ++i
    ) {
        const double error =
            std::fabs(
                actual[i]
                -
                static_cast<double>(
                    expected[i]
                )
            );

        if (
            error
            >
            result.max_abs_error
        ) {
            result.max_abs_error =
                error;
        }

        sum +=
            error;

        if (
            error
            >
            FLOAT_TOLERANCE
        ) {
            all_pass =
                false;
        }
    }

    if (!actual.empty()) {
        result.mean_abs_error =
            sum
            /
            static_cast<double>(
                actual.size()
            );
    }

    return result;
}


bool nearFloat(
    float actual,
    float expected
) {
    return std::fabs(
        actual
        -
        expected
    )
    <=
    FLOAT_TOLERANCE;
}


bool nearDouble(
    double actual,
    double expected
) {
    return std::fabs(
        actual
        -
        expected
    )
    <=
    DOUBLE_TOLERANCE;
}


}  // namespace


int main() {
    try {
        const std::string fixture_dir =
            "SW/rpi4_sign_cpp/tests/fixtures/"
            "temp_positive_full_real01/";

        const std::string runtime_dir =
            "SW/rpi4_sign_cpp/runtime_data";


        // ====================================================
        // Load REAL01 raw verified XY fixture
        // ====================================================

        const std::vector<float> raw_left =
            readBinary<float>(
                fixture_dir
                +
                "input_real01_left_87x21x2.bin"
            );

        const std::vector<float> raw_right =
            readBinary<float>(
                fixture_dir
                +
                "input_real01_right_87x21x2.bin"
            );


        const std::size_t expected_landmark_count =
            REAL_BOTH_FRAMES
            *
            sign_engine::HAND_LANDMARK_COUNT
            *
            2;


        if (
            raw_left.size()
            !=
            expected_landmark_count
            ||
            raw_right.size()
            !=
            expected_landmark_count
        ) {
            throw std::runtime_error(
                "REAL01 raw landmark size mismatch"
            );
        }


        // ====================================================
        // Load frozen Python expected fixture
        // ====================================================

        const std::vector<float>
            expected_original_feature =
                readBinary<float>(
                    fixture_dir
                    +
                    "expected_original_feature_80x172.bin"
                );

        const std::vector<float>
            expected_c4_feature =
                readBinary<float>(
                    fixture_dir
                    +
                    "expected_c4_feature_230.bin"
                );

        const std::vector<float>
            expected_rescue_feature =
                readBinary<float>(
                    fixture_dir
                    +
                    "expected_rescue_feature_80x172.bin"
                );

        const std::vector<float>
            expected_rescue_local84 =
                readBinary<float>(
                    fixture_dir
                    +
                    "expected_rescue_local84_80x84.bin"
                );

        const std::vector<std::int32_t>
            expected_ranking_ids =
                readBinary<std::int32_t>(
                    fixture_dir
                    +
                    "expected_base_ranking_class_ids.bin"
                );

        const std::vector<float>
            expected_ranking_scores =
                readBinary<float>(
                    fixture_dir
                    +
                    "expected_base_ranking_scores.bin"
                );

        const std::vector<std::int32_t>
            expected_counts =
                readBinary<std::int32_t>(
                    fixture_dir
                    +
                    "expected_recording_counts.bin"
                );

        const std::vector<double>
            expected_both_ratio =
                readBinary<double>(
                    fixture_dir
                    +
                    "expected_both_ratio.bin"
                );

        const std::vector<std::int32_t>
            expected_c4_prediction =
                readBinary<std::int32_t>(
                    fixture_dir
                    +
                    "expected_c4_prediction.bin"
                );

        const std::vector<double>
            expected_c4_distances =
                readBinary<double>(
                    fixture_dir
                    +
                    "expected_c4_distances.bin"
                );

        const std::vector<std::int32_t>
            expected_base_id =
                readBinary<std::int32_t>(
                    fixture_dir
                    +
                    "expected_base_id.bin"
                );

        const std::vector<std::int32_t>
            expected_final_id =
                readBinary<std::int32_t>(
                    fixture_dir
                    +
                    "expected_final_id.bin"
                );

        const std::vector<float>
            expected_base_margin =
                readBinary<float>(
                    fixture_dir
                    +
                    "expected_base_margin.bin"
                );

        const std::vector<std::int32_t>
            expected_rescued =
                readBinary<std::int32_t>(
                    fixture_dir
                    +
                    "expected_rescued.bin"
                );

        const std::vector<std::int32_t>
            expected_final_is_nosign =
                readBinary<std::int32_t>(
                    fixture_dir
                    +
                    "expected_final_is_nosign.bin"
                );


        const std::string expected_original_usage =
            readText(
                fixture_dir
                +
                "expected_original_usage.txt"
            );

        const std::string expected_rescue_usage =
            readText(
                fixture_dir
                +
                "expected_rescue_usage.txt"
            );

        const std::string expected_pre_temp_stage =
            readText(
                fixture_dir
                +
                "expected_pre_temp_stage.txt"
            );

        const std::string expected_final_stage =
            readText(
                fixture_dir
                +
                "expected_final_stage.txt"
            );


        if (
            expected_counts.size() != 5
            ||
            expected_both_ratio.size() != 1
            ||
            expected_c4_prediction.size() != 1
            ||
            expected_c4_distances.size() != 3
            ||
            expected_base_id.size() != 1
            ||
            expected_final_id.size() != 1
            ||
            expected_base_margin.size() != 1
            ||
            expected_rescued.size() != 1
            ||
            expected_final_is_nosign.size() != 1
        ) {
            throw std::runtime_error(
                "Expected fixture scalar size mismatch"
            );
        }


        // ====================================================
        // Runtime
        // ====================================================

        const sign_engine::RuntimeData runtime =
            sign_engine::loadRuntimeData(
                runtime_dir
            );


        // ====================================================
        // Build exact synthetic original recording
        // ====================================================

        const sign_engine::RecordingFrames recording =
            buildRecording(
                raw_left,
                raw_right
            );


        const sign_engine::RecordingStats stats =
            sign_engine::analyzeRecordingFrames(
                recording
            );


        bool all_pass =
            true;


        const bool total_pass =
            stats.total_frames
            ==
            static_cast<std::size_t>(
                expected_counts[0]
            );

        const bool left_pass =
            stats.left_count
            ==
            static_cast<std::size_t>(
                expected_counts[1]
            );

        const bool right_pass =
            stats.right_count
            ==
            static_cast<std::size_t>(
                expected_counts[2]
            );

        const bool both_pass =
            stats.both_count
            ==
            static_cast<std::size_t>(
                expected_counts[3]
            );

        const bool extra_pass =
            EXTRA_RIGHT_ONLY
            ==
            static_cast<std::size_t>(
                expected_counts[4]
            );

        const bool both_ratio_pass =
            nearDouble(
                stats.both_ratio,
                expected_both_ratio[0]
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
            extra_pass
            &&
            both_ratio_pass;


        // ====================================================
        // Original routing + Feature V3
        // ====================================================

        const OriginalFeatureResult original =
            buildOriginalFeature80(
                recording
            );


        const bool original_valid_pass =
            original.valid;

        const bool original_one_hand_pass =
            original.original_one_hand;

        const bool original_source_pass =
            original.source_mode
            ==
            "RIGHT_ONLY";

        const bool original_usage_pass =
            (
                expected_original_usage
                ==
                "one_hand"
            )
            &&
            (
                original.raw_feature.usage.type
                ==
                sign_engine::UsageType::OneHand
            );

        const bool original_selected_pass =
            original.selected_frames
            ==
            TOTAL_FRAMES;


        all_pass =
            all_pass
            &&
            original_valid_pass
            &&
            original_one_hand_pass
            &&
            original_source_pass
            &&
            original_usage_pass
            &&
            original_selected_pass;


        const ErrorStats original_feature_error =
            compareFloatVectors(
                original.feature80,
                expected_original_feature,
                all_pass
            );


        // ====================================================
        // Actual C++ C4 feature
        // ====================================================

        const std::vector<double> c4_feature =
            sign_engine::buildC4Feature(
                original.feature80
            );


        const ErrorStats c4_feature_error =
            compareDoubleToFloat(
                c4_feature,
                expected_c4_feature,
                all_pass
            );


        // ====================================================
        // Actual C++ C4 gate
        // ====================================================

        const sign_engine::C4GateResult c4_result =
            sign_engine::classifyOnehandC4Gate(
                original.feature80,
                runtime
            );


        const bool c4_prediction_pass =
            c4_result.prediction
            ==
            expected_c4_prediction[0];

        const bool c4_nosign_pass =
            c4_result.prediction
            ==
            sign_engine::C4_NOSIGN_LABEL;

        const bool c4_d_sign_pass =
            nearDouble(
                c4_result.d_sign,
                expected_c4_distances[0]
            );

        const bool c4_d_nosign_pass =
            nearDouble(
                c4_result.d_nosign,
                expected_c4_distances[1]
            );

        const bool c4_margin_pass =
            nearDouble(
                c4_result.margin_nosign_minus_sign,
                expected_c4_distances[2]
            );


        all_pass =
            all_pass
            &&
            c4_prediction_pass
            &&
            c4_nosign_pass
            &&
            c4_d_sign_pass
            &&
            c4_d_nosign_pass
            &&
            c4_margin_pass;


        // ====================================================
        // Actual C++ TEMP rescue
        //
        // No forced C4 boolean:
        // derives from actual C++ C4 result above.
        // ====================================================

        const bool c4_is_nosign =
            c4_result.prediction
            ==
            sign_engine::C4_NOSIGN_LABEL;


        const sign_engine::TempOverlapRescueResult rescue =
            sign_engine::attemptTempOverlapRescue(
                original.original_one_hand,
                c4_is_nosign,
                recording,
                runtime
            );


        const bool eligible_pass =
            rescue.eligible;

        const bool feature_valid_pass =
            rescue.feature_valid;

        const bool classifier_ran_pass =
            rescue.classifier_ran;

        const bool selected_both_pass =
            rescue
                .feature_result
                .selected_both_frames
            ==
            REAL_BOTH_FRAMES;


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
        // TEMP Feature V3
        // ====================================================

        const ErrorStats rescue_feature_error =
            compareFloatVectors(
                rescue
                    .feature_result
                    .resampled_features,
                expected_rescue_feature,
                all_pass
            );


        const ErrorStats rescue_local_error =
            compareFloatVectors(
                rescue.local84,
                expected_rescue_local84,
                all_pass
            );


        const bool rescue_usage_pass =
            (
                expected_rescue_usage
                ==
                "two_hand"
            )
            &&
            (
                rescue
                    .feature_result
                    .raw_feature
                    .usage
                    .type
                ==
                sign_engine::UsageType::TwoHand
            );


        all_pass =
            all_pass
            &&
            rescue_usage_pass;


        // ====================================================
        // Pre-TEMP classifier result
        //
        // attemptTempOverlapRescue() overwrites stage after
        // class 12 success, so call classifyTwoHand() once
        // separately to verify Python pre-TEMP stage.
        // ====================================================

        const sign_engine::TwoHandResult pre_temp =
            sign_engine::classifyTwoHand(
                rescue.local84,
                runtime
            );


        const bool pre_base_id_pass =
            pre_temp.base_id
            ==
            expected_base_id[0];

        const bool pre_final_id_pass =
            pre_temp.final_id
            ==
            expected_final_id[0];

        const bool pre_stage_pass =
            pre_temp.stage
            ==
            expected_pre_temp_stage;

        const bool pre_margin_pass =
            nearFloat(
                pre_temp.base_margin,
                expected_base_margin[0]
            );


        all_pass =
            all_pass
            &&
            pre_base_id_pass
            &&
            pre_final_id_pass
            &&
            pre_stage_pass
            &&
            pre_margin_pass;


        // ====================================================
        // Ranking comparison
        // ====================================================

        const bool ranking_count_pass =
            pre_temp.base_ranking.size()
            ==
            expected_ranking_ids.size()
            &&
            expected_ranking_ids.size()
            ==
            expected_ranking_scores.size();


        if (!ranking_count_pass) {
            all_pass =
                false;
        }


        double ranking_max_error =
            0.0;

        double ranking_sum_error =
            0.0;

        std::size_t ranking_count =
            0;


        if (ranking_count_pass) {
            for (
                std::size_t i = 0;
                i < expected_ranking_ids.size();
                ++i
            ) {
                const auto& actual =
                    pre_temp.base_ranking[i];

                if (
                    actual.class_id
                    !=
                    expected_ranking_ids[i]
                ) {
                    all_pass =
                        false;
                }

                const double error =
                    std::fabs(
                        static_cast<double>(
                            actual.score
                        )
                        -
                        static_cast<double>(
                            expected_ranking_scores[i]
                        )
                    );

                if (
                    error
                    >
                    ranking_max_error
                ) {
                    ranking_max_error =
                        error;
                }

                ranking_sum_error +=
                    error;

                ++ranking_count;

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
            ranking_count == 0
            ?
            0.0
            :
            ranking_sum_error
            /
            static_cast<double>(
                ranking_count
            );


        // ====================================================
        // Final TEMP override
        // ====================================================

        const bool candidate_final_id_pass =
            rescue.candidate_final_id
            ==
            expected_final_id[0];

        const bool rescued_pass =
            rescue.rescued
            ==
            (
                expected_rescued[0]
                !=
                0
            );

        const bool final_id_pass =
            rescue.twohand_result.final_id
            ==
            expected_final_id[0];

        const bool final_stage_pass =
            rescue.twohand_result.stage
            ==
            expected_final_stage;

        const bool inferred_final_is_nosign =
            c4_is_nosign
            &&
            !rescue.rescued;

        const bool final_is_nosign_pass =
            inferred_final_is_nosign
            ==
            (
                expected_final_is_nosign[0]
                !=
                0
            );


        all_pass =
            all_pass
            &&
            candidate_final_id_pass
            &&
            rescued_pass
            &&
            final_id_pass
            &&
            final_stage_pass
            &&
            final_is_nosign_pass;


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
            << "TEMP POSITIVE FULL REGRESSION\n";

        std::cout
            << "========================================\n\n";


        std::cout
            << "TEST-ONLY synthetic recording\n";

        std::cout
            << "REAL01 BOTH 87 + RIGHT_ONLY 247\n\n";


        std::cout
            << "RECORDING\n";

        std::cout
            << "total frames          : "
            << stats.total_frames
            << " / expected "
            << expected_counts[0]
            << " -> "
            << (total_pass ? "PASS" : "FAIL")
            << '\n';

        std::cout
            << "left count            : "
            << stats.left_count
            << " / expected "
            << expected_counts[1]
            << " -> "
            << (left_pass ? "PASS" : "FAIL")
            << '\n';

        std::cout
            << "right count           : "
            << stats.right_count
            << " / expected "
            << expected_counts[2]
            << " -> "
            << (right_pass ? "PASS" : "FAIL")
            << '\n';

        std::cout
            << "both count            : "
            << stats.both_count
            << " / expected "
            << expected_counts[3]
            << " -> "
            << (both_pass ? "PASS" : "FAIL")
            << '\n';

        std::cout
            << "both ratio            : "
            << stats.both_ratio
            << " / expected "
            << expected_both_ratio[0]
            << " -> "
            << (both_ratio_pass ? "PASS" : "FAIL")
            << '\n';


        std::cout
            << "\nORIGINAL ROUTING\n";

        std::cout
            << "source mode           : "
            << original.source_mode
            << " / expected RIGHT_ONLY -> "
            << (original_source_pass ? "PASS" : "FAIL")
            << '\n';

        std::cout
            << "original one_hand     : "
            << original.original_one_hand
            << " / expected 1 -> "
            << (original_one_hand_pass ? "PASS" : "FAIL")
            << '\n';

        std::cout
            << "selected frames       : "
            << original.selected_frames
            << " / expected "
            << TOTAL_FRAMES
            << " -> "
            << (original_selected_pass ? "PASS" : "FAIL")
            << '\n';


        std::cout
            << "\nORIGINAL FEATURE [80,172]\n";

        std::cout
            << "max abs error         : "
            << original_feature_error.max_abs_error
            << '\n';

        std::cout
            << "mean abs error        : "
            << original_feature_error.mean_abs_error
            << '\n';


        std::cout
            << "\nC4 FEATURE [230]\n";

        std::cout
            << "max abs error         : "
            << c4_feature_error.max_abs_error
            << '\n';

        std::cout
            << "mean abs error        : "
            << c4_feature_error.mean_abs_error
            << '\n';


        std::cout
            << "\nC4 GATE\n";

        std::cout
            << "prediction            : "
            << c4_result.prediction
            << " / expected "
            << expected_c4_prediction[0]
            << " -> "
            << (c4_prediction_pass ? "PASS" : "FAIL")
            << '\n';

        std::cout
            << "NO-SIGN               : "
            << c4_is_nosign
            << " / expected 1 -> "
            << (c4_nosign_pass ? "PASS" : "FAIL")
            << '\n';

        std::cout
            << "d_sign                : "
            << c4_result.d_sign
            << " / expected "
            << expected_c4_distances[0]
            << " -> "
            << (c4_d_sign_pass ? "PASS" : "FAIL")
            << '\n';

        std::cout
            << "d_nosign              : "
            << c4_result.d_nosign
            << " / expected "
            << expected_c4_distances[1]
            << " -> "
            << (c4_d_nosign_pass ? "PASS" : "FAIL")
            << '\n';

        std::cout
            << "margin                : "
            << c4_result.margin_nosign_minus_sign
            << " / expected "
            << expected_c4_distances[2]
            << " -> "
            << (c4_margin_pass ? "PASS" : "FAIL")
            << '\n';


        std::cout
            << "\nTEMP BRANCH\n";

        std::cout
            << "eligible              : "
            << rescue.eligible
            << " / expected 1 -> "
            << (eligible_pass ? "PASS" : "FAIL")
            << '\n';

        std::cout
            << "feature valid         : "
            << rescue.feature_valid
            << " / expected 1 -> "
            << (feature_valid_pass ? "PASS" : "FAIL")
            << '\n';

        std::cout
            << "classifier ran        : "
            << rescue.classifier_ran
            << " / expected 1 -> "
            << (classifier_ran_pass ? "PASS" : "FAIL")
            << '\n';

        std::cout
            << "selected BOTH         : "
            << rescue
                   .feature_result
                   .selected_both_frames
            << " / expected "
            << REAL_BOTH_FRAMES
            << " -> "
            << (selected_both_pass ? "PASS" : "FAIL")
            << '\n';


        std::cout
            << "\nRESCUE FEATURE [80,172]\n";

        std::cout
            << "max abs error         : "
            << rescue_feature_error.max_abs_error
            << '\n';

        std::cout
            << "mean abs error        : "
            << rescue_feature_error.mean_abs_error
            << '\n';


        std::cout
            << "\nRESCUE LOCAL84 [80,84]\n";

        std::cout
            << "max abs error         : "
            << rescue_local_error.max_abs_error
            << '\n';

        std::cout
            << "mean abs error        : "
            << rescue_local_error.mean_abs_error
            << '\n';


        std::cout
            << "\nPRE-TEMP CLASSIFIER\n";

        std::cout
            << "base_id               : "
            << pre_temp.base_id
            << " / expected "
            << expected_base_id[0]
            << " -> "
            << (pre_base_id_pass ? "PASS" : "FAIL")
            << '\n';

        std::cout
            << "final_id              : "
            << pre_temp.final_id
            << " / expected "
            << expected_final_id[0]
            << " -> "
            << (pre_final_id_pass ? "PASS" : "FAIL")
            << '\n';

        std::cout
            << "stage                 : "
            << pre_temp.stage
            << " / expected "
            << expected_pre_temp_stage
            << " -> "
            << (pre_stage_pass ? "PASS" : "FAIL")
            << '\n';

        std::cout
            << "base margin           : "
            << pre_temp.base_margin
            << " / expected "
            << expected_base_margin[0]
            << " -> "
            << (pre_margin_pass ? "PASS" : "FAIL")
            << '\n';


        std::cout
            << "\nBASE RANKING\n";

        if (ranking_count_pass) {
            for (
                std::size_t i = 0;
                i < expected_ranking_ids.size();
                ++i
            ) {
                const auto& actual =
                    pre_temp.base_ranking[i];

                const double error =
                    std::fabs(
                        static_cast<double>(
                            actual.score
                        )
                        -
                        static_cast<double>(
                            expected_ranking_scores[i]
                        )
                    );

                std::cout
                    << "  "
                    << (i + 1)
                    << ". class "
                    << actual.class_id
                    << " / expected "
                    << expected_ranking_ids[i]
                    << " | score "
                    << actual.score
                    << " / expected "
                    << expected_ranking_scores[i]
                    << " | error "
                    << error
                    << '\n';
            }
        }
        else {
            std::cout
                << "ranking count mismatch\n";
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
            << "\nFINAL TEMP RESULT\n";

        std::cout
            << "candidate final_id    : "
            << rescue.candidate_final_id
            << " / expected "
            << expected_final_id[0]
            << " -> "
            << (candidate_final_id_pass ? "PASS" : "FAIL")
            << '\n';

        std::cout
            << "final_id              : "
            << rescue.twohand_result.final_id
            << " / expected "
            << expected_final_id[0]
            << " -> "
            << (final_id_pass ? "PASS" : "FAIL")
            << '\n';

        std::cout
            << "rescued               : "
            << rescue.rescued
            << " / expected "
            << expected_rescued[0]
            << " -> "
            << (rescued_pass ? "PASS" : "FAIL")
            << '\n';

        std::cout
            << "final stage           : "
            << rescue.twohand_result.stage
            << " / expected "
            << expected_final_stage
            << " -> "
            << (final_stage_pass ? "PASS" : "FAIL")
            << '\n';

        std::cout
            << "final is_nosign       : "
            << inferred_final_is_nosign
            << " / expected "
            << expected_final_is_nosign[0]
            << " -> "
            << (final_is_nosign_pass ? "PASS" : "FAIL")
            << '\n';


        std::cout
            << "\nTOLERANCE\n";

        std::cout
            << "float                 : "
            << FLOAT_TOLERANCE
            << '\n';

        std::cout
            << "double                : "
            << DOUBLE_TOLERANCE
            << '\n';


        std::cout
            << "\n========================================\n";


        if (all_pass) {
            std::cout
                << "TEMP POSITIVE FULL REGRESSION PASS\n";

            std::cout
                << "========================================\n";

            return 0;
        }


        std::cout
            << "TEMP POSITIVE FULL REGRESSION FAIL\n";

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