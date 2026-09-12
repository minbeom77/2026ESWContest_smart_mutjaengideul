#pragma once

#include "sign_types.hpp"
#include "temporal_resample.hpp"
#include "twohand_classifier.hpp"

#include <cstddef>
#include <cstdint>
#include <vector>


namespace sign_engine {

constexpr double TEMP_OVERLAP_BOTH_RATIO_THRESHOLD =
    0.20;

constexpr std::size_t TEMP_OVERLAP_MIN_BOTH_FRAMES =
    15;

// Frozen Python build_webcam_feature()
// runtime.MIN_ACCEPTED_FRAMES
constexpr std::size_t TEMP_OVERLAP_FEATURE_MIN_FRAMES =
    20;

constexpr std::int32_t TEMP_OVERLAP_TARGET_CLASS_ID =
    TWOHAND_TEMP_ID;

struct TempOverlapFeatureResult {
    bool valid =
        false;

    std::size_t selected_both_frames =
        0;

    FeatureV3Result raw_feature;

    std::vector<float> resampled_features;
};

struct TempOverlapRescueResult {
    bool eligible =
        false;

    bool feature_valid =
        false;

    bool classifier_ran =
        false;

    bool rescued =
        false;

    RecordingStats stats;

    TempOverlapFeatureResult feature_result;

    std::vector<float> local84;

    TwoHandResult twohand_result;

    std::int32_t candidate_final_id =
        -1;
};

RecordingStats analyzeRecordingFrames(
    const RecordingFrames& recording_frames
);

BothHandSequences extractBothHandSequences(
    const RecordingFrames& recording_frames
);

bool isTempOverlapRescueEligible(
    bool original_one_hand,
    bool c4_is_nosign,
    const RecordingStats& stats
);

TempOverlapFeatureResult buildTempOverlapFeature80(
    const RecordingFrames& recording_frames
);

std::vector<float> extractLocal84FromFeature80(
    const std::vector<float>& feature80
);

TempOverlapRescueResult attemptTempOverlapRescue(
    bool original_one_hand,
    bool c4_is_nosign,
    const RecordingFrames& recording_frames,
    const RuntimeData& runtime_data
);

}  // namespace sign_engine