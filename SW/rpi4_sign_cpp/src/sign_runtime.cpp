#include "sign_runtime.hpp"

#include "temporal_resample.hpp"

#include <cstddef>
#include <exception>
#include <stdexcept>
#include <string>
#include <vector>


namespace sign_engine {

namespace {


// ============================================================
// Exact Feature V3 options used by frozen 06u runtime
// ============================================================

FeatureV3Options makeRuntimeFeatureOptions() {
    FeatureV3Options options;

    options.one_hand_ratio_threshold =
        0.20;

    options.no_motion_threshold =
        0.0;

    options.anchor_frame_count =
        5;

    options.canonical_hand =
        CanonicalHand::Right;

    return options;
}


// ============================================================
// Build original recording Feature V3
//
// Mirrors frozen:
//
// both_ratio >= 0.35
//     -> BOTH_ALIGNED
//
// else
//     right_count >= left_count
//         -> RIGHT_ONLY
//
//     else
//         -> LEFT_ONLY
//
// selected frames < 20
//     -> invalid input
// ============================================================

void buildOriginalFeature(
    const RecordingFrames& frames,
    SignRecognitionResult& result
) {
    if (frames.empty()) {
        throw std::runtime_error(
            "classifyRecording: empty recording"
        );
    }


    result.recording_stats =
        analyzeRecordingFrames(
            frames
        );


    const FeatureV3Options options =
        makeRuntimeFeatureOptions();


    // ========================================================
    // BOTH_ALIGNED
    // ========================================================

    if (
        result.recording_stats.both_ratio
        >=
        SIGN_RUNTIME_BOTH_RATIO_THRESHOLD
    ) {
        result.source_mode =
            "BOTH_ALIGNED";


        HandSequence left;
        HandSequence right;


        left.reserve(
            result.recording_stats.both_count
        );

        right.reserve(
            result.recording_stats.both_count
        );


        for (
            const FrameHands& frame :
            frames
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
            SIGN_RUNTIME_MIN_ACCEPTED_FRAMES
        ) {
            throw std::runtime_error(
                "BOTH_ALIGNED frame 부족"
            );
        }


        result.raw_feature =
            buildHandFeaturesV3(
                &left,
                &right,
                options
            );
    }


    // ========================================================
    // ONE-HAND source selection
    // ========================================================

    else {

        // ====================================================
        // RIGHT_ONLY
        //
        // Frozen:
        // right_count >= left_count
        // ====================================================

        if (
            result.recording_stats.right_count
            >=
            result.recording_stats.left_count
        ) {
            result.source_mode =
                "RIGHT_ONLY";


            HandSequence right;


            right.reserve(
                result.recording_stats.right_count
            );


            for (
                const FrameHands& frame :
                frames
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
                SIGN_RUNTIME_MIN_ACCEPTED_FRAMES
            ) {
                throw std::runtime_error(
                    "RIGHT_ONLY frame 부족"
                );
            }


            result.raw_feature =
                buildHandFeaturesV3(
                    nullptr,
                    &right,
                    options
                );
        }


        // ====================================================
        // LEFT_ONLY
        // ====================================================

        else {
            result.source_mode =
                "LEFT_ONLY";


            HandSequence left;


            left.reserve(
                result.recording_stats.left_count
            );


            for (
                const FrameHands& frame :
                frames
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
                SIGN_RUNTIME_MIN_ACCEPTED_FRAMES
            ) {
                throw std::runtime_error(
                    "LEFT_ONLY frame 부족"
                );
            }


            result.raw_feature =
                buildHandFeaturesV3(
                    &left,
                    nullptr,
                    options
                );
        }
    }


    // ========================================================
    // Feature validation
    // ========================================================

    if (!result.raw_feature.valid) {
        throw std::runtime_error(
            "Feature V3 invalid"
        );
    }


    if (
        result.raw_feature.usage.type
        !=
        UsageType::OneHand
        &&
        result.raw_feature.usage.type
        !=
        UsageType::TwoHand
    ) {
        throw std::runtime_error(
            "Unexpected Feature V3 usage type"
        );
    }


    const std::size_t expected_raw_size =
        result.raw_feature.frame_count
        *
        FEATURE_V3_DIM;


    if (
        result.raw_feature.features.size()
        !=
        expected_raw_size
    ) {
        throw std::runtime_error(
            "Feature V3 raw size mismatch"
        );
    }


    // ========================================================
    // Frozen temporal resample -> [80,172]
    // ========================================================

    result.feature80 =
        temporalResample(
            result.raw_feature.features,
            result.raw_feature.frame_count,
            FEATURE_V3_DIM,
            TARGET_FRAMES
        );


    const std::size_t expected_feature80_size =
        TARGET_FRAMES
        *
        FEATURE_V3_DIM;


    if (
        result.feature80.size()
        !=
        expected_feature80_size
    ) {
        throw std::runtime_error(
            "Feature80 size mismatch"
        );
    }


    // ========================================================
    // Frozen:
    //
    // local = feature[:, 0:LOCAL_DIM].copy()
    // ========================================================

    result.local84 =
        extractLocal84(
            result.feature80
        );


    const std::size_t expected_local84_size =
        TARGET_FRAMES
        *
        LOCAL_FEATURE_DIM;


    if (
        result.local84.size()
        !=
        expected_local84_size
    ) {
        throw std::runtime_error(
            "Local84 size mismatch"
        );
    }


    result.usage_type =
        result.raw_feature.usage.type;
}


}  // namespace


// ============================================================
// Production runtime
// ============================================================

SignRecognitionResult classifyRecording(
    const RecordingFrames& frames,
    const RuntimeData& runtime
) {
    SignRecognitionResult result;


    // ========================================================
    // Frozen INVALID INPUT section
    //
    // build_webcam_feature()
    // validate_webcam_feature()
    //
    // exception:
    //   prediction하지 않음
    // ========================================================

    try {
        buildOriginalFeature(
            frames,
            result
        );
    }
    catch (
        const std::exception& e
    ) {
        result.status =
            SignRuntimeStatus::InvalidInput;

        result.valid =
            false;

        result.error =
            e.what();

        return result;
    }


    // ========================================================
    // Frozen CLASSIFICATION section
    //
    // exception:
    //   이번 prediction은 폐기
    // ========================================================

    try {

        // ====================================================
        // ONE HAND
        // ====================================================

        if (
            result.usage_type
            ==
            UsageType::OneHand
        ) {

            // ================================================
            // C4 SIGN / NO-SIGN
            // ================================================

            result.c4_evaluated =
                true;


            result.c4_gate =
                classifyOnehandC4Gate(
                    result.feature80,
                    runtime
                );


            // ================================================
            // C4 NO-SIGN
            //
            // Frozen default:
            //
            // final_id = None
            // stage = ONEHAND_C4_NOSIGN_REJECT
            // is_nosign = True
            //
            // Then TEMP rescue is attempted.
            // ================================================

            if (
                result.c4_gate.prediction
                ==
                C4_NOSIGN_LABEL
            ) {
                result.final_id =
                    -1;

                result.stage =
                    "ONEHAND_C4_NOSIGN_REJECT";

                result.is_nosign =
                    true;


                // ============================================
                // TEMP OVERLAP RESCUE
                //
                // attemptTempOverlapRescue() internally checks:
                //
                // original one-hand
                // C4 NO-SIGN
                // both_ratio >= 0.20
                // BOTH count >= 15
                // feature minimum >= 20
                // candidate final_id == TEMP_ID
                // ============================================

                result.temp_checked =
                    true;


                result.temp_rescue =
                    attemptTempOverlapRescue(
                        true,
                        true,
                        frames,
                        runtime
                    );


                // ============================================
                // Frozen:
                //
                // only TEMP_ID success overrides reject.
                // ============================================

                if (
                    result.temp_rescue.rescued
                ) {
                    result.twohand_ran =
                        true;


                    result.twohand_result =
                        result
                            .temp_rescue
                            .twohand_result;


                    result.final_id =
                        result
                            .twohand_result
                            .final_id;


                    result.stage =
                        result
                            .twohand_result
                            .stage;


                    result.is_nosign =
                        false;


                    // Frozen:
                    //
                    // usage_type = "two_hand"
                    //
                    result.usage_type =
                        UsageType::TwoHand;
                }
            }


            // ================================================
            // C4 SIGN
            //
            // Frozen:
            //
            // result = classify_one_hand(...)
            // result["is_nosign"] = False
            // result["c4_gate"] = gate_result
            // ================================================

            else {
                result.onehand_ran =
                    true;


                result.onehand_result =
                    classifyOneHand(
                        result.local84,
                        runtime
                    );


                result.final_id =
                    result
                        .onehand_result
                        .final_id;


                result.stage =
                    result
                        .onehand_result
                        .stage;


                result.is_nosign =
                    false;
            }
        }


        // ====================================================
        // TWO HAND
        //
        // Frozen:
        //
        // result = classify_two_hand(
        //     local=local,
        //     aihub=aihub,
        // )
        // ====================================================

        else if (
            result.usage_type
            ==
            UsageType::TwoHand
        ) {
            result.twohand_ran =
                true;


            result.twohand_result =
                classifyTwoHand(
                    result.local84,
                    runtime
                );


            result.final_id =
                result
                    .twohand_result
                    .final_id;


            result.stage =
                result
                    .twohand_result
                    .stage;


            result.is_nosign =
                false;
        }


        // ====================================================
        // Frozen:
        //
        // raise RuntimeError(
        //     f"Unexpected usage_type: {usage_type}"
        // )
        // ====================================================

        else {
            throw std::runtime_error(
                "Unexpected usage_type"
            );
        }
    }
    catch (
        const std::exception& e
    ) {
        result.status =
            SignRuntimeStatus::ClassificationError;

        result.valid =
            false;

        result.final_id =
            -1;

        result.error =
            e.what();

        return result;
    }


    // ========================================================
    // Successful runtime result
    //
    // Includes valid C4 NO-SIGN reject.
    // ========================================================

    result.status =
        SignRuntimeStatus::Success;

    result.valid =
        true;

    return result;
}


}  // namespace sign_engine