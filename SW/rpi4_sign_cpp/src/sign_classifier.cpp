#include "sign_classifier.hpp"

#include <cstddef>
#include <stdexcept>


namespace sign_engine {

RecordingStats analyzeRecordingFrames(
    const RecordingFrames& recording_frames
) {
    if (recording_frames.empty()) {
        throw std::runtime_error(
            "analyzeRecordingFrames: no hand frames"
        );
    }

    RecordingStats stats;
    stats.total_frames =
        recording_frames.size();

    for (
        const FrameHands& frame :
        recording_frames
    ) {
        if (frame.has_left) {
            ++stats.left_count;
        }

        if (frame.has_right) {
            ++stats.right_count;
        }

        if (
            frame.has_left
            &&
            frame.has_right
        ) {
            ++stats.both_count;
        }
    }

    stats.both_ratio =
        static_cast<double>(
            stats.both_count
        )
        /
        static_cast<double>(
            stats.total_frames
        );

    return stats;
}


BothHandSequences extractBothHandSequences(
    const RecordingFrames& recording_frames
) {
    BothHandSequences result;

    result.left.reserve(
        recording_frames.size()
    );

    result.right.reserve(
        recording_frames.size()
    );

    for (
        const FrameHands& frame :
        recording_frames
    ) {
        if (
            !frame.has_left
            ||
            !frame.has_right
        ) {
            continue;
        }

        result.left.push_back(
            frame.left
        );

        result.right.push_back(
            frame.right
        );
    }

    if (
        result.left.size()
        !=
        result.right.size()
    ) {
        throw std::runtime_error(
            "extractBothHandSequences: "
            "left/right size mismatch"
        );
    }

    return result;
}


bool isTempOverlapRescueEligible(
    bool original_one_hand,
    bool c4_is_nosign,
    const RecordingStats& stats
) {
    if (!original_one_hand) {
        return false;
    }

    if (!c4_is_nosign) {
        return false;
    }

    if (
        stats.both_ratio
        <
        TEMP_OVERLAP_BOTH_RATIO_THRESHOLD
    ) {
        return false;
    }

    if (
        stats.both_count
        <
        TEMP_OVERLAP_MIN_BOTH_FRAMES
    ) {
        return false;
    }

    return true;
}


TempOverlapFeatureResult buildTempOverlapFeature80(
    const RecordingFrames& recording_frames
) {
    TempOverlapFeatureResult result;

    const BothHandSequences both =
        extractBothHandSequences(
            recording_frames
        );

    result.selected_both_frames =
        both.size();

    if (both.empty()) {
        return result;
    }

    // ========================================================
    // Frozen Python parity:
    //
    // TEMP rescue passes BOTH-only frames back into
    // build_webcam_feature().
    //
    // Because every recollected frame contains both hands,
    // both_ratio == 1.0 and Python always selects
    // BOTH_ALIGNED.
    //
    // build_webcam_feature() then requires:
    //
    // len(selected) >= runtime.MIN_ACCEPTED_FRAMES
    //
    // Frozen runtime value: 20.
    //
    // Therefore TEMP eligibility may begin at 15 frames,
    // but Feature V3 reconstruction cannot proceed with
    // only 15~19 BOTH frames.
    // ========================================================

    if (
        both.size()
        <
        TEMP_OVERLAP_FEATURE_MIN_FRAMES
    ) {
        throw std::runtime_error(
            "buildTempOverlapFeature80: "
            "BOTH_ALIGNED frame 부족"
        );
    }

    FeatureV3Options options;

    options.one_hand_ratio_threshold =
        0.20;

    options.no_motion_threshold =
        0.0;

    options.anchor_frame_count =
        5;

    options.canonical_hand =
        CanonicalHand::Right;

    result.raw_feature =
        buildHandFeaturesV3(
            &both.left,
            &both.right,
            options
        );

    if (
        !result.raw_feature.valid
    ) {
        return result;
    }

    if (
        result.raw_feature.usage.type
        !=
        UsageType::TwoHand
    ) {
        return result;
    }

    if (
        result.raw_feature.frame_count
        !=
        both.size()
    ) {
        throw std::runtime_error(
            "buildTempOverlapFeature80: "
            "raw frame count mismatch"
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
            "buildTempOverlapFeature80: "
            "raw Feature V3 size mismatch"
        );
    }

    result.resampled_features =
        temporalResample(
            result.raw_feature.features,
            result.raw_feature.frame_count,
            FEATURE_V3_DIM,
            TEMPORAL_TARGET_FRAMES
        );

    const std::size_t expected_resampled_size =
        TEMPORAL_TARGET_FRAMES
        *
        FEATURE_V3_DIM;

    if (
        result.resampled_features.size()
        !=
        expected_resampled_size
    ) {
        throw std::runtime_error(
            "buildTempOverlapFeature80: "
            "resampled Feature V3 "
            "size mismatch"
        );
    }

    result.valid =
        true;

    return result;
}


std::vector<float> extractLocal84FromFeature80(
    const std::vector<float>& feature80
) {
    const std::size_t expected_size =
        TEMPORAL_TARGET_FRAMES
        *
        FEATURE_V3_DIM;

    if (
        feature80.size()
        !=
        expected_size
    ) {
        throw std::invalid_argument(
            "extractLocal84FromFeature80: "
            "feature must be [80,172]"
        );
    }

    std::vector<float> local84(
        TEMPORAL_TARGET_FRAMES
        *
        FEATURE_V3_LOCAL_DIM
    );

    for (
        std::size_t frame = 0;
        frame
        <
        TEMPORAL_TARGET_FRAMES;
        ++frame
    ) {
        const std::size_t source_offset =
            frame
            *
            FEATURE_V3_DIM;

        const std::size_t destination_offset =
            frame
            *
            FEATURE_V3_LOCAL_DIM;

        for (
            std::size_t dim = 0;
            dim
            <
            FEATURE_V3_LOCAL_DIM;
            ++dim
        ) {
            local84[
                destination_offset + dim
            ] =
                feature80[
                    source_offset + dim
                ];
        }
    }

    return local84;
}


TempOverlapRescueResult attemptTempOverlapRescue(
    bool original_one_hand,
    bool c4_is_nosign,
    const RecordingFrames& recording_frames,
    const RuntimeData& runtime_data
) {
    TempOverlapRescueResult result;

    result.stats =
        analyzeRecordingFrames(
            recording_frames
        );

    result.eligible =
        isTempOverlapRescueEligible(
            original_one_hand,
            c4_is_nosign,
            result.stats
        );

    if (
        !result.eligible
    ) {
        return result;
    }

    // ========================================================
    // Frozen Python TEMP rescue uses try/except around the
    // recollection -> feature -> classifier path.
    //
    // In particular, 15~19 BOTH frames pass the TEMP trigger,
    // but build_webcam_feature() raises because
    // MIN_ACCEPTED_FRAMES == 20.
    //
    // The exception does NOT replace the existing C4 NO-SIGN
    // result. Rescue simply fails.
    // ========================================================

    try {
        result.feature_result =
            buildTempOverlapFeature80(
                recording_frames
            );

        result.feature_valid =
            result.feature_result.valid;

        if (
            !result.feature_valid
        ) {
            return result;
        }

        result.local84 =
            extractLocal84FromFeature80(
                result
                    .feature_result
                    .resampled_features
            );

        result.twohand_result =
            classifyTwoHand(
                result.local84,
                runtime_data
            );

        result.classifier_ran =
            true;

        result.candidate_final_id =
            result.twohand_result.final_id;

        result.rescued =
            (
                result.candidate_final_id
                ==
                TEMP_OVERLAP_TARGET_CLASS_ID
            );

        if (
            result.rescued
        ) {
            // Frozen 07g exact stage override.
            result.twohand_result.stage =
                "TWOHAND_TEMP_OVERLAP_RESCUE";
        }
    }
    catch (
        const std::exception&
    ) {
        // Frozen Python:
        //
        // except Exception as rescue_error:
        //     ...
        //
        // Existing one-hand C4 NO-SIGN result is preserved.
        // No TEMP classifier result becomes final.
        return result;
    }

    return result;
}

}  // namespace sign_engine